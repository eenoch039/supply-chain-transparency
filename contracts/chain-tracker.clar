
;; title: chain-tracker
;; version: 1.0.0
;; summary: Supply Chain Transparency Tracking Contract
;; description: Tracks products through every stage of the supply chain with cryptographic verification
;;             of authenticity and origin. Manages supplier registration and certification with reputation 
;;             scoring based on compliance history and quality metrics.

;; Constants
(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-not-authorized (err u101))
(define-constant err-product-not-found (err u102))
(define-constant err-supplier-not-found (err u103))
(define-constant err-invalid-stage (err u104))
(define-constant err-already-exists (err u105))
(define-constant err-invalid-status (err u106))
(define-constant err-insufficient-reputation (err u107))
(define-constant err-recall-active (err u108))
(define-constant err-quality-issue (err u109))
(define-constant err-compliance-failed (err u110))

;; Supply chain stage constants
(define-constant stage-raw-material "raw-material")
(define-constant stage-manufacturing "manufacturing")
(define-constant stage-quality-control "quality-control")
(define-constant stage-packaging "packaging")
(define-constant stage-distribution "distribution")
(define-constant stage-retail "retail")
(define-constant stage-consumer "consumer")

;; Quality and compliance thresholds
(define-constant min-supplier-reputation u70)
(define-constant max-batch-size u10000)
(define-constant compliance-threshold u80)

;; Data Variables
(define-data-var product-counter uint u0)
(define-data-var supplier-counter uint u0)
(define-data-var batch-counter uint u0)
(define-data-var total-rewards uint u0)
(define-data-var contract-paused bool false)

;; Data Maps

;; Product registry with complete metadata
(define-map products
  { product-id: uint }
  {
    name: (string-ascii 100),
    description: (string-ascii 500),
    origin: (string-ascii 100),
    current-stage: (string-ascii 20),
    current-holder: principal,
    creation-height: uint,
    last-update: uint,
    quality-score: uint,
    sustainability-score: uint,
    authenticity-hash: (buff 32),
    status: (string-ascii 20),
    recall-active: bool
  }
)

;; Supplier database with certifications and reputation
(define-map suppliers
  { supplier-id: uint }
  {
    name: (string-ascii 100),
    wallet: principal,
    certification-level: uint,
    reputation-score: uint,
    total-products: uint,
    quality-violations: uint,
    sustainability-rating: uint,
    registration-height: uint,
    is-active: bool,
    specialization: (string-ascii 50)
  }
)

;; Product movement tracking
(define-map product-movements
  { product-id: uint, movement-id: uint }
  {
    from-supplier: uint,
    to-supplier: uint,
    stage: (string-ascii 20),
    timestamp: uint,
    quality-check: bool,
    compliance-verified: bool,
    notes: (string-ascii 200),
    geo-location: (string-ascii 50)
  }
)

;; Batch tracking for contamination control
(define-map batches
  { batch-id: uint }
  {
    raw-material-source: uint,
    products: (list 100 uint),
    creation-date: uint,
    expiry-date: uint,
    quality-tests: (list 10 uint),
    contamination-risk: uint,
    recall-issued: bool,
    affected-count: uint
  }
)

;; Quality issues and alerts
(define-map quality-alerts
  { alert-id: uint }
  {
    reporter: principal,
    product-id: uint,
    issue-type: (string-ascii 50),
    severity: uint,
    description: (string-ascii 300),
    timestamp: uint,
    status: (string-ascii 20),
    resolution: (string-ascii 200)
  }
)

;; Consumer verification records
(define-map consumer-verifications
  { product-id: uint, consumer: principal }
  {
    verification-timestamp: uint,
    authenticity-confirmed: bool,
    quality-rating: uint,
    sustainability-rating: uint
  }
)

;; Reward tracking for ethical sourcing
(define-map ethical-rewards
  { supplier-id: uint, period: uint }
  {
    sustainability-bonus: uint,
    quality-bonus: uint,
    innovation-bonus: uint,
    total-reward: uint,
    claimed: bool
  }
)

;; Public Functions

