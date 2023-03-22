/// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Lender/Interface/IFlexLender.sol";
import "contracts/BondingCurve/Interface/IBondingCurve.sol";
import "contracts/Verification/Interface/IVerification.sol";
import "contracts/Strategy/Interface/IStrategy.sol";

/**
 * @title Flexible Lender Pool contract
 * @author Polytrade
 * @notice Users can deposit in Flexible lender pool without locking period or with locking period by their choice
 * @dev The contract is in development stage
 */
contract FlexLender is IFlexLender, AccessControl {
    using SafeERC20 for IToken;
    using ERC165Checker for address;

    mapping(address => Lender) public lenders;
    mapping(uint256 => RateInfo) public rateRounds;

    uint256 private _poolSize;
    uint256 private _withdrawPenaltyPercent;
    uint256 private _currentRateRound;
    uint256 private _minLimit;
    uint256 private _maxLimit;
    uint256 private _poolMaxLimit;
    uint256 private immutable _stableDecimal;
    uint256 private immutable _bonusDecimal;
    uint256 private immutable _minDeposit;
    uint256 private constant _YEAR = 365 days;
    bytes4 private constant _CURVE_INTERFACE_ID =
        type(IBondingCurve).interfaceId;
    bytes4 private constant _STRATEGY_INTERFACE_ID =
        type(IStrategy).interfaceId;
    bytes4 private constant _VERIFICATION_INTERFACE_ID =
        type(IVerification).interfaceId;
    bool private _verificationStatus;

    IVerification public verification;
    IStrategy public strategy;
    IBondingCurve private _aprBondingCurve;
    IBondingCurve private _rateBondingCurve;
    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;

    modifier isValid() {
        if (_verificationStatus)
            require(verification.isValid(msg.sender), "You are not verified");
        _;
    }

    /**
     * @dev Sets the values for admin, stableToken, bonusToken, minDeposit,PoolMaxLimit
     * @param admin_ address of admin
     * @param stableToken_  address of stable Token
     * @param bonusToken_ address of bonus Token
     * @param minDeposit_ minimum deposit amount for users with stable decimals
     * @param poolMaxLimit_ maximum tokens to deposit in pool, after reaching contract stops receiving deposit
     * with stable decimals
     */
    constructor(
        address admin_,
        address stableToken_,
        address bonusToken_,
        uint256 minDeposit_,
        uint256 poolMaxLimit_
    ) {
        require(admin_ != address(0), "Invalid Admin address");
        require(stableToken_ != address(0), "Invalid Stable Token address");
        require(bonusToken_ != address(0), "Invalid Bonus Token address");
        require(poolMaxLimit_ > minDeposit_, "Invalid Pool Max. Limit");
        _grantRole(DEFAULT_ADMIN_ROLE, admin_);
        _stableToken = IToken(stableToken_);
        _bonusToken = IToken(bonusToken_);
        _stableDecimal = _stableToken.decimals();
        _bonusDecimal = _bonusToken.decimals();
        _minDeposit = minDeposit_;
        _poolMaxLimit = poolMaxLimit_;
    }

    /**
     * @dev See {IFlexLender-changePoolLimit}.
     */
    function changePoolLimit(
        uint256 newLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newLimit != 0, "Max limit can not be zero");
        uint256 oldLimit = _poolMaxLimit;
        _poolMaxLimit = newLimit;
        emit PoolLimitChanged(oldLimit, _poolMaxLimit);
    }

    /**
     * @dev See {IFlexLender-changeVerificationStatus}.
     */
    function changeVerificationStatus() external onlyRole(DEFAULT_ADMIN_ROLE) {
        bool oldStatus = _verificationStatus;
        _verificationStatus = oldStatus ? false : true;
        emit VerificationStatusChanged(oldStatus, _verificationStatus);
    }

    /**
     * @dev See {IFlexLender-switchVerification}.
     */
    function switchVerification(
        address newVerification
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!newVerification.supportsInterface(_VERIFICATION_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldVerification = address(verification);
        verification = IVerification(newVerification);
        emit VerificationSwitched(oldVerification, newVerification);
    }

    /**
     * @dev See {IFlexLender-switchStrategy}.
     */
    function switchStrategy(
        address newStrategy
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!newStrategy.supportsInterface(_STRATEGY_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldStrategy = address(strategy);
        uint256 amount;
        if (oldStrategy != address(0)) {
            amount = strategy.getBalance();
            strategy.withdraw(amount);
        }
        strategy = IStrategy(newStrategy);
        if (amount > 0) _depositInStrategy(amount);
        emit StrategySwitched(oldStrategy, newStrategy);
    }

    /**
     * @dev See {IFlexLender-changeBaseRates}.
     */
    function changeBaseRates(
        uint256 baseStableApr,
        uint256 baseBonusRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(baseStableApr < 10_001, "Invalid Stable Apr");
        require(baseBonusRate < 10_001, "Invalid Bonus Rate");
        RateInfo memory roundData = rateRounds[_currentRateRound];
        uint256 newStableApr = baseStableApr / 1E2;
        uint256 newBonusRate = baseBonusRate *
            (10 ** (_bonusDecimal - _stableDecimal));
        unchecked {
            ++_currentRateRound;
        }
        rateRounds[_currentRateRound] = RateInfo(
            newStableApr,
            newBonusRate,
            block.timestamp
        );
        emit BaseRateChanged(
            roundData.stableApr,
            newStableApr,
            roundData.bonusRate,
            newBonusRate
        );
    }

    /**
     * @dev See {IFlexLender-switchAprBondingCurve}.
     */
    function switchAprBondingCurve(
        address newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!newCurve.supportsInterface(_CURVE_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldCurve = address(_aprBondingCurve);
        _aprBondingCurve = IBondingCurve(newCurve);
        emit AprBondingCurveSwitched(oldCurve, newCurve);
    }

    /**
     * @dev See {IFlexLender-switchRateBondingCurve}.
     */
    function switchRateBondingCurve(
        address newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        if (!newCurve.supportsInterface(_CURVE_INTERFACE_ID))
            revert UnsupportedInterface();
        address oldCurve = address(_rateBondingCurve);
        _rateBondingCurve = IBondingCurve(newCurve);
        emit RateBondingCurveSwitched(oldCurve, newCurve);
    }

    /**
     * @dev See {IFlexLender-changeDurationLimit}.
     */
    function changeDurationLimit(
        uint256 minLimit,
        uint256 maxLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(maxLimit < 366, "Max. Limit should be <= 365 days");
        require(minLimit > 89, "Min. Limit should be >= 90 days");
        require(maxLimit > minLimit, "Max. Limit is not > Min. Limit");
        _minLimit = minLimit;
        _maxLimit = maxLimit;
        emit DurationLimitChanged(minLimit, maxLimit);
    }

    /**
     * @dev See {IFlexLender-deposit}.
     */
    function deposit(uint256 amount) external isValid {
        require(address(strategy) != address(0), "There is no Strategy");
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            _poolMaxLimit >= _poolSize + amount,
            "Pool has reached its limit"
        );
        (uint256 stableReward, uint256 bonusReward) = _calculateBaseRewards(
            msg.sender
        );
        Lender storage lenderData = lenders[msg.sender];
        _poolSize = _poolSize + amount;
        lenderData.amount = lenderData.amount + amount;
        lenderData.pendingStableReward =
            lenderData.pendingStableReward +
            stableReward;
        lenderData.pendingBonusReward =
            lenderData.pendingBonusReward +
            bonusReward;
        lenderData.lastUpdateDate = block.timestamp;
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositInStrategy(amount);
        emit BaseDeposited(msg.sender, amount);
    }

    /**
     * @dev See {IFlexLender-deposit}.
     */
    function deposit(
        uint256 amount,
        uint256 lockingDuration
    ) external isValid returns (uint256) {
        require(address(strategy) != address(0), "There is no Strategy");
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            lockingDuration >= _minLimit,
            "Locking Duration is < Min. Limit"
        );
        require(
            lockingDuration <= _maxLimit,
            "Locking Duration is > Max. Limit"
        );
        require(
            _poolMaxLimit >= _poolSize + amount,
            "Pool has reached its limit"
        );
        Lender storage lenderData = lenders[msg.sender];
        uint256 apr = _aprBondingCurve.getRate(lockingDuration);
        uint256 rate = _rateBondingCurve.getRate(lockingDuration) *
            (10 ** (_bonusDecimal - _stableDecimal));
        uint256 lockingPeriod = lockingDuration * 1 days;
        uint256 currentId = lenderData.currentId;
        unchecked {
            ++lenderData.currentId;
        }
        _poolSize = _poolSize + amount;
        lenderData.deposits[currentId] = Deposit(
            amount,
            apr,
            rate,
            lockingPeriod,
            block.timestamp,
            block.timestamp + lockingPeriod,
            block.timestamp
        );
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositInStrategy(amount);
        emit Deposited(msg.sender, currentId, amount, lockingPeriod, apr, rate);
        return currentId;
    }

    /**
     * @dev See {IFlexLender-claimAllBonuses}.
     */
    function claimAllBonuses() external {
        require(
            _getTotalDeposit(msg.sender) != 0,
            "You have not deposited anything"
        );
        uint256 bonusReward;
        Lender storage lenderData = lenders[msg.sender];
        for (uint256 i = lenderData.startId; i < lenderData.currentId; ) {
            if (lenderData.deposits[i].amount != 0)
                bonusReward = bonusReward + _claimBonus(i);
            unchecked {
                ++i;
            }
        }
        bonusReward = bonusReward + _claimBonus();
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        emit AllBonusClaimed(msg.sender, bonusReward);
    }

    /**
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus() external {
        require(
            lenders[msg.sender].amount != 0,
            "You have not deposited anything"
        );
        uint256 claimableBonus = _claimBonus();
        _bonusToken.safeTransfer(msg.sender, claimableBonus);
        emit BaseBonusClaimed(msg.sender, claimableBonus);
    }

    /**
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus(uint256 id) external {
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        uint256 bonusReward = _claimBonus(id);
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        emit BonusClaimed(msg.sender, id, bonusReward);
    }

    /**
     * @dev See {IFlexLender-withdraw}.
     */
    function withdraw() external {
        Lender storage lenderData = lenders[msg.sender];
        require(lenderData.amount != 0, "You have not deposited anything");
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        uint256 depositedAmount = lenderData.amount;
        uint256 stableAmount = depositedAmount +
            lenderData.pendingStableReward +
            baseStableReward;
        uint256 bonusAmount = baseBonusReward + lenderData.pendingBonusReward;
        lenderData.amount = 0;
        lenderData.pendingBonusReward = 0;
        lenderData.pendingStableReward = 0;
        _poolSize = _poolSize - depositedAmount;
        strategy.withdraw(depositedAmount);
        _bonusToken.safeTransfer(msg.sender, bonusAmount);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit BaseWithdrawn(msg.sender, stableAmount, bonusAmount);
    }

    /**
     * @dev See {IFlexLender-withdraw}.
     */
    function withdraw(uint256 id) external {
        Deposit memory depositData = lenders[msg.sender].deposits[id];
        require(depositData.amount != 0, "You have nothing with this ID");
        uint256 depositEndDate = depositData.endDate;
        require(block.timestamp >= depositEndDate, "You can not withdraw yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender,
            id,
            depositEndDate
        );
        uint256 depositedAmount = depositData.amount;
        uint256 stableAmount = depositedAmount + stableReward;
        delete lenders[msg.sender].deposits[id];
        _poolSize = _poolSize - depositedAmount;
        _updateId(msg.sender);
        strategy.withdraw(depositedAmount);
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit Withdrawn(msg.sender, id, stableAmount, bonusReward);
    }

    /**
     * @dev See {IFlexLender-emergencyWithdraw}.
     */
    function emergencyWithdraw(uint256 id) external {
        Deposit memory depositData = lenders[msg.sender].deposits[id];
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        require(
            block.timestamp <
                depositData.startDate + depositData.lockingDuration,
            "You can not emergency withdraw"
        );
        uint256 depositedAmount = depositData.amount;
        uint256 withdrawFee = (depositedAmount * _withdrawPenaltyPercent) / 1E4;
        uint256 refundAmount = depositedAmount - withdrawFee;
        uint256 bonusReward = _claimBonus(id);
        delete lenders[msg.sender].deposits[id];
        _poolSize = _poolSize - depositedAmount;
        _updateId(msg.sender);
        strategy.withdraw(depositedAmount);
        _stableToken.safeTransfer(msg.sender, refundAmount);
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        emit WithdrawnEmergency(msg.sender, id, refundAmount, bonusReward);
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
    function getTotalDeposit(address lender) external view returns (uint256) {
        return _getTotalDeposit(lender);
    }

    /**
     * @dev See {IFixLender-getDeposit}.
     */
    function getDeposit(address lender) external view returns (uint256) {
        return lenders[lender].amount;
    }

    /**
     * @dev See {IFixLender-getDeposit}.
     */
    function getDeposit(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        return lenders[lender].deposits[id].amount;
    }

    /**
     * @dev See {IFixLender-getBonusRewards}.
     */
    function getBonusRewards(address lender) external view returns (uint256) {
        (, uint256 baseBonusReward) = _calculateBaseRewards(lender);
        return baseBonusReward + lenders[lender].pendingBonusReward;
    }

    /**
     * @dev See {IFixLender-getBonusRewards}.
     */
    function getBonusRewards(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        uint256 depositEndDate = lenders[lender].deposits[id].endDate;
        (, uint256 bonusReward) = _calculateRewards(
            lender,
            id,
            block.timestamp > depositEndDate ? depositEndDate : block.timestamp
        );
        return bonusReward;
    }

    /**
     * @dev See {IFixLender-getStableRewards}.
     */
    function getStableRewards(address lender) external view returns (uint256) {
        (uint256 baseStableReward, ) = _calculateBaseRewards(lender);
        return baseStableReward + lenders[lender].pendingStableReward;
    }

    /**
     * @dev See {IFixLender-getStableRewards}.
     */
    function getStableRewards(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        uint256 depositEndDate = lenders[lender].deposits[id].endDate;
        (uint256 stableReward, ) = _calculateRewards(
            lender,
            id,
            block.timestamp > depositEndDate ? depositEndDate : block.timestamp
        );
        return stableReward;
    }

    /**
     * @dev See {IFixLender-getApr}.
     */
    function getApr(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        return lenders[lender].deposits[id].apr;
    }

    /**
     * @dev See {IFixLender-getRate}.
     */
    function getRate(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        return
            lenders[lender].deposits[id].rate /
            (10 ** (_bonusDecimal - _stableDecimal));
    }

    /**
     * @dev See {IFixLender-getBaseApr}.
     */
    function getBaseApr() external view returns (uint256) {
        return rateRounds[_currentRateRound].stableApr;
    }

    /**
     * @dev See {IFixLender-getBaseRate}.
     */
    function getBaseRate() external view returns (uint256) {
        return
            rateRounds[_currentRateRound].bonusRate /
            (10 ** (_bonusDecimal - _stableDecimal));
    }

    /**
     * @dev See {IFixLender-getLockingDuration}.
     */
    function getLockingDuration(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        return lenders[lender].deposits[id].lockingDuration / 1 days;
    }

    /**
     * @dev See {IFixLender-getMinLockingDuration}.
     */
    function getMinLockingDuration() external view returns (uint256) {
        return _minLimit;
    }

    /**
     * @dev See {IFixLender-getMaxLockingDuration}.
     */
    function getMaxLockingDuration() external view returns (uint256) {
        return _maxLimit;
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
     * @dev See {IFixLender-getVerificationStatus}.
     */
    function getVerificationStatus() external view returns (bool) {
        return _verificationStatus;
    }

    /**
     * @dev See {IFixLender-getActiveDeposits}.
     */
    function getActiveDeposits(
        address lender
    ) external view returns (uint256[] memory) {
        Lender storage lenderData = lenders[lender];
        uint256 actives = _activeCount(lender);
        uint256 j;
        uint256[] memory activeDeposits = new uint256[](actives);
        for (uint256 i = lenderData.startId; i < lenderData.currentId; ) {
            if (lenderData.deposits[i].amount != 0) activeDeposits[j++] = i;
            unchecked {
                ++i;
            }
        }
        return activeDeposits;
    }

    /**
     * @notice `_depositInStrategy` deposits stable token to external protocol.
     * @dev Funds will be deposited to a Strategy (external protocols) like Aave, compound
     * @param _amount, total amount to be deposited.
     */
    function _depositInStrategy(uint _amount) private {
        _stableToken.approve(address(strategy), _amount);
        strategy.deposit(_amount);
    }

    /**
     * @dev It will called in claimBonus and claimAllBonus
     * @dev Calculates all stable and bonus rewards and updates deposit without locking period parameters
     * @dev Updates msg.sender pendingRewards
     */
    function _claimBonus() private returns (uint256) {
        Lender storage lenderData = lenders[msg.sender];
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        lenderData.pendingStableReward =
            lenderData.pendingStableReward +
            baseStableReward;
        uint256 claimableBonus = baseBonusReward +
            lenderData.pendingBonusReward;
        lenderData.pendingBonusReward = 0;
        lenderData.lastUpdateDate = block.timestamp;
        return claimableBonus;
    }

    /**
     * @dev It will called in claimBonus and claimAllBonus
     * @dev Calculates all bonus rewards for a specific deposit and updates lastClaimDate
     * @dev Updates msg.sender lastClaimDate
     * @param _id, id of the deposit
     */
    function _claimBonus(uint256 _id) private returns (uint256) {
        Lender storage lenderData = lenders[msg.sender];
        uint256 depositEndDate = lenderData.deposits[_id].endDate;
        uint256 endDate = block.timestamp > depositEndDate
            ? depositEndDate
            : block.timestamp;
        (, uint256 bonusReward) = _calculateRewards(msg.sender, _id, endDate);
        lenderData.deposits[_id].lastClaimDate = endDate;
        return bonusReward;
    }

    /**
     * @dev Updates the startId and currentId of deposits with lokcing period
     * @dev Loops through all deposits from start and end and updates id
     * @dev Called after a deposit has been withdrawn
     * @param _lender, address of lender
     */
    function _updateId(address _lender) private {
        Lender storage lenderData = lenders[_lender];
        uint256 start = lenderData.startId;
        uint256 end = lenderData.currentId;

        while (start < end && lenderData.deposits[start].amount == 0) {
            ++start;
        }

        while (start < end && lenderData.deposits[end - 1].amount == 0) {
            --end;
        }

        uint256 reset = (end == start) ? 0 : end;
        lenderData.startId = reset == 0 ? 0 : start;
        lenderData.currentId = reset;
    }

    /**
     * @dev Calculates number of active deposits by lender
     * @dev Loops through all deposits from start and end and updates count
     * @param _lender, address of lender
     */
    function _activeCount(address _lender) private view returns (uint256) {
        uint256 count;
        Lender storage lenderData = lenders[_lender];
        for (uint256 i = lenderData.startId; i < lenderData.currentId; ) {
            if (lenderData.deposits[i].amount != 0) {
                unchecked {
                    ++count;
                }
            }
            unchecked {
                ++i;
            }
        }
        return count;
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for the deposit without locking period
     * @param _lender is the address of lender
     */
    function _calculateBaseRewards(
        address _lender
    ) private view returns (uint256, uint256) {
        Lender storage lenderData = lenders[_lender];
        uint256 amount = lenderData.amount;
        uint256 lastUpdate = lenderData.lastUpdateDate;
        uint256 calculatedStableReward;
        uint256 calculatedBonusReward;
        for (uint256 i = _currentRateRound; i > 0; --i) {
            uint256 endDate = i != _currentRateRound
                ? rateRounds[i + 1].startDate
                : block.timestamp;
            uint256 startDate = lastUpdate > rateRounds[i].startDate
                ? lastUpdate
                : rateRounds[i].startDate;
            uint256 diff = endDate - startDate;
            calculatedStableReward =
                calculatedStableReward +
                _calculateFormula(amount, diff, rateRounds[i].stableApr);
            calculatedBonusReward =
                calculatedBonusReward +
                _calculateFormula(amount, diff, rateRounds[i].bonusRate);
            if (lastUpdate > rateRounds[i].startDate) break;
        }
        return (calculatedStableReward, calculatedBonusReward);
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for deposits with locking period
     * @param _lender is the address of lender
     * @param _id is the id of deposit
     * @param _endDate is the end date of calculation
     */
    function _calculateRewards(
        address _lender,
        uint256 _id,
        uint256 _endDate
    ) private view returns (uint256, uint256) {
        Deposit memory depositData = lenders[_lender].deposits[_id];
        uint256 amount = depositData.amount;
        uint256 stableDiff = _endDate - depositData.startDate;
        uint256 bonusDiff = _endDate - depositData.lastClaimDate;
        return (
            _calculateFormula(amount, stableDiff, depositData.apr) / 1E2,
            _calculateFormula(amount, bonusDiff, depositData.rate)
        );
    }

    /**
     * @dev loops through all deposits with locking period and sum it with deposit without locking period
     * @param _lender Represents the address of lender
     */
    function _getTotalDeposit(address _lender) private view returns (uint256) {
        Lender storage lenderData = lenders[_lender];
        uint256 depositedAmount = lenderData.amount;
        for (uint256 i = lenderData.startId; i < lenderData.currentId; ) {
            depositedAmount = depositedAmount + lenderData.deposits[i].amount;
            unchecked {
                ++i;
            }
        }
        return depositedAmount;
    }

    /**
     * @dev Calculates the bonus and stable rewards for all lenders
     * @param amount is the amount of deposited stable tokens
     * @param duration is the passed duration from last updated rewards
     * @param rate is the rate for bonus reward or apr for stable reward
     */
    function _calculateFormula(
        uint256 amount,
        uint256 duration,
        uint256 rate
    ) private pure returns (uint256) {
        return ((amount * duration * rate) / 1E2) / _YEAR;
    }
}
