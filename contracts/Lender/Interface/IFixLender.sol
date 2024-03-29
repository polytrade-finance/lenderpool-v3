// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

/**
 * @title IFixLender
 * @author Polytrade
 */
interface IFixLender {
    struct Lender {
        uint256 totalDeposit;
        uint256 pendingStableReward;
        uint256 pendingBonusReward;
        uint256 lastUpdateDate;
    }

    error UnsupportedInterface();
    error NotVerified();
    error NoDeposit();

    /**
     * @notice Emits when new fund is deposited to the Lender Pool
     * @param lender is the address of the 'lender'
     * @param amount is the stable tokens deposited by the lender
     */
    event Deposited(address indexed lender, uint256 amount);

    /** 
    * @notice Emits when deposited funds withdrawn from the Lender Pool 
    * @param lender is the address of the 'lender' 
    * @param amount is the principal stable amount of deposit + stable  
    Reward lender received based on APR
    * @param bonusReward is the remaining Bonus rewards lender received based on the Rate 
    */
    event Withdrawn(
        address indexed lender,
        uint256 amount,
        uint256 bonusReward
    );

    /**
     * @notice Emits when lender claims Bonus rewards
     * @param lender is the address of the 'lender'
     * @param bonusReward is the accumulated Bonus rewards lender received based on the Rate
     */
    event BonusClaimed(address indexed lender, uint256 bonusReward);

    /**
     * @notice Emits when a lender tries to withdraw from pool before pool end date
     * @param lender is the address of the 'lender'
     * @param amount is the amount that withdrawn by lender
     * @param bonusReward is the accumulated bonus rewards that withdrawn by lender
     */
    event WithdrawnEmergency(
        address indexed lender,
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
     * @notice Emits when new verification contract is used
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
     * @notice Emitted when client portal withdraws
     * @dev Emitted when clientPortalWithdraw function is called by client portal
     * @param amount is the amount of stable token to withdraw from strategy
     */
    event ClientPortalWithdrawal(uint256 amount);

    /**
     * @notice Deposits an amount of stable token for a fixed lender pool
     * @dev It transfers the approved stable tokens from msg.sender to lender pool
     * @param amount Represents the amount of stable tokens to deposit
     * Requirements:
     * - 'amount' should be greater than zero
     * - 'amount' must be approved from the stable token contract for the LenderPool
     * - It should be called before Deposit End Date
     * Emits {Deposited} event
     */
    function deposit(uint256 amount) external;

    /**
     * @notice Claims the Bonus rewards to the lender based on the Rate
     * @dev 'claimReward' transfers all the accumulated Bonus bonus rewards to 'msg.sender'
     * Requirements :
     * - 'LenderPool' should have Bonus tokens more than or equal to lender accumulated bonus rewards
     * Emits {Claimed} event
     */
    function claimBonus() external;

    /**
     * @notice Withdraws principal deposited tokens + Stable rewards + remaining Bonus rewards for locking period
     * Requirements:
     * - 'LenderPool' should have stable tokens more than or equal to lender stable rewards + principal amount
     * - 'LenderPool' should have Bonus tokens more than or equal to lender accumulated bonus rewards
     * Emits {Withdrawn} event
     */
    function withdraw() external;

    /**
     * @notice Withdraws principal total deposit minus fee that is a percentage of total deposit
     * Requirements:
     * - Should be called before pool end date
     * - 'msg.sender' should have deposit
     * - Lender should have enough stable token to transfer
     * Emits {WithdrawnEmergency} event
     */
    function emergencyWithdraw() external;

    /**
     * @notice Changes the withdraw rate for emergency withdraw
     * @dev withdraw rate is in percentage with 2 decimals
     * @param newRate is the new withdraw rate with 2 decimals
     * Emits {WithdrawRateChanged} event
     */
    function setWithdrawRate(uint256 newRate) external;

    /**
     * @dev Changes the Verification contract that has been used for checking verification of lenders
     * @param _newVerification is the address of the new verification contract
     * Emits {VerificationSwitched} event
     */
    function switchVerification(address _newVerification) external;

    /**
     * @dev Changes the Strategy contract used for managing funds in defi protocols
     * @param _newStrategy is the address of the new strategy contract
     * Emits {StrategySwitched} event
     */
    function switchStrategy(address _newStrategy) external;

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
     * @dev returns the deposited amount of a specific lender
     * @param _lender Represents the address of lender
     */
    function getTotalDeposit(address _lender) external view returns (uint256);

    /**
     * @dev returns the available Bonus rewards to claim for a specific lender
     * @param _lender Represents the address of lender
     */
    function getBonusRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the accumulated amount of stable rewards for a specific lender
     * @param _lender Represents the address of lender
     */
    function getStableRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the APR in percentage without decimals
     */
    function getApr() external view returns (uint256);

    /**
     * @dev returns the Rate of bonus reward with 2 decimals
     */
    function getBonusRate() external view returns (uint256);

    /**
     * @dev returns the duration of locking period in days
     */
    function getLockingDuration() external view returns (uint256);

    /**
     * @dev returns pool start date for which the reward calculation begins
     */
    function getPoolStartDate() external view returns (uint256);

    /**
     * @dev returns the end deposit date after which users can not deposit
     */
    function getDepositEndDate() external view returns (uint256);

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
}
