// SPDX-License-Identifier: MIT
pragma solidity ^0.8.17;

import "contracts/Verification/Interface/IVerification.sol";
import "contracts/Verification/Interface/IPolytradeProxy.sol";
import "@openzeppelin/contracts/utils/introspection/ERC165.sol";

/**
 * @title Verification Contract
 * @author Polytrade
 * @notice Verification contract used for checking users KYC if needed
 * @dev The contract is in development stage
 */
contract Verification is IVerification, ERC165 {
    IPolytradeProxy public immutable polytradeProxy;

    /// @param polytradeProxy_ is the address of polytrade proxy to check with fractal registry
    constructor(address polytradeProxy_) {
        polytradeProxy = IPolytradeProxy(polytradeProxy_);
    }

    /**
     * @dev See {IVerification-isValid}.
     */
    function isValid(address user) external view returns (bool) {
        return polytradeProxy.hasPassedKYC(user);
    }

    /**
     * @dev See {IERC165-supportsInterface}.
     */
    function supportsInterface(
        bytes4 interfaceId
    ) public view virtual override(ERC165) returns (bool) {
        return
            interfaceId == type(IVerification).interfaceId ||
            super.supportsInterface(interfaceId);
    }
}
