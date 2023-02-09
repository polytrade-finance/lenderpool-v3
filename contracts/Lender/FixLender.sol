/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Lender/Interface/IFixLender.sol";

/**
 * @title Fixed Lender Pool contract
 * @author Polytrade
 * @notice Users can deposit in predefined fixed lender pool during deposit period and withdraw their
 * Principal stable amount with its stable and bonus rewards based on APR and Rate
 * @dev The contract is in development stage
 */
contract FixLender is IFixLender, AccessControl {
    using SafeERC20 for IToken;
    mapping(address => Deposit[]) public lenders;

    uint256 public poolSize;
    uint256 private immutable _stableApr;
    uint256 private immutable _bonusRate;
    uint256 private immutable _stableDecimal;
    uint256 private immutable _bonusDecimal;
    uint256 private immutable _poolStartDate;
    uint256 private immutable _depositEndDate;
    uint256 private immutable _poolPeriod;
    uint256 private immutable _minDeposit;
    uint256 private immutable _poolMaxLimit;
    bool private immutable _verificationStatus;

    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;

    /**
     * @dev Sets the values for admin, stableToken, bonusToken, stableApr, bonusRate, bonusRate, poolStartDate,
     * depositEndDate, minDeposit, PoolMaxLimit and verification
     * @param admin_ address of admin
     * @param stableToken_  address of stable Token
     * @param bonusToken_ address of bonus Token
     * @param stableApr_ fixed APR for stable tokens, with 2 decimals
     * @param bonusRate_ fixed bonus rate per deposited stable token, with 2 decimals
     * @param poolStartDate_ timestamp for start of reward calculations
     * @param depositEndDate_ timestamp for the end of depositing
     * @param poolPeriod_ duration of pool in days, starting from poolStartDate
     * @param minDeposit_ minimum deposit amount for users
     * @param poolMaxLimit_ maximum tokens to deposit in pool, after reaching contract stops receiving deposit
     * @param verification_ verification status for pool(True = KYC required, False = KYC not required)
     */
    constructor(
        address admin_,
        address stableToken_,
        address bonusToken_,
        uint256 stableApr_,
        uint256 bonusRate_,
        uint256 poolStartDate_,
        uint256 depositEndDate_,
        uint256 poolPeriod_,
        uint256 minDeposit_,
        uint256 poolMaxLimit_,
        bool verification_
    ) {
        require(admin_ != address(0), "Invalid Admin address");
        require(stableToken_ != address(0), "Invalid Stable Token address");
        require(bonusToken_ != address(0), "Invalid Bonus Token address");
        require(poolStartDate_ > block.timestamp, "Invalid Pool Start Date");
        require(depositEndDate_ > block.timestamp, "Invalid Deposit End Date");
        require(poolPeriod_ != 0, "Invalid Pool Duration");
        require(poolMaxLimit_ > minDeposit_, "Invalid Pool Max. Limit");
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _stableToken = IToken(stableToken_);
        _bonusToken = IToken(bonusToken_);
        _stableDecimal = _stableToken.decimals();
        _bonusDecimal = _bonusToken.decimals();
        _stableApr = stableApr_;
        _bonusRate = bonusRate_ * (10 ** (_bonusDecimal - _stableDecimal));
        _poolStartDate = poolStartDate_;
        _depositEndDate = depositEndDate_;
        _poolPeriod = poolPeriod_ * 1 days;
        _minDeposit = minDeposit_ * (10 ** _stableDecimal);
        _poolMaxLimit = poolMaxLimit_ * (10 ** _stableDecimal);
        _verificationStatus = verification_;
    }

    /**
     * @dev See {IFixLender-deposit}.
     */
    function deposit(uint256 amount) external {
        require(
            _poolMaxLimit > poolSize + amount,
            "Pool has reached its limit"
        );
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            block.timestamp < _depositEndDate,
            "Deposit End Date has passed"
        );
        poolSize += amount;
        lenders[msg.sender].push(
            Deposit(amount, block.timestamp, block.timestamp)
        );
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev See {IFixLender-claim}.
     */
    function claim() external {
        require(block.timestamp > _poolStartDate, "Pool has not started yet");
        require(
            lenders[msg.sender][0].amount > 0,
            "You have not deposited anything"
        );
        uint256 claimableAmount = _calculateBonus();
        _bonusToken.safeTransfer(msg.sender, claimableAmount);
        emit Claimed(msg.sender, claimableAmount);
    }

    function _calculateBonus() private returns (uint256) {
        uint256 claimableAmount;
        uint256 diff;
        uint256 poolEndDate = _poolPeriod + _poolStartDate;
        for (uint256 i = 0; i < lenders[msg.sender].length; i++) {
            uint256 amount = lenders[msg.sender][i].amount;
            uint256 lastClaimTime = lenders[msg.sender][i].lastClaimDate;
            if (block.timestamp < poolEndDate) {
                diff = block.timestamp - lastClaimTime;
                lenders[msg.sender][i].lastClaimDate = block.timestamp;
            } else {
                diff = poolEndDate - lastClaimTime;
                lenders[msg.sender][i].lastClaimDate = poolEndDate;
            }
            claimableAmount +=
                ((amount * diff * _bonusRate) / 1E2) /
                _poolPeriod;
        }
        return claimableAmount;
    }
}
