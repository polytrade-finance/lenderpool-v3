/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
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
    bool private _verificationStatus;

    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;
    IBondingCurve private _aprBondingCurve;
    IBondingCurve private _rateBondingCurve;
    IVerification public verification;
    IStrategy public strategy;

    modifier isValid() {
        if (_verificationStatus) {
            require(verification.isValid(msg.sender), "You are not verified");
        }
        _;
    }

    /**
     * @dev Sets the values for admin, stableToken, bonusToken, minDeposit,PoolMaxLimit
     * @param admin_ address of admin
     * @param stableToken_  address of stable Token
     * @param bonusToken_ address of bonus Token
     * @param minDeposit_ minimum deposit amount for users
     * @param poolMaxLimit_ maximum tokens to deposit in pool, after reaching contract stops receiving deposit
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
        _minDeposit = minDeposit_ * (10 ** _stableDecimal);
        _poolMaxLimit = poolMaxLimit_ * (10 ** _stableDecimal);
    }

    /**
     * @dev See {IFlexLender-changePoolLimit}.
     */
    function changePoolLimit(
        uint256 newLimit
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newLimit != 0, "Max limit can not be zero");
        uint256 oldLimit = _poolMaxLimit;
        _poolMaxLimit = newLimit * (10 ** _stableDecimal);
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
        require(newVerification != address(0), "Invalid Verification Address");
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
        require(newStrategy != address(0), "Invalid Strategy Address");
        address oldStrategy = address(strategy);
        if (oldStrategy != address(0)) {
            uint256 amount = strategy.getBalance();
            strategy.withdraw(amount);
            strategy = IStrategy(newStrategy);
            _depositInStrategy(amount);
        }
        strategy = IStrategy(newStrategy);
        emit StrategySwitched(oldStrategy, newStrategy);
    }

    /**
     * @dev See {IFlexLender-changeBaseRates}.
     */
    function changeBaseRates(
        uint256 baseStableApr,
        uint256 baseBonusRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(baseStableApr <= 10000, "Invalid Stable Apr");
        require(baseBonusRate <= 10000, "Invalid Bonus Rate");
        uint256 oldStableApr = rateRounds[_currentRateRound].stableApr;
        uint256 oldBonusRate = rateRounds[_currentRateRound].bonusRate;
        uint256 newStableApr = baseStableApr / 1E2;
        uint256 newBonusRate = baseBonusRate *
            (10 ** (_bonusDecimal - _stableDecimal));
        _currentRateRound++;
        rateRounds[_currentRateRound] = RateInfo(
            newStableApr,
            newBonusRate,
            block.timestamp
        );
        emit BaseRateChanged(
            oldStableApr,
            newStableApr,
            oldBonusRate,
            newBonusRate
        );
    }

    /**
     * @dev See {IFlexLender-switchAprBondingCurve}.
     */
    function switchAprBondingCurve(
        address newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(newCurve != address(0), "Invalid Curve Address");
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
        require(newCurve != address(0), "Invalid Curve Address");
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
        require(maxLimit > minLimit, "Max. Limit is not > Min. Limit");
        require(maxLimit <= 365, "Max. Limit should be <= 365 days");
        require(minLimit >= 90, "Min. Limit should be >= 90 days");
        _minLimit = minLimit;
        _maxLimit = maxLimit;
        emit DurationLimitChanged(minLimit, maxLimit);
    }

    /**
     * @dev See {IFlexLender-deposit}.
     */
    function deposit(uint256 amount) external isValid {
        require(address(strategy) != address(0), "There is no Strategy");
        require(
            _poolMaxLimit >= _poolSize + amount,
            "Pool has reached its limit"
        );
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        (uint256 stableReward, uint256 bonusReward) = _calculateBaseRewards(
            msg.sender
        );
        _poolSize += amount;
        lenders[msg.sender].amount += amount;
        lenders[msg.sender].pendingStableReward += stableReward;
        lenders[msg.sender].pendingBonusReward += bonusReward;
        lenders[msg.sender].lastUpdateDate = block.timestamp;
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        _depositInStrategy(amount);
        emit BaseDeposited(msg.sender, amount);
    }

    /**
     * @dev See {IFlexLender-deposit}.
     */
    function deposit(uint256 amount, uint256 lockingDuration) external isValid {
        require(address(strategy) != address(0), "There is no Strategy");
        require(
            _poolMaxLimit >= _poolSize + amount,
            "Pool has reached its limit"
        );
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        require(
            lockingDuration >= _minLimit,
            "Locking Duration is < Min. Limit"
        );
        require(
            lockingDuration <= _maxLimit,
            "Locking Duration is > Max. Limit"
        );
        uint256 apr = _aprBondingCurve.getRate(lockingDuration);
        uint256 rate = _rateBondingCurve.getRate(lockingDuration) *
            (10 ** (_bonusDecimal - _stableDecimal));
        uint256 lockingPeriod = lockingDuration * 1 days;
        uint256 currentId = lenders[msg.sender].currentId;
        lenders[msg.sender].currentId++;
        _poolSize += amount;
        lenders[msg.sender].deposits[currentId] = Deposit(
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
        for (
            uint256 i = lenders[msg.sender].startId;
            i < lenders[msg.sender].currentId;
            i++
        ) {
            if (lenders[msg.sender].deposits[i].amount != 0) {
                bonusReward += _claimBonus(i);
            }
        }
        bonusReward += _claimBonus();
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
        require(
            lenders[msg.sender].amount != 0,
            "You have not deposited anything"
        );
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        uint256 depositedAmount = lenders[msg.sender].amount;
        uint256 stableAmount = depositedAmount +
            lenders[msg.sender].pendingStableReward +
            baseStableReward;
        uint256 bonusAmount = baseBonusReward +
            lenders[msg.sender].pendingBonusReward;
        lenders[msg.sender].amount = 0;
        lenders[msg.sender].pendingBonusReward = 0;
        lenders[msg.sender].pendingStableReward = 0;
        _poolSize -= depositedAmount;
        strategy.withdraw(depositedAmount);
        _bonusToken.safeTransfer(msg.sender, bonusAmount);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit BaseWithdrawn(msg.sender, stableAmount, bonusAmount);
    }

    /**
     * @dev See {IFlexLender-withdraw}.
     */
    function withdraw(uint256 id) external {
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        uint256 depositEndDate = lenders[msg.sender].deposits[id].endDate;
        require(block.timestamp >= depositEndDate, "You can not withdraw yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender,
            id,
            depositEndDate
        );
        uint256 depositedAmount = lenders[msg.sender].deposits[id].amount;
        uint256 stableAmount = depositedAmount + stableReward;
        delete lenders[msg.sender].deposits[id];
        _poolSize -= depositedAmount;
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
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        uint256 depositEndDate = lenders[msg.sender].deposits[id].startDate +
            lenders[msg.sender].deposits[id].lockingDuration;
        require(
            block.timestamp < depositEndDate,
            "You can not emergency withdraw"
        );
        uint256 depositedAmount = lenders[msg.sender].deposits[id].amount;
        uint256 withdrawFee = (depositedAmount * _withdrawPenaltyPercent) / 1E4;
        uint256 refundAmount = depositedAmount - withdrawFee;
        delete lenders[msg.sender].deposits[id];
        _poolSize -= depositedAmount;
        _updateId(msg.sender);
        strategy.withdraw(depositedAmount);
        _stableToken.safeTransfer(msg.sender, refundAmount);
        emit WithdrawnEmergency(msg.sender, id, refundAmount);
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
        uint256 actives = _activeCount(lender);
        uint256 j;
        uint256[] memory activeDeposits = new uint256[](actives);
        for (
            uint256 i = lenders[lender].startId;
            i < lenders[lender].currentId;
            i++
        ) {
            if (lenders[lender].deposits[i].amount != 0) {
                activeDeposits[j] = i;
                j++;
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
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        lenders[msg.sender].pendingStableReward += baseStableReward;
        uint256 claimableBonus = baseBonusReward +
            lenders[msg.sender].pendingBonusReward;
        lenders[msg.sender].pendingBonusReward = 0;
        lenders[msg.sender].lastUpdateDate = block.timestamp;
        return claimableBonus;
    }

    /**
     * @dev It will called in claimBonus and claimAllBonus
     * @dev Calculates all bonus rewards for a specific deposit and updates lastClaimDate
     * @dev Updates msg.sender lastClaimDate
     * @param _id, id of the deposit
     */
    function _claimBonus(uint256 _id) private returns (uint256) {
        uint256 depositEndDate = lenders[msg.sender].deposits[_id].endDate;
        uint256 endDate = block.timestamp > depositEndDate
            ? depositEndDate
            : block.timestamp;
        (, uint256 bonusReward) = _calculateRewards(msg.sender, _id, endDate);
        lenders[msg.sender].deposits[_id].lastClaimDate = endDate;
        return bonusReward;
    }

    /**
     * @dev Updates the startId and currentId of deposits with lokcing period
     * @dev Loops through all deposits from start and end and updates id
     * @dev Called after a deposit has been withdrawn
     * @param _lender, address of lender
     */
    function _updateId(address _lender) private {
        uint256 start = lenders[_lender].startId;
        uint256 end = lenders[_lender].currentId;
        uint256 amount;
        for (uint256 i = start; i < end; i++) {
            amount += lenders[_lender].deposits[i].amount;
            if (amount == 0) {
                start = i + 1;
            } else {
                amount = 0;
                break;
            }
        }
        for (uint256 i = end; i > start; i--) {
            amount += lenders[_lender].deposits[i - 1].amount;
            if (amount == 0) {
                end = i - 1;
            } else {
                break;
            }
        }
        if (end == start) {
            lenders[_lender].startId = 0;
            lenders[_lender].currentId = 0;
        } else {
            lenders[_lender].startId = start;
            lenders[_lender].currentId = end;
        }
    }

    /**
     * @dev Calculates number of active deposits by lender
     * @dev Loops through all deposits from start and end and updates count
     * @param _lender, address of lender
     */
    function _activeCount(address _lender) private view returns (uint256) {
        uint256 count;
        for (
            uint256 i = lenders[_lender].startId;
            i < lenders[_lender].currentId;
            i++
        ) {
            if (lenders[_lender].deposits[i].amount != 0) {
                count++;
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
        uint256 amount = lenders[_lender].amount;
        uint256 lastUpdate = lenders[_lender].lastUpdateDate;
        uint256 calculatedStableReward;
        uint256 calculatedBonusReward;
        for (uint256 i = _currentRateRound; i > 0; i--) {
            uint256 endDate = i != _currentRateRound
                ? rateRounds[i + 1].startDate
                : block.timestamp;
            uint256 startDate = lastUpdate > rateRounds[i].startDate
                ? lastUpdate
                : rateRounds[i].startDate;
            uint256 diff = endDate - startDate;
            calculatedStableReward += _calculateFormula(
                amount,
                diff,
                rateRounds[i].stableApr,
                _YEAR
            );
            calculatedBonusReward += _calculateFormula(
                amount,
                diff,
                rateRounds[i].bonusRate,
                _YEAR
            );
            if (lastUpdate > rateRounds[i].startDate) {
                break;
            }
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
        uint256 amount = lenders[_lender].deposits[_id].amount;
        uint256 stableDiff = _endDate -
            lenders[_lender].deposits[_id].startDate;
        uint256 bonusDiff = _endDate -
            lenders[_lender].deposits[_id].lastClaimDate;
        return (
            _calculateFormula(
                amount,
                stableDiff,
                lenders[_lender].deposits[_id].apr,
                _YEAR
            ) / 1E2,
            _calculateFormula(
                amount,
                bonusDiff,
                lenders[_lender].deposits[_id].rate,
                lenders[_lender].deposits[_id].lockingDuration
            )
        );
    }

    /**
     * @dev loops through all deposits with locking period and sum it with deposit without locking period
     * @param _lender Represents the address of lender
     */
    function _getTotalDeposit(address _lender) private view returns (uint256) {
        uint256 depositedAmount = lenders[_lender].amount;
        for (
            uint256 i = lenders[_lender].startId;
            i < lenders[_lender].currentId;
            i++
        ) {
            depositedAmount += lenders[_lender].deposits[i].amount;
        }
        return depositedAmount;
    }

    /**
     * @dev Calculates the bonus and stable rewards for all lenders
     * @param _amount is the amount of deposited stable tokens
     * @param _duration is the passed duration from last updated rewards
     * @param _rate is the rate for bonus reward or apr for stable reward
     * @param _period is the period that calculates rewards based on that
     */
    function _calculateFormula(
        uint256 _amount,
        uint256 _duration,
        uint256 _rate,
        uint256 _period
    ) private pure returns (uint256) {
        return ((_amount * _duration * _rate) / 1E2) / _period;
    }
}
