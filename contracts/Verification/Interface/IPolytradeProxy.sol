// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IPolytradeProxy
 * @author Polytrade
 */
interface IPolytradeProxy {
    /**
     * @param addr is address of user
     * @return bool true if addr is verified and false if not
     */
    function hasPassedKYC(address addr) external view returns (bool);
}
