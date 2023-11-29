// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

import {Test, console2} from "forge-std/Test.sol";

import {DCA} from "../src/DCA.sol";

contract DCATest is Test {
    DCA public dca;

    function setUp() public {
        dca = new DCA();
    }
}
