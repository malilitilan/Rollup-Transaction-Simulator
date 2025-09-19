(define-constant contract-owner tx-sender)
(define-constant err-owner-only (err u100))
(define-constant err-insufficient-balance (err u101))
(define-constant err-invalid-amount (err u102))
(define-constant err-invalid-batch (err u103))
(define-constant err-batch-empty (err u104))
(define-constant err-batch-full (err u105))
(define-constant err-user-not-found (err u106))
(define-constant err-batch-not-ready (err u107))
(define-constant max-batch-size u50)
(define-constant min-settlement-delay u10)

(define-data-var batch-counter uint u0)
(define-data-var settlement-fee uint u10)
(define-data-var operator-address principal contract-owner)

(define-map user-balances principal uint)
(define-map batch-transactions uint {transactions: (list 50 {from: principal, to: principal, amount: uint}), count: uint, created-at: uint, settled: bool})
(define-map pending-transactions principal (list 10 {to: principal, amount: uint, batch-id: uint}))
(define-map settlement-history uint {batch-id: uint, settled-at: uint, total-amount: uint, transaction-count: uint})

(define-public (initialize)
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (map-set user-balances contract-owner u1000000)
    (ok true)))

(define-public (deposit (amount uint))
  (begin
    (asserts! (> amount u0) err-invalid-amount)
    (try! (stx-transfer? amount tx-sender (as-contract tx-sender)))
    (let ((current-balance (default-to u0 (map-get? user-balances tx-sender))))
      (map-set user-balances tx-sender (+ current-balance amount))
      (print {action: "deposit", user: tx-sender, amount: amount, new-balance: (+ current-balance amount)})
      (ok (+ current-balance amount)))))

(define-public (withdraw (amount uint))
  (let ((current-balance (default-to u0 (map-get? user-balances tx-sender))))
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= current-balance amount) err-insufficient-balance)
    (map-set user-balances tx-sender (- current-balance amount))
    (try! (as-contract (stx-transfer? amount tx-sender tx-sender)))
    (print {action: "withdraw", user: tx-sender, amount: amount, new-balance: (- current-balance amount)})
    (ok (- current-balance amount))))

(define-public (queue-transfer (to principal) (amount uint))
  (let (
    (sender-balance (default-to u0 (map-get? user-balances tx-sender)))
    (current-pending (default-to (list) (map-get? pending-transactions tx-sender)))
  )
    (asserts! (> amount u0) err-invalid-amount)
    (asserts! (>= sender-balance amount) err-insufficient-balance)
    (asserts! (< (len current-pending) u10) err-batch-full)
    (let ((new-pending (unwrap! (as-max-len? (append current-pending {to: to, amount: amount, batch-id: u0}) u10) err-batch-full)))
      (map-set pending-transactions tx-sender new-pending)
      (print {action: "queue-transfer", from: tx-sender, to: to, amount: amount})
      (ok (len new-pending)))))

(define-public (create-batch)
  (begin
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let (
      (current-batch-id (+ (var-get batch-counter) u1))
      (empty-transactions (list))
    )
      (var-set batch-counter current-batch-id)
      (map-set batch-transactions current-batch-id {
        transactions: empty-transactions,
        count: u0,
        created-at: block-height,
        settled: false
      })
      (print {action: "create-batch", batch-id: current-batch-id, created-at: block-height})
      (ok current-batch-id))))

(define-public (add-to-batch (batch-id uint) (from principal) (to principal) (amount uint))
  (begin
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (asserts! (> amount u0) err-invalid-amount)
    (let (
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (current-transactions (get transactions batch-data))
      (current-count (get count batch-data))
      (sender-balance (default-to u0 (map-get? user-balances from)))
    )
      (asserts! (not (get settled batch-data)) err-batch-not-ready)
      (asserts! (< current-count max-batch-size) err-batch-full)
      (asserts! (>= sender-balance amount) err-insufficient-balance)
      (let ((new-transaction {from: from, to: to, amount: amount}))
        (let ((updated-transactions (unwrap! (as-max-len? (append current-transactions new-transaction) u50) err-batch-full)))
          (map-set batch-transactions batch-id {
            transactions: updated-transactions,
            count: (+ current-count u1),
            created-at: (get created-at batch-data),
            settled: false
          })
          (print {action: "add-to-batch", batch-id: batch-id, from: from, to: to, amount: amount})
          (ok (+ current-count u1)))))))

