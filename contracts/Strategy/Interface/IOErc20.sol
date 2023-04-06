//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

interface IOErc20 {
    /*** User Interface ***/

    function mint(uint mintAmount) external returns (uint256);

    function redeem(uint redeemTokens) external returns (uint256);

    function redeemUnderlying(uint redeemAmount) external returns (uint256);

    function balanceOfUnderlying(address owner) external returns (uint256);

    function exchangeRateStored() external view returns (uint256);

    function balanceOf(address owner) external view returns (uint256);

    function decimals() external view returns (uint8);
}
