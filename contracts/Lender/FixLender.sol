/// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Lender/Interface/IFixLender.sol";
import "contracts/Verification/Interface/IVerification.sol";
import "contracts/Strategy/Interface/IStrategy.sol";

/**
 * @title Fixed Lender Pool contract
 * @author Polytrade
 * @notice Users can deposit in predefined fixed lender pool during deposit period and withdraw their
 * Principal stable amount with its stable and bonus rewards based on APR and Rate
 * @dev The contract is in development stage
 */
contract FixLender is IFixLender, AccessControl {
    using SafeERC20 for IToken;
    using ERC165Checker for address;

    mapping(address => Lender) public lenders;

    uint256 private _poolSize;
    uint256 private _totalWithdrawFee;
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
    bytes32 public constant CLIENT_PORTAL =
        0xe86416a2d82e87b14776ede109c81c092d7b4e557918dd147487d8259a8a6bcf;
    bytes4 private constant _STRATEGY_INTERFACE_ID =
        type(IStrategy).interfaceId;
    bytes4 private constant _VERIFICATION_INTERFACE_ID =
        type(IVerification).interfaceId;
    bool private immutable _verificationStatus;

    IVerification private _verification;
    IStrategy private _strategy;
    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;

    modifier isValid() {
        if (_verificationStatus) {
            if (!_verification.isValid(msg.sender)) revert NotVerified();
        }
        _;
    }

    modifier hasDeposit() {
        if (lenders[msg.sender].totalDeposit == 0) revert NoDeposit();
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
        require(minDeposit_ != 0, "Invalid Min. Deposit");
        require(poolMaxLimit_ > minDeposit_, "Invalid Pool Max. Limit");
        require(bonusRate_ < 10_001, "Invalid Bonus Rate");
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
        _minDeposit = minDeposit_;
        _poolMaxLimit = poolMaxLimit_;
        _verificationStatus = verification_;
        _poolEndDate = _poolPeriod + _poolStartDate;
    }

    /**
     * @dev See {IFixLender-withdrawFees}.
     */
    function withdrawFees() external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_totalWithdrawFee != 0, "Nothing to withdraw");
        uint256 amount = _totalWithdrawFee;
        _totalWithdrawFee = 0;
        _stableToken.safeTransfer(msg.sender, amount);
        emit PenaltyFeeWithdrawn(amount);
    }

    /**
     * @dev See {IFixLender-clientPortalWithdraw}.
     */
    function clientPortalWithdraw(
        uint256 amount
    ) external onlyRole(CLIENT_PORTAL) {
        require(_strategy.getBalance() >= amount, "Not enough balance");
        _strategy.withdraw(amount);
        _stableToken.safeTransfer(msg.sender, amount);
        emit ClientPortalWithdrawal(amount);
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
        if (!newVerification.supportsInterface(_VERIFICATION_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldVerification = address(_verification);
        _verification = IVerification(newVerification);
        emit VerificationSwitched(oldVerification, newVerification);
    }

    /**
     * @notice `switchStrategy` updates the Strategy contract address.
     * @dev It moves all the funds from the old strategy to the new strategy.
     * @dev Changed strategy contract must comply with `IStrategy`.
     * @param newStrategy, address of the new staking strategy.
     * Emits {StrategySwitched} event
     */
    function switchStrategy(
        address newStrategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!newStrategy.supportsInterface(_STRATEGY_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldStrategy = address(_strategy);
        uint256 amount;
        if (oldStrategy != address(0)) {
            amount = _strategy.getBalance();
            _strategy.withdraw(amount);
            _stableToken.approve(address(_strategy), 0);
        }
        amount = _stableToken.balanceOf(address(this));
        _strategy = IStrategy(newStrategy);
        if (amount != 0) _depositInStrategy(amount);
        emit StrategySwitched(oldStrategy, newStrategy);
    }

    /**
     * @dev See {IFixLender-deposit}.
     */
    function deposit(uint256 amount) external isValid {
        require(address(_strategy) != address(0), "There is no Strategy");
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            _poolMaxLimit >= _poolSize + amount,
            "Pool has reached its limit"
        );
        require(
            block.timestamp < _depositEndDate,
            "Deposit End Date has passed"
        );
        Lender memory lenderData = lenders[msg.sender];
        uint256 currentDeposit = lenderData.totalDeposit;
        uint256 pendingStableReward = lenderData.pendingStableReward;
        uint256 pendingBonusReward = lenderData.pendingBonusReward;
        uint256 lastUpdateDate = _poolStartDate;
        _poolSize = _poolSize + amount;
        if (block.timestamp > _poolStartDate) {
            (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
                msg.sender
            );
            pendingStableReward = pendingStableReward + stableReward;
            pendingBonusReward = pendingBonusReward + bonusReward;
            lastUpdateDate = block.timestamp;
        }
        lenders[msg.sender] = Lender(
            currentDeposit + amount,
            pendingStableReward,
            pendingBonusReward,
            lastUpdateDate
        );
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositInStrategy(amount);
        emit Deposited(msg.sender, amount);
    }

    /**
     * @dev See {IFixLender-claimBonus}.
     */
    function claimBonus() external hasDeposit {
        require(block.timestamp > _poolStartDate, "Pool has not started yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender
        );
        Lender storage lenderData = lenders[msg.sender];
        lenderData.pendingStableReward =
            lenderData.pendingStableReward +
            stableReward;
        uint256 claimableBonus = bonusReward + lenderData.pendingBonusReward;
        lenderData.pendingBonusReward = 0;
        lenderData.lastUpdateDate = block.timestamp > _poolEndDate
            ? _poolEndDate
            : block.timestamp;
        _bonusToken.safeTransfer(msg.sender, claimableBonus);
        emit BonusClaimed(msg.sender, claimableBonus);
    }

    /**
     * @dev See {IFixLender-withdraw}.
     */
    function withdraw() external hasDeposit {
        require(block.timestamp > _poolEndDate, "Pool has not ended yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender
        );
        Lender memory lenderData = lenders[msg.sender];
        uint256 totalDeposit = lenderData.totalDeposit;
        uint256 stableAmount = stableReward +
            lenderData.pendingStableReward +
            totalDeposit;
        uint256 bonusAmount = bonusReward + lenderData.pendingBonusReward;
        delete lenders[msg.sender];
        _poolSize = _poolSize - totalDeposit;
        _strategy.withdraw(stableAmount);
        _bonusToken.safeTransfer(msg.sender, bonusAmount);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit Withdrawn(msg.sender, stableAmount, bonusAmount);
    }

    /**
     * @dev See {IFixLender-emergencyWithdraw}.
     */
    function emergencyWithdraw() external hasDeposit {
        require(
            block.timestamp < _poolEndDate,
            "You can not emergency withdraw"
        );
        uint256 totalDeposit = lenders[msg.sender].totalDeposit;
        uint256 withdrawFee = (totalDeposit * _withdrawPenaltyPercent) / 1E4;
        uint256 refundAmount = totalDeposit - withdrawFee;
        uint256 bonusReward;
        if (block.timestamp > _poolStartDate)
            (, bonusReward) = _calculateRewards(msg.sender);
        delete lenders[msg.sender];
        _poolSize = _poolSize - totalDeposit;
        _totalWithdrawFee =
            _totalWithdrawFee +
            _strategy.withdraw(totalDeposit) -
            refundAmount;
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        _stableToken.safeTransfer(msg.sender, refundAmount);
        emit WithdrawnEmergency(msg.sender, refundAmount, bonusReward);
    }

    /**
     * @dev See {IFixLender-setWithdrawRate}.
     */
    function setWithdrawRate(
        uint256 newRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newRate < 10_000, "Rate can not be more than 100%");
        uint256 oldRate = _withdrawPenaltyPercent;
        _withdrawPenaltyPercent = newRate;
        emit WithdrawRateChanged(oldRate, newRate);
    }

    /**
     * @dev See {IFixLender-getTotalDeposit}.
     */
    function getTotalDeposit(address _lender) external view returns (uint256) {
        return lenders[_lender].totalDeposit;
    }

    /**
     * @dev See {IFixLender-getBonusRewards}.
     */
    function getBonusRewards(address _lender) external view returns (uint256) {
        uint256 bonusReward;
        if (block.timestamp > _poolStartDate) {
            (, bonusReward) = _calculateRewards(_lender);
            bonusReward = bonusReward + lenders[_lender].pendingBonusReward;
        }
        return bonusReward;
    }

    /**
     * @dev See {IFixLender-getStableRewards}.
     */
    function getStableRewards(address _lender) external view returns (uint256) {
        uint256 stableReward;
        if (block.timestamp > _poolStartDate) {
            (stableReward, ) = _calculateRewards(_lender);
            stableReward = stableReward + lenders[_lender].pendingStableReward;
        }
        return stableReward;
    }

    /**
     * @dev See {IFixLender-getApr}.
     */
    function getApr() external view returns (uint256) {
        return _stableApr;
    }

    /**
     * @dev See {IFixLender-getBonusRate}.
     */
    function getBonusRate() external view returns (uint256) {
        return _bonusRate / (10 ** (_bonusDecimal - _stableDecimal));
    }

    /**
     * @dev See {IFixLender-getLockingDuration}.
     */
    function getLockingDuration() external view returns (uint256) {
        return _poolPeriod / 1 days;
    }

    /**
     * @dev See {IFixLender-getPoolStartDate}.
     */
    function getPoolStartDate() external view returns (uint256) {
        return _poolStartDate;
    }

    /**
     * @dev See {IFixLender-getDepositEndDate}.
     */
    function getDepositEndDate() external view returns (uint256) {
        return _depositEndDate;
    }

    /**
     * @dev See {IFixLender-getPoolSize}.
     */
    function getPoolSize() external view returns (uint256) {
        return _poolSize;
    }

    /**
     * @dev See {IFixLender-getMaxPoolSize}.
     */
    function getMaxPoolSize() external view returns (uint256) {
        return _poolMaxLimit;
    }

    /**
     * @dev See {IFixLender-getMinDeposit}.
     */
    function getMinDeposit() external view returns (uint256) {
        return _minDeposit;
    }

    /**
     * @dev See {IFixLender-getTotalPenaltyFee}.
     */
    function getTotalPenaltyFee() external view returns (uint256) {
        return _totalWithdrawFee;
    }

    /**
     * @dev See {IFixLender-getWithdrawPenaltyPercent}.
     */
    function getWithdrawPenaltyPercent() external view returns (uint256) {
        return _withdrawPenaltyPercent;
    }

    /**
     * @dev See {IFixLender-stableToken}.
     */
    function stableToken() external view returns (address) {
        return address(_stableToken);
    }

    /**
     * @dev See {IFixLender-bonusToken}.
     */
    function bonusToken() external view returns (address) {
        return address(_bonusToken);
    }

    /**
     * @dev See {IFlexLender-verification}.
     */
    function verification() external view returns (address) {
        return address(_verification);
    }

    /**
     * @dev See {IFlexLender-strategy}.
     */
    function strategy() external view returns (address) {
        return address(_strategy);
    }

    /**
     * @dev See {IFixLender-getVerificationStatus}.
     */
    function getVerificationStatus() external view returns (bool) {
        return _verificationStatus;
    }

    /**
     * @notice `_depositInStrategy` deposits stable token to external protocol.
     * @dev Funds will be deposited to a Strategy (external protocols) like Aave, compound
     * @param amount, total amount to be deposited.
     */
    function _depositInStrategy(uint amount) private {
        _stableToken.approve(address(_strategy), amount);
        _strategy.deposit(amount);
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for lender
     * @param _lender is the address of lender
     */
    function _calculateRewards(
        address _lender
    ) private view returns (uint256, uint256) {
        Lender memory lenderData = lenders[_lender];
        uint256 endDate = block.timestamp > _poolEndDate
            ? _poolEndDate
            : block.timestamp;
        uint256 diff = endDate - lenderData.lastUpdateDate;
        uint256 totalDeposit = lenderData.totalDeposit;
        return (
            _calculateFormula(totalDeposit, diff, _stableApr) / 1E2,
            _calculateFormula(totalDeposit, diff, _bonusRate)
        );
    }

    /**
     * @dev Calculates the bonus and stable rewards for all lenders
     * @param amount is the amount of deposited stable tokens
     * @param duration is the passed duration from last updated rewards
     * @param rate is the fixed _bonusRate or _stableApr for the pool
     */
    function _calculateFormula(
        uint256 amount,
        uint256 duration,
        uint256 rate
    ) private pure returns (uint256) {
        return ((amount * duration * rate) / 1E2) / _YEAR;
    }
}
