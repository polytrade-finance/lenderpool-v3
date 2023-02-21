/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Lender/Interface/IFixLender.sol";
import "contracts/Verification/Interface/IVerification.sol";

/**
 * @title Fixed Lender Pool contract
 * @author Polytrade
 * @notice Users can deposit in predefined fixed lender pool during deposit period and withdraw their
 * Principal stable amount with its stable and bonus rewards based on APR and Rate
 * @dev The contract is in development stage
 */
contract FixLender is IFixLender, AccessControl {
    using SafeERC20 for IToken;
    mapping(address => Lender) public lenders;

    uint256 public poolSize;
    uint256 private _withdrawPenaltyPercent;
    uint256 private constant _YEAR = 365 days;
    uint256 private immutable _stableApr;
    uint256 private immutable _bonusRate;
    uint256 private immutable _stableDecimal;
    uint256 private immutable _bonusDecimal;
    uint256 private immutable _poolStartDate;
    uint256 private immutable _depositEndDate;
    uint256 private immutable _poolPeriod;
    uint256 private immutable _poolEndDate;
    uint256 private immutable _minDeposit;
    uint256 private immutable _poolMaxLimit;
    bool private immutable _verificationStatus;

    IVerification public verification;
    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;

    modifier isValid() {
        if (_verificationStatus) {
            require(verification.isValid(msg.sender), "You are not verified");
        }
        _;
    }

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
        require(bonusRate_ <= 10000, "Invalid Bonus Rate");
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _stableToken = IToken(stableToken_);
        _bonusToken = IToken(bonusToken_);
        _stableDecimal = _stableToken.decimals();
        _bonusDecimal = _bonusToken.decimals();
        _stableApr = stableApr_ / 1E2;
        _bonusRate = bonusRate_ * (10 ** (_bonusDecimal - _stableDecimal));
        _poolStartDate = poolStartDate_;
        _depositEndDate = depositEndDate_;
        _poolPeriod = poolPeriod_ * 1 days;
        _minDeposit = minDeposit_ * (10 ** _stableDecimal);
        _poolMaxLimit = poolMaxLimit_ * (10 ** _stableDecimal);
        _verificationStatus = verification_;
        _poolEndDate = _poolPeriod + _poolStartDate;
    }

    /**
     * @notice `switchVerification` updates the Verification contract address.
     * @dev Changed verification Contract must comply with `IVerification`
     * @param newVerification, address of the new Verification contract
     * Emits {VerificationSwitched} event
     */
    function switchVerification(
        address newVerification
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newVerification != address(0), "Invalid Verification Address");
        address oldVerification = address(verification);
        verification = IVerification(newVerification);
        emit VerificationSwitched(oldVerification, newVerification);
    }

    /**
     * @dev See {IFixLender-deposit}.
     */
    function deposit(uint256 amount) external isValid {
        require(
            _poolMaxLimit >= poolSize + amount,
            "Pool has reached its limit"
        );
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            block.timestamp < _depositEndDate,
            "Deposit End Date has passed"
        );
        uint256 currentDeposit = lenders[msg.sender].totalDeposit;
        uint256 pendingStableReward = lenders[msg.sender].pendingStableReward;
        uint256 pendingBonusReward = lenders[msg.sender].pendingBonusReward;
        uint256 lastUpdateDate = _poolStartDate;
        poolSize += amount;
        if (block.timestamp > _poolStartDate) {
            (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
                msg.sender
            );
            pendingStableReward += stableReward;
            pendingBonusReward += bonusReward;
            lastUpdateDate = block.timestamp;
        }
        lenders[msg.sender] = Lender(
            currentDeposit + amount,
            pendingStableReward,
            pendingBonusReward,
            lastUpdateDate
        );
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev See {IFixLender-claimBonus}.
     */
    function claimBonus() external {
        require(
            lenders[msg.sender].totalDeposit != 0,
            "You have not deposited anything"
        );
        require(block.timestamp > _poolStartDate, "Pool has not started yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender
        );
        lenders[msg.sender].pendingStableReward += stableReward;
        uint256 claimableBonus = bonusReward +
            lenders[msg.sender].pendingBonusReward;
        lenders[msg.sender].pendingBonusReward = 0;
        lenders[msg.sender].lastUpdateDate = block.timestamp > _poolEndDate
            ? _poolEndDate
            : block.timestamp;
        _bonusToken.safeTransfer(msg.sender, claimableBonus);
        emit BonusClaimed(msg.sender, claimableBonus);
    }

    /**
     * @dev See {IFixLender-withdraw}.
     */
    function withdraw() external {
        require(block.timestamp > _poolEndDate, "Pool has not ended yet");
        require(
            lenders[msg.sender].totalDeposit != 0,
            "You have nothing to withdraw"
        );
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender
        );
        uint256 totalDeposit = lenders[msg.sender].totalDeposit;
        uint256 stableAmount = stableReward +
            lenders[msg.sender].pendingStableReward +
            totalDeposit;
        uint256 bonusAmount = bonusReward +
            lenders[msg.sender].pendingBonusReward;
        delete lenders[msg.sender];
        poolSize -= totalDeposit;
        _bonusToken.safeTransfer(msg.sender, bonusAmount);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit Withdrawn(msg.sender, stableAmount, bonusAmount);
    }

    /**
     * @dev See {IFixLender-emergencyWithdraw}.
     */
    function emergencyWithdraw() external {
        require(
            lenders[msg.sender].totalDeposit != 0,
            "You have nothing to withdraw"
        );
        require(
            block.timestamp < _poolEndDate,
            "You can not emergency withdraw"
        );
        uint256 totalDeposit = lenders[msg.sender].totalDeposit;
        uint256 withdrawFee = (totalDeposit * _withdrawPenaltyPercent) / 1E4;
        uint256 refundAmount = totalDeposit - withdrawFee;
        delete lenders[msg.sender];
        poolSize -= totalDeposit;
        _stableToken.safeTransfer(msg.sender, refundAmount);
        emit WithdrawnEmergency(msg.sender, refundAmount);
    }

    /**
     * @dev See {IFixLender-setWithdrawRate}.
     */
    function setWithdrawRate(
        uint256 newRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate < 10000, "Rate can not be more than 100%");
        uint256 oldRate = _withdrawPenaltyPercent;
        _withdrawPenaltyPercent = newRate;
        emit WithdrawRateChanged(oldRate, newRate);
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for lender
     * @param _lender is the address of lender
     */
    function _calculateRewards(
        address _lender
    ) private view returns (uint256, uint256) {
        uint256 endDate = block.timestamp > _poolEndDate
            ? _poolEndDate
            : block.timestamp;
        uint256 diff = endDate - lenders[_lender].lastUpdateDate;
        uint256 totalDeposit = lenders[_lender].totalDeposit;
        return (
            _calculateStableReward(diff, totalDeposit),
            _calculateBonusReward(diff, totalDeposit)
        );
    }

    /**
     * @dev Calculates the stable reward based on _stableApr for all lender deposits
     * @dev Rewards are only applicable for the pool period duration
     * @param _diff is duration of calculation
     * @param _totalDeposit is the total amount of stable token deposited
     */
    function _calculateStableReward(
        uint256 _diff,
        uint256 _totalDeposit
    ) private view returns (uint256) {
        uint256 calculatedReward = _calculateFormula(
            _totalDeposit,
            _diff,
            _stableApr,
            _YEAR
        );
        return calculatedReward;
    }

    /**
     * @dev Calculates the bonus reward based on _bonusRate for all lender deposits
     * @dev Rewards are only applicable for the pool period duration
     * @param _diff is duration of calculation
     * @param _totalDeposit is the total amount of stable token deposited
     */
    function _calculateBonusReward(
        uint256 _diff,
        uint256 _totalDeposit
    ) private view returns (uint256) {
        uint256 calculatedBonus = _calculateFormula(
            _totalDeposit,
            _diff,
            _bonusRate,
            _poolPeriod
        );
        return calculatedBonus;
    }

    /**
     * @dev Calculates the bonus and stable rewards for all lender
     * @param amount is the amount of deposited stable tokens
     * @param duration is the passed duration from last updated rewards
     * @param rate is the fixed _bonusRate or _stableApr for the pool
     * @param period is the period that calculates rewards based on that
     */
    function _calculateFormula(
        uint256 amount,
        uint256 duration,
        uint256 rate,
        uint256 period
    ) private pure returns (uint256) {
        return ((amount * duration * rate) / 1E2) / period;
    }
}
