// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

interface IFixLender {
    struct Lender {
        uint256 totalDeposit;
        uint256 unClaimedBonuses;
        Deposit[] deposits;
    }

    struct Deposit {
        uint256 amount;
        uint256 depositDate;
        uint256 lastClaimDate;
    }

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
    event Claimed(address indexed lender, uint256 bonusReward);

    /**
     * @notice Emits when an unverified lender withdraws the principal amount after given access from owner
     * @param lender is the address of the 'lender'
     * @param amount is the principal amount that withdrawn by lender
     */
    event PrincipalWithdrawn(address indexed lender, uint256 amount);

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
     * @notice Deposits an amount of stable token for a fixed lender pool
     * @dev It transfers the approved stable tokens from msg.sender to lender pool
     * @param _amount Represents the amount of stable tokens to deposit
     * Requirements:
     * - '_amount' should be greater than zero
     * - '_amount' must be approved from the stable token contract for the LenderPool
     * - It should be called before Deposit End Date
     * Emits {Deposited} event
     */
    function deposit(uint256 _amount) external;

    /**
     * @notice Claims the Bonus rewards to the lender based on the Rate
     * @dev 'claimReward' transfers all the accumulated Bonus bonus rewards to 'msg.sender'
     * Requirements :
     * - 'LenderPool' should have Bonus tokens more than or equal to lender accumulated bonus rewards
     * Emits {Claimed} event
     */
    function claimReward() external;

    /**
     * @notice Withdraws principal deposited tokens + Stable rewards + remaining Bonus rewards for locking period
     * Requirements:
     * - 'LenderPool' should have stable tokens more than or equal to lender stable rewards + principal amount
     * - 'LenderPool' should have Bonus tokens more than or equal to lender accumulated bonus rewards
     * Emits {Withdrawn} event
     */
    function withdraw() external;

    /**
     * @notice Withdraws principal deposit for unverified lenders after given access from admin
     * Requirements:
     * - 'msg.sender' should be unverified
     * - 'msg.sender' should have access
     * Emits {PrincipalWithdrawn} event
     */
    function withdrawPricinpal() external;

    /**
     * @dev Changes the Verification contract that has been used for checking verification of lenders
     * @param _newVerification is the address of the new verification contract
     * Emits {VerificationSwitched} event
     */
    function switchVerification(address _newVerification) external;

    /**
     * @dev Changes the Strategy contract that has been used for using funds in defi protocols
     * @param _newStrategy is the address of the new strategy contract
     * Emits {StrategySwitched} event
     */
    function switchStrategy(address _newStrategy) external;

    /**
     * @dev returns the deposited amount of a specific lender
     * @param _lender Represents the address of lender
     */
    function getDeposit(address _lender) external view returns (uint256);

    /**
     * @dev returns the available Bonus rewards to claim for a specific lender
     * @param _lender Represents the address of lender
     */
    function getBonusRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the available amount of stable rewards for a specific lender
     * @param _lender Represents the address of lender
     */
    function getStableRewards(address _lender) external view returns (uint256);

    /**
     * @dev returns the APR with 2 decimals
     */
    function getApr() external view returns (uint256);

    /**
     * @dev returns the Rate of bonus reward with 2 decimals
     */
    function getRate() external view returns (uint256);

    /**
     * @dev returns the duration of locking period
     */
    function getLockingDuration() external view returns (uint256);

    /**
     * @dev returns pool start date that after that reward calculation begins
     */
    function getPoolStartDate() external view returns (uint256);

    /**
     * @dev returns the end deposit date that after that users can not deposit
     */
    function getDepositEndDate() external view returns (uint256);

    /**
     * @dev returns the pool maximum size that after reaching this limit users can not deposit
     */
    function getMaxPoolSize() external view returns (uint256);

    /**
     * @dev returns the require verification status of lender pool
     */
    function getVerificationStatus() external view returns (bool);
}
