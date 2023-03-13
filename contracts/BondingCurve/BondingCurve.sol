// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/BondingCurve/Interface/IBondingCurve.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title BondingCurve
 * @author Polytrade
 */
contract BondingCurve is IBondingCurve, ERC165 {
    uint256 private immutable _p1;
    uint256 private immutable _p2;
    uint256 private immutable _p3;
    uint256 private immutable _multiple;

    /**
     * @param p1_ is the first parameter in polynomial bonding curve function
     * @param p2_ is the second parameter in polynomial bonding curve function
     * @param p3_ is the third parameter in polynomial bonding curve function
     * @param decimals_ is the number decimals added to parameters that is necessary for calculation
     */
    constructor(uint256 p1_, uint256 p2_, uint256 p3_, uint256 decimals_) {
        require(decimals_ != 0, "Decimals can not be zero");
        _p1 = p1_;
        _p2 = p2_;
        _p3 = p3_;
        _multiple = 10 ** decimals_;
    }

    /**
     * @dev See {IBondingCurve-getRate}.
     */
    function getRate(uint256 lockingDuration) external view returns (uint256) {
        uint256 result = _p1 *
            (lockingDuration ** 2) -
            _p2 *
            lockingDuration +
            _p3;
        return result / _multiple;
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IBondingCurve).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
