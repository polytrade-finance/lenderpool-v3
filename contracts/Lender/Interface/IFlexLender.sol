// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

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
        uint256 endDate;
        uint256 lastClaimDate;
    }

    struct RateInfo {
        uint256 stableApr;
        uint256 bonusRate;
        uint256 startDate;
    }

    error UnsupportedInterface();
    error NotVerified();

    /**
     * @notice Emits when a new fund is deposited to the Lender Pool without locking period
     * @param lender is the address of the `lender`
     * @param amount is the stable tokens deposited by the lender
     */
    event BaseDeposited(address indexed lender, uint256 amount);

    /**
     * @notice Emits when a new fund is deposited to the Lender Pool with locking period
     * @param lender is the address of the `lender`
     * @param id is the deposit ID
     * @param amount is the stable tokens deposited by the lender
     * @param lockingDuration is the duration of locking period
     * @param apr is the deposit APR for calculating stable rewards
     * @param rate is the deposit Rate for calculating Bonus rewards
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
     * @notice Emits when deposited funds are withdrawn from the Lender Pool
     * @param lender is the address of the `lender`
     * @param amount is the principal stable amount of deposit + stable Reward lender received based on Base APR
     * @param bonusReward is the remaining Bonus rewards lender received based on the Rate
     */
    event BaseWithdrawn(
        address indexed lender,
        uint256 amount,
        uint256 bonusReward
    );

    /**
     * @notice Emits when deposited funds are withdrawn from the Lender Pool for specific deposit
     * @param lender is the address of the `lender`
     * @param id is the deposit ID
     * @param amount is the principal stable amount of deposit + stable Reward lender received based on APR
     * @param bonusReward is the remaining Bonus rewards lender received based on the Rate
     */
    event Withdrawn(
        address indexed lender,
        uint256 id,
        uint256 amount,
        uint256 bonusReward
    );

    /**
     * @notice Emits when lender claims Bonus rewards for a specific deposit
     * @param lender is the address of the 'lender'
     * @param id is the deposit ID
     * @param bonusReward is the accumulated Bonus rewards lender received based on the Rate
     */
    event BonusClaimed(address indexed lender, uint256 id, uint256 bonusReward);

    /**
     * @notice Emits when lender claims Bonus rewards from a base deposit
     * @param lender is the address of the 'lender'
     * @param bonusReward is the accumulated Bonus rewards lender received based on the Base Rate
     */
    event BaseBonusClaimed(address indexed lender, uint256 bonusReward);

    /**
     * @notice Emits when lender claims Bonus rewards from all deposits
     * @param lender is the address of the 'lender'
     * @param bonusReward is the total accumulated Bonus rewards lender received based on the Rate
     */
    event AllBonusClaimed(address indexed lender, uint256 bonusReward);

    /**
     * @notice Emits when a lender tries to withdraw from pool before the pool's end date
     * @param lender is the address of the 'lender'
     * @param id is the deposit ID
     * @param amount is the amount that is withdrawn by lender
     * @param bonusReward is the amount available bonus rewards that is claimed automatically
     */
    event WithdrawnEmergency(
        address indexed lender,
        uint256 id,
        uint256 amount,
        uint256 bonusReward
    );

    /**
     * @notice Emits when an admin changes the rate for the emergency withdraw fee
     * @param oldRate is the old withdraw rate
     * @param newRate is the new withdraw rate
     */
    event WithdrawRateChanged(uint256 oldRate, uint256 newRate);

    /**
     * @notice Emits when an admin changes the status of verification
     * @param oldStatus is the old status for verification requirement
     * @param newStatus is the new status for verification requirement
     */
    event VerificationStatusChanged(bool oldStatus, bool newStatus);

    /**
     * @notice Emits when a new verification contract is used
     * @dev Emitted when switchVerification function is called by owner
     * @param oldVerification is the old verification contract Address
     * @param newVerification is the new verification contract Address
     */
    event VerificationSwitched(
        address oldVerification,
        address newVerification
    );

    /**
     * @notice Emitted when staking strategy is switched
     * @dev Emitted when switchStrategy function is called by owner
     * @param oldStrategy is the address of the old staking strategy
     * @param newStrategy is the address of the new staking strategy
     */
    event StrategySwitched(address oldStrategy, address newStrategy);

    /**
     * @notice Emitted when penalty fees is withdrawn
     * @dev Emitted when withdrawFees function is called by owner
     * @param amount is the total amount of accumulated emergency penalty withdraw fees
     */
    event PenaltyFeeWithdrawn(uint256 amount);

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
     * @notice Emits when a new APR and rate are set for a base pool
     * @dev Emitted when `changeBaseRates` function is called by admin
     * @param oldStableApr is the old APR for calculating stable rewards
     * @param newStableApr is the new APR for calculating stable rewards
     * @param oldBonusRate is the old rate for calculating bonus rewards
     * @param newBonusRate is the new rate for calculating bonus rewards
     */
    event BaseRateChanged(
        uint256 oldStableApr,
        uint256 newStableApr,
        uint256 oldBonusRate,
        uint256 newBonusRate
    );

    /**
     * @notice Emits when a new limit is set for the locking duration
     * @dev Emitted when changeDurationLimit function is called by owner
     * @param minLimit is the minimum limit for locking period in days
     * @param maxLimit is the maximum limit for locking period in days
     */
    event DurationLimitChanged(uint256 minLimit, uint256 maxLimit);

    /**
     * @notice Emits when a new limit is set for flexible lender pool
     * @dev Emitted when changeMaxLimit function is called by owner
     * @param oldLimit is the old maximum limit for depositing
     * @param newLimit is the new maximum limit for depositing
     */
    event PoolLimitChanged(uint256 oldLimit, uint256 newLimit);

    /**
     * @notice Emitted when client portal withdraws
     * @dev Emitted when clientPortalWithdraw function is called by client portal
     * @param amount is the amount of stable token to withdraw from strategy
     */
    event ClientPortalWithdrawal(uint256 amount);

    /**
     * @notice Deposits an amount of stable token without locking period in the base lender pool
     * @dev It transfers the approved stable tokens from msg.sender to lender pool
     * @param amount Represents the amount of tokens to deposit
     * Requirements:
     * - `amount` should be greater than zero
     * - `amount` must be approved from the stable token contract for the LenderPool
     * Emits {BaseDeposited} event
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
     * return Deposit ID
     */
    function deposit(
        uint256 amount,
        uint256 lockingDuration
    ) external returns (uint256);

    /**
     * @notice Claims the bonus rewards to the lender for all deposits
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender's accumulated bonus rewards for that deposit
     * Emits {AllBonusClaimed} event
     */
    function claimAllBonuses() external;

    /**
     * @notice Claims the bonus rewards to the lender the deposit without locking period
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender's accumulated bonus rewards for that deposit
     * Emits {BaseBonusClaimed} event
     */
    function claimBonus() external;

    /**
     * @notice Claims the bonus rewards to the lender for a specific deposit
     * @dev `claimBonus` transfers all the accumulated bonus rewards to `msg.sender`
     * @param id Represents the id of deposit
     * Requirements :
     * - `LenderPool` should have tokens more than or equal to lender's accumulated bonus rewards for that deposit
     * Emits {BonusClaimed} event
     */
    function claimBonus(uint256 id) external;

    /**
     * @notice Withdraws principal deposited tokens + Stable rewards + remaining bonus rewards
     * for the deposit without locking period
     * Requirements:
     * - `LenderPool` should have stable tokens more than or equal to lender's stable rewards + principal amount
     * - `LenderPool` should have bonus tokens more than or equal to lender's accumulated bonus rewards
     * Emits {BaseWithdrawn} event
     */
    function withdraw() external;

    /**
     * @notice Withdraws principal deposited tokens + Stable rewards + remaining bonus rewards for a specific deposit
     * @param id Represents the ID of deposit that lender tries to withdraw after locking period
     * Requirements:
     * - `id` should represent a deposit that has passed its lock period
     * - `LenderPool` should have stable tokens more than or equal to lender's stable rewards + principal amount
     * - `LenderPool` should have tokens more than or equal to lender's accumulated bonus rewards for that deposit
     * Emits {Withdrawn} event
     */
    function withdraw(uint256 id) external;

    /**
     * @notice Withdraws principal total deposit minus fee that is a percentage of total deposit for a specific deposit
     * @param id Represents the ID of deposit that lender tries to emergency withdraw before locking period
     * Requirements:
     * - Should be called before locking period ends
     * - 'msg.sender' should have deposit with specific id
     * - Lender should have enough stable token to transfer
     * Emits {WithdrawnEmergency} event
     */
    function emergencyWithdraw(uint256 id) external;

    /**
     * @dev Changes the Bonding Curve that calculates the APR for different locking periods and
     * affects the future deposits
     * @dev Implemented ERC165 and only accepts address with Curve interface support
     * @param newCurve is the address of new Bonding curve
     * Emits {AprBondingCurveSwitched} event
     */
    function switchAprBondingCurve(address newCurve) external;

    /**
     * @dev Changes the Bonding Curve that calculates the Rate for different locking periods and
     * affects the future deposits
     * @dev Implemented ERC165 and only accepts address with Curve interface support
     * @param newCurve is the address of new Bonding curve
     * Emits {RateBondingCurveSwitched} event
     */
    function switchRateBondingCurve(address newCurve) external;

    /**
     * @dev Changes the APR and Rate that calculates stable and bonus rewards
     * @dev Only affects the future deposits
     * @param newApr is the new apr percentage with 2 decimals
     * @param newRate is the new rate with 2 decimals
     * Emits {BaseRateChanged} event
     */
    function changeBaseRates(uint256 newApr, uint256 newRate) external;

    /**
     * @dev Changes the minimum and maximum limit of locking period in days
     * @param minLimit is the new minimum limit in days
     * @param maxLimit is the new maximum limit in days
     * Emits {DurationLimitChanged} event
     */
    function changeDurationLimit(uint256 minLimit, uint256 maxLimit) external;

    /**
     * @dev Changes the maximum limit of deposit allowed for flexible pool
     * @param newLimit is the new maximum limit for lender pool with stable decimals
     * Emits {PoolLimitChanged} event
     */
    function changePoolLimit(uint256 newLimit) external;

    /**
     * @dev Changes status of verification requirement for depositing
     * @dev can be called only by owner
     * Emits {VerificationStatusChanged} event
     */
    function changeVerificationStatus() external;

    /**
     * @dev Changes the Verification contract that has been used for checking verification of lenders
     * @param newVerification is the address of the new verification contract
     * Emits {VerificationSwitched} event
     */
    function switchVerification(address newVerification) external;

    /**
     * @dev Changes the Strategy contract used for managing funds in defi protocols
     * @param newStrategy is the address of the new strategy contract
     * Emits {StrategySwitched} event
     */
    function switchStrategy(address newStrategy) external;

    /**
     * @dev Withdraws the amount of stable tokens by client portal to fund invoices
     * Emits {ClientPortalWithdrawal} event
     */
    function clientPortalWithdraw(uint256 amount) external;

    /**
     * @dev Withdraws accumulated penalty emergency withdraw fees to owner
     * Emits {PenaltyFeeWithdrawn} event
     */
    function withdrawFees() external;

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
     * @dev returns all the available bonus rewards to claim for a specific lender for a deposit without locking
     * @param lender Represents the address of lender
     */
    function getBonusRewards(address lender) external view returns (uint256);

    /**
     * @dev returns the available bonus rewards to claim for a specific lender and deposit
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit and for base pool is `0`
     */
    function getBonusRewards(
        address lender,
        uint256 id
    ) external view returns (uint256);

    /**
     * @dev returns all the accumulated amount of stable rewards for a specific lender
     * @param lender Represents the address of lender
     */
    function getStableRewards(address lender) external view returns (uint256);

    /**
     * @dev returns the accumulated amount of stable rewards for a specific lender and depsoit
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit and for base pool is `0`
     */
    function getStableRewards(
        address lender,
        uint256 id
    ) external view returns (uint256);

    /**
     * @dev returns the APR for a specific deposit and lender without decimals in percentage
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit
     */
    function getApr(address lender, uint256 id) external view returns (uint256);

    /**
     * @dev returns the Rate of bonus reward for a specific deposit and lender with 2 decimals
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit
     */
    function getRate(
        address lender,
        uint256 id
    ) external view returns (uint256);

    /**
     * @dev returns the base APR without decimals in percentage
     */
    function getBaseApr() external view returns (uint256);

    /**
     * @dev returns the base Rate of bonus reward with 2 decimals
     */
    function getBaseRate() external view returns (uint256);

    /**
     * @dev returns the duration of locking period for a lender and a specific deposit
     * @param lender Represents the address of lender
     * @param id Represents the id of a deposit
     */
    function getLockingDuration(
        address lender,
        uint256 id
    ) external view returns (uint256);

    /**
     * @dev returns the minimum duration required for locking in the pool
     */
    function getMinLockingDuration() external view returns (uint256);

    /**
     * @dev returns the maximum duration required for locking in the pool
     */
    function getMaxLockingDuration() external view returns (uint256);

    /**
     * @dev returns the current pool size
     */
    function getPoolSize() external view returns (uint256);

    /**
     * @dev returns the pool maximum size that once reached lender can not deposit
     */
    function getMaxPoolSize() external view returns (uint256);

    /**
     * @dev returns the minimum stable tokens required for depositing
     */
    function getMinDeposit() external view returns (uint256);

    /**
     * @dev returns accumulated emergency penalty withdraw fees
     */
    function getTotalPenaltyFee() external view returns (uint256);

    /**
     * @dev returns emergency withdraw penalty percentage with 2 decimals
     */
    function getWithdrawPenaltyPercent() external view returns (uint256);

    /**
     * @dev returns the address of Stable Token
     */
    function stableToken() external view returns (address);

    /**
     * @dev returns the address of Bonus Token
     */
    function bonusToken() external view returns (address);

    /**
     * @dev returns the address of Apr Bonding Curve
     */
    function aprBondingCurve() external view returns (address);

    /**
     * @dev returns the address of Rate Bonding Curve
     */
    function rateBondingCurve() external view returns (address);

    /**
     * @dev returns the address of verification contract
     */
    function verification() external view returns (address);

    /**
     * @dev returns the address of strategy contract
     */
    function strategy() external view returns (address);

    /**
     * @dev returns the required verification status of lender pool
     */
    function getVerificationStatus() external view returns (bool);

    /**
     * @dev returns an id array of the active deposits for a lender
     * @param lender Represents the address of lender
     */
    function getActiveDeposits(
        address lender
    ) external view returns (uint256[] calldata);
}
