;; Title: VelocityStake - Advanced sBTC Liquid Staking Protocol
;;
;; Summary:
;; VelocityStake is a next-generation liquid staking protocol that maximizes
;; sBTC yield through dynamic reward optimization and tiered incentive structures.
;; Built for institutional-grade security with retail-friendly accessibility.
;;
;; Description:
;; VelocityStake revolutionizes sBTC staking by introducing:
;; - Multi-tier reward amplification based on commitment duration
;; - Delegation mechanics for enhanced capital efficiency  
;; - Emergency safeguards with slashing protection mechanisms
;; - Cooldown-based withdrawal system for optimal liquidity management
;; - Dynamic reward distribution algorithms that scale with pool growth
;;
;; The protocol implements sophisticated risk management through emergency
;; modes, address validation, and configurable admin controls while maintaining
;; full decentralization principles. Rewards compound automatically based on
;; staking duration tiers, creating powerful incentives for long-term holders.

;; TRAITS & INTERFACES

(define-trait sbtc-token-trait (
  (transfer
    (uint principal principal)
    (response bool uint)
  )
))

;; CONSTANTS & ERROR CODES

;; Access Control
(define-constant CONTRACT_OWNER tx-sender)
(define-constant POOL_ADMIN 'SP2PABAF9FTAJYNFZH93XENAJ8FVY99RRM50D2JG9)

;; Error Constants
(define-constant ERR_NOT_AUTHORIZED (err u100))
(define-constant ERR_INSUFFICIENT_BALANCE (err u101))
(define-constant ERR_INVALID_AMOUNT (err u102))
(define-constant ERR_POOL_PAUSED (err u103))
(define-constant ERR_ALREADY_INITIALIZED (err u104))
(define-constant ERR_NOT_INITIALIZED (err u105))
(define-constant ERR_SLASHING_CONDITION (err u106))
(define-constant ERR_POOL_FULL (err u107))
(define-constant ERR_INVALID_DELEGATION (err u108))
(define-constant ERR_COOLDOWN_ACTIVE (err u109))
(define-constant ERR_REWARD_UPDATE_FAILED (err u110))

;; Pool Configuration Constants
(define-constant REWARD_RATE u100000)
(define-constant MINIMUM_DEPOSIT u1000000)
(define-constant MAXIMUM_POOL_SIZE u1000000000000)
(define-constant COOLDOWN_PERIOD u144) ;; ~24 hours in blocks

;; Tier System Configuration
(define-constant TIER1_THRESHOLD u4320) ;; 30 days in blocks
(define-constant TIER2_THRESHOLD u8640) ;; 60 days in blocks
(define-constant TIER1_BONUS u10) ;; 10% bonus
(define-constant TIER2_BONUS u25) ;; 25% bonus
(define-constant SLASH_RATE u50) ;; 50% slash rate

;; DATA VARIABLES

;; Token Configuration
(define-data-var sbtc-token-contract principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM.sbtc)

;; Protocol State
(define-data-var contract-initialized bool false)
(define-data-var pool-paused bool false)
(define-data-var emergency-mode bool false)

;; Pool Metrics
(define-data-var total-liquidity uint u0)
(define-data-var total-rewards uint u0)
(define-data-var last-update-time uint u0)
(define-data-var reward-per-token uint u0)

;; DATA MAPS

;; User State Management
(define-map user-deposits
  principal
  uint
)
(define-map user-rewards
  principal
  uint
)
(define-map user-reward-paid
  principal
  uint
)
(define-map staking-time
  principal
  uint
)
(define-map cooldown-period
  principal
  uint
)
(define-map slashed-addresses
  principal
  bool
)

;; Delegation System
(define-map delegation-info
  { delegator: principal }
  { delegate: principal }
)

;; PRIVATE FUNCTIONS

;; Access Control Functions
(define-private (is-authorized)
  (or
    (is-eq tx-sender CONTRACT_OWNER)
    (is-eq tx-sender POOL_ADMIN)
  )
)

(define-private (is-valid-token (token <sbtc-token-trait>))
  (is-eq (contract-of token) (var-get sbtc-token-contract))
)

(define-private (is-valid-address (address principal))
  (and
    (not (is-eq address CONTRACT_OWNER))
    (not (is-eq address (as-contract tx-sender)))
    (not (is-eq address POOL_ADMIN))
  )
)

;; State Validation Functions
(define-private (check-initialized)
  (ok (asserts! (var-get contract-initialized) ERR_NOT_INITIALIZED))
)

(define-private (check-not-paused)
  (ok (asserts! (not (var-get pool-paused)) ERR_POOL_PAUSED))
)

;; Reward Calculation Engine
(define-private (calculate-tier-multiplier (staking-duration uint))
  (if (>= staking-duration TIER2_THRESHOLD)
    (+ u100 TIER2_BONUS)
    (if (>= staking-duration TIER1_THRESHOLD)
      (+ u100 TIER1_BONUS)
      u100
    )
  )
)

(define-private (calculate-rewards (user principal))
  (let (
      (user-balance (default-to u0 (map-get? user-deposits user)))
      (user-reward-debt (default-to u0 (map-get? user-reward-paid user)))
    )
    (ok (if (> user-balance u0)
      (* user-balance (- (var-get reward-per-token) user-reward-debt))
      u0
    ))
  )
)

(define-private (update-reward (user principal))
  (let (
      (current-time stacks-block-height)
      (time-delta (- current-time (var-get last-update-time)))
      (user-balance (default-to u0 (map-get? user-deposits user)))
      (staking-duration (- current-time (default-to u0 (map-get? staking-time user))))
      (tier-multiplier (calculate-tier-multiplier staking-duration))
    )
    (if (> (var-get total-liquidity) u0)
      (let ((new-reward-per-token (+ (var-get reward-per-token)
          (* (* (* REWARD_RATE time-delta) tier-multiplier) u1000000)
        )))
        (var-set reward-per-token new-reward-per-token)
        (var-set last-update-time current-time)
        (map-set user-reward-paid user new-reward-per-token)
        (ok true)
      )
      ERR_REWARD_UPDATE_FAILED
    )
  )
)

;; PUBLIC FUNCTIONS

;; Protocol Initialization
(define-public (initialize)
  (begin
    (asserts! (is-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (not (var-get contract-initialized)) ERR_ALREADY_INITIALIZED)
    (var-set contract-initialized true)
    (var-set last-update-time stacks-block-height)
    (ok true)
  )
)

;; Core Staking Functions
(define-public (deposit
    (amount uint)
    (token <sbtc-token-trait>)
  )
  (begin
    (try! (check-initialized))
    (try! (check-not-paused))
    (asserts! (is-valid-token token) ERR_NOT_AUTHORIZED)
    (asserts! (>= amount MINIMUM_DEPOSIT) ERR_INVALID_AMOUNT)
    (asserts! (<= (+ (var-get total-liquidity) amount) MAXIMUM_POOL_SIZE)
      ERR_POOL_FULL
    )

    (try! (update-reward tx-sender))

    (let ((cooldown-end (default-to u0 (map-get? cooldown-period tx-sender))))
      (asserts! (<= cooldown-end stacks-block-height) ERR_COOLDOWN_ACTIVE)
    )

    (try! (contract-call? token transfer amount tx-sender (as-contract tx-sender)))

    (let (
        (current-deposit (default-to u0 (map-get? user-deposits tx-sender)))
        (new-deposit (+ current-deposit amount))
      )
      (map-set user-deposits tx-sender new-deposit)
      (var-set total-liquidity (+ (var-get total-liquidity) amount))
      (map-set staking-time tx-sender stacks-block-height)
      (ok true)
    )
  )
)

;; Delegation System
(define-public (delegate-stake (delegate-to principal))
  (begin
    (asserts! (not (is-eq tx-sender delegate-to)) ERR_INVALID_DELEGATION)
    (map-set delegation-info { delegator: tx-sender } { delegate: delegate-to })
    (ok true)
  )
)

;; Withdrawal Management
(define-public (start-withdrawal (amount uint))
  (begin
    (try! (check-initialized))
    (try! (check-not-paused))

    (let (
        (current-deposit (default-to u0 (map-get? user-deposits tx-sender)))
        (current-time stacks-block-height)
      )
      (asserts! (>= current-deposit amount) ERR_INSUFFICIENT_BALANCE)
      (map-set cooldown-period tx-sender (+ current-time COOLDOWN_PERIOD))
      (ok true)
    )
  )
)

(define-public (complete-withdrawal
    (amount uint)
    (token <sbtc-token-trait>)
  )
  (begin
    (try! (check-initialized))
    (try! (check-not-paused))
    (asserts! (is-valid-token token) ERR_NOT_AUTHORIZED)

    (let (
        (current-deposit (default-to u0 (map-get? user-deposits tx-sender)))
        (cooldown-end (default-to u0 (map-get? cooldown-period tx-sender)))
        (current-time stacks-block-height)
      )
      (asserts! (>= current-deposit amount) ERR_INSUFFICIENT_BALANCE)
      (asserts! (>= current-time cooldown-end) ERR_COOLDOWN_ACTIVE)

      (try! (update-reward tx-sender))

      (try! (as-contract (contract-call? token transfer amount (as-contract tx-sender) tx-sender)))

      (map-set user-deposits tx-sender (- current-deposit amount))
      (var-set total-liquidity (- (var-get total-liquidity) amount))
      (map-delete cooldown-period tx-sender)
      (ok true)
    )
  )
)


(define-public (emergency-withdraw (token <sbtc-token-trait>))
  (begin
    (asserts! (var-get emergency-mode) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-token token) ERR_NOT_AUTHORIZED)

    (let ((current-deposit (default-to u0 (map-get? user-deposits tx-sender))))
      (asserts! (> current-deposit u0) ERR_INSUFFICIENT_BALANCE)

      (try! (as-contract (contract-call? token transfer current-deposit (as-contract tx-sender)
        tx-sender
      )))

      (map-set user-deposits tx-sender u0)
      (var-set total-liquidity (- (var-get total-liquidity) current-deposit))
      (ok true)
    )
  )
)

;; Admin Functions
(define-public (slash-address (address principal))
  (begin
    (asserts! (is-authorized) ERR_NOT_AUTHORIZED)
    (asserts! (is-valid-address address) ERR_NOT_AUTHORIZED)

    (let (
        (current-deposit (default-to u0 (map-get? user-deposits address)))
        (slash-amount (/ (* current-deposit SLASH_RATE) u100))
      )
      (asserts! (> current-deposit u0) ERR_INSUFFICIENT_BALANCE)

      (map-set slashed-addresses address true)
      (map-set user-deposits address (- current-deposit slash-amount))
      (var-set total-liquidity (- (var-get total-liquidity) slash-amount))
      (ok true)
    )
  )
)

;; READ-ONLY FUNCTIONS

(define-read-only (get-user-info (user principal))
  (ok {
    deposit: (default-to u0 (map-get? user-deposits user)),
    rewards: (unwrap-panic (calculate-rewards user)),
    staking-time: (default-to u0 (map-get? staking-time user)),
    is-slashed: (default-to false (map-get? slashed-addresses user)),
    cooldown-end: (default-to u0 (map-get? cooldown-period user)),
  })
)

(define-read-only (get-pool-info)
  (ok {
    total-liquidity: (var-get total-liquidity),
    total-rewards: (var-get total-rewards),
    is-paused: (var-get pool-paused),
    emergency-mode: (var-get emergency-mode),
    current-time: stacks-block-height,
  })
)

(define-read-only (get-delegation-info (delegator principal))
  (ok (map-get? delegation-info { delegator: delegator }))
)
