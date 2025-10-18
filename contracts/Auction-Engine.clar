(define-constant ERR-NOT-AUTHORIZED u100)
(define-constant ERR-AUCTION-ENDED u101)
(define-constant ERR-AUCTION-ACTIVE u102)
(define-constant ERR-INVALID-BID u103)
(define-constant ERR-NO-AUCTION u104)
(define-constant ERR-INVALID-INITIATIVE u105)
(define-constant ERR-INVALID-NFT u106)
(define-constant ERR-INVALID-RESERVE u107)
(define-constant ERR-INVALID-DURATION u108)
(define-constant ERR-INVALID-START-TIME u109)
(define-constant ERR-INVALID-END-TIME u110)
(define-constant ERR-BID-TOO-LOW u111)
(define-constant ERR-NOT-OWNER u112)
(define-constant ERR-TRANSFER-FAILED u113)
(define-constant ERR-ESCROW-FAILED u114)
(define-constant ERR-ALREADY-ENDED u115)
(define-constant ERR-NOT-STARTED u116)
(define-constant ERR-INVALID-INCREMENT u117)
(define-constant ERR-MAX-AUCTIONS-EXCEEDED u118)
(define-constant ERR-INVALID-STATUS u119)
(define-constant ERR-INVALID-EXTENSION u120)
(define-constant ERR-INVALID-COMMISSION u121)
(define-constant ERR-INVALID-LOCATION u122)
(define-constant ERR-INVALID-CURRENCY u123)
(define-constant ERR-INVALID-BIDDER u124)
(define-constant ERR-AUCTION-NOT-FOUND u125)

(define-data-var next-auction-id uint u0)
(define-data-var max-auctions uint u10000)
(define-data-var min-bid-increment uint u100)
(define-data-var extension-period uint u144)
(define-data-var platform-commission uint u5)
(define-data-var nft-contract principal tx-sender)
(define-data-var escrow-contract principal tx-sender)
(define-data-var fund-contract principal tx-sender)
(define-data-var initiative-registry principal tx-sender)

(define-map auctions
  { auction-id: uint }
  {
    nft-id: uint,
    initiative-id: uint,
    seller: principal,
    highest-bidder: (optional principal),
    highest-bid: uint,
    start-time: uint,
    end-time: uint,
    reserve-price: uint,
    active: bool,
    extended: bool,
    location: (string-utf8 100),
    currency: (string-utf8 20),
    status: uint
  }
)

(define-map bids
  { auction-id: uint, bidder: principal }
  { bid-amount: uint, timestamp: uint }
)

(define-read-only (get-auction (id uint))
  (map-get? auctions { auction-id: id })
)

(define-read-only (get-bid (id uint) (bidder principal))
  (map-get? bids { auction-id: id, bidder: bidder })
)

(define-read-only (get-next-auction-id)
  (var-get next-auction-id)
)

(define-private (validate-nft-id (nft uint))
  (if (> nft u0)
    (ok true)
    (err ERR-INVALID-NFT))
)

(define-private (validate-initiative-id (init uint))
  (if (> init u0)
    (ok true)
    (err ERR-INVALID-INITIATIVE))
)

(define-private (validate-reserve-price (price uint))
  (if (> price u0)
    (ok true)
    (err ERR-INVALID-RESERVE))
)

(define-private (validate-duration (dur uint))
  (if (and (> dur u144) (< dur u10080))
    (ok true)
    (err ERR-INVALID-DURATION))
)

(define-private (validate-start-time (start uint))
  (if (>= start block-height)
    (ok true)
    (err ERR-INVALID-START-TIME))
)

(define-private (validate-end-time (end uint) (start uint))
  (if (> end start)
    (ok true)
    (err ERR-INVALID-END-TIME))
)

(define-private (validate-bid-amount (amount uint) (current uint))
  (if (>= amount (+ current (var-get min-bid-increment)))
    (ok true)
    (err ERR-BID-TOO-LOW))
)

