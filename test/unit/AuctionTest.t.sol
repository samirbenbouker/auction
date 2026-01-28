// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "src/Auction.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC721} from "test/mock/MockERC721.sol";
import {RejectETH} from "test/mock/RejectETH.sol";

contract AuctionTest is Test {
    Auction public auction;
    HelperConfig public config;
    MockERC721 public nft;
    RejectETH public attacker;

    uint256 public constant STATUS_NOT_STARTED = 0;
    uint256 public constant STATUS_START = 1;
    uint256 public constant STATUS_END = 2;
    address public constant ADDRESS_ZERO = address(0);
    uint256 public constant ZERO = 0;
    uint256 public constant INITAL_BALANCE = 100 ether;
    uint256 public constant FIRST_BID = 0.1 ether;
    uint256 public constant DURATION = 1 days;
    uint256 public constant RESERVE_PRICE = 1 ether;

    address public bob = makeAddr("bob");
    address public alice = makeAddr("alice");

    address public seller;
    uint256 public tokenId;

    modifier startAuction() {
        vm.prank(seller);
        auction.start(address(nft), tokenId);
        _;
    }

    modifier executeBid(address bidder, uint256 amount) {
        vm.prank(bidder);
        auction.bid{value: amount}();
        _;
    }

    function setUp() public {
        config = new HelperConfig();
        auction = config.run();

        seller = auction.getSeller();
        nft = new MockERC721();
        tokenId = nft.mint(seller);

        vm.prank(seller);
        nft.approve(address(auction), tokenId);

        vm.deal(bob, INITAL_BALANCE);
        vm.deal(alice, INITAL_BALANCE);

        attacker = new RejectETH();
        vm.deal(address(attacker), INITAL_BALANCE);
    }

    // start
    /// revert YouAreNotSeller
    function test__start__revertYouAreNotSeller() public {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__YouAreNotSeller.selector);
        auction.start(ADDRESS_ZERO, ZERO);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// revert NftAddressCanNotBeZero
    function test__start__revertNftAddressCanNotBeZero() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__NftAddressCanNotBeZero.selector);
        auction.start(ADDRESS_ZERO, tokenId);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// revert TokenIdCanNotBeZero
    function test__start__revertTokenIdCanNotBeZero() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__TokenIdCanNotBeZero.selector);
        auction.start(address(nft), ZERO);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    /// revert AuctionAlreadyStarted
    function test__start__revertAuctionAlreadyStarted() public {
        vm.startPrank(seller);
        auction.start(address(nft), tokenId);

        assertEq(auction.getAuctionStatus(), STATUS_START);

        vm.expectRevert(Auction.Auction__AuctionAlreadyStarted.selector);
        auction.start(address(nft), tokenId);

        vm.stopPrank();

        assertEq(auction.getAuctionStatus(), STATUS_START);
    }

    /// start successfully
    function test__start() public {
        vm.prank(seller);
        auction.start(address(nft), tokenId);

        assertEq(nft.ownerOf(tokenId), address(auction));

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(uint256(auctionInformation.status), STATUS_START);
        assertEq(auctionInformation.endAt, block.timestamp + auction.getDuration());
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);

        Auction.WorkOfArt memory workOfArt = auctionInformation.workOfArt;
        assertEq(address(workOfArt.nft), address(nft));
        assertEq(workOfArt.tokenId, tokenId);
    }

    // bid
    /// revert AuctionNotStarted
    function test__bid__revertAuctionNotStarted() public {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__AuctionNotStarted.selector);
        auction.bid();

        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);
    }

    /// revert BidNeedBeHigherThanCurrentHighestBid
    function test__bid__revertBidNeedBeHigherThanCurrentHighestBid() public startAuction executeBid(alice, FIRST_BID) {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__BidNeedBeHigherThanCurrentHighestBid.selector);
        auction.bid{value: FIRST_BID / 2}();

        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, FIRST_BID);
        assertEq(auctionInformation.highestBidder, alice);
    }

    /// revert AuctionTimeEnded
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

    /// bid successfully
    function test__bid() public startAuction executeBid(alice, FIRST_BID) executeBid(bob, FIRST_BID * 2) {
        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID);
        assertEq(auction.getPendingReturnsByUser(bob), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, FIRST_BID * 2);
        assertEq(auctionInformation.highestBidder, bob);
    }

    // withdraw
    /// revert NothingToWithdraw
    function test__withdraw__revertNothingToWithdraw() public startAuction {
        vm.prank(alice);
        vm.expectRevert(Auction.Auction__NothingToWithdraw.selector);
        auction.withdraw();
    }

    /// revert WithdrawFailed
    function test__withdraw__revertWithdrawFailed()
        public
        startAuction
        executeBid(address(attacker), FIRST_BID)
        executeBid(alice, FIRST_BID * 2)
    {
        vm.prank(address(attacker));
        vm.expectRevert(Auction.Auction__WithdrawFailed.selector);
        auction.withdraw();

        assertEq(auction.getPendingReturnsByUser(address(attacker)), FIRST_BID);
    }

    /// withdraw successfully
    function test__withdraw() public startAuction executeBid(bob, FIRST_BID) executeBid(alice, FIRST_BID * 2) {
        vm.prank(bob);
        auction.withdraw();

        assertEq(bob.balance, INITAL_BALANCE);
        assertEq(auction.getPendingReturnsByUser(bob), ZERO);
    }

    // end
    /// revert only seller
    function test__end__revertYouAreNotSeller() public startAuction {
        vm.prank(bob);
        vm.expectRevert(Auction.Auction__YouAreNotSeller.selector);
        auction.end();

        assertEq(auction.getAuctionStatus(), STATUS_START);
    }

    /// revert AuctionNotStarted
    function test__end__revertAuctionNotStarted() public {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__AuctionNotStarted.selector);
        auction.end();
    }

    /// revert TimeDoNotEndYet
    function test__end__revertTimeDoNotEndYet() public startAuction {
        vm.prank(seller);
        vm.expectRevert(Auction.Auction__TimeDoNotEndYet.selector);
        auction.end();
    }

    /// end successfully
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

        assertEq(nft.ownerOf(tokenId), alice);
        assert(seller.balance > currentBalanceSeller);
    }

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

        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID * 2);

        assertEq(nft.ownerOf(tokenId), seller);
        assertEq(seller.balance, currentBalanceSeller);
    }

    // get functions
    function test__get__getSeller() public view {
        assertEq(auction.getSeller(), seller);
    }

    function test__get__getDuration() public view {
        assertEq(auction.getDuration(), DURATION);
    }

    function test__get__getReservePrice() public view {
        assertEq(auction.getReservePrice(), RESERVE_PRICE);
    }

    function test__get__getPendingReturnsByUser()
        public
        startAuction
        executeBid(alice, FIRST_BID)
        executeBid(bob, FIRST_BID * 2)
    {
        assertEq(auction.getPendingReturnsByUser(alice), FIRST_BID);
    }

    function test__get__getAuctionStatus() public view {
        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }
}
