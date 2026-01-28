// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

contract AuctionFlow is Script {
    // commands:
    // Anvil
    // forge script script/AuctionFlow.s.ol:AuctionFlow --fork-url http://127.0.0.1:8545 -vvvv (don't send transactions)
    // Testnet
    // forge script script/AuctionFlow.s.ol:AuctionFlow --fork-url $RPC_URL -vvvv (don't send transactions)
    // forge script script/AuctionFlow.s.ol:AuctionFlow --fork-url $RPC_URL --broadcast -vvvv (send transactions)
    
    function run() external {
        // anvil PK 
        // uint256 sellerPk = 0xac0974bec39a17e36ba4a6b4d238ff944bacb478cbed5efcae784d7bf4f2ff80;
        // uint256 bidder1Pk = 0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
        // uint256 bidder2Pk = 0x5de4111afa1a4b94908f83103eb1f1706367c2e68ca870fc3fb9a804cdab365a;
        uint256 sellerPk = vm.envUint("SELLER_PK");
        uint256 bidder1Pk = vm.envUint("BIDDER1_PK");
        uint256 bidder2Pk = vm.envUint("BIDDER2_PK");

        address seller = vm.addr(sellerPk);
        address bidder1 = vm.addr(bidder1Pk);
        address bidder2 = vm.addr(bidder2Pk);

        uint256 duration = 1;
        uint256 reservePrice = 0.0001 ether;

        // 1. Deploy Seller
        vm.startBroadcast(sellerPk);

        Auction auction = new Auction(duration, reservePrice);
        MockERC721 nft = new MockERC721();

        /// seller mint nft and approve auction 
        uint256 tokenId = nft.mint(seller);
        nft.approve(address(auction), tokenId);

        // start
        auction.start(address(nft), tokenId);
        vm.stopBroadcast();

        Auction.AuctionInformation memory a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1);
        vm.assertTrue(a.highestBid == 0);
        vm.assertTrue(a.highestBidder == address(0));

        // 2. bid bidder1
        vm.startBroadcast(bidder1Pk);
        auction.bid{value: 0.00001 ether}();
        vm.stopBroadcast();

        a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1);
        vm.assertTrue(a.highestBid == 0.00001 ether);
        vm.assertTrue(a.highestBidder == bidder1);

        // 3. bid bidder2 -> bid2 hight to bid1
        //      bid1 go to pendingReturns
        vm.startBroadcast(bidder2Pk);
        auction.bid{value: 0.0001 ether}();
        vm.stopBroadcast();

        vm.assertTrue(auction.getPendingReturnsByUser(bidder1) == 0.00001 ether);
        
        a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1);
        vm.assertTrue(a.highestBid == 0.0001 ether);
        vm.assertTrue(a.highestBidder == bidder2);

        uint256 currentBalance = bidder1.balance;

        // 4. withdraw
        vm.startBroadcast(bidder1Pk);
        auction.withdraw();
        vm.stopBroadcast();

        vm.assertTrue(bidder1.balance > currentBalance);

        // 5. end
        vm.startBroadcast(sellerPk);
        auction.end();
        vm.stopBroadcast();

        vm.assertTrue(nft.ownerOf(tokenId) == bidder2);
    }
}
