// SPDX-License-Identifier: MIT
pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

/// @title MockERC721
/// @notice Minimal ERC721 implementation used for testing and local development.
/// @dev
/// - Intentionally simple and permissionless: anyone can mint.
/// - NOT intended for production use.
/// - Token IDs are assigned sequentially starting from 1 (for `mint`)
///   and from 0 (for `safeMint`).
contract MockERC721 is ERC721 {
    /// @dev Tracks the next token ID to be minted.
    uint256 private s_nextTokenId;

    /// @notice Initializes the mock NFT collection.
    /// @dev Name and symbol are hardcoded for convenience.
    constructor() ERC721("Mock NFT", "MNFT") {}

    /// @notice Mints a new NFT using `_mint`.
    /// @dev
    /// - Increments the token counter before minting.
    /// - Uses `_mint` (not safe), so it does NOT check for ERC721Receiver
    ///   support if `_to` is a contract.
    /// - Suitable for tests where the receiver is known to be an EOA.
    ///
    /// @param _to Address that will receive the newly minted token.
    /// @return tokenId The ID of the newly minted token.
    function mint(address _to) external returns (uint256) {
        s_nextTokenId++;
        uint256 tokenId = s_nextTokenId;

        _mint(_to, tokenId);
        return tokenId;
    }

    /// @notice Mints a new NFT using `_safeMint`.
    /// @dev
    /// - Increments the token counter after reading it.
    /// - Uses `_safeMint`, which checks that contract recipients
    ///   implement `onERC721Received`.
    /// - Useful for tests involving contracts as NFT recipients.
    ///
    /// @param _to Address that will receive the newly minted token.
    /// @return tokenId The ID of the newly minted token.
    function safeMint(address _to) external returns (uint256) {
        uint256 tokenId = s_nextTokenId;
        s_nextTokenId++;

        _safeMint(_to, tokenId);
        return tokenId;
    }
}
