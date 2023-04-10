//SPDX-License-Identifier: MIT
pragma solidity 0.8.17;

contract OracleMock {
    function getUnderlyingPrice(address oToken) public view returns (uint256) {
        oToken;
        return 999799000000000000000000000000;
    }
}
