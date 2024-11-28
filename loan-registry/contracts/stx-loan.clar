;; Debt Market Smart Contract
;; Enables peer-to-peer lending and borrowing with collateral-backed loans

;; Define contract owner - the address that deployed the contract
(define-constant contract-owner tx-sender)

;; Error codes
(define-constant ERR-CALLER-NOT-AUTHORIZED (err u100))
(define-constant ERR-WALLET-BALANCE-TOO-LOW (err u101))
(define-constant ERR-COLLATERAL-BELOW-MINIMUM (err u102))
(define-constant ERR-REQUESTED-LOAN-NOT-FOUND (err u103))
(define-constant ERR-INVALID-MONETARY-AMOUNT (err u104))
(define-constant ERR-LOAN-NOT-ELIGIBLE-LIQUIDATION (err u105))
(define-constant ERR-INVALID-PROTOCOL-PARAMETER (err u106))

;; Protocol parameters
;; Define reasonable bounds for protocol parameters
(define-constant MAX-COLLATERAL-RATIO-BPS u30000)   ;; 300% maximum
(define-constant MIN-COLLATERAL-RATIO-BPS u10000)   ;; 100% minimum
(define-constant MAX-INTEREST-RATE-BPS u5000)       ;; 50% maximum annual rate
(define-constant MIN-INTEREST-RATE-BPS u100)        ;; 1% minimum annual rate

(define-data-var minimum-required-collateral-ratio-bps uint u15000)  ;; 150% in basis points
(define-data-var protocol-interest-rate-yearly-bps uint u500)        ;; 5% annual rate in basis points
(define-data-var minimum-liquidation-threshold-bps uint u13000)      ;; 130% in basis points

;; Core data structures
(define-map protocol-loan-registry
    { protocol-loan-id: uint }
    {
        borrower-address: principal,
        loan-principal-amount: uint,
        deposited-collateral-amount: uint,
        applied-interest-rate-bps: uint,
        loan-origination-block: uint,
        current-loan-state: (string-ascii 20)
    }
)

(define-map protocol-user-account-state
    principal
    {
        current-lending-pool-balance: uint,
        current-borrowed-principal: uint,
        current-locked-collateral: uint
    }
)

;; Global protocol state
(define-data-var protocol-total-loan-count uint u1)

;; Administrative functions with enhanced validation
(define-public (update-protocol-collateral-requirement (new-minimum-collateral-ratio-bps uint))
    (begin
        ;; Validate caller is contract owner
        (asserts! (is-eq tx-sender contract-owner) ERR-CALLER-NOT-AUTHORIZED)
        
        ;; Validate new collateral ratio is within acceptable bounds
        (asserts! (and 
            (>= new-minimum-collateral-ratio-bps MIN-COLLATERAL-RATIO-BPS)
            (<= new-minimum-collateral-ratio-bps MAX-COLLATERAL-RATIO-BPS)
        ) ERR-INVALID-PROTOCOL-PARAMETER)
        
        ;; Update protocol parameter
        (var-set minimum-required-collateral-ratio-bps new-minimum-collateral-ratio-bps)
        (ok true)
    )
)

(define-public (update-protocol-interest-rate (new-yearly-interest-rate-bps uint))
    (begin
        ;; Validate caller is contract owner
        (asserts! (is-eq tx-sender contract-owner) ERR-CALLER-NOT-AUTHORIZED)
        
        ;; Validate new interest rate is within acceptable bounds
        (asserts! (and 
            (>= new-yearly-interest-rate-bps MIN-INTEREST-RATE-BPS)
            (<= new-yearly-interest-rate-bps MAX-INTEREST-RATE-BPS)
        ) ERR-INVALID-PROTOCOL-PARAMETER)
        
        ;; Update protocol parameter
        (var-set protocol-interest-rate-yearly-bps new-yearly-interest-rate-bps)
        (ok true)
    )
)