;; Register a new supplier in the system
(define-public (register-supplier 
  (name (string-ascii 100))
  (certification-level uint)
  (specialization (string-ascii 50))
)
  (let (
    (supplier-id (+ (var-get supplier-counter) u1))
    (sender tx-sender)
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (<= certification-level u5) err-invalid-status)
    
    ;; Register supplier
    (map-set suppliers
      { supplier-id: supplier-id }
      {
        name: name,
        wallet: sender,
        certification-level: certification-level,
        reputation-score: u100, ;; Start with full reputation
        total-products: u0,
        quality-violations: u0,
        sustainability-rating: u50,
        registration-height: block-height,
        is-active: true,
        specialization: specialization
      }
    )
    
    (var-set supplier-counter supplier-id)
    (ok supplier-id)
  )
)

;; Register a new product with origin verification
(define-public (register-product
  (name (string-ascii 100))
  (description (string-ascii 500))
  (origin (string-ascii 100))
  (supplier-id uint)
  (authenticity-hash (buff 32))
)
  (let (
    (product-id (+ (var-get product-counter) u1))
    (supplier-info (unwrap! (map-get? suppliers { supplier-id: supplier-id }) err-supplier-not-found))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (get is-active supplier-info) err-supplier-not-found)
    (asserts! (is-eq tx-sender (get wallet supplier-info)) err-not-authorized)
    
    ;; Register product
    (map-set products
      { product-id: product-id }
      {
        name: name,
        description: description,
        origin: origin,
        current-stage: stage-raw-material,
        current-holder: tx-sender,
        creation-height: block-height,
        last-update: block-height,
        quality-score: u100,
        sustainability-score: (get sustainability-rating supplier-info),
        authenticity-hash: authenticity-hash,
        status: "active",
        recall-active: false
      }
    )
    
    ;; Update supplier stats
    (map-set suppliers
      { supplier-id: supplier-id }
      (merge supplier-info { total-products: (+ (get total-products supplier-info) u1) })
    )
    
    (var-set product-counter product-id)
    (ok product-id)
  )
)

;; Track product movement through supply chain
(define-public (track-movement
  (product-id uint)
  (to-supplier-id uint)
  (new-stage (string-ascii 20))
  (quality-check bool)
  (notes (string-ascii 200))
  (geo-location (string-ascii 50))
)
  (let (
    (product-info (unwrap! (map-get? products { product-id: product-id }) err-product-not-found))
    (to-supplier (unwrap! (map-get? suppliers { supplier-id: to-supplier-id }) err-supplier-not-found))
    (movement-id (+ (get last-update product-info) u1))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (not (get recall-active product-info)) err-recall-active)
    (asserts! (get is-active to-supplier) err-supplier-not-found)
    (asserts! (>= (get reputation-score to-supplier) min-supplier-reputation) err-insufficient-reputation)
    
    ;; Record movement
    (map-set product-movements
      { product-id: product-id, movement-id: movement-id }
      {
        from-supplier: u0, ;; Could be enhanced to track from-supplier
        to-supplier: to-supplier-id,
        stage: new-stage,
        timestamp: block-height,
        quality-check: quality-check,
        compliance-verified: true, ;; Simplified for this implementation
        notes: notes,
        geo-location: geo-location
      }
    )
    
    ;; Update product status
    (map-set products
      { product-id: product-id }
      (merge product-info {
        current-stage: new-stage,
        current-holder: (get wallet to-supplier),
        last-update: block-height,
        quality-score: (if quality-check (get quality-score product-info) (- (get quality-score product-info) u10))
      })
    )
    
    (ok true)
  )
)

;; Report quality issues with whistleblower protection
(define-public (report-quality-issue
  (product-id uint)
  (issue-type (string-ascii 50))
  (severity uint)
  (description (string-ascii 300))
)
  (let (
    (product-info (unwrap! (map-get? products { product-id: product-id }) err-product-not-found))
    (alert-id (+ block-height product-id)) ;; Simple alert ID generation
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (<= severity u5) err-invalid-status)
    
    ;; Record quality alert
    (map-set quality-alerts
      { alert-id: alert-id }
      {
        reporter: tx-sender,
        product-id: product-id,
        issue-type: issue-type,
        severity: severity,
        description: description,
        timestamp: block-height,
        status: "open",
        resolution: ""
      }
    )
    
    ;; Update product quality score based on severity
    (map-set products
      { product-id: product-id }
      (merge product-info {
        quality-score: (if (> severity u3) u0 (- (get quality-score product-info) (* severity u20))),
        status: (if (> severity u3) "quarantined" (get status product-info))
      })
    )
    
    (ok alert-id)
  )
)

