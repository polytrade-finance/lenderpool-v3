/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "contracts/Token/Interface/IToken.sol";
import "contracts/Lender/Interface/IFlexLender.sol";
import "contracts/BondingCurve/Interface/IBondingCurve.sol";

/**
 * @title Flexible Lender Pool contract
 * @author Polytrade
 * @notice Users can deposit in Flexible lender pool without locking period or with locking period by their choice
 * @dev The contract is in development stage
 */
contract FlexLender is IFlexLender, AccessControl {
    using SafeERC20 for IToken;
    mapping(address => Lender) public lenders;
    mapping(uint256 => RoundInfo) public aprRounds;
    mapping(uint256 => RoundInfo) public rateRounds;

    uint256 public poolSize;
    uint256 private _withdrawPenaltyPercent;
    uint256 private _currentAprRound;
    uint256 private _currentRateRound;
    uint256 private _minLimit;
    uint256 private _maxLimit;
    uint256 private immutable _stableDecimal;
    uint256 private immutable _bonusDecimal;
    uint256 private immutable _minDeposit;
    uint256 private immutable _poolMaxLimit;
    uint256 private constant _YEAR = 365 days;

    IToken private immutable _stableToken;
    IToken private immutable _bonusToken;
    IBondingCurve private _aprBondingCurve;
    IBondingCurve private _rateBondingCurve;

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
     * @dev See {IFlexLender-changeBaseApr}.
     */
    function changeBaseApr(
        uint256 baseStableApr
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        uint256 oldApr = aprRounds[_currentAprRound].rate;
        uint256 newApr = baseStableApr;
        _currentAprRound++;
        aprRounds[_currentAprRound] = RoundInfo(newApr, block.timestamp);
        emit BaseAprChanged(oldApr, newApr);
    }

    /**
     * @dev See {IFlexLender-changeBaseRate}.
     */
    function changeBaseRate(
        uint256 baseBonusRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(baseBonusRate <= 10000, "Invalid Bonus Rate");
        uint256 oldRate = rateRounds[_currentRateRound].rate;
        uint256 newRate = baseBonusRate *
            (10 ** (_bonusDecimal - _stableDecimal));
        _currentRateRound++;
        rateRounds[_currentRateRound] = RoundInfo(newRate, block.timestamp);
        emit BaseRateChanged(oldRate, newRate);
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
    function deposit(uint256 amount) external {
        require(
            _poolMaxLimit >= poolSize + amount,
            "Pool has reached its limit"
        );
        require(amount >= _minDeposit, "Amount is less than Min. Deposit");
        (uint256 stableReward, uint256 bonusReward) = _calculateBaseRewards(
            msg.sender
        );
        poolSize += amount;
        lenders[msg.sender].amount += amount;
        lenders[msg.sender].pendingStableReward += stableReward;
        lenders[msg.sender].pendingBonusReward += bonusReward;
        lenders[msg.sender].lastUpdateDate = block.timestamp;
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
        emit Deposited(msg.sender, 0, amount, 0, 0, 0);
    }

    /**
     * @dev See {IFlexLender-deposit}.
     */
    function deposit(uint256 amount, uint256 lockingDuration) external {
        require(
            _poolMaxLimit >= poolSize + amount,
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
        lenders[msg.sender].currentId++;
        uint256 currentId = lenders[msg.sender].currentId;
        poolSize += amount;
        lenders[msg.sender].deposits[currentId] = Deposit(
            amount,
            apr,
            rate,
            lockingPeriod,
            block.timestamp,
            block.timestamp
        );
        _stableToken.safeTransferFrom(msg.sender, address(this), amount);
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
        _claimBonus();
        for (
            uint256 i = lenders[msg.sender].startId;
            i < lenders[msg.sender].currentId;
            i++
        ) {
            _claimBonus(i + 1);
        }
    }

    /**
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus() external {
        require(
            lenders[msg.sender].amount != 0,
            "You have not deposited anything"
        );
        _claimBonus();
    }

    /**
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus(uint256 id) external {
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        _claimBonus(id);
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
        poolSize -= depositedAmount;
        _bonusToken.safeTransfer(msg.sender, bonusAmount);
        _stableToken.safeTransfer(msg.sender, stableAmount);
        emit Withdrawn(msg.sender, 0, stableAmount, bonusAmount);
    }

    /**
     * @dev See {IFlexLender-withdraw}.
     */
    function withdraw(uint256 id) external {
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        uint256 depositEndDate = lenders[msg.sender].deposits[id].startDate +
            lenders[msg.sender].deposits[id].lockingDuration;
        require(block.timestamp >= depositEndDate, "You can not withdraw yet");
        (uint256 stableReward, uint256 bonusReward) = _calculateRewards(
            msg.sender,
            id
        );
        uint256 depositedAmount = lenders[msg.sender].deposits[id].amount;
        uint256 stableAmount = depositedAmount + stableReward;
        delete lenders[msg.sender].deposits[id];
        poolSize -= depositedAmount;
        // _updateId(msg.sender);
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
        poolSize -= depositedAmount;
        _updateId(msg.sender);
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
     * @dev It will called in claimBonus and claimAllBonus
     * @dev Calculates all stable and bonus rewards and updates deposit without locking period parameters
     * @dev Transfers all bonus rewards to sender
     * @dev emit {BonusClaimed} event
     */
    function _claimBonus() private {
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        lenders[msg.sender].pendingStableReward += baseStableReward;
        uint256 claimableBonus = baseBonusReward +
            lenders[msg.sender].pendingBonusReward;
        lenders[msg.sender].pendingBonusReward = 0;
        lenders[msg.sender].lastUpdateDate = block.timestamp;
        _bonusToken.safeTransfer(msg.sender, claimableBonus);
        emit BonusClaimed(msg.sender, 0, claimableBonus);
    }

    /**
     * @dev It will called in claimBonus and claimAllBonus
     * @dev Calculates all bonus rewards for a specific deposit and updates lastClaimDate
     * @dev Transfers all bonus rewards to sender
     * @dev emit {BonusClaimed} event
     */
    function _claimBonus(uint256 _id) private {
        (, uint256 bonusReward) = _calculateRewards(msg.sender, _id);
        uint256 depositEndDate = lenders[msg.sender].deposits[_id].startDate +
            lenders[msg.sender].deposits[_id].lockingDuration;
        lenders[msg.sender].deposits[_id].lastClaimDate = depositEndDate >
            block.timestamp
            ? block.timestamp
            : depositEndDate;
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        emit BonusClaimed(msg.sender, _id, bonusReward);
    }

    /**
     * @dev Updates the startId and currentId of deposits with lokcing period
     * @dev Loops through all deposits from start and end and updates id
     * @dev Called after a deposit has been withdrawn
     */
    function _updateId(address _lender) private {
        uint256 start = lenders[_lender].startId;
        uint256 end = lenders[_lender].currentId;
        uint256 amount;
        for (uint256 i = start; i < end; i++) {
            amount += lenders[_lender].deposits[i + 1].amount;
            if (amount == 0) {
                start = i + 2;
            } else {
                amount = 0;
                break;
            }
        }
        for (uint256 i = end; i > start; i--) {
            amount += lenders[_lender].deposits[i].amount;
            if (amount == 0) {
                end = i - 1;
            } else {
                break;
            }
        }
        lenders[_lender].startId = start;
        lenders[_lender].currentId = end;
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
        return (
            _calculateBaseStableReward(amount, lastUpdate),
            _calculateBaseBonusReward(amount, lastUpdate)
        );
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for deposits with locking period
     * @param _lender is the address of lender
     * @param _id is the id of deposit
     */
    function _calculateRewards(
        address _lender,
        uint256 _id
    ) private view returns (uint256, uint256) {
        uint256 depositEndDate = lenders[_lender].deposits[_id].startDate +
            lenders[_lender].deposits[_id].lockingDuration;
        uint256 amount = lenders[_lender].deposits[_id].amount;
        uint256 endDate = block.timestamp > depositEndDate
            ? depositEndDate
            : block.timestamp;
        uint256 stableDiff = endDate - lenders[_lender].deposits[_id].startDate;
        uint256 bonusDiff = endDate -
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
     * @dev Calculates stable rewards for the deposit without locking period
     * @dev This will be called for stable rewards in _calculateBaseRewards function
     * @param _amount is the deposited amount
     * @param _lastUpdate is the timestamp of calculation start
     */
    function _calculateBaseStableReward(
        uint256 _amount,
        uint256 _lastUpdate
    ) private view returns (uint256) {
        uint256 calculatedReward;
        for (uint256 i = _currentAprRound; i > 0; i--) {
            uint256 endDate = i != _currentAprRound
                ? aprRounds[i + 1].startDate
                : block.timestamp;
            uint256 startDate = _lastUpdate > aprRounds[i].startDate
                ? _lastUpdate
                : aprRounds[i].startDate;
            uint256 diff = endDate - startDate;
            calculatedReward +=
                _calculateFormula(_amount, diff, aprRounds[i].rate, _YEAR) /
                1E2;
            if (_lastUpdate > aprRounds[i].startDate) {
                break;
            }
        }
        return calculatedReward;
    }

    /**
     * @dev Calculates bonus rewards for the deposit without locking period
     * @dev This will be called for bonus rewards in _calculateBaseRewards function
     * @param _amount is the deposited amount
     * @param _lastUpdate is the timestamp of calculation start
     */
    function _calculateBaseBonusReward(
        uint256 _amount,
        uint256 _lastUpdate
    ) private view returns (uint256) {
        uint256 calculatedReward;
        for (uint256 i = _currentRateRound; i > 0; i--) {
            uint256 endDate = i != _currentRateRound
                ? rateRounds[i + 1].startDate
                : block.timestamp;
            uint256 startDate = _lastUpdate > rateRounds[i].startDate
                ? _lastUpdate
                : rateRounds[i].startDate;
            uint256 diff = endDate - startDate;
            calculatedReward += _calculateFormula(
                _amount,
                diff,
                rateRounds[i].rate,
                _YEAR
            );
            if (_lastUpdate > rateRounds[i].startDate) {
                break;
            }
        }
        return calculatedReward;
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
            depositedAmount += lenders[_lender].deposits[i + 1].amount;
        }
        return depositedAmount;
    }

    /**
     * @dev Calculates the bonus and stable rewards for all lenders
     * @param amount is the amount of deposited stable tokens
     * @param duration is the passed duration from last updated rewards
     * @param rate is the rate for bonus reward or apr for stable reward
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
