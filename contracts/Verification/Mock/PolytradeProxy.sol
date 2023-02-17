// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title PolytradeProxy
 * @author Polytrade
 */
contract PolytradeProxy {
    mapping(address => bool) public status;

    function addKYC(address addr) external {
        status[addr] = true;
    }

    function revokeKYC(address addr) external {
        status[addr] = false;
    }

    function hasPassedKYC(address addr) external view returns (bool) {
        return status[addr];
    }
}
