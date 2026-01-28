// SPDX-License-Identifier: MIT

pragma solidity 0.8.30;

import {Script} from "forge-std/Script.sol";
import {Auction} from "src/Auction.sol";

contract HelperConfig is Script {

    uint256 public constant DURATION = 1 days;
    uint256 public constant RESERVE_PRICE = 1 ether;

    function run() public returns (Auction) {
        return deployAuction();
    }

    function deployAuction() public returns (Auction) {
        vm.startBroadcast();
        Auction auction = new Auction(DURATION, RESERVE_PRICE);
        vm.stopBroadcast();
        return auction;
    }

}