(define-private (validate-seller (seller principal))
  (if (is-eq seller tx-sender)
    (ok true)
    (err ERR-NOT-OWNER))
)

(define-private (validate-location (loc (string-utf8 100)))
  (if (and (> (len loc) u0) (<= (len loc) u100))
    (ok true)
    (err ERR-INVALID-LOCATION))
)

(define-private (validate-currency (cur (string-utf8 20)))
  (if (or (is-eq cur u"STX") (is-eq cur u"USD") (is-eq cur u"BTC"))
    (ok true)
    (err ERR-INVALID-CURRENCY))
)

(define-private (validate-bidder (bidder principal))
  (if (not (is-eq bidder tx-sender))
    (ok true)
    (err ERR-INVALID-BIDDER))
)

(define-public (set-min-bid-increment (new-inc uint))
  (begin
    (asserts! (is-eq tx-sender (var-get nft-contract)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> new-inc u0) (err ERR-INVALID-INCREMENT))
    (var-set min-bid-increment new-inc)
    (ok true)
  )
)

(define-public (set-extension-period (new-ext uint))
  (begin
    (asserts! (is-eq tx-sender (var-get nft-contract)) (err ERR-NOT-AUTHORIZED))
    (asserts! (> new-ext u0) (err ERR-INVALID-EXTENSION))
    (var-set extension-period new-ext)
    (ok true)
  )
)

(define-public (set-platform-commission (new-com uint))
  (begin
    (asserts! (is-eq tx-sender (var-get nft-contract)) (err ERR-NOT-AUTHORIZED))
    (asserts! (<= new-com u10) (err ERR-INVALID-COMMISSION))
    (var-set platform-commission new-com)
    (ok true)
  )
)

(define-public (create-auction (nft-id uint) (initiative-id uint) (reserve-price uint) (start-time uint) (duration uint) (location (string-utf8 100)) (currency (string-utf8 20)))
  (let
    (
      (auction-id (var-get next-auction-id))
      (end-time (+ start-time duration))
    )
    (asserts! (< auction-id (var-get max-auctions)) (err ERR-MAX-AUCTIONS-EXCEEDED))
    (try! (validate-nft-id nft-id))
    (try! (validate-initiative-id initiative-id))
    (try! (validate-reserve-price reserve-price))
    (try! (validate-start-time start-time))
    (try! (validate-duration duration))
    (try! (validate-end-time end-time start-time))
    (try! (validate-location location))
    (try! (validate-currency currency))
    (asserts! (is-eq tx-sender (as-contract (contract-call? .nft-minter get-owner nft-id))) (err ERR-NOT-OWNER))
    (try! (as-contract (contract-call? .nft-minter transfer nft-id tx-sender (as-contract tx-sender))))
    (map-set auctions { auction-id: auction-id }
      {
        nft-id: nft-id,
        initiative-id: initiative-id,
        seller: tx-sender,
        highest-bidder: none,
        highest-bid: u0,
        start-time: start-time,
        end-time: end-time,
        reserve-price: reserve-price,
        active: true,
        extended: false,
        location: location,
        currency: currency,
        status: u1
      }
    )
    (var-set next-auction-id (+ auction-id u1))
    (print { event: "auction-created", id: auction-id })
    (ok auction-id)
  )
)

(define-public (place-bid (auction-id uint) (bid-amount uint))
  (let
    (
      (auction (unwrap! (get-auction auction-id) (err ERR-NO-AUCTION)))
      (current-bid (get highest-bid auction))
      (current-bidder (get highest-bidder auction))
      (end-time (get end-time auction))
    )
    (asserts! (get active auction) (err ERR-AUCTION-ENDED))
    (asserts! (>= block-height (get start-time auction)) (err ERR-NOT-STARTED))
    (asserts! (< block-height end-time) (err ERR-AUCTION-ENDED))
    (try! (validate-bid-amount bid-amount current-bid))
    (try! (stx-transfer? bid-amount tx-sender (as-contract tx-sender)))
    (match current-bidder
      bidder
      (try! (as-contract (stx-transfer? current-bid (as-contract tx-sender) bidder)))
      true
    )
    (if (>= (- end-time block-height) (var-get extension-period))
      (ok true)
      (map-set auctions { auction-id: auction-id }
        (merge auction { end-time: (+ end-time (var-get extension-period)), extended: true })
      )
    )
    (map-set auctions { auction-id: auction-id }
      (merge auction { highest-bidder: (some tx-sender), highest-bid: bid-amount })
    )
    (map-set bids { auction-id: auction-id, bidder: tx-sender }
      { bid-amount: bid-amount, timestamp: block-height }
    )
    (print { event: "bid-placed", id: auction-id, bidder: tx-sender, amount: bid-amount })
    (ok true)
  )
)

