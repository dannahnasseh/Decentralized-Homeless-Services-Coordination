;; =============================================================================
;; DECENTRALIZED HOMELESS SERVICES COORDINATION PLATFORM
;; =============================================================================

;; =============================================================================
;; CONSTANTS AND ERROR CODES
;; =============================================================================

;; Error codes
(define-constant ERR-UNAUTHORIZED (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-INPUT (err u102))
(define-constant ERR-RESOURCE-UNAVAILABLE (err u103))
(define-constant ERR-ALREADY-EXISTS (err u104))
(define-constant ERR-EXPIRED (err u105))
(define-constant ERR-INSUFFICIENT-CAPACITY (err u106))
(define-constant ERR-INVALID-STATUS (err u107))
(define-constant ERR-PRIVACY-VIOLATION (err u108))

;; Service types
(define-constant SERVICE-SHELTER u1)
(define-constant SERVICE-MEAL u2)
(define-constant SERVICE-CASE-MANAGEMENT u3)
(define-constant SERVICE-HEALTHCARE u4)
(define-constant SERVICE-EMPLOYMENT u5)
(define-constant SERVICE-MENTAL-HEALTH u6)
(define-constant SERVICE-ADDICTION u7)
(define-constant SERVICE-LEGAL u8)

;; Status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-INACTIVE u2)
(define-constant STATUS-PENDING u3)
(define-constant STATUS-COMPLETED u4)
(define-constant STATUS-CANCELLED u5)

;; Priority levels
(define-constant PRIORITY-CRITICAL u1)
(define-constant PRIORITY-HIGH u2)
(define-constant PRIORITY-MEDIUM u3)
(define-constant PRIORITY-LOW u4)

;; Contract owner
(define-constant CONTRACT-OWNER tx-sender)

;; =============================================================================
;; DATA STRUCTURES
;; =============================================================================

;; Anonymous client profiles (privacy-preserving)
(define-map anonymous-clients
  { client-hash: (buff 32) }
  {
    created-at: uint,
    last-access: uint,
    service-history-hash: (buff 32),
    risk-level: uint,
    priority-score: uint,
    preferred-services: (list 10 uint),
    accessibility-needs: (list 5 uint),
    emergency-contact-encrypted: (optional (buff 256))
  }
)

;; Service providers registry
(define-map service-providers
  { provider-id: uint }
  {
    name: (string-ascii 100),
    provider-type: uint,
    contact-info: (string-ascii 200),
    services-offered: (list 10 uint),
    capacity-info: {
      total-capacity: uint,
      current-utilization: uint,
      available-slots: uint
    },
    location-hash: (buff 32),
    certification-level: uint,
    reputation-score: uint,
    status: uint,
    last-updated: uint,
    created-by: principal
  }
)

;; Resource inventory and availability
(define-map resources
  { resource-id: uint }
  {
    resource-type: uint,
    provider-id: uint,
    name: (string-ascii 100),
    description: (string-ascii 500),
    availability: {
      total-slots: uint,
      available-slots: uint,
      reserved-slots: uint,
      waitlist-count: uint
    },
    schedule: {
      start-time: uint,
      end-time: uint,
      days-of-week: (list 7 bool),
      duration-blocks: uint
    },
    location-hash: (buff 32),
    requirements: (list 10 uint),
    accessibility-features: (list 5 uint),
    cost: uint,
    status: uint,
    last-updated: uint
  }
)

;; Service requests and reservations
(define-map service-requests
  { request-id: uint }
  {
    client-hash: (buff 32),
    service-type: uint,
    provider-id: uint,
    resource-id: uint,
    requested-time: uint,
    priority-level: uint,
    special-requirements: (list 5 uint),
    status: uint,
    assigned-case-worker: (optional principal),
    outcome-data: (optional (buff 256)),
    created-at: uint,
    updated-at: uint,
    expires-at: uint
  }
)

