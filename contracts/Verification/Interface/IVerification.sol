// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IVerification
 * @author Polytrade
 */
interface IVerification {
    struct UserStatus {
        bytes2 provider;
        bool status;
    }

    /**
     * @notice Emits when a agent is set (added, removed)
     * @param agent is the address of the agent to be added or removed
     * @param status is true if added or false if removed
     */
    event AgentSet(address indexed agent, bool status);

    /**
     * @notice Emits when a user is validated or removed
     * @param user is the address of the user to be validated or removed
     * @param provider is the code of the provider (bytes2)
     * @param status is true if added or false if removed
     */
    event ValidationSet(address indexed user, bytes2 provider, bool status);

    /**
     * @notice Returns whether a user's KYC is verified or not
     * @dev returns true if user's KYC is valid or false if not
     * @param user, address of the user to check
     */
    function isValid(address user) external view returns (bool);
}
