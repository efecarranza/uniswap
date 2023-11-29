// SPDX-License-Identifier: No-License

pragma solidity 0.8.20;

contract DCA {
    uint256 public number;

    function setNumber(uint256 newNumber) public {
        number = newNumber;
    }

    function increment() public {
        number++;
    }
}
