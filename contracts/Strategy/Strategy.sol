// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "contracts/Strategy/Interface/IAaveLendingPool.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Strategy/Interface/IStrategy.sol";

/**
 * @author Polytrade
 * @title Strategy
 */
contract Strategy is IStrategy, AccessControl {
    using SafeERC20 for IToken;

    IToken public stable;
    IToken public aStable;

    IAaveLendingPool public immutable aave;

    bytes32 public constant LENDER_POOL = keccak256("LENDER_POOL");

    constructor(address _aave, address _stable, address _aStable) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stable = IToken(_stable);
        aStable = IToken(_aStable);
        aave = IAaveLendingPool(_aave);
    }

    /**
     * @notice transfer funds to defi protocol lending pool
     * @dev accepts token from msg.sender and transfers to defi protocol lending pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     * Emits {Deposited} event
     */
    function deposit(uint amount) external onlyRole(LENDER_POOL) {
        stable.safeTransferFrom(msg.sender, address(this), amount);
        stable.safeApprove(address(aave), amount);
        aave.deposit(address(stable), amount, address(this), 0);
        emit Deposited(amount);
    }

    /**
     * @notice withdraw funds from defi protocl and send to lending pool
     * @dev can be called by only lender pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     * Emits {Withdrawn} event
     */
    function withdraw(uint amount) external onlyRole(LENDER_POOL) {
        aave.withdraw(address(stable), amount, msg.sender);
        emit Withdrawn(amount);
    }

    /**
     * @notice get aStable balance of staking strategy smart contract
     * @return total amount of aStable token in this contract
     */
    function getBalance() external view returns (uint) {
        return aStable.balanceOf(address(this));
    }
}
