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