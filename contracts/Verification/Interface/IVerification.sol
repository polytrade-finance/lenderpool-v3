//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @author Polytrade
 * @title IVerification
 */
interface IVerification {
    struct UserStatus {
        bytes2 provider;
        bool status;
    }

    /**
     * @notice Emits when a agent is set (added, removed)
     * @param agent, address of the agent to be added or removed
     * @param status, true if added or false if removed
     */
    event AgentSet(address indexed agent, bool status);

    /**
     * @notice Emits when a user is validated or removed
     * @param user, address of the user to be validated or removed
     * @param provider, code of the provider (bytes2)
     * @param status, true if added or false if removed
     */
    event UserValidation(address indexed user, bytes2 provider, bool status);

    /**
     * @notice Returns whether a user's KYC is verified or not
     * @dev returns a boolean if the KYC is valid
     * @param user, address of the user to check
     * @return returns true if user's KYC is valid or false if not
     */
    function isValid(address user) external view returns (bool);
}
