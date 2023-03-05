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
    RoundInfo[] public aprRounds;
    RoundInfo[] public rateRounds;

    uint256 public poolSize;
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
        uint256 currentRound = aprRounds.length;
        uint256 oldApr = currentRound != 0
            ? aprRounds[currentRound - 1].rate
            : 0;
        uint256 newApr = baseStableApr / 1E2;
        aprRounds.push(RoundInfo(newApr, block.timestamp));
        emit BaseAprChanged(oldApr, newApr);
    }

    /**
     * @dev See {IFlexLender-changeBaseRate}.
     */
    function changeBaseRate(
        uint256 baseBonusRate
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(baseBonusRate <= 10000, "Invalid Bonus Rate");
        uint256 currentRound = rateRounds.length;
        uint256 oldRate = currentRound != 0
            ? rateRounds[currentRound - 1].rate
            : 0;
        uint256 newRate = baseBonusRate *
            (10 ** (_bonusDecimal - _stableDecimal));
        rateRounds.push(RoundInfo(newRate, block.timestamp));
        emit BaseRateChanged(oldRate, newRate);
    }

    /**
     * @dev See {IFlexLender-switchAprBondingCurve}.
     */
    function switchAprBondingCurve(
        address _newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newCurve != address(0), "Invalid Curve Address");
        address oldCurve = address(_aprBondingCurve);
        _aprBondingCurve = IBondingCurve(_newCurve);
        emit AprBondingCurveSwitched(oldCurve, _newCurve);
    }

    /**
     * @dev See {IFlexLender-switchRateBondingCurve}.
     */
    function switchRateBondingCurve(
        address _newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newCurve != address(0), "Invalid Curve Address");
        address oldCurve = address(_rateBondingCurve);
        _rateBondingCurve = IBondingCurve(_newCurve);
        emit RateBondingCurveSwitched(oldCurve, _newCurve);
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
        uint256 rate = _rateBondingCurve.getRate(lockingDuration);
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
            "You have nothing in deposit"
        );
        (
            uint256 baseStableReward,
            uint256 baseBonusReward
        ) = _calculateBaseRewards(msg.sender);
        lenders[msg.sender].pendingStableReward += baseStableReward;
        uint256 claimableBonus = baseBonusReward +
            lenders[msg.sender].pendingBonusReward;
        lenders[msg.sender].pendingBonusReward = 0;
        lenders[msg.sender].lastUpdateDate = block.timestamp;
        for (
            uint256 i = lenders[msg.sender].startId;
            i < lenders[msg.sender].currentId + 1;
            i++
        ) {
            (, uint256 bonusReward) = _calculateRewards(msg.sender, i);
            lenders[msg.sender].deposits[i].lastClaimDate = block.timestamp;
            claimableBonus += bonusReward;
        }
        _bonusToken.safeTransfer(msg.sender, claimableBonus);
        emit BonusClaimed(msg.sender, 0, claimableBonus);
    }

    /**
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus() external {
        require(lenders[msg.sender].amount != 0, "You have nothing is deposit");
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
     * @dev See {IFlexLender-claimBonus}.
     */
    function claimBonus(uint256 id) external {
        require(
            lenders[msg.sender].deposits[id].amount != 0,
            "You have nothing with this ID"
        );
        (, uint256 bonusReward) = _calculateRewards(msg.sender, id);
        lenders[msg.sender].deposits[id].lastClaimDate = block.timestamp;
        _bonusToken.safeTransfer(msg.sender, bonusReward);
        emit BonusClaimed(msg.sender, id, bonusReward);
    }

    /**
     * @dev See {IFlexLender-getTotalDeposit}.
     */
    function getTotalDeposit(address lender) external view returns (uint256) {
        return _getTotalDeposit(lender);
    }

    /**
     * @dev See {IFlexLender-getDeposit}.
     */
    function getDeposit(address lender) external view returns (uint256) {
        return lenders[lender].amount;
    }

    /**
     * @dev See {IFlexLender-getDeposit}.
     */
    function getDeposit(
        address lender,
        uint256 id
    ) external view returns (uint256) {
        return lenders[lender].deposits[id].amount;
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for the deposit without locking period
     * @param _lender is the address of lender
     */
    function _calculateBaseRewards(
        address _lender
    ) private view returns (uint256, uint256) {
        uint256 amount = lenders[_lender].amount;
        uint256 startDate = lenders[_lender].lastUpdateDate;
        return (
            _calculateBaseReward(amount, startDate, aprRounds),
            _calculateBaseReward(amount, startDate, rateRounds)
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
            ),
            _calculateFormula(
                amount,
                bonusDiff,
                lenders[_lender].deposits[_id].rate,
                lenders[_lender].deposits[_id].lockingDuration
            )
        );
    }

    /**
     * @dev Calculates both the bonus reward and stable rewards for the deposit without locking period
     * @dev This will be called sepratly for stable and bonus rewards in _calculateBaseRewards function
     * @param _amount is the deposited amount
     * @param _startDate is the timestamp of calculation start
     * @param _round is the array of apr or rates from beginning to current round
     */
    function _calculateBaseReward(
        uint256 _amount,
        uint256 _startDate,
        RoundInfo[] memory _round
    ) private view returns (uint256) {
        uint256 calculatedReward;
        uint256 currentRound = _round.length;
        for (uint256 i = currentRound; i > 0; i--) {
            uint256 endDate = i != currentRound
                ? _round[i + 1].startDate
                : block.timestamp;
            uint256 startDate = _startDate > _round[i].startDate
                ? _startDate
                : _round[i].startDate;
            uint256 diff = endDate - startDate;
            calculatedReward += _calculateFormula(
                _amount,
                diff,
                _round[i].rate,
                _YEAR
            );
            if (_startDate > _round[i].startDate) {
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
            i < lenders[_lender].currentId + 1;
            i++
        ) {
            depositedAmount += lenders[_lender].deposits[i].amount;
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
