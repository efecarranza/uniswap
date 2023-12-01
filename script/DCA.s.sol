// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {Script} from "forge-std/Script.sol";

import {DCA} from "../src/DCA.sol";

contract DCAScript is Script {
    address public constant AAVE_USD_FEED =
        0x547a514d5e3769680Ce22B2361c10Ea13619e8a9;
    address public constant AAVE = 0x7Fc66500c84A76Ad7e9c93437bFc5Ac33E2DDaE9;

    function run() public {
        vm.startBroadcast();
        new DCA(AAVE, AAVE_USD_FEED);
        vm.stopBroadcast();
    }
}
