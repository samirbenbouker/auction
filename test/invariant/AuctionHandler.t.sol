// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

/// @title AuctionHandler
/// @notice Stateful fuzzing / invariant-testing handler for the Auction contract.
/// @dev
/// A "handler" is used with Foundry's invariant testing to model arbitrary sequences
/// of actions (start, bid, withdraw, warp, end) executed by different actors.
///
/// Key design choices:
/// - Maintains a fixed set of bidder addresses funded with ETH.
/// - Uses deterministic "randomness" (seed mod N) to pick the caller.
/// - Wraps calls in `try/catch` to prevent the invariant run from reverting
///   when an action is invalid given the current state (e.g., bidding before start).
/// - Includes a `warp` action to simulate time passing.
contract AuctionHandler is Test {
    Auction public auction;
    MockERC721 public nft;

    address public seller;
    uint256 public tokenId;

    /// @dev Set of possible participants in the system (besides the seller).
    address[] public bidders;

    /// @dev Initial ETH balance for each bidder to allow bidding/withdrawing.
    uint256 public constant INITIAL_BALANCE = 100 ether;

    /// @param _auction Deployed Auction contract under test.
    /// @param _nft Deployed MockERC721 contract being auctioned.
    /// @param _seller The auction seller (authorized to start/end).
    /// @param _tokenId Token ID minted to seller and approved to Auction.
    constructor(Auction _auction, MockERC721 _nft, address _seller, uint256 _tokenId) {
        auction = _auction;
        nft = _nft;
        seller = _seller;
        tokenId = _tokenId;

        // Build a small fixed set of bidder actors.
        // Using `makeAddr` ensures deterministic, unique addresses across test runs.
        bidders.push(makeAddr("bob"));
        bidders.push(makeAddr("carol"));
        bidders.push(makeAddr("deve"));
        bidders.push(makeAddr("erin"));

        // Fund each bidder so they can place bids.
        for (uint256 i = 0; i < bidders.length; i++) {
            vm.deal(bidders[i], INITIAL_BALANCE);
        }
    }

    /// @notice Picks one bidder from the `bidders` array based on a seed.
    /// @dev Deterministic pseudo-random selection via modulo.
    function _pickBidder(uint256 seed) internal view returns (address) {
        return bidders[seed % bidders.length];
    }

    /// @notice Attempts to start the auction.
    /// @dev
    /// - Sometimes called by the seller, sometimes by a random bidder.
    /// - Uses `startPrank/stopPrank` so that both the external call and potential
    ///   internal `msg.sender` checks behave as if `caller` initiated it.
    /// - Wrapped in try/catch to ignore expected reverts (e.g., non-seller start,
    ///   already started auction).
    function start(uint256 seed) external {
        // ~1/3 of the time we choose the seller; otherwise, a bidder.
        address caller = (seed % 3 == 0) ? seller : _pickBidder(seed);

        vm.startPrank(caller);
        try auction.start(address(nft), tokenId) {
            // no-op: successful start
        } catch {
            // ignore failures: invalid in current state or unauthorized caller
        }
        vm.stopPrank();
    }

    /// @notice Attempts to place a bid.
    /// @dev
    /// - Selects a bidder via seed.
    /// - Bounds the bid amount to a reasonable range so calls remain realistic
    ///   and do not overflow balances or consume extreme gas.
    /// - Wrapped in try/catch to ignore reverts (auction not started, time ended,
    ///   bid too low, etc.).
    function bid(uint256 bidderSeed, uint256 rawAmount) external {
        address bidder = _pickBidder(bidderSeed);

        // Constrain bid amount to avoid unrealistic or pathological values.
        uint256 amount = bound(rawAmount, 1 wei, 10 ether);

        vm.prank(bidder);
        try auction.bid{value: amount}() {
            // no-op: successful bid
        } catch {
            // ignore failures: invalid bid for current auction state
        }
    }

    /// @notice Attempts to withdraw refundable funds.
    /// @dev
    /// - Many calls will revert because most bidders have nothing to withdraw.
    /// - try/catch prevents failing the full invariant run.
    function withdraw(uint256 bidderSeed) external {
        address bidder = _pickBidder(bidderSeed);

        vm.prank(bidder);
        try auction.withdraw() {
            // no-op: successful withdrawal
        } catch {
            // ignore failures: nothing to withdraw or other expected conditions
        }
    }

    /// @notice Advances time by a bounded number of seconds.
    /// @dev
    /// - Important for exploring transitions that depend on `endAt`.
    /// - Bounds are kept small to avoid jumping too far into the future and
    ///   collapsing the state space.
    function warp(uint256 rawSeconds) external {
        uint256 secs = bound(rawSeconds, 0, 2 hours);
        vm.warp(block.timestamp + secs);
    }

    /// @notice Attempts to end the auction.
    /// @dev
    /// - Sometimes called by the seller (valid), sometimes by a bidder (invalid).
    /// - Wrapped in try/catch because end can revert if:
    ///   - not started,
    ///   - not enough time has passed,
    ///   - caller is not seller.
    function end(uint256 seed) external {
        // ~1/2 of the time we choose the seller; otherwise, a bidder.
        address caller = (seed % 2 == 0) ? seller : _pickBidder(seed);

        vm.prank(caller);
        try auction.end() {
            // no-op: successful end
        } catch {
            // ignore failures: invalid caller or auction not ready to end
        }
    }
}
