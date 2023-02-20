// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IStrategy {
    /**
     * @notice Emitted when funds are deposited
     * @param amount, total amount deposited
     */
    event Deposited(uint amount);

    /**
     * @notice Emitted when funds are withdrawn from lender pool
     * @param amount, total amount withdrawn
     */
    event Withdrawn(uint amount);

    /**
     * @notice transfer funds to defi protocol
     * @dev accepts token from msg.sender and transfers to defi protocol
     * @dev can be called by only lender pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     */
    function deposit(uint amount) external;

    /**
     * @notice withdraw funds from defi protocol and send to lending pool
     * @dev can be called by only lender pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     */
    function withdraw(uint amount) external;

    /**
     * @notice get deposited balance of staking strategy smart contract
     * @return total amount of deposited token for this contract
     */
    function getBalance() external view returns (uint);
}
