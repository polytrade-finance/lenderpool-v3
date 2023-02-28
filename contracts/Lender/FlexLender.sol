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
}
