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
        uint256 currentDeposit = lenders[msg.sender].deposits[0].amount;
        poolSize += amount;
        lenders[msg.sender].deposits[0] = Deposit(
            currentDeposit + amount,
            0,
            0,
            0,
            block.timestamp,
            block.timestamp
        );
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
        lenders[msg.sender].activeDeposits.push(currentId);
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
}