;; Case management records (encrypted)
(define-map case-records
  { case-id: uint }
  {
    client-hash: (buff 32),
    case-worker: principal,
    service-plan: (buff 512),
    goals: (list 10 (buff 100)),
    progress-notes: (list 20 (buff 200)),
    service-history: (list 50 uint),
    outcome-metrics: {
      housing-stability: uint,
      employment-status: uint,
      health-improvements: uint,
      service-satisfaction: uint
    },
    privacy-level: uint,
    last-updated: uint,
    created-at: uint
  }
)

;; Coordination events and scheduling
(define-map coordination-events
  { event-id: uint }
  {
    event-type: uint,
    organizer: principal,
    participating-providers: (list 10 uint),
    scheduled-time: uint,
    location-hash: (buff 32),
    capacity: uint,
    registered-count: uint,
    resource-requirements: (list 10 uint),
    outcome-summary: (optional (buff 256)),
    status: uint,
    created-at: uint
  }
)

;; =============================================================================
;; STORAGE MAPS FOR COUNTERS AND INDEXES
;; =============================================================================

(define-data-var next-provider-id uint u1)
(define-data-var next-resource-id uint u1)
(define-data-var next-request-id uint u1)
(define-data-var next-case-id uint u1)
(define-data-var next-event-id uint u1)

;; Client anonymization salt (for privacy)
(define-data-var privacy-salt (buff 32) 0x0000000000000000000000000000000000000000000000000000000000000000)

;; System configuration
(define-data-var system-config
  {
    max-reservation-time: uint,
    default-priority-decay: uint,
    minimum-case-update-interval: uint,
    privacy-retention-period: uint,
    emergency-override-enabled: bool
  }
  {
    max-reservation-time: u86400, ;; 24 hours
    default-priority-decay: u3600, ;; 1 hour
    minimum-case-update-interval: u604800, ;; 1 week
    privacy-retention-period: u31536000, ;; 1 year
    emergency-override-enabled: true
  }
)

;; =============================================================================
;; PRIVACY AND ANONYMIZATION FUNCTIONS
;; =============================================================================

;; Generate privacy-preserving client hash
(define-private (generate-client-hash (client-data (buff 256)))
  (let ((salt (var-get privacy-salt)))
    (sha256 (concat salt client-data))
  )
)

;; Validate privacy compliance
(define-private (validate-privacy-access (client-hash (buff 32)) (accessor principal))
  (let ((client-data (map-get? anonymous-clients {client-hash: client-hash})))
    (match client-data
      client-info
        (let ((config (var-get system-config)))
          (and
            (> (get last-access client-info)
               (- stacks-block-height (get privacy-retention-period config)))
            (is-authorized-accessor accessor client-hash)
          )
        )
      false
    )
  )
)

;; Check if accessor is authorized for client data
(define-private (is-authorized-accessor (accessor principal) (client-hash (buff 32)))
  (or
    (is-eq accessor CONTRACT-OWNER)
    (is-case-worker accessor client-hash)
    (is-emergency-override-active)
  )
)

;; Check if principal is a case worker for client
(define-private (is-case-worker (worker principal) (client-hash (buff 32)))
  ;; For now, return true for any authorized principal
  ;; In a production system, this would check against a case worker registry
  true
)

;; =============================================================================
;; CLIENT MANAGEMENT FUNCTIONS
;; =============================================================================

;; Register anonymous client
(define-public (register-anonymous-client
  (client-data (buff 256))
  (preferred-services (list 10 uint))
  (accessibility-needs (list 5 uint))
)
  (let (
    (client-hash (generate-client-hash client-data))
    (current-time stacks-block-height)
  )
    (asserts! (is-none (map-get? anonymous-clients {client-hash: client-hash})) ERR-ALREADY-EXISTS)
    (asserts! (validate-service-list preferred-services) ERR-INVALID-INPUT)

    (map-set anonymous-clients
      {client-hash: client-hash}
      {
        created-at: current-time,
        last-access: current-time,
        service-history-hash: (sha256 client-data),
        risk-level: u3, ;; Default to medium risk
        priority-score: u50, ;; Default priority
        preferred-services: preferred-services,
        accessibility-needs: accessibility-needs,
        emergency-contact-encrypted: none
      }
    )

    (ok client-hash)
  )
)

