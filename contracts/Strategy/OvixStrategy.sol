// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/access/AccessControl.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Strategy/Interface/IOErc20.sol";
import "contracts/Strategy/Interface/IStrategy.sol";

/**
 * @author Polytrade
 * @title Strategy
 */
contract OvixStrategy is IStrategy, AccessControl {
    using SafeERC20 for IToken;

    IToken public stable;
    IOErc20 public oStable;

    bytes32 public constant LENDER_POOL = keccak256("LENDER_POOL");

    constructor(address _stable, address _oStable) {
        _grantRole(DEFAULT_ADMIN_ROLE, msg.sender);
        stable = IToken(_stable);
        oStable = IOErc20(_oStable);
    }

    /**
     * @notice transfer funds to defi protocol lending pool
     * @dev accepts token from msg.sender and transfers to defi protocol lending pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     * Emits {Deposited} event
     */
    function deposit(uint256 amount) external onlyRole(LENDER_POOL) {
        stable.safeTransferFrom(msg.sender, address(this), amount);
        stable.safeApprove(address(oStable), amount);
        require(oStable.mint(amount) == 0);
        emit Deposited(amount);
    }

    /**
     * @notice withdraw funds from defi protocl and send to lending pool
     * @dev can be called by only lender pool
     * @param amount, total amount accepted from user and transferred to defi protocol
     * Emits {Withdrawn} event
     * @return The final amount withdrawn
     */
    function withdraw(
        uint256 amount
    ) external onlyRole(LENDER_POOL) returns (uint256) {
        require(
            oStable.redeemUnderlying(amount) == 0,
            "Failed to withdraw from strategy"
        );
        emit Withdrawn(amount);
        return amount;
    }

    /**
     * @notice get aStable balance of staking strategy smart contract
     * @return total amount of aStable token in this contract
     */
    function getBalance() external returns (uint256) {
        return oStable.balanceOfUnderlying(address(this));
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(AccessControl) returns (bool) {
        return
            interfaceId == type(IStrategy).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
