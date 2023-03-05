// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFlexLender {
    struct Lender {
        uint256 amount;
        uint256 pendingStableReward;
        uint256 pendingBonusReward;
        uint256 lastUpdateDate;
        uint256 startId;
        uint256 currentId;
        mapping(uint256 => Deposit) deposits;
    }

    struct Deposit {
        uint256 amount;
        uint256 apr;
        uint256 rate;
        uint256 lockingDuration;
        uint256 startDate;
        uint256 lastClaimDate;
    }

    struct RoundInfo {
        uint256 rate;
        uint256 startDate;
    }

    /**
     * @notice Emits when new fund is deposited to the Lender Pool
     * @param lender is the address of the `lender`
     * @param id is the deposit ID
     * @param amount is the stable tokens deposited by the lender
     * @param lockingDuration is the duration of locking period
     * @param apr is the deposit APR for calculating stable rewards
     * @param rate is the deposit Rate for calculating Trade rewards
     */
    event Deposited(
        address indexed lender,
        uint256 id,
        uint256 amount,
        uint256 lockingDuration,
        uint256 apr,
        uint256 rate
    );

    /**
     * @notice Emits when deposited funds withdrawn from the Lender Pool
     * @param lender is the address of the `lender`
     * @param id is the deposit ID
     * @param amount is the principal stable amount of deposit + stable Reward lender received based on APR
     * @param bonusReward is the remaining $TRADE rewards lender received based on the Rate
     */
    // event Withdrawn(
    //     address indexed lender,
    //     uint256 id,
    //     uint256 amount,
    //     uint256 bonusReward
    // );

    /**
     * @notice Emits when lender claims Bonus rewards
     * @param lender is the address of the 'lender'
     * @param id is the deposit ID and id zerp represents deposit without locking period
     * @param bonusReward is the accumulated Bonus rewards lender received based on the Rate
     */
    event BonusClaimed(address indexed lender, uint256 id, uint256 bonusReward);

    /**
     * @notice Emits when a lender tries to withdraw from pool before pool end date
     * @param lender is the address of the 'lender'
     * @param id is the deposit ID
     * @param amount is the amount that withdrawn by lender
     */
    // event WithdrawnEmergency(
    //     address indexed lender,
    //     uint256 id,
    //     uint256 amount
    // );

    /**
     * @notice Emits when a admin change the rate for emergency withdraw fee
     * @param oldRate is the old withdraw rate
     * @param newRate is the new withdraw rate
     */
    // event WithdrawRateChanged(uint256 oldRate, uint256 newRate);

    /**
     * @notice Emits when new verification contract is used
     * @dev Emitted when switchVerification function is called by owner
     * @param oldVerification is the old verification contract Address
     * @param newVerification is the new verification contract Address
     */
    // event VerificationSwitched(
    //     address oldVerification,
    //     address newVerification
    // );

    /**
     * @notice Emitted when staking strategy is switched
     * @dev Emitted when switchStrategy function is called by owner
     * @param oldStrategy is the address of the old staking strategy
     * @param newStrategy is the address of the new staking strategy
     */
    // event StrategySwitched(address oldStrategy, address newStrategy);

    /**
     * @notice Emitted when APR bonding curve is switched
     * @dev Emitted when switchAprBondingCurve function is called by owner
     * @param oldBondingCurve is the address of the old staking strategy
     * @param newBondingCurve is the address of the new staking strategy
     */
    event AprBondingCurveSwitched(
        address oldBondingCurve,
        address newBondingCurve
    );

    /**
     * @notice Emitted when Rate bonding curve is switched
     * @dev Emitted when switchRateBondingCurve function is called by owner
     * @param oldBondingCurve is the address of the old staking strategy
     * @param newBondingCurve is the address of the new staking strategy
     */
    event RateBondingCurveSwitched(
        address oldBondingCurve,
        address newBondingCurve
    );

    /**
     * @notice Emits when new APR is changed for base pool
     * @dev Emitted when changeBaseApr function is called by owner
     * @param oldAPR is the old APR contract percentage without decimals
     * @param newAPR is the new APR contract percentage without decimals
     */
    event BaseAprChanged(uint256 oldAPR, uint256 newAPR);

    /**
     * @notice Emits when new rate is set for base pool
     * @dev Emitted when changeBaseRate function is called by owner
     * @param oldRate is the old rate for calculating bonus rewards with 2 decimals
     * @param newRate is the new rate for calculating bonus rewards with 2 decimals
     */
    event BaseRateChanged(uint256 oldRate, uint256 newRate);

    /**
     * @notice Emits when new limit is set locking duration
     * @dev Emitted when changeDurationLimit function is called by owner
     * @param minLimit is the minimum limit for locking period in days
     * @param maxLimit is the maximum limit for locking period in days
     */
    event DurationLimitChanged(uint256 minLimit, uint256 maxLimit);

    /**
     * @notice Emits when new limit is set for flexible lender pool
     * @dev Emitted when changeMaxLimit function is called by owner
     * @param oldLimit is the old maximum limit for depositing
     * @param newLimit is the new maximum limit for depositing
     */
    // event MaxLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Deposits an amount of stable token without locking period in the base lender pool
     * @dev It transfers the approved stable tokens from msg.sender to lender pool
     * @param amount Represents the amount of tokens to deposit
     * Requirements:
     * - `amount` should be greater than zero
     * - `amount` must be approved from the stable token contract for the LenderPool
     * Emits {Deposited} event
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Deposits an amount of stable token for a locking period in the dynamic lender pool
     * @dev It transfers the approved stable tokens from msg.sender to lender pool
     * @param amount Represents the amount of tokens to deposit
     * @param lockingDuration Represents the duration of locking period for the deposited amount in days
     * Requirements:
     * - `amount` should be greater than zero
     * - `amount` must be approved from the stable token contract for the LenderPool
     * - `lockingDuration` should be less than max duration and more than min duration
     * Emits {Deposited} event
     */
    function deposit(uint256 amount, uint256 lockingDuration) external;

    /**
     * @notice Claims the bonus rewards to the lender for all deposits
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender accumulated bonus rewards for that deposit
     * Emits {BonusClaimed} event
     */
    function claimAllBonuses() external;

    /**
     * @notice Claims the bonus rewards to the lender the deposit without locking period
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender accumulated bonus rewards for that deposit
     * Emits {BonusClaimed} event
     */
    function claimBonus() external;

    /**
     * @notice Claims the bonus rewards to the lender for a specific deposit
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * @param id Represents the id of deposit
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender accumulated bonus rewards for that deposit
     * Emits {BonusClaimed} event
     */
    function claimBonus(uint256 id) external;

    /**
     * @notice Withdraws principal deposited tokens + Stable rewards + remaining bonus rewards
     * @param _id Represents the ID of deposit that lender tries to withdraw after locking period
     * Requirements:
     * - `_id` should represent a deposit that has been passed its lock period or `0` for base pool
     * - `LenderPool` should have stable tokens more than or equal to lender stable rewards + principal amount
     * - `LenderPool` should have tokens more than or equal to lender accumulated bonus rewards for that deposit
     * Emits {Withdrawn} event
     */
    // function withdraw(uint256 _id) external;

    /**
     * @notice Withdraws principal total deposit minus fee that is a percentage of total deposit for a specific deposit
     * Requirements:
     * - Should be called before pool end date
     * - 'msg.sender' should have deposit
     * - Lender should have enough stable token to transfer
     * Emits {WithdrawnEmergency} event
     */
    // function emergencyWithdraw(uint256 _id) external;

    /**
     * @dev Changes the Bonding Curve that calculates the APR for different locking periods and
     * affects the future deposits
     * @param newCurve is the address of new Bonding curve
     * Emits {AprBondingCurveSwitched} event
     */
    function switchAprBondingCurve(address newCurve) external;

    /**
     * @dev Changes the Bonding Curve that calculates the Rate for different locking periods and
     * affects the future deposits
     * @param newCurve is the address of new Bonding curve
     * Emits {RateBondingCurveSwitched} event
     */
    function switchRateBondingCurve(address newCurve) external;

    /**
     * @dev Changes the the APR for deposits without locking period
     * @param newApr is the new APR in percentage without decimals
     * Emits {BaseAprChanged} event
     */
    function changeBaseApr(uint256 newApr) external;

    /**
     * @dev Changes the Rate that calculates bonus rewards and affects the future deposits
     * @param newRate is the new rate with 2 decimals
     * Emits {BaseRateChanged} event
     */
    function changeBaseRate(uint256 newRate) external;

    /**
     * @dev Changes the minimum and maximum limit of locking period in days
     * @param minLimit is the new minimum limit in days
     * @param maxLimit is the new maximum limit in days
     * Emits {DurationLimitChanged} event
     */
    function changeDurationLimit(uint256 minLimit, uint256 maxLimit) external;

    /**
     * @dev Changes the maximum limit of deposit allowed for flexible pool
     * @param _newLimit is the new maximum limit for lender pool
     * Emits {MaxLimitChanged} event
     */
    // function changeMaxLimit(uint256 _newLimit) external;

    /**
     * @dev Changes status of requirement of verification for depositing
     * @dev can be called only by owner
     */
    // function changeVerificationStatus() external;

    /**
     * @dev Changes the Verification contract that has been used for checking verification of lenders
     * @param _newVerification is the address of the new verification contract
     * Emits {VerificationSwitched} event
     */
    // function switchVerification(address _newVerification) external;

    /**
     * @dev Changes the Strategy contract that has been used for using funds in defi protocols
     * @param _newStrategy is the address of the new strategy contract
     * Emits {StrategySwitched} event
     */
    // function switchStrategy(address _newStrategy) external;

    /**
     * @dev returns the all deposited amount of a specific lender
     * @param lender Represents the address of lender
     */
    function getTotalDeposit(address lender) external view returns (uint256);

    /**
     * @dev returns the deposited amount without locking period for a specific lender
     * @param lender Represents the address of lender
     */
    function getDeposit(address lender) external view returns (uint256);

    /**
     * @dev returns the deposited amount of a specific lender and deposit
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit
     */
    function getDeposit(
        address lender,
        uint256 id
    ) external view returns (uint256);

    /**
     * @dev returns all the available bonus rewards to claim for a specific lender and deposit
     * @param _lender Represents the address of lender
     */
    // function getBonusRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the available bonus rewards to claim for a specific lender and deposit
     * @param _lender Represents the address of lender
     * @param _id Represents the id of a deposit and for base pool is `0`
     */
    // function getBonusRewards(
    //     address _lender,
    //     uint256 _id
    // ) external view returns (uint256);

    /**
     * @dev returns all the accumulated amount of stable rewards for a specific lender
     * @param _lender Represents the address of lender
     */
    // function getStableRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the accumulated amount of stable rewards for a specific lender and depsoit
     * @param _lender Represents the address of lender
     * @param _id Represents the id of a deposit and for base pool is `0`
     */
    // function getStableRewards(
    //     address _lender,
    //     uint256 _id
    // ) external view returns (uint256);

    /**
     * @dev returns the APR for a specific deposit and lender without decimals in percenrtage
     * @param _id Represents the id of a deposit
     */
    // function getApr(
    //     address _lender,
    //     uint256 _id
    // ) external view returns (uint256);

    /**
     * @dev returns the Rate of bonus reward for a specific deposit and lender with 2 decimals
     * @param _id Represents the id of a deposit
     */
    // function getRate(
    //     address _lender,
    //     uint256 _id
    // ) external view returns (uint256);

    /**
     * @dev returns the base APR without decimals in percenrtage
     */
    // function getBaseApr() external view returns (uint256);

    /**
     * @dev returns the base Rate of bonus reward with 2 decimals
     */
    // function getBaseRate() external view returns (uint256);

    /**
     * @dev returns the duration of locking period for a lender and a specific deposit
     * @param _id Represents the id of a deposit
     */
    // function getLockingDuration(
    //     address _lender,
    //     uint256 _id
    // ) external view returns (uint256);

    /**
     * @dev returns the minimum duration required for locking in the pool
     */
    // function getMinLockingDuration() external view returns (uint256);

    /**
     * @dev returns the maximum duration required for locking in the pool
     */
    // function getMaxLockingDuration() external view returns (uint256);

    /**
     * @dev returns the current pool size
     */
    // function getPoolSize() external view returns (uint256);

    /**
     * @dev returns the pool maximum size that after reaching this limit users can not deposit
     */
    // function getMaxPoolSize() external view returns (uint256);

    /**
     * @dev returns the require verification status of lender pool
     */
    // function getVerificationStatus() external view returns (bool);

    /**
     * @dev returns an id array of the active deposits for a lender
     * @param _lender Represents the address of lender
     */
    // function getActiveDeposits(
    //     address _lender
    // ) external view returns (uint256[] calldata);
}