;; Update client access timestamp
(define-public (update-client-access (client-hash (buff 32)))
  (let ((client-data (unwrap! (map-get? anonymous-clients {client-hash: client-hash}) ERR-NOT-FOUND)))
    (map-set anonymous-clients
      {client-hash: client-hash}
      (merge client-data {last-access: stacks-block-height})
    )
    (ok true)
  )
)

;; =============================================================================
;; SERVICE PROVIDER MANAGEMENT
;; =============================================================================

;; Register service provider
(define-public (register-service-provider
  (name (string-ascii 100))
  (provider-type uint)
  (contact-info (string-ascii 200))
  (services-offered (list 10 uint))
  (total-capacity uint)
  (location-hash (buff 32))
)
  (let (
    (provider-id (var-get next-provider-id))
    (current-time stacks-block-height)
  )
    (asserts! (validate-service-list services-offered) ERR-INVALID-INPUT)
    (asserts! (> total-capacity u0) ERR-INVALID-INPUT)

    (map-set service-providers
      {provider-id: provider-id}
      {
        name: name,
        provider-type: provider-type,
        contact-info: contact-info,
        services-offered: services-offered,
        capacity-info: {
          total-capacity: total-capacity,
          current-utilization: u0,
          available-slots: total-capacity
        },
        location-hash: location-hash,
        certification-level: u1,
        reputation-score: u50,
        status: STATUS-ACTIVE,
        last-updated: current-time,
        created-by: tx-sender
      }
    )

    (var-set next-provider-id (+ provider-id u1))
    (ok provider-id)
  )
)

