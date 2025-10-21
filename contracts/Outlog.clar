(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-found (err u101))
(define-constant err-already-exists (err u102))
(define-constant err-invalid-status (err u103))
(define-constant err-insufficient-funds (err u104))
(define-constant err-unauthorized (err u105))
(define-constant err-invalid-duration (err u106))
(define-constant err-already-resolved (err u107))
(define-constant err-already-escalated (err u108))
(define-constant err-too-early (err u109))
(define-constant err-invalid-resolution (err u110))
(define-constant err-appeal-cooldown (err u111))

(define-data-var next-outage-id uint u1)
(define-data-var total-compensation-pool uint u0)
(define-data-var base-compensation-rate uint u1000000)
(define-data-var verification-threshold uint u3)
(define-data-var escalation-deadline-blocks uint u144)
(define-data-var critical-population-threshold uint u1000)
(define-data-var penalty-amount uint u5000000)

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

(define-map escalations
  { outage-id: uint }
  {
    escalator: principal,
    escalation-block: uint,
    status: (string-ascii 20),
    penalty-applied: bool
  }
)

(define-map utility-penalties
  { utility: principal }
  { total-penalties: uint }
)

(define-map utility-reputation
  { utility: principal }
  {
    total-reports: uint,
    total-penalties: uint,
    total-response-blocks: uint,
    reputation-score: uint
  }
)

(define-map emergency-alerts
  { outage-id: uint }
  {
    triggered-by: principal,
    alert-block: uint,
    population-affected: uint
  }
)

(define-map appeal-records
  { outage-id: uint, utility: principal }
  { appealed: bool, appeal-block: uint, outcome: (string-ascii 20) }
)

(define-map utility-appeal-cooldown
  principal
  { last-appeal-block: uint, next-available-block: uint }
)

