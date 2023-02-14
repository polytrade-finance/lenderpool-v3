//SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/Verification/Interface/IVerification.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @author Polytrade
 * @title Verification
 */
contract Verification is IVerification, Ownable {
    mapping(address => bool) public agents;
    mapping(address => UserStatus) public userValidation;

    constructor() {
        agents[_msgSender()] = true;
        emit AgentSet(_msgSender(), true);
    }

    /**
     * @notice Function to set agent on the verification contract
     * @param agent, address of the agent to be added or removed
     * @param status, true if added or false if removed
     */
    function setAgent(address agent, bool status) external onlyOwner {
        agents[agent] = status;
        emit AgentSet(agent, status);
    }

    /**
     * @notice Function to approve/revoke Validation for any user
     * @param user, address of the user to set Validation
     * @param status, true = approve Validation and false = revoke Validation
     */
    function setValidation(
        address user,
        bytes2 provider,
        bool status
    ) external {
        require(agents[msg.sender], "Callable by agents only");
        userValidation[user] = UserStatus(provider, status);
        emit UserValidation(user, provider, status);
    }

    /**
     * @notice Returns whether a user's Validation is verified or not
     * @dev returns a boolean if the Validation is valid
     * @param user, address of the user to check
     * @return returns true if user's Validation is valid or false if not
     */
    function isValid(address user) external view returns (bool) {
        return (userValidation[user].status);
    }

    /**
     * @notice Returns user's provider
     * @dev returns a bytes2 representation of the provider if valid
     * @param user, address of the user to check
     * @return returns bytes2 code representing the provider
     */
    function getUserProvider(address user) external view returns (bytes2) {
        return (userValidation[user].provider);
    }
}
