// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";
import {AuctionHandler} from "test/invariant/AuctionHandler.t.sol";

/// @title AuctionInvariantTest
/// @notice Invariant tests for the Auction contract using a stateful fuzzing handler.
/// @dev
/// - `StdInvariant` executes randomized sequences of handler calls.
/// - `AuctionHandler` exposes a set of actions (start/bid/withdraw/warp/end),
///   often called in invalid states; the handler wraps calls in try/catch so the
///   invariant run does not revert.
/// - The invariants are checked after each sequence step to ensure certain
///   properties always hold.
contract AuctionInvariantTest is StdInvariant, Test {
    Auction public auction;
    MockERC721 public nft;
    AuctionHandler public handler;

    address public seller;
    uint256 public tokenId;

    // -----------------------------
    // Constants / configuration
    // -----------------------------
    address public constant ADDRESS_ZERO = address(0);
    uint256 public constant ZERO = 0;

    uint256 public constant DURATION = 1 hours;
    uint256 public constant RESERVE_PRICE = 1 ether;

    // Mirroring Auction.Status enum cast to uint
    uint256 public constant STATUS_NOT_STARTED = 0;
    uint256 public constant STATUS_START = 1;
    uint256 public constant STATUS_END = 2;

    /// @notice Deploys contracts and wires the handler as the fuzz target.
    /// @dev
    /// - The seller deploys Auction and mints an NFT.
    /// - The handler is configured with references to auction/nft/seller/tokenId.
    /// - `targetContract(handler)` tells Foundry: "randomly call functions on this handler".
    function setUp() external {
        seller = makeAddr("seller");

        vm.startPrank(seller);

        auction = new Auction(DURATION, RESERVE_PRICE);

        nft = new MockERC721();
        tokenId = nft.mint(seller);

        vm.stopPrank();

        handler = new AuctionHandler(auction, nft, seller, tokenId);

        // Foundry will fuzz-call the handler methods in arbitrary sequences.
        targetContract(address(handler));
    }

    /// @notice If the auction is STARTED, the NFT must be held in escrow by the auction contract.
    /// @dev
    /// When `Auction.start()` is successful, it transfers the NFT into the auction contract.
    /// This invariant ensures the escrow property holds throughout the active auction phase.
    function invariant__ifStarted_nftIsInEscrow() external view {
        uint256 status = auction.getAuctionStatus();

        if (status == STATUS_START) {
            address owner = nft.ownerOf(tokenId);
            assertEq(owner, address(auction));
        }
    }

    /// @notice If the auction is NOT_STARTED or ENDED, the auction contract should not hold the NFT.
    /// @dev
    /// - NOT_STARTED: NFT should still belong to the seller (never escrowed).
    /// - ENDED: NFT should belong to either the seller (reserve not met) or the winner (reserve met).
    /// In both cases, the auction contract must not remain the owner.
    function invariant__ifNotStartedOrEnded__contractDoesNotHoldNft() external view {
        uint256 status = auction.getAuctionStatus();

        if (status == STATUS_NOT_STARTED || status == STATUS_END) {
            address owner = nft.ownerOf(tokenId);
            assertTrue(owner != address(auction));
        }
    }

    /// @notice Highest-bid state should be reset when the auction has ended.
    /// @dev
    /// ⚠️ NOTE: The current implementation checks `STATUS_START` but the name says "end resets".
    /// In the provided Auction contract, `highestBid` and `highestBidder` are reset inside `end()`,
    /// which sets status to END. That means this invariant likely intends to check `STATUS_END`,
    /// not `STATUS_START`.
    ///
    /// If you keep it as-is, it will fail as soon as a valid bid is placed (expected),
    /// because during START the highestBid can be > 0.
    function invariant__endResetsHighestBidState() external view {
        uint256 status = auction.getAuctionStatus();
        Auction.AuctionInformation memory a = auction.getAuction();

        // Likely intended:
        // if (status == STATUS_END) { ... }
        if (status == STATUS_START) {
            assertEq(a.highestBid, ZERO);
            assertEq(a.highestBidder, ADDRESS_ZERO);
        }
    }

    /// @notice If there is no highestBidder, then highestBid must be zero.
    /// @dev
    /// This should always hold because:
    /// - Initial state: (highestBidder=0, highestBid=0)
    /// - After bids: highestBidder != 0
    /// - After end(): state is reset to (0,0)
    function invariant__highestBidderZeroMeansHighestBidZero() external view {
        Auction.AuctionInformation memory a = auction.getAuction();

        if (a.highestBidder == ADDRESS_ZERO) {
            assertEq(a.highestBid, ZERO);
        }
    }
}
