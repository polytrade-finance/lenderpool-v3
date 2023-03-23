// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IVerification
 * @author Polytrade
 */
interface IVerification {
    /**
     * @notice Returns whether a user's KYC is verified or not
     * @dev returns true if user's KYC is valid or false if not
     * @param user, address of the user to check
     */
    function isValid(address user) external view returns (bool);
}
