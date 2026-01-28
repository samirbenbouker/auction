// SDPX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Test} from "forge-std/Test.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

contract AuctionHandler is Test {
    Auction public auction;
    MockERC721 public nft;
    
    address public seller;
    uint256 public tokenId;

    address[] public bidders;

    uint256 public constant INITIAL_BALANCE = 100 ether;

    constructor(Auction _auction, MockERC721 _nft, address _seller, uint256 _tokenId) {
        auction = _auction;
        nft = _nft;
        seller = _seller;
        tokenId = _tokenId;

        bidders.push(makeAddr("bob"));
        bidders.push(makeAddr("carol"));
        bidders.push(makeAddr("deve"));
        bidders.push(makeAddr("erin"));

        for(uint256 i = 0; i < bidders.length; i++) {
            vm.deal(bidders[i], INITIAL_BALANCE);
        }
    }

    function _pickBidder(uint256 seed) internal view returns (address) {
        return bidders[seed % bidders.length];
    }

    function start(uint256 seed) external {
        address caller = (seed % 3 == 0) ? seller : _pickBidder(seed);

        vm.startPrank(caller);
        try auction.start(address(nft), tokenId) {} catch {}
        vm.stopPrank();
    }

    function bid(uint256 bidderSeed, uint256 rawAmount) external {
        address bidder = _pickBidder(bidderSeed);

        uint256 amount = bound(rawAmount, 1 wei, 10 ether);
        vm.prank(bidder);
        try auction.bid{value: amount}() {} catch {}
    }

    function withdraw(uint256 bidderSeed) external {
        address bidder = _pickBidder(bidderSeed);
        vm.prank(bidder);
        try auction.withdraw() {} catch{}
    }

    function warp(uint256 rawSeconds) external {
        uint256 secs = bound(rawSeconds, 0, 2 hours);
        vm.warp(block.timestamp + secs);
    }

    function end(uint256 seed) external {
        address caller = (seed % 2 == 0) ? seller : _pickBidder(seed);

        vm.prank(caller);
        try auction.end() {} catch {}
    }

}