// SDPX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test, console} from "forge-std/Test.sol";
import {Auction} from "src/Auction.sol";
import {HelperConfig} from "script/HelperConfig.s.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

contract AuctionFuzzTest is Test {
    Auction public auction;
    MockERC721 public nft;
    HelperConfig public config;

    uint256 public tokenId;
    address public seller;

    uint256 public constant INITAL_BALANCE = 100 ether;
    uint256 public constant MAX_UINT_128 = type(uint128).max;
    address public constant ADDRESS_ZERO = address(0);
    uint256 public constant ZERO = 0;
    uint256 public constant STATUS_NOT_STARTED = 0;
    uint256 public constant STATUS_START = 1;
    uint256 public constant STATUS_END = 2;

    address public bob = makeAddr("bob");

    modifier startAuction() {
        vm.prank(seller);
        auction.start(address(nft), tokenId);
        _;
    }

    function setUp() public {
        config = new HelperConfig();

        (auction, nft, tokenId) = config.run();

        seller = auction.getSeller();
        vm.deal(bob, MAX_UINT_128);
    }

    // start
    /// reveert YouAreNotSeller
    function testFuzz__start__revertYouAreNotSeller(address user) public {
        vm.assume(user != ADDRESS_ZERO && user != seller);

        vm.prank(user);
        vm.expectRevert(Auction.Auction__YouAreNotSeller.selector);
        auction.start(ADDRESS_ZERO, ZERO);

        assertEq(auction.getAuctionStatus(), STATUS_NOT_STARTED);
    }

    // bid
    /// revert AuctionNotStarted
    function testFuzz__bid__revertAuctionNotStarted(address user, uint256 bid) public {
        vm.assume(user != ADDRESS_ZERO && user != seller);
        bid = bound(bid, 1, type(uint256).max);

        vm.deal(user, bid);

        vm.prank(user);
        vm.expectRevert(Auction.Auction__AuctionNotStarted.selector);
        auction.bid{value: bid}();

        assertEq(auction.getPendingReturnsByUser(user), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);
    }

    /// revert BidNeedBeHigherThanCurrentHighestBid
    function testFuzz__bid__revertBidNeedBeHigherThanCurrentHighestBid(address user, uint256 bid) public startAuction {
        vm.assume(user != ADDRESS_ZERO && user != seller);
        bid = bound(bid, 1, type(uint128).max - 1);

        vm.deal(user, bid);

        vm.prank(bob);
        auction.bid{value: MAX_UINT_128}();

        vm.prank(user);
        vm.expectRevert(Auction.Auction__BidNeedBeHigherThanCurrentHighestBid.selector);
        auction.bid{value: bid}();

        assertEq(auction.getPendingReturnsByUser(user), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, MAX_UINT_128);
        assertEq(auctionInformation.highestBidder, bob);
    }

    /// revert AuctionTimeEnded
    function testFuzz__bid__revertAuctionTimeEnded(address user, uint256 bid) public startAuction {
        vm.assume(user != ADDRESS_ZERO && user != seller);
        bid = bound(bid, 1, type(uint256).max);

        vm.deal(user, bid);

        vm.warp(block.timestamp + auction.getDuration() + 1);

        vm.prank(user);
        vm.expectRevert(Auction.Auction__AuctionTimeEnded.selector);
        auction.bid{value: bid}();

        assertEq(auction.getPendingReturnsByUser(user), ZERO);

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBid, ZERO);
        assertEq(auctionInformation.highestBidder, ADDRESS_ZERO);
    }

    /// bid success
    function testFuzz__bid(address user, uint256 bid) public startAuction {
        vm.assume(user != ADDRESS_ZERO && user != seller);
        bid = bound(bid, 1, type(uint256).max);

        vm.deal(user, bid);

        vm.prank(user);
        auction.bid{value: bid}();

        Auction.AuctionInformation memory auctionInformation = auction.getAuction();
        assertEq(auctionInformation.highestBidder, user);
        assertEq(auctionInformation.highestBid, bid);
    }
}
