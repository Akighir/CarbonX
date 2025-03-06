;; Carbon Credit Trading Platform - Advanced Management

;; Error codes
(define-constant ERR-UNAUTHORIZED-ACCESS (err u100))
(define-constant ERR-INSUFFICIENT-CREDIT-BALANCE (err u101))
(define-constant ERR-INVALID-CREDIT-AMOUNT (err u102))
(define-constant ERR-ZERO-AMOUNT (err u109))
(define-constant ERR-INVALID-PRICE (err u106))

;; Constants
(define-constant CONTRACT-ADMINISTRATOR tx-sender)
(define-constant MINIMUM-CARBON-CREDIT-MINT u100000000)
(define-constant MAXIMUM-CARBON-PRICE u1000000000000)

;; Data variables
(define-data-var total-carbon-credits-supply uint u0)
(define-data-var carbon-market-price uint u0)
(define-data-var carbon-price-last-update-block uint u0)

;; Data maps
(define-map carbon-credit-account-balances principal uint)
(define-map emission-offset-portfolios
    principal
    {
        total-offset: uint,
        credited-offset: uint
    }
)

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

;; Administrative functions
(define-public (update-carbon-market-price (new-price uint))
    (begin
        (asserts! (is-eq tx-sender CONTRACT-ADMINISTRATOR) ERR-UNAUTHORIZED-ACCESS)
        (asserts! (> new-price u0) ERR-INVALID-PRICE)
        (asserts! (< new-price MAXIMUM-CARBON-PRICE) ERR-INVALID-PRICE)
        
        (var-set carbon-market-price new-price)
        (var-set carbon-price-last-update-block block-height)
        
        (ok true)
    )
)

;; Carbon Credit Management Functions
(define-public (mint-carbon-credits (recipient principal) (quantity uint) (offset-amount uint))
    (begin
        (asserts! (> quantity u0) ERR-ZERO-AMOUNT)
        (asserts! (>= quantity MINIMUM-CARBON-CREDIT-MINT) ERR-INVALID-CREDIT-AMOUNT)
        
        ;; Update account balances
        (map-set carbon-credit-account-balances recipient 
            (+ (get-account-credit-balance recipient) quantity))
        
        ;; Update total supply
        (var-set total-carbon-credits-supply 
            (+ (var-get total-carbon-credits-supply) quantity))
        
        ;; Track emission offset
        (map-set emission-offset-portfolios recipient
            {
                total-offset: offset-amount,
                credited-offset: quantity
            })
        
        (ok true)
    )
)

(define-public (transfer-carbon-credits (recipient principal) (quantity uint))
    (let (
        (sender-balance (get-account-credit-balance tx-sender))
    )
    (asserts! (>= sender-balance quantity) ERR-INSUFFICIENT-CREDIT-BALANCE)
    
    (map-set carbon-credit-account-balances tx-sender 
        (- sender-balance quantity))
    
    (map-set carbon-credit-account-balances recipient
        (+ (get-account-credit-balance recipient) quantity))
    
    (ok true))
)

(define-public (burn-carbon-credits (quantity uint))
    (let (
        (sender-balance (get-account-credit-balance tx-sender))
        (portfolio-details (default-to 
            { total-offset: u0, credited-offset: u0 }
            (map-get? emission-offset-portfolios tx-sender)))
    )
    (asserts! (>= sender-balance quantity) ERR-INSUFFICIENT-CREDIT-BALANCE)
    
    ;; Update account balances
    (map-set carbon-credit-account-balances tx-sender 
        (- sender-balance quantity))
    
    ;; Update total supply
    (var-set total-carbon-credits-supply 
        (- (var-get total-carbon-credits-supply) quantity))
    
    ;; Update portfolio
    (map-set emission-offset-portfolios tx-sender
        {
            total-offset: (get total-offset portfolio-details),
            credited-offset: (- (get credited-offset portfolio-details) quantity)
        })
    
    (ok true))
)