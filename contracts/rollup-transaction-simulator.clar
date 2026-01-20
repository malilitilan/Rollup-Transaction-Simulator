(define-constant contract-owner tx-sender)
(define-constant err-paused (err u113))
(define-data-var paused bool false)

(define-read-only (get-paused)
  (var-get paused))

(define-public (pause)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set paused true)
    (ok true)))

(define-public (resume)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set paused false)
    (ok true)))

(define-data-var owner principal tx-sender)
(define-data-var pending-owner (optional principal) none)

(define-constant err-not-owner u100)
(define-constant err-no-pending-owner u101)
(define-constant err-not-pending-owner u102)

(define-read-only (get-owner)
  (ok (var-get owner))
)

(define-read-only (get-pending-owner)
  (ok (var-get pending-owner))
)

(define-public (propose-owner (new-owner principal))
  (if (is-eq tx-sender (var-get owner))
      (begin
        (var-set pending-owner (some new-owner))
        (ok new-owner)
      )
      (err err-not-owner)
  )
)

(define-public (accept-ownership)
  (let ((po (var-get pending-owner)))
    (if (is-some po)
        (let ((candidate (unwrap-panic po)))
          (if (is-eq tx-sender candidate)
              (begin
                (var-set owner tx-sender)
                (var-set pending-owner none)
                (ok tx-sender)
              )
              (err err-not-pending-owner)
          )
        )
        (err err-no-pending-owner)
    )
  )
)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-invalid-batch (err u103))
(define-constant err-batch-empty (err u104))
(define-constant err-batch-full (err u105))
(define-constant err-user-not-found (err u106))
(define-constant err-batch-not-ready (err u107))
(define-constant err-dispute-window-closed (err u108))
(define-constant err-dispute-not-found (err u109))
(define-constant err-dispute-already-resolved (err u110))
(define-constant err-invalid-fee-recipient (err u111))
(define-constant err-invalid-fee-percentage (err u112))
(define-constant max-batch-size u50)
(define-constant min-settlement-delay u10)
(define-constant dispute-window-blocks u100)
(define-constant max-fee-percentage u100)

(define-data-var batch-counter uint u0)
(define-data-var settlement-fee uint u10)
(define-data-var operator-address principal contract-owner)
(define-data-var dispute-counter uint u0)
(define-data-var fee-recipient principal contract-owner)
(define-data-var fee-percentage uint u5)
(define-data-var total-fees-collected uint u0)

(define-map user-balances principal uint)
(define-map batch-transactions uint {transactions: (list 50 {from: principal, to: principal, amount: uint}), count: uint, created-at: uint, settled: bool})
(define-map pending-transactions principal (list 10 {to: principal, amount: uint, batch-id: uint}))
(define-map settlement-history uint {batch-id: uint, settled-at: uint, total-amount: uint, transaction-count: uint})
(define-map disputes uint {batch-id: uint, initiator: principal, reason: (string-ascii 256), filed-at: uint, status: (string-ascii 20), resolved-at: uint})
(define-map fee-distributions uint {batch-id: uint, distributed-at: uint, fee-amount: uint, recipient: principal})
(define-map recipient-rewards principal uint)

(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set user-balances contract-owner u1000000)
    (ok true)))
 

(define-public (deposit (amount uint))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (let ((current-balance (default-to u0 (map-get? user-balances tx-sender))))
      (map-set user-balances tx-sender (+ current-balance amount))
      (ok (+ current-balance amount)))))

(define-public (withdraw (amount uint))
  (let ((current-balance (default-to u0 (map-get? user-balances tx-sender))))
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (map-set user-balances tx-sender (- current-balance amount))
    (ok (- current-balance amount))))

(define-public (queue-transfer (to principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (map-get? user-balances tx-sender)))
    (current-pending (default-to (list) (map-get? pending-transactions tx-sender)))
  )
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (asserts! (< (len current-pending) u10) err-batch-full)
    (let ((new-pending (unwrap! (as-max-len? (append current-pending {to: to, amount: amount, batch-id: u0}) u10) err-batch-full)))
      (map-set pending-transactions tx-sender new-pending)
      (ok (len new-pending)))))

(define-public (create-batch)
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let ((current-batch-id (+ (var-get batch-counter) u1)))
      (var-set batch-counter current-batch-id)
      (map-set batch-transactions current-batch-id {
        transactions: (list),
        count: u0,
        created-at: stacks-block-height,
        settled: false
      })
      (ok current-batch-id))))

