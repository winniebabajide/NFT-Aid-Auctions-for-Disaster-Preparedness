import { describe, it, expect, beforeEach } from "vitest";
import { uintCV } from "@stacks/transactions";

const ERR_NOT_AUTHORIZED = 100;
const ERR_AUCTION_ENDED = 101;
const ERR_AUCTION_ACTIVE = 102;
const ERR_INVALID_BID = 103;
const ERR_NO_AUCTION = 104;
const ERR_INVALID_INITIATIVE = 105;
const ERR_INVALID_NFT = 106;
const ERR_INVALID_RESERVE = 107;
const ERR_INVALID_DURATION = 108;
const ERR_INVALID_START_TIME = 109;
const ERR_INVALID_END_TIME = 110;
const ERR_BID_TOO_LOW = 111;
const ERR_NOT_OWNER = 112;
const ERR_INVALID_LOCATION = 122;
const ERR_INVALID_CURRENCY = 123;
const ERR_MAX_AUCTIONS_EXCEEDED = 118;
const ERR_NOT_STARTED = 116;

interface Auction {
  nftId: number;
  initiativeId: number;
  seller: string;
  highestBidder: string | null;
  highestBid: number;
  startTime: number;
  endTime: number;
  reservePrice: number;
  active: boolean;
  extended: boolean;
  location: string;
  currency: string;
  status: number;
}

interface Bid {
  bidAmount: number;
  timestamp: number;
}

interface Result<T> {
  ok: boolean;
  value: T;
}

class AuctionEngineMock {
  state: {
    nextAuctionId: number;
    maxAuctions: number;
    minBidIncrement: number;
    extensionPeriod: number;
    platformCommission: number;
    nftContract: string;
    escrowContract: string;
    fundContract: string;
    initiativeRegistry: string;
    auctions: Map<number, Auction>;
    bids: Map<string, Bid>;
  } = {
    nextAuctionId: 0,
    maxAuctions: 10000,
    minBidIncrement: 100,
    extensionPeriod: 144,
    platformCommission: 5,
    nftContract: "ST1TEST",
    escrowContract: "ST1TEST",
    fundContract: "ST1TEST",
    initiativeRegistry: "ST1TEST",
    auctions: new Map(),
    bids: new Map(),
  };
  blockHeight: number = 0;
  caller: string = "ST1TEST";
  nftOwners: Map<number, string> = new Map();
  stxTransfers: Array<{ amount: number; from: string; to: string }> = [];

  constructor() {
    this.reset();
  }

  reset() {
    this.state = {
      nextAuctionId: 0,
      maxAuctions: 10000,
      minBidIncrement: 100,
      extensionPeriod: 144,
      platformCommission: 5,
      nftContract: "ST1TEST",
      escrowContract: "ST1TEST",
      fundContract: "ST1TEST",
      initiativeRegistry: "ST1TEST",
      auctions: new Map(),
      bids: new Map(),
    };
    this.blockHeight = 0;
    this.caller = "ST1TEST";
    this.nftOwners = new Map();
    this.stxTransfers = [];
  }

  createAuction(
    nftId: number,
    initiativeId: number,
    reservePrice: number,
    startTime: number,
    duration: number,
    location: string,
    currency: string
  ): Result<number> {
    if (this.state.nextAuctionId >= this.state.maxAuctions) return { ok: false, value: ERR_MAX_AUCTIONS_EXCEEDED };
    if (nftId <= 0) return { ok: false, value: ERR_INVALID_NFT };
    if (initiativeId <= 0) return { ok: false, value: ERR_INVALID_INITIATIVE };
    if (reservePrice <= 0) return { ok: false, value: ERR_INVALID_RESERVE };
    if (startTime < this.blockHeight) return { ok: false, value: ERR_INVALID_START_TIME };
    if (duration <= 144 || duration >= 10080) return { ok: false, value: ERR_INVALID_DURATION };
    if (!location || location.length > 100) return { ok: false, value: ERR_INVALID_LOCATION };
    if (!["STX", "USD", "BTC"].includes(currency)) return { ok: false, value: ERR_INVALID_CURRENCY };
    if (this.nftOwners.get(nftId) !== this.caller) return { ok: false, value: ERR_NOT_OWNER };
    this.nftOwners.set(nftId, "contract");
    const id = this.state.nextAuctionId;
    const endTime = startTime + duration;
    this.state.auctions.set(id, {
      nftId,
      initiativeId,
      seller: this.caller,
      highestBidder: null,
      highestBid: 0,
      startTime,
      endTime,
      reservePrice,
      active: true,
      extended: false,
      location,
      currency,
      status: 1,
    });
    this.state.nextAuctionId++;
    return { ok: true, value: id };
  }