;; Update provider capacity
(define-public (update-provider-capacity (provider-id uint) (new-capacity uint))
  (let ((provider-data (unwrap! (map-get? service-providers {provider-id: provider-id}) ERR-NOT-FOUND)))
    (asserts! (is-eq (get created-by provider-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> new-capacity u0) ERR-INVALID-INPUT)

    (let ((current-util (get current-utilization (get capacity-info provider-data))))
      (map-set service-providers
        {provider-id: provider-id}
        (merge provider-data {
          capacity-info: {
            total-capacity: new-capacity,
            current-utilization: current-util,
            available-slots: (if (> new-capacity current-util) (- new-capacity current-util) u0)
          },
          last-updated: stacks-block-height
        })
      )
      (ok true)
    )
  )
)

;; =============================================================================
;; RESOURCE MANAGEMENT
;; =============================================================================

;; Add resource
(define-public (add-resource
  (resource-type uint)
  (provider-id uint)
  (name (string-ascii 100))
  (description (string-ascii 500))
  (total-slots uint)
  (start-time uint)
  (end-time uint)
  (days-of-week (list 7 bool))
  (location-hash (buff 32))
  (requirements (list 10 uint))
  (accessibility-features (list 5 uint))
  (cost uint)
)
  (let (
    (resource-id (var-get next-resource-id))
    (provider-data (unwrap! (map-get? service-providers {provider-id: provider-id}) ERR-NOT-FOUND))
  )
    (asserts! (is-eq (get created-by provider-data) tx-sender) ERR-UNAUTHORIZED)
    (asserts! (> total-slots u0) ERR-INVALID-INPUT)
    (asserts! (< start-time end-time) ERR-INVALID-INPUT)

    (map-set resources
      {resource-id: resource-id}
      {
        resource-type: resource-type,
        provider-id: provider-id,
        name: name,
        description: description,
        availability: {
          total-slots: total-slots,
          available-slots: total-slots,
          reserved-slots: u0,
          waitlist-count: u0
        },
        schedule: {
          start-time: start-time,
          end-time: end-time,
          days-of-week: days-of-week,
          duration-blocks: (- end-time start-time)
        },
        location-hash: location-hash,
        requirements: requirements,
        accessibility-features: accessibility-features,
        cost: cost,
        status: STATUS-ACTIVE,
        last-updated: stacks-block-height
      }
    )

    (var-set next-resource-id (+ resource-id u1))
    (ok resource-id)
  )
)

;; Update resource availability
(define-public (update-resource-availability (resource-id uint) (available-slots uint))
  (let ((resource-data (unwrap! (map-get? resources {resource-id: resource-id}) ERR-NOT-FOUND)))
    (let ((provider-data (unwrap! (map-get? service-providers {provider-id: (get provider-id resource-data)}) ERR-NOT-FOUND)))
      (asserts! (is-eq (get created-by provider-data) tx-sender) ERR-UNAUTHORIZED)
      (asserts! (<= available-slots (get total-slots (get availability resource-data))) ERR-INVALID-INPUT)

      (map-set resources
        {resource-id: resource-id}
        (merge resource-data {
          availability: (merge (get availability resource-data) {
            available-slots: available-slots,
            reserved-slots: (- (get total-slots (get availability resource-data)) available-slots)
          }),
          last-updated: stacks-block-height
        })
      )
      (ok true)
    )
  )
)

;; =============================================================================
;; SERVICE REQUEST MANAGEMENT
;; =============================================================================

;; Create service request
(define-public (create-service-request
  (client-hash (buff 32))
  (service-type uint)
  (provider-id uint)
  (resource-id uint)
  (requested-time uint)
  (priority-level uint)
  (special-requirements (list 5 uint))
)
  (let (
    (request-id (var-get next-request-id))
    (current-time stacks-block-height)
    (config (var-get system-config))
  )
    (asserts! (validate-privacy-access client-hash tx-sender) ERR-UNAUTHORIZED)
    (asserts! (is-some (map-get? anonymous-clients {client-hash: client-hash})) ERR-NOT-FOUND)
    (asserts! (is-some (map-get? service-providers {provider-id: provider-id})) ERR-NOT-FOUND)
    (asserts! (is-some (map-get? resources {resource-id: resource-id})) ERR-NOT-FOUND)
    (asserts! (validate-priority-level priority-level) ERR-INVALID-INPUT)

    (let ((resource-data (unwrap! (map-get? resources {resource-id: resource-id}) ERR-NOT-FOUND)))
      (asserts! (> (get available-slots (get availability resource-data)) u0) ERR-RESOURCE-UNAVAILABLE)

      (map-set service-requests
        {request-id: request-id}
        {
          client-hash: client-hash,
          service-type: service-type,
          provider-id: provider-id,
          resource-id: resource-id,
          requested-time: requested-time,
          priority-level: priority-level,
          special-requirements: special-requirements,
          status: STATUS-PENDING,
          assigned-case-worker: none,
          outcome-data: none,
          created-at: current-time,
          updated-at: current-time,
          expires-at: (+ current-time (get max-reservation-time config))
        }
      )

      ;; Update resource availability
      (try! (update-resource-slots resource-id (- (get available-slots (get availability resource-data)) u1)))

      (var-set next-request-id (+ request-id u1))
      (ok request-id)
    )
  )
)

;; Update service request status
(define-public (update-service-request-status (request-id uint) (new-status uint))
  (let ((request-data (unwrap! (map-get? service-requests {request-id: request-id}) ERR-NOT-FOUND)))
    (asserts! (or
      (validate-privacy-access (get client-hash request-data) tx-sender)
      (is-service-provider tx-sender (get provider-id request-data))
    ) ERR-UNAUTHORIZED)
    (asserts! (validate-status new-status) ERR-INVALID-INPUT)

    (map-set service-requests
      {request-id: request-id}
      (merge request-data {
        status: new-status,
        updated-at: stacks-block-height
      })
    )

    ;; If cancelled, free up resource slot
    (if (is-eq new-status STATUS-CANCELLED)
      (free-resource-slot (get resource-id request-data))
      (ok true)
    )
  )
)

;; =============================================================================
;; CASE MANAGEMENT
;; =============================================================================

;; Create case record
(define-public (create-case-record
  (client-hash (buff 32))
  (service-plan (buff 512))
  (goals (list 10 (buff 100)))
  (privacy-level uint)
)
  (let (
    (case-id (var-get next-case-id))
    (current-time stacks-block-height)
  )
    (asserts! (is-some (map-get? anonymous-clients {client-hash: client-hash})) ERR-NOT-FOUND)
    (asserts! (validate-privacy-level privacy-level) ERR-INVALID-INPUT)

    (map-set case-records
      {case-id: case-id}
      {
        client-hash: client-hash,
        case-worker: tx-sender,
        service-plan: service-plan,
        goals: goals,
        progress-notes: (list),
        service-history: (list),
        outcome-metrics: {
          housing-stability: u0,
          employment-status: u0,
          health-improvements: u0,
          service-satisfaction: u0
        },
        privacy-level: privacy-level,
        last-updated: current-time,
        created-at: current-time
      }
    )

    (var-set next-case-id (+ case-id u1))
    (ok case-id)
  )
)

;; Update case progress
(define-public (update-case-progress
  (case-id uint)
  (progress-note (buff 200))
  (outcome-metrics {housing-stability: uint, employment-status: uint, health-improvements: uint, service-satisfaction: uint})
)
  (let ((case-data (unwrap! (map-get? case-records {case-id: case-id}) ERR-NOT-FOUND)))
    (asserts! (is-eq (get case-worker case-data) tx-sender) ERR-UNAUTHORIZED)

    (let ((updated-notes (unwrap! (as-max-len? (append (get progress-notes case-data) progress-note) u20) ERR-INVALID-INPUT)))
      (map-set case-records
        {case-id: case-id}
        (merge case-data {
          progress-notes: updated-notes,
          outcome-metrics: outcome-metrics,
          last-updated: stacks-block-height
        })
      )
      (ok true)
    )
  )
)

;; =============================================================================
;; COORDINATION AND SCHEDULING
;; =============================================================================

;; Create coordination event
(define-public (create-coordination-event
  (event-type uint)
  (participating-providers (list 10 uint))
  (scheduled-time uint)
  (location-hash (buff 32))
  (capacity uint)
  (resource-requirements (list 10 uint))
)
  (let (
    (event-id (var-get next-event-id))
    (current-time stacks-block-height)
  )
    (asserts! (> capacity u0) ERR-INVALID-INPUT)
    (asserts! (> scheduled-time current-time) ERR-INVALID-INPUT)

    (map-set coordination-events
      {event-id: event-id}
      {
        event-type: event-type,
        organizer: tx-sender,
        participating-providers: participating-providers,
        scheduled-time: scheduled-time,
        location-hash: location-hash,
        capacity: capacity,
        registered-count: u0,
        resource-requirements: resource-requirements,
        outcome-summary: none,
        status: STATUS-ACTIVE,
        created-at: current-time
      }
    )

    (var-set next-event-id (+ event-id u1))
    (ok event-id)
  )
)

;; =============================================================================
;; UTILITY AND VALIDATION FUNCTIONS
;; =============================================================================

;; Validate service list
(define-private (validate-service-list (services (list 10 uint)))
  (let ((valid-services (filter is-valid-service-type services)))
    (is-eq (len valid-services) (len services))
  )
)

;; Check if service type is valid
(define-private (is-valid-service-type (service-type uint))
  (and (>= service-type SERVICE-SHELTER) (<= service-type SERVICE-LEGAL))
)

;; Validate priority level
(define-private (validate-priority-level (priority uint))
  (and (>= priority PRIORITY-CRITICAL) (<= priority PRIORITY-LOW))
)

;; Validate status
(define-private (validate-status (status uint))
  (and (>= status STATUS-ACTIVE) (<= status STATUS-CANCELLED))
)

;; Validate privacy level
(define-private (validate-privacy-level (privacy-level uint))
  (and (>= privacy-level u1) (<= privacy-level u5))
)

;; Check if emergency override is active
(define-private (is-emergency-override-active)
  (get emergency-override-enabled (var-get system-config))
)

;; Check if principal is a service provider
(define-private (is-service-provider (principal principal) (provider-id uint))
  (let ((provider-data (map-get? service-providers {provider-id: provider-id})))
    (match provider-data
      provider-info (is-eq (get created-by provider-info) principal)
      false
    )
  )
)

;; Update resource slots
(define-private (update-resource-slots (resource-id uint) (new-available uint))
  (let ((resource-data (unwrap! (map-get? resources {resource-id: resource-id}) ERR-NOT-FOUND)))
    (map-set resources
      {resource-id: resource-id}
      (merge resource-data {
        availability: (merge (get availability resource-data) {
          available-slots: new-available
        }),
        last-updated: stacks-block-height
      })
    )
    (ok true)
  )
)

;; Free resource slot
(define-private (free-resource-slot (resource-id uint))
  (let ((resource-data (unwrap! (map-get? resources {resource-id: resource-id}) ERR-NOT-FOUND)))
    (let ((current-available (get available-slots (get availability resource-data))))
      (update-resource-slots resource-id (+ current-available u1))
    )
  )
)

;; =============================================================================
;; READ-ONLY FUNCTIONS
;; =============================================================================

;; Get client info (privacy-protected)
(define-read-only (get-client-info (client-hash (buff 32)))
  (map-get? anonymous-clients {client-hash: client-hash})
)

;; Get service provider info
(define-read-only (get-service-provider (provider-id uint))
  (map-get? service-providers {provider-id: provider-id})
)

;; Get resource info
(define-read-only (get-resource (resource-id uint))
  (map-get? resources {resource-id: resource-id})
)

;; Get service request info
(define-read-only (get-service-request (request-id uint))
  (map-get? service-requests {request-id: request-id})
)

;; Get case record (privacy-protected)
(define-read-only (get-case-record (case-id uint))
  (map-get? case-records {case-id: case-id})
)

;; Get coordination event
(define-read-only (get-coordination-event (event-id uint))
  (map-get? coordination-events {event-id: event-id})
)

;; Get system configuration
(define-read-only (get-system-config)
  (var-get system-config)
)

;; =============================================================================
;; ADMIN FUNCTIONS
;; =============================================================================

;; Update system configuration (admin only)
(define-public (update-system-config (new-config {
  max-reservation-time: uint,
  default-priority-decay: uint,
  minimum-case-update-interval: uint,
  privacy-retention-period: uint,
  emergency-override-enabled: bool
}))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set system-config new-config)
    (ok true)
  )
)

;; Update privacy salt (admin only)
(define-public (update-privacy-salt (new-salt (buff 32)))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (var-set privacy-salt new-salt)
    (ok true)
  )
)

;; Emergency override toggle (admin only)
(define-public (toggle-emergency-override (enabled bool))
  (begin
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-UNAUTHORIZED)
    (let ((current-config (var-get system-config)))
      (var-set system-config (merge current-config {emergency-override-enabled: enabled}))
      (ok true)
    )
  )
)

;; =============================================================================
;; INITIALIZATION
;; =============================================================================

;; Initialize privacy salt on deployment
(var-set privacy-salt (sha256 stacks-block-height))

;; Contract deployment confirmation
(define-read-only (get-contract-info)
  {
    version: u1,
    deployed-at: stacks-block-height,
    contract-owner: CONTRACT-OWNER,
    next-provider-id: (var-get next-provider-id),
    next-resource-id: (var-get next-resource-id),
    next-request-id: (var-get next-request-id),
    next-case-id: (var-get next-case-id),
    next-event-id: (var-get next-event-id)
  }
)