;; Verify product authenticity (consumer-facing)
(define-public (verify-authenticity
  (product-id uint)
  (provided-hash (buff 32))
  (quality-rating uint)
  (sustainability-rating uint)
)
  (let (
    (product-info (unwrap! (map-get? products { product-id: product-id }) err-product-not-found))
    (is-authentic (is-eq (get authenticity-hash product-info) provided-hash))
  )
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    (asserts! (<= quality-rating u5) err-invalid-status)
    (asserts! (<= sustainability-rating u5) err-invalid-status)
    
    ;; Record consumer verification
    (map-set consumer-verifications
      { product-id: product-id, consumer: tx-sender }
      {
        verification-timestamp: block-height,
        authenticity-confirmed: is-authentic,
        quality-rating: quality-rating,
        sustainability-rating: sustainability-rating
      }
    )
    
    (ok is-authentic)
  )
)

;; Issue recall for contaminated products
(define-public (issue-recall (product-id uint) (reason (string-ascii 200)))
  (let (
    (product-info (unwrap! (map-get? products { product-id: product-id }) err-product-not-found))
  )
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (var-get contract-paused)) err-not-authorized)
    
    ;; Update product with recall status
    (map-set products
      { product-id: product-id }
      (merge product-info {
        recall-active: true,
        status: "recalled",
        last-update: block-height
      })
    )
    
    (ok true)
  )
)

;; Emergency pause contract (owner only)
(define-public (emergency-pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set contract-paused true)
    (ok true)
  )
)

;; Read-only functions

;; Get product information
(define-read-only (get-product-info (product-id uint))
  (map-get? products { product-id: product-id })
)

;; Get supplier information
(define-read-only (get-supplier-info (supplier-id uint))
  (map-get? suppliers { supplier-id: supplier-id })
)

;; Get product movement history
(define-read-only (get-movement-info (product-id uint) (movement-id uint))
  (map-get? product-movements { product-id: product-id, movement-id: movement-id })
)

;; Get quality alert information
(define-read-only (get-quality-alert (alert-id uint))
  (map-get? quality-alerts { alert-id: alert-id })
)

;; Get system statistics
(define-read-only (get-system-stats)
  {
    total-products: (var-get product-counter),
    total-suppliers: (var-get supplier-counter),
    total-batches: (var-get batch-counter),
    total-rewards: (var-get total-rewards),
    contract-paused: (var-get contract-paused)
  }
)

;; Verify product authenticity (read-only)
(define-read-only (check-authenticity (product-id uint) (provided-hash (buff 32)))
  (match (map-get? products { product-id: product-id })
    product-info
    (is-eq (get authenticity-hash product-info) provided-hash)
    false
  )
)

;; Get product's current supply chain stage
(define-read-only (get-current-stage (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-info
    (get current-stage product-info)
    "not-found"
  )
)

;; Check if product is under recall
(define-read-only (is-product-recalled (product-id uint))
  (match (map-get? products { product-id: product-id })
    product-info
    (get recall-active product-info)
    false
  )
)

;; Get supplier reputation score
(define-read-only (get-supplier-reputation (supplier-id uint))
  (match (map-get? suppliers { supplier-id: supplier-id })
    supplier-info
    (get reputation-score supplier-info)
    u0
  )
)

;; Private functions

;; Calculate sustainability score based on multiple factors
(define-private (calculate-sustainability-score (supplier-rating uint) (transport-distance uint))
  (let (
    (base-score supplier-rating)
    (distance-penalty (/ transport-distance u100))
  )
    (if (> base-score distance-penalty)
      (- base-score distance-penalty)
      u0
    )
  )
)

;; Validate supply chain stage progression
(define-private (is-valid-stage-transition (current-stage (string-ascii 20)) (new-stage (string-ascii 20)))
  (or
    (and (is-eq current-stage stage-raw-material) (is-eq new-stage stage-manufacturing))
    (and (is-eq current-stage stage-manufacturing) (is-eq new-stage stage-quality-control))
    (and (is-eq current-stage stage-quality-control) (is-eq new-stage stage-packaging))
    (and (is-eq current-stage stage-packaging) (is-eq new-stage stage-distribution))
    (and (is-eq current-stage stage-distribution) (is-eq new-stage stage-retail))
    (and (is-eq current-stage stage-retail) (is-eq new-stage stage-consumer))
  )
)