  placeBid(auctionId: number, bidAmount: number): Result<boolean> {
    const auction = this.state.auctions.get(auctionId);
    if (!auction) return { ok: false, value: false };
    if (!auction.active) return { ok: false, value: false };
    if (this.blockHeight < auction.startTime) return { ok: false, value: ERR_NOT_STARTED };
    if (this.blockHeight >= auction.endTime) return { ok: false, value: false };
    if (bidAmount < auction.highestBid + this.state.minBidIncrement) return { ok: false, value: ERR_BID_TOO_LOW };
    if (auction.highestBidder) {
      this.stxTransfers.push({ amount: auction.highestBid, from: "contract", to: auction.highestBidder });
    }
    this.stxTransfers.push({ amount: bidAmount, from: this.caller, to: "contract" });
    if (auction.endTime - this.blockHeight < this.state.extensionPeriod) {
      auction.endTime += this.state.extensionPeriod;
      auction.extended = true;
    }
    auction.highestBidder = this.caller;
    auction.highestBid = bidAmount;
    this.state.bids.set(`${auctionId}-${this.caller}`, { bidAmount, timestamp: this.blockHeight });
    return { ok: true, value: true };
  }

  endAuction(auctionId: number): Result<boolean> {
    const auction = this.state.auctions.get(auctionId);
    if (!auction) return { ok: false, value: false };
    if (!auction.active) return { ok: false, value: false };
    if (this.blockHeight < auction.endTime) return { ok: false, value: false };
    auction.active = false;
    auction.status = 2;
    if (auction.highestBid >= auction.reservePrice && auction.highestBidder) {
      this.nftOwners.set(auction.nftId, auction.highestBidder);
      const commission = (auction.highestBid * this.state.platformCommission) / 100;
      const net = auction.highestBid - commission;
      this.stxTransfers.push({ amount: net, from: "contract", to: auction.seller });
      this.stxTransfers.push({ amount: commission, from: "contract", to: this.state.fundContract });
    } else {
      this.nftOwners.set(auction.nftId, auction.seller);
    }
    return { ok: true, value: true };
  }

  getAuction(id: number): Auction | undefined {
    return this.state.auctions.get(id);
  }
}

describe("AuctionEngine", () => {
  let contract: AuctionEngineMock;

  beforeEach(() => {
    contract = new AuctionEngineMock();
    contract.reset();
  });

  it("creates auction successfully", () => {
    contract.nftOwners.set(1, "ST1TEST");
    const result = contract.createAuction(1, 1, 1000, 0, 288, "LocationX", "STX");
    expect(result.ok).toBe(true);
    expect(result.value).toBe(0);
    const auction = contract.getAuction(0);
    expect(auction?.nftId).toBe(1);
    expect(auction?.reservePrice).toBe(1000);
    expect(auction?.active).toBe(true);
  });

  it("rejects invalid NFT", () => {
    const result = contract.createAuction(0, 1, 1000, 0, 288, "LocationX", "STX");
    expect(result.ok).toBe(false);
    expect(result.value).toBe(ERR_INVALID_NFT);
  });

  it("places bid successfully", () => {
    contract.nftOwners.set(1, "ST1TEST");
    contract.createAuction(1, 1, 1000, 0, 288, "LocationX", "STX");
    contract.blockHeight = 10;
    contract.caller = "ST2BIDDER";
    const result = contract.placeBid(0, 1100);
    expect(result.ok).toBe(true);
    const auction = contract.getAuction(0);
    expect(auction?.highestBid).toBe(1100);
    expect(auction?.highestBidder).toBe("ST2BIDDER");
  });

  it("rejects low bid", () => {
    contract.nftOwners.set(1, "ST1TEST");
    contract.createAuction(1, 1, 1000, 0, 288, "LocationX", "STX");
    contract.blockHeight = 10;
    contract.caller = "ST2BIDDER";
    contract.placeBid(0, 1100);
    const result = contract.placeBid(0, 1150);
    expect(result.ok).toBe(false);
    expect(result.value).toBe(ERR_BID_TOO_LOW);
  });

  it("ends auction successfully", () => {
    contract.nftOwners.set(1, "ST1TEST");
    contract.createAuction(1, 1, 1000, 0, 288, "LocationX", "STX");
    contract.blockHeight = 10;
    contract.caller = "ST2BIDDER";
    contract.placeBid(0, 1100);
    contract.blockHeight = 300;
    contract.caller = "ST1TEST";
    const result = contract.endAuction(0);
    expect(result.ok).toBe(true);
    const auction = contract.getAuction(0);
    expect(auction?.active).toBe(false);
    expect(contract.nftOwners.get(1)).toBe("ST2BIDDER");
  });

  it("parses auction params with Clarity", () => {
    const nftId = uintCV(1);
    const reserve = uintCV(1000);
    expect(nftId.value).toEqual(BigInt(1));
    expect(reserve.value).toEqual(BigInt(1000));
  });
});