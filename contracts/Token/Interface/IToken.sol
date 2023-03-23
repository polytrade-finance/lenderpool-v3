// SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/**
 * @dev Interface of the ERC20 standard as defined in the EIP.
 */
interface IToken is IERC20 {
    function mint(address to, uint amount) external;

    function decimals() external view returns (uint8);
}
