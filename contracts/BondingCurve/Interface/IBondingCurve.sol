// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

/**
 * @title IBondingCurve
 * @author Polytrade
 */
interface IBondingCurve {
    
    /**
     * @notice Returns Stable or Bonus Rate based on Locking Duration in days
     * @dev returns Apr percentage and Bonus rate with 2 decimals 
     * @param lockingDuration, days of locking period chosen by user
     */
    function getRate(uint256 lockingDuration) external view returns(uint256);
}