(define-public (add-to-batch (batch-id uint) (sender principal) (to principal) (amount uint))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (let (
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (current-transactions (get transactions batch-data))
      (current-count (get count batch-data))
      (sender-balance (default-to u0 (map-get? user-balances sender)))
    )
      (asserts! (not (get settled batch-data)) err-batch-not-ready)
      (asserts! (< current-count max-batch-size) err-batch-full)
      (asserts! (>= sender-balance amount) err-insufficient-balance)
      (let ((new-transaction {from: sender, to: to, amount: amount}))
        (let ((updated-transactions (unwrap! (as-max-len? (append current-transactions new-transaction) u50) err-batch-full)))
          (map-set batch-transactions batch-id {
            transactions: updated-transactions,
            count: (+ current-count u1),
            created-at: (get created-at batch-data),
            settled: false
          })
          (ok (+ current-count u1)))))))

(define-private (get-tx-amount (tx {from: principal, to: principal, amount: uint}))
  (get amount tx))

(define-private (sum-uint (a uint) (b uint))
  (+ a b))

(define-private (process-tx-for-preview (tx {from: principal, to: principal, amount: uint}) (state {user: principal, incoming: uint, outgoing: uint}))
  (let (
    (user (get user state))
    (incoming (get incoming state))
    (outgoing (get outgoing state))
    (amt (get amount tx))
    (is-incoming (is-eq (get to tx) user))
    (is-outgoing (is-eq (get from tx) user))
  )
    {
      user: user,
      incoming: (if is-incoming (+ incoming amt) incoming),
      outgoing: (if is-outgoing (+ outgoing amt) outgoing)
    }
  ))

(define-public (settle-batch (batch-id uint))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let (
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (transactions (get transactions batch-data))
      (transaction-count (get count batch-data))
      (created-at (get created-at batch-data))
      (settlement-result (fold sum-uint (map get-tx-amount transactions) u0))
    )
      (asserts! (not (get settled batch-data)) err-batch-not-ready)
      (asserts! (> transaction-count u0) err-batch-empty)
      (asserts! (>= (- stacks-block-height created-at) min-settlement-delay) err-batch-not-ready)
      (map-set batch-transactions batch-id {
        transactions: transactions,
        count: transaction-count,
        created-at: created-at,
        settled: true
      })
      (map-set settlement-history batch-id {
        batch-id: batch-id,
        settled-at: stacks-block-height,
        total-amount: settlement-result,
        transaction-count: transaction-count
      })
      (ok settlement-result))))

 

(define-public (set-operator (new-operator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set operator-address new-operator)
    (ok true)))

(define-public (set-settlement-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set settlement-fee new-fee)
    (ok true)))

(define-public (set-fee-recipient (new-recipient principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (not (is-eq new-recipient contract-owner)) err-invalid-fee-recipient)
    (var-set fee-recipient new-recipient)
    (ok true)))

(define-public (set-fee-percentage (new-percentage uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (asserts! (<= new-percentage max-fee-percentage) err-invalid-fee-percentage)
    (var-set fee-percentage new-percentage)
    (ok true)))

(define-public (distribute-settlement-fees (batch-id uint))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let (
      (settlement-data (unwrap! (map-get? settlement-history batch-id) err-invalid-batch))
      (total-amount (get total-amount settlement-data))
      (fee-amount (/ (* total-amount (var-get fee-percentage)) u100))
      (recipient (var-get fee-recipient))
      (recipient-current-rewards (default-to u0 (map-get? recipient-rewards recipient)))
    )
      (asserts! (> fee-amount u0) err-invalid-amount)
      (map-set fee-distributions batch-id {
        batch-id: batch-id,
        distributed-at: stacks-block-height,
        fee-amount: fee-amount,
        recipient: recipient
      })
      (map-set recipient-rewards recipient (+ recipient-current-rewards fee-amount))
      (var-set total-fees-collected (+ (var-get total-fees-collected) fee-amount))
      (ok fee-amount))))

(define-read-only (get-user-balance (user principal))
  (default-to u0 (map-get? user-balances user)))

(define-read-only (get-batch-info (batch-id uint))
  (map-get? batch-transactions batch-id))

(define-read-only (get-pending-transfers (user principal))
  (default-to (list) (map-get? pending-transactions user)))

(define-read-only (get-settlement-history (batch-id uint))
  (map-get? settlement-history batch-id))

