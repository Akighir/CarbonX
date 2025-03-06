;; Carbon Credit Trading Platform Smart Contract

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INSUFFICIENT-CREDIT-BALANCE (err u101))
(define-constant ERR-INVALID-CREDIT-AMOUNT (err u102))
(define-constant ERR-CARBON-PRICE-EXPIRED (err u103))
(define-constant ERR-INSUFFICIENT-EMISSION-OFFSET (err u104))
(define-constant ERR-BELOW-MINIMUM-OFFSET-THRESHOLD (err u105))
(define-constant ERR-INVALID-PRICE (err u106))
(define-constant ERR-ARITHMETIC-OVERFLOW (err u107))
(define-constant ERR-INVALID-RECIPIENT (err u108))
(define-constant ERR-ZERO-AMOUNT (err u109))
(define-constant ERR-NO-PORTFOLIO-EXISTS (err u110))

;; Constants
(define-constant CONTRACT-ADMINISTRATOR tx-sender)
(define-constant CARBON-PRICE-EXPIRY-BLOCKS u900) ;; 15 minutes in blocks
(define-constant REQUIRED-OFFSET-RATIO u150) ;; 150%
(define-constant LIQUIDATION-THRESHOLD-RATIO u120) ;; 120%
(define-constant MINIMUM-CARBON-CREDIT-MINT u100000000) ;; 1.00 credits (8 decimals)
(define-constant MAXIMUM-CARBON-PRICE u1000000000000) ;; Set reasonable maximum price
(define-constant MAXIMUM-UINT-VALUE u340282366920938463463374607431768211455) ;; 2^128 - 1

;; Data variables
(define-data-var carbon-price-last-update-block uint u0)
(define-data-var carbon-market-price uint u0)
(define-data-var total-carbon-credits-supply uint u0)

;; Data maps
(define-map carbon-credit-account-balances principal uint)
(define-map emission-offset-portfolios
    principal
    {
        emission-offset-locked: uint,
        carbon-credits-issued: uint,
        entry-offset-price: uint
    }
)

;; Safe math functions
(define-private (safe-multiply-numbers (first-number uint) (second-number uint))
    (let ((multiplication-result (* first-number second-number)))
        (asserts! (or (is-eq first-number u0) (is-eq (/ multiplication-result first-number) second-number)) ERR-ARITHMETIC-OVERFLOW)
        (ok multiplication-result)))

(define-private (safe-add-numbers (first-number uint) (second-number uint))
    (let ((addition-result (+ first-number second-number)))
        (asserts! (>= addition-result first-number) ERR-ARITHMETIC-OVERFLOW)
        (ok addition-result)))

(define-private (safe-subtract-numbers (minuend uint) (subtrahend uint))
    (begin
        (asserts! (>= minuend subtrahend) ERR-ARITHMETIC-OVERFLOW)
        (ok (- minuend subtrahend))))

;; Read-only functions
(define-read-only (get-account-credit-balance (account-holder principal))
    (default-to u0 (map-get? carbon-credit-account-balances account-holder))
)

(define-read-only (get-total-carbon-credit-supply)
    (var-get total-carbon-credits-supply)
)

(define-read-only (get-current-carbon-price)
    (var-get carbon-market-price)
)

(define-read-only (get-emission-offset-portfolio-details (portfolio-owner principal))
    (map-get? emission-offset-portfolios portfolio-owner)
)

(define-read-only (calculate-portfolio-offset-ratio (portfolio-owner principal))
    (let (
        (portfolio-details (unwrap! (get-emission-offset-portfolio-details portfolio-owner) (err u0)))
        (current-market-price (var-get carbon-market-price))
    )
    (if (> (get carbon-credits-issued portfolio-details) u0)
        (match (safe-multiply-numbers (get emission-offset-locked portfolio-details) u100)
            success1 (match (safe-multiply-numbers success1 u100)
                success2 (match (safe-multiply-numbers (get carbon-credits-issued portfolio-details) current-market-price)
                    denominator (ok (/ success2 denominator))
                    error ERR-ARITHMETIC-OVERFLOW)
                error ERR-ARITHMETIC-OVERFLOW)
            error ERR-ARITHMETIC-OVERFLOW)
        (err u0)))
)

