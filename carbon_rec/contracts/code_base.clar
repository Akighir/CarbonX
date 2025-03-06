;; Carbon Credit Trading Platform - Basic Tracking

;; Error codes
(define-constant ERR-INSUFFICIENT-CREDIT-BALANCE (err u101))
(define-constant ERR-INVALID-CREDIT-AMOUNT (err u102))
(define-constant ERR-ZERO-AMOUNT (err u109))

;; Data variables
(define-data-var total-carbon-credits-supply uint u0)

;; Data maps
(define-map carbon-credit-account-balances principal uint)

;; Read-only functions
(define-read-only (get-account-credit-balance (account-holder principal))
    (default-to u0 (map-get? carbon-credit-account-balances account-holder))
)

(define-read-only (get-total-carbon-credit-supply)
    (var-get total-carbon-credits-supply)
)

;; Public functions
(define-public (mint-carbon-credits (recipient principal) (quantity uint))
    (begin
        (asserts! (> quantity u0) ERR-ZERO-AMOUNT)
        
        (map-set carbon-credit-account-balances recipient 
            (+ (get-account-credit-balance recipient) quantity))
        
        (var-set total-carbon-credits-supply 
            (+ (var-get total-carbon-credits-supply) quantity))
        
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
    )
    (asserts! (>= sender-balance quantity) ERR-INSUFFICIENT-CREDIT-BALANCE)
    
    (map-set carbon-credit-account-balances tx-sender 
        (- sender-balance quantity))
    
    (var-set total-carbon-credits-supply 
        (- (var-get total-carbon-credits-supply) quantity))
    
    (ok true))
)