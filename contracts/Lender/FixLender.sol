/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../Token/Interface/IToken.sol";
import "./Interface/IFixLender.sol";

/**
 * @title Fixed Lender Pool contract
 * @author Mohammad Z. Rad
 * @notice Users can deposit in predefined fixed lender pool during deposit period and withdraw their
 * Principal stable amount with its stable and bonus rewards based on APR and Rate
 * @dev The contract is in development stage
 */
abstract contract FixLender is IFixLender, AccessControl {
    using SafeERC20 for IToken;
    mapping(address => Lender) public lenders;

    uint256 private immutable _stableApr;
    uint256 private immutable _bonusRate;
    uint256 private immutable _poolStartDate;
    uint256 private immutable _depositEndDate;
    uint256 private immutable _poolPeriod;
    uint256 private immutable _minDeposit;
    uint256 private immutable _maxPoolSize;
    bool private immutable _verificationStatus;

    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;

    /**
     * @dev Sets the values for {admin_}, {stableToken_}, {bonusToken_}, {stableApr_}, {bonusRate_},
     *{bonusRate_}, {poolStartDate_}, {depositEndDate_}, {minDeposit_}, {maxPoolSize_} and {verification_}
     * @param admin_ is the address of admin
     * @param stableToken_ is the address of stable Token
     * @param bonusToken_ is the address of bonus Token
     * @param stableApr_ is the fixed annual percentage rate for stable tokens that are distributed
     * after the pool period with 2 decimals
     * @param bonusRate_ is the fixed bonus token rate per deposited stable token for the pool period with 2 decimals
     * @param poolStartDate_ is the timestamp of start date of pool that represents start of reward calculations
     * @param depositEndDate_ is the timestamp of end of depositing
     * @param poolPeriod_ is the duration of pool in days starts from poolStartDate
     * @param minDeposit_ is the minimum amount of stable tokens that users should deposit
     * @param maxPoolSize_ is the maximum amount of tokens that pool can have and after reaching
     * it stops receiving depsoits
     * @param verification_ is the verification status for pool, True means kyc is needed and False means
     *  kyc is not needed
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
        uint256 maxPoolSize_,
        bool verification_
    ) {
        require(admin_ != address(0), "Invalid Admin address");
        require(stableToken_ != address(0), "Invalid Stable Token address");
        require(bonusToken_ != address(0), "Invalid Bonus Token address");
        require(poolStartDate_ > block.timestamp, "Invalid Pool Start Date");
        require(depositEndDate_ > block.timestamp, "Invalid Deposit End Date");
        require(poolPeriod_ != 0, "Invalid Pool Duration");
        require(maxPoolSize_ > minDeposit_, "Invalid Max. Pool Size");
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _stableToken = IToken(stableToken_);
        _bonusToken = IToken(bonusToken_);
        _stableApr = stableApr_;
        _bonusRate =
            bonusRate_ *
            (10 ** (_bonusToken.decimals() - _stableToken.decimals()));
        _poolStartDate = poolStartDate_;
        _depositEndDate = depositEndDate_;
        _poolPeriod = poolPeriod_ * 1 days;
        _minDeposit = minDeposit_;
        _maxPoolSize = maxPoolSize_;
        _verificationStatus = verification_;
    }
}