;; Private functions
(define-private (execute-credit-transfer (sender-account principal) (recipient-account principal) (transfer-quantity uint))
    (let (
        (sender-current-balance (get-account-credit-balance sender-account))
    )
    ;; Secondary validations in case this function is called directly
    (asserts! (> transfer-quantity u0) ERR-ZERO-AMOUNT)
    (asserts! (not (is-eq sender-account recipient-account)) ERR-INVALID-RECIPIENT)
    (asserts! (>= sender-current-balance transfer-quantity) ERR-INSUFFICIENT-CREDIT-BALANCE)
    (asserts! (is-some (map-get? carbon-credit-account-balances sender-account)) ERR-UNAUTHORIZED-ACCESS)
    
    (match (safe-add-numbers (get-account-credit-balance recipient-account) transfer-quantity)
        recipient-updated-balance
            (match (safe-subtract-numbers sender-current-balance transfer-quantity)
                sender-updated-balance
                    (begin
                        (map-set carbon-credit-account-balances sender-account sender-updated-balance)
                        (map-set carbon-credit-account-balances recipient-account recipient-updated-balance)
                        (ok true))
                error ERR-ARITHMETIC-OVERFLOW)
        error ERR-ARITHMETIC-OVERFLOW))
)

;; Public functions
(define-public (update-carbon-market-price (updated-price uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMINISTRATOR) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> updated-price u0) ERR-INVALID-PRICE)
        (asserts! (< updated-price MAXIMUM-CARBON-PRICE) ERR-INVALID-PRICE)
        (var-set carbon-market-price updated-price)
        (var-set carbon-price-last-update-block block-height)
        (ok true))
)

(define-public (mint-new-carbon-credits (credit-quantity uint))
    (let (
        (current-market-price (var-get carbon-market-price))
    )
    (asserts! (> credit-quantity u0) ERR-ZERO-AMOUNT)
    (asserts! (>= credit-quantity MINIMUM-CARBON-CREDIT-MINT) ERR-INVALID-CREDIT-AMOUNT)
    (asserts! (<= (- block-height (var-get carbon-price-last-update-block)) 
                 CARBON-PRICE-EXPIRY-BLOCKS) 
              ERR-CARBON-PRICE-EXPIRED)
    
    (match (safe-multiply-numbers credit-quantity (/ current-market-price u100))
        required-base-offset 
        (match (safe-multiply-numbers required-base-offset (/ REQUIRED-OFFSET-RATIO u100))
            minimum-offset-required
            (match (stx-transfer? minimum-offset-required tx-sender (as-contract tx-sender))
                success
                (begin
                    (map-set emission-offset-portfolios tx-sender
                        {
                            emission-offset-locked: minimum-offset-required,
                            carbon-credits-issued: credit-quantity,
                            entry-offset-price: current-market-price
                        })
                    (match (safe-add-numbers (get-account-credit-balance tx-sender) credit-quantity)
                        updated-balance
                        (begin
                            (map-set carbon-credit-account-balances tx-sender updated-balance)
                            (match (safe-add-numbers (var-get total-carbon-credits-supply) credit-quantity)
                                updated-supply
                                (begin
                                    (var-set total-carbon-credits-supply updated-supply)
                                    (ok true))
                                error ERR-ARITHMETIC-OVERFLOW))
                        error ERR-ARITHMETIC-OVERFLOW))
                error ERR-INSUFFICIENT-EMISSION-OFFSET)
            error ERR-ARITHMETIC-OVERFLOW)
        error ERR-ARITHMETIC-OVERFLOW))
)

