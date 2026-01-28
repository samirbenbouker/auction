// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {StdInvariant} from "forge-std/StdInvariant.sol";

import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";
import {AuctionHandler} from "test/invariant/AuctionHandler.t.sol";

contract AuctionInvariantTest is StdInvariant, Test {
    Auction public auction;
    MockERC721 public nft;
    AuctionHandler public handler;

    address public seller;
    uint256 public tokenId;

    address public constant ADDRESS_ZERO = address(0);
    uint256 public constant ZERO = 0;
    uint256 public constant DURATION = 1 hours;
    uint256 public constant RESERVE_PRICE = 1 ether;
    uint256 public constant STATUS_NOT_STARTED = 0;
    uint256 public constant STATUS_START = 1;
    uint256 public constant STATUS_END = 2;

    function setUp() external {
        seller = makeAddr("seller");

        vm.startPrank(seller);
        
        auction = new Auction(DURATION, RESERVE_PRICE);
        
        nft = new MockERC721();
        tokenId = nft.mint(seller);

        vm.stopPrank();

        handler = new AuctionHandler(auction, nft, seller, tokenId);
        targetContract(address(handler));
    }

    function invariant__ifStarted_nftIsInEscrow() external view {
        uint256 status = auction.getAuctionStatus();

        if(status == STATUS_START) {
            address owner = nft.ownerOf(tokenId);
            assertEq(owner, address(auction));
        }
    }

    function invariant__ifNotStartedOrEnded__contractDoesNotHoldNft() external view {
        uint256 status = auction.getAuctionStatus();

        if(status == STATUS_NOT_STARTED || status == STATUS_END) {
            // if never start, owner will be seller
            // if never end, owner is seller or winner
            // in both cases auction never will be owner
            address owner = nft.ownerOf(tokenId);
            assertTrue(owner != address(auction));
        }
    }

    function invariant__endResetsHighestBidState() external view {
        uint256 status = auction.getAuctionStatus();
        Auction.AuctionInformation memory a = auction.getAuction();

        if(status == STATUS_START) {
            assertEq(a.highestBid, ZERO);
            assertEq(a.highestBidder, ADDRESS_ZERO);
        }
    }

    function invariant__highestBidderZeroMeansHighestBidZero() external view {
        Auction.AuctionInformation memory a = auction.getAuction();

        if(a.highestBidder == ADDRESS_ZERO) {
            assertEq(a.highestBid, ZERO);
        }
    }
}