(define-read-only (get-contract-stats)
  {
    batch-counter: (var-get batch-counter),
    settlement-fee: (var-get settlement-fee),
    operator: (var-get operator-address),
    max-batch-size: max-batch-size,
    min-settlement-delay: min-settlement-delay
  })

(define-read-only (get-batch-transactions (batch-id uint))
  (match (map-get? batch-transactions batch-id)
    batch-data (some (get transactions batch-data))
    none))

(define-public (file-dispute (batch-id uint) (reason (string-ascii 256)))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (let (
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (settled-at (get settled-at (unwrap! (map-get? settlement-history batch-id) err-invalid-batch)))
      (dispute-id (+ (var-get dispute-counter) u1))
    )
      (asserts! (get settled batch-data) err-batch-not-ready)
      (asserts! (<= (- stacks-block-height settled-at) dispute-window-blocks) err-dispute-window-closed)
      (var-set dispute-counter dispute-id)
      (map-set disputes dispute-id {
        batch-id: batch-id,
        initiator: tx-sender,
        reason: reason,
        filed-at: stacks-block-height,
        status: "pending",
        resolved-at: u0
      })
      (ok dispute-id))))

(define-public (resolve-dispute (dispute-id uint) (approved bool))
  (begin
    (asserts! (not (var-get paused)) err-paused)
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (let (
      (dispute-data (unwrap! (map-get? disputes dispute-id) err-dispute-not-found))
      (batch-id (get batch-id dispute-data))
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (transactions (get transactions batch-data))
    )
      (asserts! (is-eq (get status dispute-data) "pending") err-dispute-already-resolved)
      (if approved
        (begin
          (map-set disputes dispute-id {
            batch-id: batch-id,
            initiator: (get initiator dispute-data),
            reason: (get reason dispute-data),
            filed-at: (get filed-at dispute-data),
            status: "approved",
            resolved-at: stacks-block-height
          })
          (map-set batch-transactions batch-id {
            transactions: transactions,
            count: (get count batch-data),
            created-at: (get created-at batch-data),
            settled: false
          })
          (ok true))
        (begin
          (map-set disputes dispute-id {
            batch-id: batch-id,
            initiator: (get initiator dispute-data),
            reason: (get reason dispute-data),
            filed-at: (get filed-at dispute-data),
            status: "rejected",
            resolved-at: stacks-block-height
          })
          (ok true))))))

(define-read-only (get-dispute-info (dispute-id uint))
  (map-get? disputes dispute-id))

(define-read-only (get-dispute-status (dispute-id uint))
  (match (map-get? disputes dispute-id)
    dispute-data (some (get status dispute-data))
    none))

(define-read-only (get-fee-distribution (batch-id uint))
  (map-get? fee-distributions batch-id))

(define-read-only (get-recipient-rewards (recipient principal))
  (default-to u0 (map-get? recipient-rewards recipient)))

(define-read-only (get-fee-config)
  {
    fee-recipient: (var-get fee-recipient),
    fee-percentage: (var-get fee-percentage),
    total-fees-collected: (var-get total-fees-collected),
    max-fee-percentage: max-fee-percentage
  })

(define-read-only (get-batch-summary (batch-id uint))
  (match (map-get? batch-transactions batch-id)
    batch-data
    (let (
      (txs (get transactions batch-data))
      (total (fold sum-uint (map get-tx-amount txs) u0))
      (count (get count batch-data))
      (fee (/ (* total (var-get fee-percentage)) u100))
    )
      (some {
        batch-id: batch-id,
        total-amount: total,
        transaction-count: count,
        fee-percentage: (var-get fee-percentage),
        fee-amount: fee
      }))
    none))

(define-read-only (get-user-batch-preview (batch-id uint) (user principal))
  (match (map-get? batch-transactions batch-id)
    batch-data
    (let (
      (txs (get transactions batch-data))
      (initial-state {user: user, incoming: u0, outgoing: u0})
      (final-state (fold process-tx-for-preview txs initial-state))
      (incoming (get incoming final-state))
      (outgoing (get outgoing final-state))
      (balance (default-to u0 (map-get? user-balances user)))
      (base (if (>= balance outgoing) (- balance outgoing) u0))
    )
      (some {
        user: user,
        incoming: incoming,
        outgoing: outgoing,
        pre-balance: balance,
        post-balance: (+ base incoming)
      }))
    none))