(define-public (settle-batch (batch-id uint))
  (begin
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let (
      (batch-data (unwrap! (map-get? batch-transactions batch-id) err-invalid-batch))
      (transactions (get transactions batch-data))
      (transaction-count (get count batch-data))
      (created-at (get created-at batch-data))
    )
      (asserts! (not (get settled batch-data)) err-batch-not-ready)
      (asserts! (> transaction-count u0) err-batch-empty)
      (asserts! (>= (- block-height created-at) min-settlement-delay) err-batch-not-ready)
      (let ((settlement-result (try! (process-batch-settlements transactions u0 u0))))
        (map-set batch-transactions batch-id {
          transactions: transactions,
          count: transaction-count,
          created-at: created-at,
          settled: true
        })
        (map-set settlement-history batch-id {
          batch-id: batch-id,
          settled-at: block-height,
          total-amount: settlement-result,
          transaction-count: transaction-count
        })
        (print {action: "settle-batch", batch-id: batch-id, settled-at: block-height, total-amount: settlement-result, count: transaction-count})
        (ok settlement-result)))))

(define-private (process-batch-settlements (transactions (list 50 {from: principal, to: principal, amount: uint})) (index uint) (total-amount uint))
  (match (element-at transactions index)
    transaction (let (
      (from (get from transaction))
      (to (get to transaction))
      (amount (get amount transaction))
      (sender-balance (default-to u0 (map-get? user-balances from)))
      (receiver-balance (default-to u0 (map-get? user-balances to)))
    )
      (if (>= sender-balance amount)
        (begin
          (map-set user-balances from (- sender-balance amount))
          (map-set user-balances to (+ receiver-balance amount))
          (if (< index u49)
            (process-batch-settlements transactions (+ index u1) (+ total-amount amount))
            (ok (+ total-amount amount))))
        (if (< index u49)
          (process-batch-settlements transactions (+ index u1) total-amount)
          (ok total-amount))))
    (ok total-amount)))

(define-public (execute-pending-transfers (user principal))
  (begin
    (asserts! (is-eq tx-sender (var-get operator-address)) err-owner-only)
    (let (
      (pending (default-to (list) (map-get? pending-transactions user)))
      (current-batch-id (var-get batch-counter))
    )
      (asserts! (> (len pending) u0) err-batch-empty)
      (let ((execution-result (try! (execute-pending-list pending user current-batch-id u0))))
        (map-delete pending-transactions user)
        (print {action: "execute-pending", user: user, batch-id: current-batch-id, processed: execution-result})
        (ok execution-result)))))

(define-private (execute-pending-list (pending (list 10 {to: principal, amount: uint, batch-id: uint})) (from principal) (batch-id uint) (processed uint))
  (match (element-at pending processed)
    transfer (let (
      (to (get to transfer))
      (amount (get amount transfer))
    )
      (try! (add-to-batch batch-id from to amount))
      (if (< processed u9)
        (execute-pending-list pending from batch-id (+ processed u1))
        (ok (+ processed u1))))
    (ok processed)))

(define-public (set-operator (new-operator principal))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set operator-address new-operator)
    (print {action: "set-operator", new-operator: new-operator})
    (ok true)))

(define-public (set-settlement-fee (new-fee uint))
  (begin
    (asserts! (is-eq tx-sender contract-owner) err-owner-only)
    (var-set settlement-fee new-fee)
    (print {action: "set-settlement-fee", new-fee: new-fee})
    (ok true)))

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
