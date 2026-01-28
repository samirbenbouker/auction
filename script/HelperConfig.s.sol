// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

contract HelperConfig is Script {
    uint256 public constant DURATION = 1 days;
    uint256 public constant RESERVE_PRICE = 1 ether;

    function run() public returns (Auction, MockERC721, uint256) {
        return deployAuction();
    }

    function deployAuction() public returns (Auction, MockERC721, uint256) {
        vm.startBroadcast();

        Auction auction = new Auction(DURATION, RESERVE_PRICE);
        MockERC721 nft = new MockERC721();
        
        vm.stopBroadcast();

        address seller = auction.getSeller();
        uint256 tokenId = nft.mint(seller);
        
        vm.prank(seller);
        nft.approve(address(auction), tokenId);

        return (auction, nft, tokenId);
    }
}
