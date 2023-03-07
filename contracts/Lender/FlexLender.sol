/// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "@openzeppelin/contracts/access/AccessControl.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165Checker.sol";
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
    using ERC165Checker for address;

    mapping(address => Lender) public lenders;
    mapping(uint256 => RoundInfo) public aprRounds;
    mapping(uint256 => RoundInfo) public rateRounds;

    uint256 public poolSize;
    uint256 private _currentAprRound;
    uint256 private _currentRateRound;
    uint256 private _minLimit;
    uint256 private _maxLimit;
    uint256 private immutable _stableDecimal;
    uint256 private immutable _bonusDecimal;
    uint256 private immutable _minDeposit;
    uint256 private immutable _poolMaxLimit;
    uint256 private constant _YEAR = 365 days;
    bytes4 private constant _CURVE_INTERFACE_ID =
        type(IBondingCurve).interfaceId;

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
        require(baseStableApr <= 10000, "Invalid Stable Apr");
        uint256 oldApr = aprRounds[_currentAprRound].rate;
        uint256 newApr = baseStableApr / 1E2;
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
        address _newCurve
    ) external onlyRole(DEFAULT_ADMIN_ROLE) {
        require(_newCurve != address(0), "Invalid Curve Address");
        require(
            _newCurve.supportsInterface(_CURVE_INTERFACE_ID),
            "Does not support Curve interface"
        );
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
        require(
            _newCurve.supportsInterface(_CURVE_INTERFACE_ID),
            "Does not support Curve interface"
        );
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
        uint256 currentId = lenders[msg.sender].currentId;
        lenders[msg.sender].currentId++;
        poolSize += amount;
        lenders[msg.sender].deposits[currentId] = Deposit(
            amount,
            apr,
            rate * (10 ** (_bonusDecimal - _stableDecimal)),
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
            _claimBonus(i);
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
            calculatedReward += _calculateFormula(
                _amount,
                diff,
                aprRounds[i].rate,
                _YEAR
            );
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