;; Lending pool functions
(define-public (deposit-funds-to-lending-pool (deposit-amount-ustx uint))
    (let (
        (depositor-address tx-sender)
        (depositor-account-state (default-to
            { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
            (map-get? protocol-user-account-state depositor-address)))
    )
    (begin
        (asserts! (> deposit-amount-ustx u0) ERR-INVALID-MONETARY-AMOUNT)
        (try! (stx-transfer? deposit-amount-ustx depositor-address (as-contract tx-sender)))
        (map-set protocol-user-account-state
            depositor-address
            (merge depositor-account-state
                { current-lending-pool-balance: (+ (get current-lending-pool-balance depositor-account-state) deposit-amount-ustx) })
        )
        (ok true)
    ))
)

(define-public (withdraw-funds-from-lending-pool (withdrawal-amount-ustx uint))
    (let (
        (withdrawer-address tx-sender)
        (withdrawer-account-state (default-to
            { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
            (map-get? protocol-user-account-state withdrawer-address)))
    )
    (begin
        (asserts! (>= (get current-lending-pool-balance withdrawer-account-state) withdrawal-amount-ustx)
            ERR-WALLET-BALANCE-TOO-LOW)
        (try! (as-contract (stx-transfer? withdrawal-amount-ustx tx-sender withdrawer-address)))
        (map-set protocol-user-account-state
            withdrawer-address
            (merge withdrawer-account-state
                { current-lending-pool-balance: (- (get current-lending-pool-balance withdrawer-account-state) withdrawal-amount-ustx) })
        )
        (ok true)
    ))
)

;; Loan operations
(define-public (create-collateralized-loan-request (requested-principal-ustx uint) (offered-collateral-ustx uint))
    (let (
        (borrower-address tx-sender)
        (new-protocol-loan-id (var-get protocol-total-loan-count))
        (borrower-account-state (default-to
            { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
            (map-get? protocol-user-account-state borrower-address)))
        (calculated-collateral-ratio-bps 
            (if (> requested-principal-ustx u0)
                (/ (* offered-collateral-ustx u10000) requested-principal-ustx)
                u0
            )
        )
    )
    (begin
        ;; Validate loan amounts
        (asserts! (> requested-principal-ustx u0) ERR-INVALID-MONETARY-AMOUNT)
        (asserts! (> offered-collateral-ustx u0) ERR-INVALID-MONETARY-AMOUNT)
        
        ;; Validate collateralization
        (asserts! (>= calculated-collateral-ratio-bps (var-get minimum-required-collateral-ratio-bps))
            ERR-COLLATERAL-BELOW-MINIMUM)
        
        (try! (stx-transfer? offered-collateral-ustx borrower-address (as-contract tx-sender)))
        
        ;; Register new loan
        (map-set protocol-loan-registry
            { protocol-loan-id: new-protocol-loan-id }
            {
                borrower-address: borrower-address,
                loan-principal-amount: requested-principal-ustx,
                deposited-collateral-amount: offered-collateral-ustx,
                applied-interest-rate-bps: (var-get protocol-interest-rate-yearly-bps),
                loan-origination-block: block-height,
                current-loan-state: "active"
            }
        )
        
        ;; Update borrower's account state
        (map-set protocol-user-account-state
            borrower-address
            (merge borrower-account-state {
                current-borrowed-principal: (+ (get current-borrowed-principal borrower-account-state) requested-principal-ustx),
                current-locked-collateral: (+ (get current-locked-collateral borrower-account-state) offered-collateral-ustx)
            })
        )
        
        ;; Disburse loan principal
        (try! (as-contract (stx-transfer? requested-principal-ustx tx-sender borrower-address)))
        
        ;; Update protocol state
        (var-set protocol-total-loan-count (+ new-protocol-loan-id u1))
        (ok new-protocol-loan-id)
    ))
)

(define-public (repay-outstanding-loan (protocol-loan-id uint) (repayment-amount-ustx uint))
    (let (
        (repayer-address tx-sender)
        (loan-record (unwrap! (map-get? protocol-loan-registry { protocol-loan-id: protocol-loan-id })
            ERR-REQUESTED-LOAN-NOT-FOUND))
    )
    (begin
        ;; Validate protocol-loan-id
        (asserts! (< protocol-loan-id (var-get protocol-total-loan-count)) ERR-REQUESTED-LOAN-NOT-FOUND)
        
        ;; Validate loan state and ownership
        (asserts! (is-eq (get borrower-address loan-record) repayer-address) ERR-CALLER-NOT-AUTHORIZED)
        (asserts! (is-eq (get current-loan-state loan-record) "active") ERR-REQUESTED-LOAN-NOT-FOUND)
        
        ;; Calculate total repayment required
        (let (
            (blocks-since-origination (- block-height (get loan-origination-block loan-record)))
            (accrued-interest-amount (/ (* (get loan-principal-amount loan-record)
                (get applied-interest-rate-bps loan-record) blocks-since-origination) u10000))
            (total-required-repayment (+ (get loan-principal-amount loan-record) accrued-interest-amount))
        )
            (asserts! (>= repayment-amount-ustx total-required-repayment) ERR-WALLET-BALANCE-TOO-LOW)
            
            ;; Process loan repayment
            (try! (stx-transfer? repayment-amount-ustx repayer-address (as-contract tx-sender)))
            
            ;; Return collateral to borrower
            (try! (as-contract (stx-transfer? (get deposited-collateral-amount loan-record) tx-sender repayer-address)))
            
            ;; Update loan status
            (map-set protocol-loan-registry
                { protocol-loan-id: protocol-loan-id }
                (merge loan-record { current-loan-state: "repaid" })
            )
            
            ;; Update account state
            (map-set protocol-user-account-state
                repayer-address
                (merge (default-to
                    { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                    (map-get? protocol-user-account-state repayer-address))
                    {
                        current-borrowed-principal: (- (get current-borrowed-principal 
                            (default-to
                                { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                                (map-get? protocol-user-account-state repayer-address)))
                            (get loan-principal-amount loan-record)),
                        current-locked-collateral: (- (get current-locked-collateral 
                            (default-to
                                { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                                (map-get? protocol-user-account-state repayer-address)))
                            (get deposited-collateral-amount loan-record))
                    }
                )
            )
            (ok true)
        )
    ))
)

;; Liquidation mechanism
(define-public (initiate-undercollateralized-loan-liquidation (protocol-loan-id uint))
    (let (
        (liquidator-address tx-sender)
        (loan-record (unwrap! (map-get? protocol-loan-registry { protocol-loan-id: protocol-loan-id })
            ERR-REQUESTED-LOAN-NOT-FOUND))
    )
    (begin
        ;; Validate protocol-loan-id
        (asserts! (< protocol-loan-id (var-get protocol-total-loan-count)) ERR-REQUESTED-LOAN-NOT-FOUND)
        
        ;; Additional validation checks
        (asserts! (is-eq (get current-loan-state loan-record) "active") ERR-REQUESTED-LOAN-NOT-FOUND)
        (asserts! (< (/ (* (get deposited-collateral-amount loan-record) u10000)
                        (get loan-principal-amount loan-record))
                    (var-get minimum-liquidation-threshold-bps))
            ERR-LOAN-NOT-ELIGIBLE-LIQUIDATION)
        
        ;; Transfer collateral to liquidator
        (try! (as-contract (stx-transfer? (get deposited-collateral-amount loan-record) tx-sender liquidator-address)))
        
        ;; Update loan record
        (map-set protocol-loan-registry
            { protocol-loan-id: protocol-loan-id }
            (merge loan-record { current-loan-state: "liquidated" })
        )
        
        ;; Update borrower's account state
        (map-set protocol-user-account-state
            (get borrower-address loan-record)
            (merge (default-to
                { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                (map-get? protocol-user-account-state (get borrower-address loan-record)))
                {
                    current-borrowed-principal: (- (get current-borrowed-principal 
                        (default-to
                            { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                            (map-get? protocol-user-account-state (get borrower-address loan-record))))
                        (get loan-principal-amount loan-record)),
                    current-locked-collateral: (- (get current-locked-collateral 
                        (default-to
                            { current-lending-pool-balance: u0, current-borrowed-principal: u0, current-locked-collateral: u0 }
                            (map-get? protocol-user-account-state (get borrower-address loan-record))))
                        (get deposited-collateral-amount loan-record))
                }
            )
        )
        (ok true)
    ))
)

;; Read-only functions
(define-read-only (get-loan-details (protocol-loan-id uint))
    (map-get? protocol-loan-registry { protocol-loan-id: protocol-loan-id })
)

(define-read-only (get-user-account-details (user-address principal))
    (map-get? protocol-user-account-state user-address)
)

(define-read-only (get-protocol-interest-rate)
    (var-get protocol-interest-rate-yearly-bps)
)

(define-read-only (get-protocol-collateral-requirement)
    (var-get minimum-required-collateral-ratio-bps)
)

(define-read-only (get-protocol-liquidation-threshold)
    (var-get minimum-liquidation-threshold-bps)
)

(define-read-only (get-total-loan-count)
    (var-get protocol-total-loan-count)
)