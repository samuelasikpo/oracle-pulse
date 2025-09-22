;; Title: OraclePulse - Bitcoin Price Prediction Protocol
;;
;; Summary:
;;   A sophisticated decentralized prediction market infrastructure built on Stacks,
;;   enabling trustless speculation on Bitcoin price movements through liquid markets
;;   with automated settlement mechanisms and dynamic reward distributions.
;;
;; Description:
;;   OraclePulse revolutionizes Bitcoin price speculation by creating liquid prediction
;;   markets directly on Bitcoin's Layer-2. Users can leverage their STX holdings to
;;   participate in time-bound price prediction contests, earning proportional rewards
;;   based on market accuracy and stake size. The protocol features automated market
;;   resolution through verified oracles, transparent fee structures, and instant
;;   reward distribution, making it the premier destination for Bitcoin price discovery
;;   and speculative trading on the Stacks ecosystem.
;;
;;   Key Features:
;;   - Liquid prediction markets with customizable time horizons
;;   - Proportional reward distribution based on accuracy and stake
;;   - Oracle-driven price feeds for trustless settlement
;;   - Dynamic fee optimization for sustainable protocol growth
;;   - Granular administrative controls for market governance

;; ERROR CONSTANTS
(define-constant CONTRACT-OWNER tx-sender)
(define-constant ERR-OWNER-ONLY (err u100))
(define-constant ERR-NOT-FOUND (err u101))
(define-constant ERR-INVALID-PREDICTION (err u102))
(define-constant ERR-MARKET-CLOSED (err u103))
(define-constant ERR-ALREADY-CLAIMED (err u104))
(define-constant ERR-INSUFFICIENT-BALANCE (err u105))
(define-constant ERR-INVALID-PARAMETER (err u106))

;; DATA VARIABLES
(define-data-var oracle-address principal 'ST1PQHQKV0RJXZFY1DGX8MNSNYVE3VGZJSRTPGZGM)
(define-data-var minimum-stake uint u1000000) ;; 1 STX minimum stake requirement
(define-data-var fee-percentage uint u2) ;; 2% protocol fee for sustainability
(define-data-var market-counter uint u0) ;; Incremental market identifier

;; DATA STRUCTURES

;; Market state mapping with comprehensive market data
(define-map markets
  uint ;; market-id
  {
    start-price: uint, ;; Initial Bitcoin price at market creation
    end-price: uint, ;; Final Bitcoin price at market resolution
    total-up-stake: uint, ;; Aggregate stake for bullish predictions
    total-down-stake: uint, ;; Aggregate stake for bearish predictions
    start-block: uint, ;; Market opening block height
    end-block: uint, ;; Market closing block height
    resolved: bool, ;; Market resolution status
  }
)

;; User prediction tracking with claim status
(define-map user-predictions
  {
    market-id: uint,
    user: principal,
  }
  {
    prediction: (string-ascii 4), ;; "up" or "down" market direction
    stake: uint, ;; User's staked amount in microSTX
    claimed: bool, ;; Reward claim status
  }
)

;; PUBLIC FUNCTIONS - CORE FUNCTIONALITY

;; Creates a new Bitcoin price prediction market
;; @param start-price: Initial BTC price in microBTC
;; @param start-block: Block height when predictions begin
;; @param end-block: Block height when market closes
;; @returns: Market ID on success
(define-public (create-market
    (start-price uint)
    (start-block uint)
    (end-block uint)
  )
  (let ((market-id (var-get market-counter)))
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-OWNER-ONLY)
    (asserts! (> end-block start-block) ERR-INVALID-PARAMETER)
    (asserts! (> start-price u0) ERR-INVALID-PARAMETER)

    (map-set markets market-id {
      start-price: start-price,
      end-price: u0,
      total-up-stake: u0,
      total-down-stake: u0,
      start-block: start-block,
      end-block: end-block,
      resolved: false,
    })
    (var-set market-counter (+ market-id u1))
    (ok market-id)
  )
)

;; Submits a price prediction with STX stake
;; @param market-id: Target market identifier
;; @param prediction: Market direction ("up" or "down")
;; @param stake: STX amount to stake in microSTX
;; @returns: Success boolean
(define-public (make-prediction
    (market-id uint)
    (prediction (string-ascii 4))
    (stake uint)
  )
  (let (
      (market (unwrap! (map-get? markets market-id) ERR-NOT-FOUND))
      (current-block-height stacks-block-height)
    )
    ;; Validate market timing and parameters
    (asserts!
      (and
        (>= current-block-height (get start-block market))
        (< current-block-height (get end-block market))
      )
      ERR-MARKET-CLOSED
    )
    (asserts! (or (is-eq prediction "up") (is-eq prediction "down"))
      ERR-INVALID-PREDICTION
    )
    (asserts! (>= stake (var-get minimum-stake)) ERR-INVALID-PREDICTION)
    (asserts! (<= stake (stx-get-balance tx-sender)) ERR-INSUFFICIENT-BALANCE)

    ;; Transfer stake to contract escrow
    (try! (stx-transfer? stake tx-sender (as-contract tx-sender)))

    ;; Record user prediction
    (map-set user-predictions {
      market-id: market-id,
      user: tx-sender,
    } {
      prediction: prediction,
      stake: stake,
      claimed: false,
    })

    ;; Update market stake totals
    (map-set markets market-id
      (merge market {
        total-up-stake: (if (is-eq prediction "up")
          (+ (get total-up-stake market) stake)
          (get total-up-stake market)
        ),
        total-down-stake: (if (is-eq prediction "down")
          (+ (get total-down-stake market) stake)
          (get total-down-stake market)
        ),
      })
    )
    (ok true)
  )
)

;; Resolves market with final Bitcoin price from oracle
;; @param market-id: Market to resolve
;; @param end-price: Final BTC price in microBTC
;; @returns: Success boolean
(define-public (resolve-market
    (market-id uint)
    (end-price uint)
  )
  (let ((market (unwrap! (map-get? markets market-id) ERR-NOT-FOUND)))
    (asserts! (is-eq tx-sender (var-get oracle-address)) ERR-OWNER-ONLY)
    (asserts! (>= stacks-block-height (get end-block market)) ERR-MARKET-CLOSED)
    (asserts! (not (get resolved market)) ERR-MARKET-CLOSED)
    (asserts! (> end-price u0) ERR-INVALID-PARAMETER)

    (map-set markets market-id
      (merge market {
        end-price: end-price,
        resolved: true,
      })
    )
    (ok true)
  )
)