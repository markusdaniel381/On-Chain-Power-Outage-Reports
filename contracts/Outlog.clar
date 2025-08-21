(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-duration (err u106))
(define-constant err-already-resolved (err u107))

(define-data-var next-outage-id uint u1)
(define-data-var total-compensation-pool uint u0)
(define-data-var base-compensation-rate uint u1000000)
(define-data-var verification-threshold uint u3)

(define-map outage-reports
  { outage-id: uint }
  {
    reporter: principal,
    affected-area: (string-ascii 64),
    start-block: uint,
    end-block: (optional uint),
    severity: uint,
    description: (string-ascii 256),
    status: (string-ascii 20),
    verifications: uint,
    compensation-claimed: bool,
    total-affected: uint
  }
)

(define-map user-verifications
  { outage-id: uint, verifier: principal }
  { verified: bool, verification-block: uint }
)

(define-map user-claims
  { outage-id: uint, claimant: principal }
  { 
    claimed: bool,
    compensation-amount: uint,
    claim-block: uint
  }
)

(define-map authorized-utilities
  { utility: principal }
  { authorized: bool, name: (string-ascii 32) }
)

(define-map utility-deposits
  { utility: principal }
  { deposit-amount: uint }
)

(define-public (authorize-utility (utility principal) (name (string-ascii 32)))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-utilities { utility: utility } { authorized: true, name: name }))
  )
)

(define-public (revoke-utility (utility principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (ok (map-set authorized-utilities { utility: utility } { authorized: false, name: "" }))
  )
)

(define-public (deposit-compensation (amount uint))
  (let ((current-deposit (default-to u0 (get deposit-amount (map-get? utility-deposits { utility: tx-sender })))))
    (asserts! (is-some (map-get? authorized-utilities { utility: tx-sender })) err-unauthorized)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (map-set utility-deposits { utility: tx-sender } { deposit-amount: (+ current-deposit amount) })
    (var-set total-compensation-pool (+ (var-get total-compensation-pool) amount))
    (ok amount)
  )
)

(define-public (report-outage (affected-area (string-ascii 64)) (severity uint) (description (string-ascii 256)) (total-affected uint))
  (let ((outage-id (var-get next-outage-id)))
    (asserts! (is-some (map-get? authorized-utilities { utility: tx-sender })) err-unauthorized)
    (asserts! (and (>= severity u1) (<= severity u5)) err-invalid-status)
    (asserts! (> total-affected u0) err-invalid-status)
    (map-set outage-reports
      { outage-id: outage-id }
      {
        reporter: tx-sender,
        affected-area: affected-area,
        start-block: stacks-block-height,
        end-block: none,
        severity: severity,
        description: description,
        status: "active",
        verifications: u0,
        compensation-claimed: false,
        total-affected: total-affected
      }
    )
    (var-set next-outage-id (+ outage-id u1))
    (ok outage-id)
  )
)

(define-public (resolve-outage (outage-id uint))
  (let ((outage (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get reporter outage)) err-unauthorized)
    (asserts! (is-eq (get status outage) "active") err-already-resolved)
    (map-set outage-reports
      { outage-id: outage-id }
      (merge outage { 
        status: "resolved", 
        end-block: (some stacks-block-height)
      })
    )
    (ok true)
  )
)

(define-public (verify-outage (outage-id uint))
  (let ((outage (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found))
        (existing-verification (map-get? user-verifications { outage-id: outage-id, verifier: tx-sender })))
    (asserts! (is-none existing-verification) err-already-exists)
    (asserts! (not (is-eq tx-sender (get reporter outage))) err-unauthorized)
    (map-set user-verifications 
      { outage-id: outage-id, verifier: tx-sender }
      { verified: true, verification-block: stacks-block-height }
    )
    (map-set outage-reports
      { outage-id: outage-id }
      (merge outage { verifications: (+ (get verifications outage) u1) })
    )
    (ok true)
  )
)

(define-public (claim-compensation (outage-id uint))
  (let ((outage (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found))
        (existing-claim (map-get? user-claims { outage-id: outage-id, claimant: tx-sender }))
        (compensation-amount (calculate-compensation outage-id)))
    (asserts! (is-none existing-claim) err-already-exists)
    (asserts! (>= (get verifications outage) (var-get verification-threshold)) err-invalid-status)
    (asserts! (is-eq (get status outage) "resolved") err-invalid-status)
    (asserts! (> compensation-amount u0) err-insufficient-funds)
    (asserts! (<= compensation-amount (var-get total-compensation-pool)) err-insufficient-funds)
    
    (try! (as-contract (stx-transfer? compensation-amount tx-sender tx-sender)))
    (var-set total-compensation-pool (- (var-get total-compensation-pool) compensation-amount))
    
    (map-set user-claims
      { outage-id: outage-id, claimant: tx-sender }
      {
        claimed: true,
        compensation-amount: compensation-amount,
        claim-block: stacks-block-height
      }
    )
    (ok compensation-amount)
  )
)

(define-public (update-compensation-rate (new-rate uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set base-compensation-rate new-rate)
    (ok new-rate)
  )
)

(define-public (update-verification-threshold (new-threshold uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (> new-threshold u0) err-invalid-status)
    (var-set verification-threshold new-threshold)
    (ok new-threshold)
  )
)

(define-read-only (get-outage-details (outage-id uint))
  (map-get? outage-reports { outage-id: outage-id })
)

(define-read-only (get-user-verification (outage-id uint) (verifier principal))
  (map-get? user-verifications { outage-id: outage-id, verifier: verifier })
)

(define-read-only (get-user-claim (outage-id uint) (claimant principal))
  (map-get? user-claims { outage-id: outage-id, claimant: claimant })
)

(define-read-only (is-utility-authorized (utility principal))
  (default-to false (get authorized (map-get? authorized-utilities { utility: utility })))
)

(define-read-only (get-utility-deposit (utility principal))
  (default-to u0 (get deposit-amount (map-get? utility-deposits { utility: utility })))
)

(define-read-only (get-total-compensation-pool)
  (var-get total-compensation-pool)
)

(define-read-only (get-next-outage-id)
  (var-get next-outage-id)
)

(define-read-only (get-base-compensation-rate)
  (var-get base-compensation-rate)
)

(define-read-only (get-verification-threshold)
  (var-get verification-threshold)
)

(define-read-only (calculate-compensation (outage-id uint))
  (let ((outage (unwrap! (map-get? outage-reports { outage-id: outage-id }) u0)))
    (let ((duration-blocks (match (get end-block outage)
                             end-block (- end-block (get start-block outage))
                             u0))
          (severity-multiplier (get severity outage))
          (affected-multiplier (if (<= (get total-affected outage) u1000) 
                                    (get total-affected outage) 
                                    u1000)))
      (* (* (var-get base-compensation-rate) severity-multiplier) 
         (* duration-blocks affected-multiplier) 
         u1))))

(define-read-only (get-outage-duration (outage-id uint))
  (let ((outage (unwrap! (map-get? outage-reports { outage-id: outage-id }) u0)))
    (match (get end-block outage)
      end-block (- end-block (get start-block outage))
      (if (is-eq (get status outage) "active")
          (- stacks-block-height (get start-block outage))
          u0))))

(define-read-only (is-outage-verified (outage-id uint))
  (match (map-get? outage-reports { outage-id: outage-id })
    outage (>= (get verifications outage) (var-get verification-threshold))
    false))

(define-read-only (get-contract-balance)
  (stx-get-balance (as-contract tx-sender)))
