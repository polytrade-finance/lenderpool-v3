// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/Verification/Interface/IVerification.sol";
import "@openzeppelin/contracts/access/Ownable.sol";

/**
 * @title Verification Contract
 * @author Polytrade
 * @notice Verification contract used for checking users KYC if needed
 * @dev The contract is in development stage
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
     * @param agent is the address of the agent to be added or removed
     * @param status is true if added or false if removed
     * Emits {AgentSet} event
     */
    function setAgent(address agent, bool status) external onlyOwner {
        agents[agent] = status;
        emit AgentSet(agent, status);
    }

    /**
     * @notice Function to approve/revoke Validation for any user
     * @param user is the address of the user to set Validation
     * @param status is true for approve Validation and false for revoke Validation
     * Emits {ValidationSet} event
     */
    function setValidation(
        address user,
        bytes2 provider,
        bool status
    ) external {
        require(agents[msg.sender], "Callable by agents only");
        userValidation[user] = UserStatus(provider, status);
        emit ValidationSet(user, provider, status);
    }

    /**
     * @dev See {IVerification-isValid}.
     */
    function isValid(address user) external view returns (bool) {
        return (userValidation[user].status);
    }
}