(define-public (end-auction (auction-id uint))
  (let
    (
      (auction (unwrap! (get-auction auction-id) (err ERR-NO-AUCTION)))
      (highest-bid (get highest-bid auction))
      (highest-bidder (get highest-bidder auction))
      (seller (get seller auction))
      (nft-id (get nft-id auction))
      (initiative-id (get initiative-id auction))
      (commission-amount (/ (* highest-bid (var-get platform-commission)) u100))
      (net-amount (- highest-bid commission-amount))
    )
    (asserts! (get active auction) (err ERR-ALREADY-ENDED))
    (asserts! (>= block-height (get end-time auction)) (err ERR-AUCTION_ACTIVE))
    (map-set auctions { auction-id: auction-id }
      (merge auction { active: false, status: u2 })
    )
    (if (>= highest-bid (get reserve-price auction))
      (begin
        (match highest-bidder
          bidder
          (begin
            (try! (as-contract (contract-call? .nft-minter transfer nft-id (as-contract tx-sender) bidder)))
            (try! (as-contract (stx-transfer? net-amount (as-contract tx-sender) seller)))
            (try! (as-contract (stx-transfer? commission-amount (as-contract tx-sender) (var-get fund-contract))))
            (print { event: "auction-ended", id: auction-id, winner: bidder, amount: highest-bid })
          )
          (begin
            (try! (as-contract (contract-call? .nft-minter transfer nft-id (as-contract tx-sender) seller)))
            (print { event: "auction-ended-no-bids", id: auction-id })
          )
        )
      )
      (begin
        (try! (as-contract (contract-call? .nft-minter transfer nft-id (as-contract tx-sender) seller)))
        (print { event: "auction-ended-below-reserve", id: auction-id })
      )
    )
    (ok true)
  )
)

(define-public (cancel-auction (auction-id uint))
  (let
    (
      (auction (unwrap! (get-auction auction-id) (err ERR-NO-AUCTION)))
      (highest-bidder (get highest-bidder auction))
      (highest-bid (get highest-bid auction))
      (nft-id (get nft-id auction))
      (seller (get seller auction))
    )
    (asserts! (is-eq tx-sender seller) (err ERR-NOT-AUTHORIZED))
    (asserts! (get active auction) (err ERR-AUCTION-ENDED))
    (asserts! (< block-height (get start-time auction)) (err ERR-AUCTION_ACTIVE))
    (map-set auctions { auction-id: auction-id }
      (merge auction { active: false, status: u3 })
    )
    (try! (as-contract (contract-call? .nft-minter transfer nft-id (as-contract tx-sender) seller)))
    (match highest-bidder
      bidder
      (try! (as-contract (stx-transfer? highest-bid (as-contract tx-sender) bidder)))
      true
    )
    (print { event: "auction-cancelled", id: auction-id })
    (ok true)
  )
)

(define-read-only (get-active-auctions-count)
  (fold count-active (map-get? auctions) u0)
)

(define-private (count-active (auction { nft-id: uint, initiative-id: uint, seller: principal, highest-bidder: (optional principal), highest-bid: uint, start-time: uint, end-time: uint, reserve-price: uint, active: bool, extended: bool, location: (string-utf8 100), currency: (string-utf8 20), status: uint }) (acc uint))
  (if (get active auction)
    (+ acc u1)
    acc)
)