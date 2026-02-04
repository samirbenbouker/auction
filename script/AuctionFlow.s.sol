// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

/// @title AuctionFlow
/// @notice Foundry script that demonstrates the full English auction lifecycle:
///         deploy -> mint/approve -> start -> bids -> withdraw -> end.
/// @dev
/// - Uses `vm.startBroadcast(pk)` to send real transactions when `--broadcast` is enabled.
/// - Reads private keys from environment variables for safety when running on testnets.
/// - Includes lightweight assertions via `vm.assertTrue` to validate expected state transitions.
contract AuctionFlow is Script {
    // Example commands:
    // Local fork (Anvil):
    // forge script script/AuctionFlow.s.sol:AuctionFlow --fork-url http://127.0.0.1:8545 -vvvv
    //
    // Testnet fork (simulation only, no transactions sent):
    // forge script script/AuctionFlow.s.sol:AuctionFlow --fork-url $RPC_URL -vvvv
    //
    // Testnet broadcast (sends transactions):
    // forge script script/AuctionFlow.s.sol:AuctionFlow --fork-url $RPC_URL --broadcast -vvvv

    function run() external {
        // --- Key management ----------------------------------------------------
        // For local Anvil you can hardcode known dev keys (commented out here).
        // For testnets/mainnet forks, read them from env to avoid committing secrets.
        //
        // Example Anvil PKs (DO NOT USE ON REAL NETWORKS):
        // uint256 sellerPk  = 0xac0974...ff80;
        // uint256 bidder1Pk = 0x59c699...690d;
        // uint256 bidder2Pk = 0x5de411...365a;

        uint256 sellerPk = vm.envUint("SELLER_PK");
        uint256 bidder1Pk = vm.envUint("BIDDER1_PK");
        uint256 bidder2Pk = vm.envUint("BIDDER2_PK");

        // Derive EOAs from private keys (deterministic, no chain interaction).
        address seller = vm.addr(sellerPk);
        address bidder1 = vm.addr(bidder1Pk);
        address bidder2 = vm.addr(bidder2Pk);

        // --- Auction parameters ------------------------------------------------
        // NOTE: duration = 1 second is intentionally tiny for quick demos.
        // If you broadcast to a network, ensure you wait/sleep or advance time on a local chain.
        uint256 duration = 1;
        uint256 reservePrice = 0.0001 ether;

        // ----------------------------------------------------------------------
        // 1) Seller deploys contracts, mints NFT, approves auction, and starts it
        // ----------------------------------------------------------------------
        vm.startBroadcast(sellerPk);

        // Deploy the auction and a mock ERC721 used as the auctioned asset.
        Auction auction = new Auction(duration, reservePrice);
        MockERC721 nft = new MockERC721();

        // Mint an NFT to the seller and approve the auction contract to transfer it.
        uint256 tokenId = nft.mint(seller);
        nft.approve(address(auction), tokenId);

        // Start the auction: transfers NFT into escrow and initializes auction state.
        auction.start(address(nft), tokenId);
        vm.stopBroadcast();

        // Validate initial auction state
        Auction.AuctionInformation memory a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1); // START
        vm.assertTrue(a.highestBid == 0);
        vm.assertTrue(a.highestBidder == address(0));

        // -------------------------------------------------
        // 2) Bidder1 places the first bid (becomes highest)
        // -------------------------------------------------
        vm.startBroadcast(bidder1Pk);
        auction.bid{value: 0.00001 ether}();
        vm.stopBroadcast();

        // Validate state after bidder1 bid
        a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1); // START
        vm.assertTrue(a.highestBid == 0.00001 ether);
        vm.assertTrue(a.highestBidder == bidder1);

        // ---------------------------------------------------------------------
        // 3) Bidder2 outbids bidder1. bidder1's bid becomes a refundable balance
        //    in `pendingReturns` (pull-payment refund pattern).
        // ---------------------------------------------------------------------
        vm.startBroadcast(bidder2Pk);
        auction.bid{value: 0.0001 ether}();
        vm.stopBroadcast();

        // bidder1 should now have funds available to withdraw
        vm.assertTrue(auction.getPendingReturnsByUser(bidder1) == 0.00001 ether);

        // Validate state after bidder2 bid
        a = auction.getAuction();
        vm.assertTrue(auction.getAuctionStatus() == 1); // START
        vm.assertTrue(a.highestBid == 0.0001 ether);
        vm.assertTrue(a.highestBidder == bidder2);

        // Save bidder1 ETH balance to check withdraw increases it
        uint256 currentBalance = bidder1.balance;

        // -----------------------------------
        // 4) bidder1 withdraws their refund
        // -----------------------------------
        vm.startBroadcast(bidder1Pk);
        auction.withdraw();
        vm.stopBroadcast();

        // In practice, balance should increase minus gas costs.
        // This assertion is a coarse check; on some networks/gas configs,
        // you might want a more precise delta-based assertion.
        vm.assertTrue(bidder1.balance > currentBalance);

        // -----------------------------------
        // 5) Seller ends the auction (settle)
        // -----------------------------------
        // IMPORTANT: With duration=1, this will revert unless time has passed.
        // - On Anvil, you may need to advance time:
        //   vm.warp(block.timestamp + duration + 1);
        // - On live networks, you must wait in real time.
        vm.startBroadcast(sellerPk);
        auction.end();
        vm.stopBroadcast();

        // Validate final ownership transfer: bidder2 should receive the NFT.
        vm.assertTrue(nft.ownerOf(tokenId) == bidder2);
    }
}
