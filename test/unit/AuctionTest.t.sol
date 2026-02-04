// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "src/Auction.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC721} from "test/mock/MockERC721.sol";
import {RejectETH} from "test/mock/RejectETH.sol";

/// @title AuctionTest
/// @notice Unit tests for Auction (start, bid, withdraw, end, and getters).
/// @dev
/// - Uses HelperConfig to deploy Auction + MockERC721 and prepare token approval.
/// - Uses two bidder EOAs (bob, alice) and a malicious receiver (RejectETH).
/// - Exercises both reserve-met and reserve-not-met settlement paths.
/// - Ensures pull-payment refunds work and are not blocked by a reverting receiver.
contract AuctionTest is Test {
    Auction public auction;
    HelperConfig public config;
    MockERC721 public nft;
    RejectETH public attacker;

    // -----------------------------
    // Constants / test configuration
    // -----------------------------
    uint256 public constant STATUS_NOT_STARTED = 0;
    uint256 public constant STATUS_START = 1;
    uint256 public constant STATUS_END = 2;

    address public constant ADDRESS_ZERO = address(0);
    uint256 public constant ZERO = 0;

    uint256 public constant INITAL_BALANCE = 100 ether;
    uint256 public constant FIRST_BID = 0.1 ether;

    // These should match HelperConfig defaults, otherwise getter tests will fail.
    uint256 public constant DURATION = 1 days;
    uint256 public constant RESERVE_PRICE = 1 ether;

    // Test actors (EOAs)
    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");

    // Seller comes from the deployed Auction contract (immutable set in constructor).
    address public seller;
    uint256 public tokenId;

    /// @notice Starts the auction as the seller.
    modifier startAuction() {
        vm.prank(seller);
        auction.start(address(nft), tokenId);
        _;
    }

    /// @notice Executes a bid from `bidder` for `amount`.
    /// @dev Helper modifier to keep tests concise.
    modifier executeBid(address bidder, uint256 amount) {
        vm.prank(bidder);
        auction.bid{value: amount}();
        _;
    }

    /// @notice Test setup executed before each test.
    /// @dev
    /// - Deploy contracts via HelperConfig (also mints + approves the NFT).
    /// - Funds bidders with ETH.
    /// - Deploys RejectETH and funds it to simulate a bidder that cannot receive refunds.
    function setUp() public {
        config = new HelperConfig();
        (auction, nft, tokenId) = config.run();

        seller = auction.getSeller();

        vm.deal(bob, INITAL_BALANCE);
        vm.deal(alice, INITAL_BALANCE);

        attacker = new RejectETH();
        vm.deal(address(attacker), INITAL_BALANCE);
    }

    // ============================================================
    // START() TESTS
    // ============================================================

    /// @notice start() should revert if caller is not the seller.
    function test__start__revertYouAreNotSeller() public {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__YouAreNotSeller.selector);
        auction.start(ADDRESS_ZERO, ZERO);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// @notice start() should revert if NFT address is zero.
    function test__start__revertNftAddressCanNotBeZero() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__NftAddressCanNotBeZero.selector);
        auction.start(ADDRESS_ZERO, tokenId);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// @notice start() should revert if tokenId is zero (disallowed by contract design).
    function test__start__revertTokenIdCanNotBeZero() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__TokenIdCanNotBeZero.selector);
        auction.start(address(nft), ZERO);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// @notice start() should revert if the auction is already active.
    function test__start__revertAuctionAlreadyStarted() public {
        vm.startPrank(seller);
        auction.start(address(nft), tokenId);

        assertEq(auction.getAuctionStatus(), STATUS_START);

        vm.expectRevert(Auction.Auction__AuctionAlreadyStarted.selector);
        auction.start(address(nft), tokenId);

        vm.stopPrank();

        assertEq(auction.getAuctionStatus(), STATUS_START);
    }

    /// @notice start() success path: NFT escrow + correct state initialization.
    function test__start() public {
        vm.prank(seller);
        auction.start(address(nft), tokenId);

        // NFT must be escrowed in the auction contract
        assertEq(nft.ownerOf(tokenId), address(auction));

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(uint256(auctionInformation.status), STATUS_START);
        assertEq(auctionInformation.endAt, block.timestamp + auction.getDuration());
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);

        // Verify stored NFT metadata
        Auction.WorkOfArt memory workOfArt = auctionInformation.workOfArt;
        assertEq(address(workOfArt.nft), address(nft));
        assertEq(workOfArt.tokenId, tokenId);
    }

    // ============================================================
    // BID() TESTS
    // ============================================================

    /// @notice bid() should revert when auction is not started.
    function test__bid__revertAuctionNotStarted() public {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__AuctionNotStarted.selector);
        auction.bid();

        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);
    }

    /// @notice bid() should revert if the bid is not strictly higher than highestBid.
    /// @dev
    /// - Auction starts
    /// - Alice bids FIRST_BID
    /// - Bob tries lower bid and must revert
    function test__bid__revertBidNeedBeHigherThanCurrentHighestBid()
        public
        startAuction
        executeBid(alice, FIRST_BID)
    {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__BidNeedBeHigherThanCurrentHighestBid.selector);
        auction.bid{value: FIRST_BID / 2}();

        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, FIRST_BID);
        assertEq(auctionInformation.highestBidder, alice);
    }

    /// @notice bid() should revert after auction end time.
    /// @dev Warp beyond endAt and ensure bids revert.
    function test__bid__revertAuctionTimeEnded() public startAuction executeBid(alice, FIRST_BID) {
        vm.warp(block.timestamp + auction.getDuration() + 1);

        vm.prank(bob);
        vm.expectRevert(Auction.Auction__AuctionTimeEnded.selector);
        auction.bid{value: FIRST_BID * 2}();

        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, FIRST_BID);
        assertEq(auctionInformation.highestBidder, alice);
    }

    /// @notice bid() success: outbidding updates leader and credits previous bidder in pendingReturns.
    function test__bid() public startAuction executeBid(alice, FIRST_BID) executeBid(bob, FIRST_BID * 2) {
        // Alice should be refundable (was outbid)
        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID);
        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, FIRST_BID * 2);
        assertEq(auctionInformation.highestBidder, bob);
    }

    // ============================================================
    // WITHDRAW() TESTS
    // ============================================================

    /// @notice withdraw() should revert if caller has nothing to withdraw.
    function test__withdraw__revertNothingToWithdraw() public startAuction {
        vm.prank(alice);
        vm.expectRevert(Auction.Auction__NothingToWithdraw.selector);
        auction.withdraw();
    }

    /// @notice withdraw() should revert if ETH transfer to receiver fails.
    /// @dev
    /// - `RejectETH` is used to simulate a receiver that reverts on receiving ETH.
    /// - The refund remains in `pendingReturns` if the call fails (since the function reverts).
    function test__withdraw__revertWithdrawFailed()
        public
        startAuction
        executeBid(address(attacker), FIRST_BID)
        executeBid(alice, FIRST_BID * 2)
    {
        vm.prank(address(attacker));
        vm.expectRevert(Auction.Auction__WithdrawFailed.selector);
        auction.withdraw();

        // pendingReturns should remain unchanged since withdrawal reverted
        assertEq(auction.getPendingReturnsByUser(address(attacker)), FIRST_BID);
    }

    /// @notice withdraw() success: outbid bidder can retrieve funds.
    /// @dev
    /// - Bob bids first
    /// - Alice outbids
    /// - Bob withdraws and should recover his exact outbid amount
    function test__withdraw() public startAuction executeBid(bob, FIRST_BID) executeBid(alice, FIRST_BID * 2) {
        vm.prank(bob);
        auction.withdraw();

        // Bob started with INITAL_BALANCE and paid FIRST_BID, then withdrew FIRST_BID => back to initial
        assertEq(bob.balance, INITAL_BALANCE);
        assertEq(auction.getPendingReturnsByUser(bob), ZERO);
    }

    // ============================================================
    // END() TESTS
    // ============================================================

    /// @notice end() should revert if caller is not seller.
    function test__end__revertYouAreNotSeller() public startAuction {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__YouAreNotSeller.selector);
        auction.end();

        assertEq(auction.getAuctionStatus(), STATUS_START);
    }

    /// @notice end() should revert if auction was never started.
    function test__end__revertAuctionNotStarted() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__AuctionNotStarted.selector);
        auction.end();
    }

    /// @notice end() should revert if called before endAt.
    function test__end__revertTimeDoNotEndYet() public startAuction {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__TimeDoNotEndYet.selector);
        auction.end();
    }

    /// @notice end() success when highest bid meets reserve price.
    /// @dev
    /// - Auction ends: NFT -> winner, ETH -> seller
    /// - Highest bid state is reset
    function test__end__highestBidHighToReservePrice()
        public
        startAuction
        executeBid(bob, FIRST_BID)
        executeBid(alice, FIRST_BID * 100)
    {
        vm.warp(block.timestamp + auction.getDuration() + 1);

        uint256 currentBalanceSeller = seller.balance;

        vm.prank(seller);
        auction.end();

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(uint256(auctionInformation.status), STATUS_END);
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);

        // Winner receives the NFT
        assertEq(nft.ownerOf(tokenId), alice);

        // Seller receives ETH (exact increase depends on gas/accounting, so we only check it increased)
        assert(seller.balance > currentBalanceSeller);
    }

    /// @notice end() success when highest bid DOES NOT meet reserve price.
    /// @dev
    /// - NFT is returned to seller
    /// - Highest bidder can withdraw their bid via pendingReturns
    /// - Seller balance should not increase
    function test__end__highestBidLowToReservePrice()
        public
        startAuction
        executeBid(bob, FIRST_BID)
        executeBid(alice, FIRST_BID * 2)
    {
        vm.warp(block.timestamp + auction.getDuration() + 1);

        uint256 currentBalanceSeller = seller.balance;

        vm.prank(seller);
        auction.end();

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(uint256(auctionInformation.status), STATUS_END);
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);

        // Highest bidder can withdraw their full highest bid
        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID * 2);

        // NFT is returned to seller
        assertEq(nft.ownerOf(tokenId), seller);

        // Seller should not receive ETH if reserve is not met
        assertEq(seller.balance, currentBalanceSeller);
    }

    // ============================================================
    // GETTER TESTS
    // ============================================================

    /// @notice Getter: seller address should match the deployment seller.
    function test__get__getSeller() public view {
        assertEq(auction.getSeller(), seller);
    }

    /// @notice Getter: duration should match HelperConfig constant.
    function test__get__getDuration() public view {
        assertEq(auction.getDuration(), DURATION);
    }

    /// @notice Getter: reserve price should match HelperConfig constant.
    function test__get__getReservePrice() public view {
        assertEq(auction.getReservePrice(), RESERVE_PRICE);
    }

    /// @notice Getter: pendingReturns should reflect the outbid amount.
    function test__get__getPendingReturnsByUser()
        public
        startAuction
        executeBid(alice, FIRST_BID)
        executeBid(bob, FIRST_BID * 2)
    {
        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID);
    }

    /// @notice Getter: auction status should be NOT_STARTED before start().
    function test__get__getAuctionStatus() public view {
        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }
}
