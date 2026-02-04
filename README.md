# 🏷️ NFT English Auction — Solidity & Foundry

This project implements a **secure English auction** for **ERC-721 NFTs** using Solidity and Foundry.
It includes **unit tests, fuzz tests, invariant tests**, and multiple **security-focused mocks** to validate real-world attack scenarios.

The auction supports:

* Time-bounded bidding
* Reserve price enforcement
* Safe refund handling (pull payments)
* Robust testing against edge cases and malicious actors

---

## 📦 Features

* ✅ **English auction** (highest bid wins)
* ✅ **Reserve price** support
* ✅ **NFT escrow** during active auction
* ✅ **Pull-payment refunds** (`pendingReturns`)
* ✅ **Reentrancy protection**
* ✅ Extensive test suite:

  * Unit tests
  * Fuzz tests
  * Invariant (stateful) tests
* ✅ Security mocks (reverting ETH receiver)

---

## 🧱 Architecture

### Core Contract

#### `Auction.sol`

Main auction contract responsible for:

* Auction lifecycle (`start → bid → withdraw → end`)
* NFT custody and settlement
* Bid tracking and refunds

**Key design decisions**

* Uses **custom errors** (gas efficient)
* Uses **pull payments** to prevent DoS via failed refunds
* Uses `ReentrancyGuard` on ETH transfers
* Immutable configuration (seller, duration, reserve price)

---

### Supporting Contracts

#### `MockERC721.sol`

Minimal ERC721 mock used for testing:

* Permissionless minting
* Sequential token IDs
* Not intended for production

#### `RejectETH.sol`

Security mock that **reverts on ETH receive**:

* Simulates malicious or incompatible receivers
* Used to test refund failure scenarios

---

## 🔁 Auction Flow

1. **Start**

   * Seller starts auction
   * NFT transferred to contract (escrow)
2. **Bid**

   * Users place bids with ETH
   * Higher bids replace previous ones
   * Outbid users receive refundable balance
3. **Withdraw**

   * Outbid users withdraw ETH manually
4. **End**

   * If `highestBid ≥ reservePrice`:

     * NFT → winner
     * ETH → seller
   * Else:

     * NFT → seller
     * Highest bidder can withdraw ETH

---

## 🧪 Testing Strategy

### ✅ Unit Tests (`AuctionTest.t.sol`)

Covers:

* All revert paths
* Successful flows
* Reserve met vs not met
* Refund logic
* Getter correctness
* ETH transfer failures via `RejectETH`

### 🔀 Fuzz Tests (`AuctionFuzzTest.t.sol`)

Uses randomized inputs to test:

* Unauthorized access
* Bid edge cases
* Time-based failures
* State consistency under random actors

### ♾️ Invariant Tests

Uses **stateful fuzzing** with a handler:

#### `AuctionHandler.t.sol`

Simulates arbitrary sequences of:

* `start`
* `bid`
* `withdraw`
* `warp`
* `end`

All calls are wrapped in `try/catch` to explore invalid states safely.

#### `AuctionInvariantTest.t.sol`

Ensures properties like:

* NFT escrow correctness
* No NFT stuck in contract
* Bid state consistency
* Post-end state cleanup

---

## 🔐 Security Considerations

* **Pull over push payments** → avoids refund-based DoS
* **Reentrancy-safe ETH transfers**
* **Malicious receiver simulation**
* **Invariant testing** to detect unexpected state corruption
* Explicit access control (`onlySeller`)

---

## 🛠️ Tech Stack

* **Solidity** `0.8.30`
* **Foundry**

  * forge
  * cast
  * anvil
* **OpenZeppelin Contracts**

  * ERC721
  * ReentrancyGuard

---

## 🚀 Getting Started

### Prerequisites

* Foundry installed
  👉 [https://book.getfoundry.sh/getting-started/installation](https://book.getfoundry.sh/getting-started/installation)

### Install dependencies

```bash
forge install
```

### Build

```bash
forge build
```

### Run tests

```bash
forge test -vvvv
```

### Run invariant tests

```bash
forge test --match-contract AuctionInvariantTest -vvvv
```

---

## 📁 Project Structure

```text
src/
 └── Auction.sol

script/
 └── HelperConfig.s.sol

test/
 ├── unit/
 │   └── AuctionTest.t.sol
 ├── fuzz/
 │   └── AuctionFuzzTest.t.sol
 ├── invariant/
 │   ├── AuctionHandler.t.sol
 │   └── AuctionInvariantTest.t.sol
 └── mock/
     ├── MockERC721.sol
     └── RejectETH.sol
```

---

## ⚠️ Disclaimer

This project is **for educational and testing purposes**.
It has **not been audited** and should **not be used in production** without a professional security review.

* hacerlo más **Web3-friendly** para recruiters,
* o escribir una **sección “Known Limitations / Future Improvements”** para dejarlo aún más pro.
