// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title PolytradeProxy Mock Contract for test
 * @author Polytrade
 */
contract PolytradeProxy {
    mapping(address => bool) public status;

    /**
     * @notice test function to verify user KYC
     * @param addr is the address of user
     */
    function addKYC(address addr) external {
        status[addr] = true;
    }

    /**
     * @notice test function to revoke user KYC
     * @param addr is the address of user
     */
    function revokeKYC(address addr) external {
        status[addr] = false;
    }

    /**
     * @notice test function to check user KYC
     * @param addr is the address of user
     */
    function hasPassedKYC(address addr) external view returns (bool) {
        return status[addr];
    }
}