(define-map appeal-counter
  principal
  uint
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
    (unwrap! (update-reputation tx-sender outage-id false) err-invalid-status)
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

(define-public (escalate-outage (outage-id uint))
  (let ((outage-details (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found)))
    (asserts! (is-none (map-get? escalations { outage-id: outage-id })) err-already-escalated)
    (asserts! (is-eq (get status outage-details) "active") err-already-resolved)
    (asserts! (>= (- stacks-block-height (get start-block outage-details)) (var-get escalation-deadline-blocks)) err-too-early)
    
    (map-set escalations 
      { outage-id: outage-id }
      {
        escalator: tx-sender,
        escalation-block: stacks-block-height,
        status: "escalated",
        penalty-applied: false
      }
    )
    
    (if (>= (get total-affected outage-details) (var-get critical-population-threshold))
        (unwrap! (trigger-emergency-alert outage-id (get total-affected outage-details)) err-invalid-status)
        true
    )
    
    (print { event: "outage-escalated", outage-id: outage-id, escalator: tx-sender })
    (ok outage-id)
  )
)

(define-public (resolve-escalation (outage-id uint) (is-valid-escalation bool))
  (let ((escalation (unwrap! (map-get? escalations { outage-id: outage-id }) err-not-found))
        (outage-details (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found)))
    (asserts! (is-eq tx-sender (get reporter outage-details)) err-unauthorized)
    (asserts! (is-eq (get status escalation) "escalated") err-already-resolved)
    
    (map-set escalations
      { outage-id: outage-id }
      (merge escalation { status: "resolved" })
    )
    
    (if is-valid-escalation
        (begin
          (unwrap! (apply-penalty (get reporter outage-details) outage-id) err-invalid-status)
          (unwrap! (update-reputation (get reporter outage-details) outage-id true) err-invalid-status)
        )
        (unwrap! (update-reputation (get reporter outage-details) outage-id false) err-invalid-status)
    )
    
    (print { event: "escalation-resolved", outage-id: outage-id, valid: is-valid-escalation })
    (ok is-valid-escalation)
  )
)

(define-public (auto-penalize-overdue (outage-id uint))
  (let ((escalation (unwrap! (map-get? escalations { outage-id: outage-id }) err-not-found))
        (outage-details (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found)))
    (asserts! (>= (- stacks-block-height (get escalation-block escalation)) u72) err-too-early)
    (asserts! (is-eq (get status escalation) "escalated") err-already-resolved)
    (asserts! (not (get penalty-applied escalation)) err-already-resolved)
    
    (map-set escalations
      { outage-id: outage-id }
      (merge escalation { 
        status: "auto-penalized",
        penalty-applied: true 
      })
    )
    
    (unwrap! (apply-penalty (get reporter outage-details) outage-id) err-invalid-status)
    (unwrap! (update-reputation (get reporter outage-details) outage-id true) err-invalid-status)
    
    (print { event: "auto-penalty-applied", outage-id: outage-id, utility: (get reporter outage-details) })
    (ok true)
  )
)

(define-public (appeal-escalation (outage-id uint))
  (let (
    (utility tx-sender)
    (outage-data (unwrap! (map-get? outage-reports { outage-id: outage-id }) err-not-found))
    (escalation-data (map-get? escalations { outage-id: outage-id }))
    (cooldown-data (map-get? utility-appeal-cooldown utility))
    (current-block stacks-block-height)
    (appeal-exists (map-get? appeal-records { outage-id: outage-id, utility: utility }))
  )
    (asserts! (is-eq (get reporter outage-data) utility) err-unauthorized)
    (asserts! (is-some escalation-data) err-not-found)
    (asserts! (is-none appeal-exists) err-already-exists)
    (asserts! 
      (or 
        (is-none cooldown-data)
        (>= current-block (get next-available-block (unwrap! cooldown-data err-appeal-cooldown)))
      )
      err-appeal-cooldown
    )
    (map-set appeal-records
      { outage-id: outage-id, utility: utility }
      { appealed: true, appeal-block: current-block, outcome: "pending" }
    )
    (map-set utility-appeal-cooldown
      utility
      { last-appeal-block: current-block, next-available-block: (+ current-block u50) }
    )
    (map-set appeal-counter
      utility
      (+ (default-to u0 (map-get? appeal-counter utility)) u1)
    )
    (print { event: "escalation-appealed", outage-id: outage-id, utility: utility })
    (ok true)
  )
)

(define-private (trigger-emergency-alert (outage-id uint) (population-affected uint))
  (begin
    (map-set emergency-alerts
      { outage-id: outage-id }
      {
        triggered-by: tx-sender,
        alert-block: stacks-block-height,
        population-affected: population-affected
      }
    )
    (print { event: "emergency-alert", outage-id: outage-id, population: population-affected })
    (ok true)
  )
)

(define-private (apply-penalty (utility principal) (outage-id uint))
  (let ((current-penalties (default-to u0 (get total-penalties (map-get? utility-penalties { utility: utility }))))
        (is-emergency (is-some (map-get? emergency-alerts { outage-id: outage-id })))
        (penalty-final (if is-emergency (* (var-get penalty-amount) u3) (var-get penalty-amount))))
    (map-set utility-penalties
      { utility: utility }
      { total-penalties: (+ current-penalties penalty-final) }
    )
    (print { event: "penalty-applied", utility: utility, amount: penalty-final })
    (ok penalty-final)
  )
)

(define-private (update-reputation (utility principal) (outage-id uint) (penalized bool))
  (let ((current-rep (default-to 
                       { total-reports: u0, total-penalties: u0, total-response-blocks: u0, reputation-score: u1000 }
                       (map-get? utility-reputation { utility: utility })))
        (outage-details (unwrap! (map-get? outage-reports { outage-id: outage-id }) (err u999)))
        (response-blocks (match (get end-block outage-details)
                           end-block (- end-block (get start-block outage-details))
                           (- stacks-block-height (get start-block outage-details))))
        (new-penalties (if penalized (+ (get total-penalties current-rep) u1) (get total-penalties current-rep)))
        (new-reports (+ (get total-reports current-rep) u1))
        (new-total-blocks (+ (get total-response-blocks current-rep) response-blocks))
        (avg-response (if (> new-reports u0) (/ new-total-blocks new-reports) u0))
        (penalty-ratio (if (> new-reports u0) (/ (* new-penalties u100) new-reports) u0))
        (response-score (if (> avg-response u144) u0 (- u1000 (* (/ avg-response u144) u800))))
        (penalty-score (if (> penalty-ratio u20) u0 (- u1000 (* penalty-ratio u40))))
        (final-score (/ (+ response-score penalty-score) u2)))
    
    (map-set utility-reputation
      { utility: utility }
      {
        total-reports: new-reports,
        total-penalties: new-penalties,
        total-response-blocks: new-total-blocks,
        reputation-score: final-score
      }
    )
    (print { event: "reputation-updated", utility: utility, score: final-score })
    (ok final-score)
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

(define-read-only (get-escalation-details (outage-id uint))
  (map-get? escalations { outage-id: outage-id })
)

(define-read-only (get-utility-penalties (utility principal))
  (default-to u0 (get total-penalties (map-get? utility-penalties { utility: utility })))
)

(define-read-only (get-utility-reputation (utility principal))
  (default-to 
    { total-reports: u0, total-penalties: u0, total-response-blocks: u0, reputation-score: u1000 }
    (map-get? utility-reputation { utility: utility })
  )
)

(define-read-only (get-emergency-alert (outage-id uint))
  (map-get? emergency-alerts { outage-id: outage-id })
)

(define-read-only (can-escalate-outage (outage-id uint))
  (match (map-get? outage-reports { outage-id: outage-id })
    outage-details (and
                     (is-eq (get status outage-details) "active")
                     (is-none (map-get? escalations { outage-id: outage-id }))
                     (>= (- stacks-block-height (get start-block outage-details)) (var-get escalation-deadline-blocks)))
    false)
)

(define-read-only (is-escalation-overdue (outage-id uint))
  (match (map-get? escalations { outage-id: outage-id })
    escalation (and 
                 (is-eq (get status escalation) "escalated")
                 (>= (- stacks-block-height (get escalation-block escalation)) u72))
    false)
)

(define-read-only (get-reputation-score (utility principal))
  (default-to u1000 (get reputation-score (map-get? utility-reputation { utility: utility })))
)

(define-read-only (get-escalation-deadline)
  (var-get escalation-deadline-blocks)
)

(define-read-only (get-penalty-amount)
  (var-get penalty-amount)
)

(define-read-only (get-critical-threshold)
  (var-get critical-population-threshold)
)

(define-read-only (can-utility-appeal (utility principal))
  (let (
    (cooldown-data (map-get? utility-appeal-cooldown utility))
    (current-block stacks-block-height)
  )
(match cooldown-data
      cooldown-info (>= current-block (get next-available-block cooldown-info))
      true
    )
  )
)

(define-read-only (get-appeal-record (outage-id uint) (utility principal))
  (map-get? appeal-records { outage-id: outage-id, utility: utility })
)

(define-read-only (get-utility-appeal-count (utility principal))
  (default-to u0 (map-get? appeal-counter utility))
)

(define-read-only (get-utility-cooldown-info (utility principal))
  (map-get? utility-appeal-cooldown utility)
)
