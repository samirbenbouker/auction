// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {ERC721} from "@openzeppelin/contracts/token/ERC721/ERC721.sol";

contract MockERC721 is ERC721 {
    uint256 private s_nextTokenId;

    constructor() ERC721("Mock NFT", "MNFT") {}

    function mint(address _to) external returns (uint256) {
        s_nextTokenId++;
        uint256 tokenId = s_nextTokenId;

        _mint(_to, tokenId);
        return tokenId;
    }

    function safeMint(address _to) external returns (uint256) {
        uint256 tokenId = s_nextTokenId;
        s_nextTokenId++;

        _safeMint(_to, tokenId);
        return tokenId;
    }
}
