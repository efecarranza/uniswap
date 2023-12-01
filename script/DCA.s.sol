// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {DCA} from "../src/DCA.sol";

contract DCAScript is Script {
    address public constant UNI_FACTORY =
        0x5C69bEe701ef814a2B6a3EDD4B1652CB9cc5aA6f;
    address public constant UNI_ROUTER =
        0x7a250d5630B4cF539739dF2C5dAcb4c659F2488D;
    address public constant ETH_USD_FEED =
        0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419;
    address public constant AAVE_USD_FEED =
        0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    function run() public {
        vm.startBroadcast();
        new DCA(AAVE, AAVE_USD_FEED, ETH_USD_FEED, UNI_FACTORY, UNI_ROUTER);
        vm.stopBroadcast();
    }
}