(define-public (burn-existing-carbon-credits (credit-quantity uint))
    (let (
        (portfolio-details (unwrap! (get-emission-offset-portfolio-details tx-sender) 
                               ERR-NO-PORTFOLIO-EXISTS))
        (account-balance (get-account-credit-balance tx-sender))
    )
    (asserts! (> credit-quantity u0) ERR-ZERO-AMOUNT)
    (asserts! (>= account-balance credit-quantity) ERR-INSUFFICIENT-CREDIT-BALANCE)
    (asserts! (>= (get carbon-credits-issued portfolio-details) credit-quantity) 
              ERR-UNAUTHORIZED-ACCESS)
    
    (match (safe-multiply-numbers (get emission-offset-locked portfolio-details) credit-quantity)
        offset-calculation
        (let (
            (offset-return-amount (/ offset-calculation 
                                       (get carbon-credits-issued portfolio-details)))
        )
        
        (try! (as-contract (stx-transfer? offset-return-amount
                                         (as-contract tx-sender)
                                         tx-sender)))
        
        (match (safe-subtract-numbers (get emission-offset-locked portfolio-details) 
                            offset-return-amount)
            updated-offset-amount
            (match (safe-subtract-numbers (get carbon-credits-issued portfolio-details) 
                                credit-quantity)
                updated-credit-amount
                (begin
                    (map-set emission-offset-portfolios tx-sender
                        {
                            emission-offset-locked: updated-offset-amount,
                            carbon-credits-issued: updated-credit-amount,
                            entry-offset-price: (var-get carbon-market-price)
                        })
                    
                    (match (safe-subtract-numbers account-balance credit-quantity)
                        updated-balance
                        (begin
                            (map-set carbon-credit-account-balances tx-sender updated-balance)
                            (match (safe-subtract-numbers (var-get total-carbon-credits-supply) 
                                                credit-quantity)
                                updated-supply
                                (begin
                                    (var-set total-carbon-credits-supply updated-supply)
                                    (ok true))
                                error ERR-ARITHMETIC-OVERFLOW))
                        error ERR-ARITHMETIC-OVERFLOW))
                error ERR-ARITHMETIC-OVERFLOW)
            error ERR-ARITHMETIC-OVERFLOW))
        error ERR-ARITHMETIC-OVERFLOW))
)

(define-public (transfer-carbon-credits (recipient-account principal) (transfer-quantity uint))
    (begin
        ;; Input validation
        (asserts! (> transfer-quantity u0) ERR-ZERO-AMOUNT)
        (asserts! (<= transfer-quantity (get-account-credit-balance tx-sender)) ERR-INSUFFICIENT-CREDIT-BALANCE)
        (asserts! (not (is-eq tx-sender recipient-account)) ERR-INVALID-RECIPIENT)
        
        ;; Only proceed with transfer if validations pass
        (execute-credit-transfer tx-sender recipient-account transfer-quantity))
)

(define-public (add-emission-offset-to-portfolio (offset-quantity uint))
    (let (
        (portfolio-details (default-to 
            {
                emission-offset-locked: u0, 
                carbon-credits-issued: u0, 
                entry-offset-price: u0
            }
            (get-emission-offset-portfolio-details tx-sender)))
    )
    (asserts! (> offset-quantity u0) ERR-ZERO-AMOUNT)
    (try! (stx-transfer? offset-quantity tx-sender (as-contract tx-sender)))
    
    (match (safe-add-numbers (get emission-offset-locked portfolio-details) 
                    offset-quantity)
        updated-offset-amount
        (begin
            (map-set emission-offset-portfolios tx-sender
                {
                    emission-offset-locked: updated-offset-amount,
                    carbon-credits-issued: (get carbon-credits-issued portfolio-details),
                    entry-offset-price: (var-get carbon-market-price)
                })
            (ok true))
        error ERR-ARITHMETIC-OVERFLOW))
)

(define-public (liquidate-emission-offset-portfolio (portfolio-owner principal))
    (let (
        (portfolio-details (unwrap! (get-emission-offset-portfolio-details portfolio-owner) 
                               ERR-NO-PORTFOLIO-EXISTS))
        (current-offset-ratio (unwrap! (calculate-portfolio-offset-ratio portfolio-owner) 
                                         ERR-UNAUTHORIZED-ACCESS))
    )
    (asserts! (< current-offset-ratio LIQUIDATION-THRESHOLD-RATIO) 
              ERR-UNAUTHORIZED-ACCESS)
    
    ;; Transfer emission offset to liquidator
    (try! (as-contract (stx-transfer? (get emission-offset-locked portfolio-details)
                                     (as-contract tx-sender)
                                     tx-sender)))
    
    ;; Clear the portfolio
    (map-delete emission-offset-portfolios portfolio-owner)
    
    ;; Burn the carbon credits
    (map-set carbon-credit-account-balances portfolio-owner u0)
    (match (safe-subtract-numbers (var-get total-carbon-credits-supply) 
                         (get carbon-credits-issued portfolio-details))
        updated-supply
        (begin
            (var-set total-carbon-credits-supply updated-supply)
            (ok true))
        error ERR-ARITHMETIC-OVERFLOW))
)