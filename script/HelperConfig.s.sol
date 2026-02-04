// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Auction} from "src/Auction.sol";
import {MockERC721} from "test/mock/MockERC721.sol";

/// @title HelperConfig
/// @notice Deployment helper script for the Auction system.
/// @dev
/// - Centralizes common deployment parameters (duration, reserve price).
/// - Deploys the Auction and a MockERC721 used for testing or demos.
/// - Mints an NFT to the auction seller and approves the auction contract.
/// - Designed to be reused across scripts and tests.
contract HelperConfig is Script {
    /// @notice Default auction duration.
    uint256 public constant DURATION = 1 days;

    /// @notice Minimum price required for a successful auction.
    uint256 public constant RESERVE_PRICE = 1 ether;

    /// @notice Entry point when running `forge script`.
    /// @return auction The deployed Auction contract
    /// @return nft The deployed MockERC721 contract
    /// @return tokenId The tokenId minted to the seller and approved for auction
    function run() public returns (Auction, MockERC721, uint256) {
        return deployAuction();
    }

    /// @notice Deploys the Auction and MockERC721 contracts and prepares them for use.
    /// @dev
    /// Deployment steps:
    /// 1. Broadcast deployment transactions (Auction + MockERC721).
    /// 2. Stop broadcasting to avoid accidental state changes.
    /// 3. Mint an NFT to the auction seller.
    /// 4. Approve the Auction contract to transfer the NFT.
    ///
    /// This pattern keeps deployment logic clean and reusable.
    function deployAuction() public returns (Auction, MockERC721, uint256) {
        // Begin broadcasting transactions (uses the default private key)
        vm.startBroadcast();

        // Deploy contracts
        Auction auction = new Auction(DURATION, RESERVE_PRICE);
        MockERC721 nft = new MockERC721();

        // Stop broadcasting: everything below is local state manipulation
        vm.stopBroadcast();

        // Retrieve the seller address from the Auction contract
        address seller = auction.getSeller();

        // Mint an NFT to the seller (used as the auctioned asset)
        uint256 tokenId = nft.mint(seller);

        // Approve the auction contract to transfer the NFT on behalf of the seller
        vm.prank(seller);
        nft.approve(address(auction), tokenId);

        return (auction, nft, tokenId);
    }
}
