// SDPX-License-Identifier: MIT

pragma solidity 0.8.30;

contract RejectETH {
    receive() external payable {
        revert("I reject ETH");
    }
}
