// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IORAAxonManager {
    function createORALPToken(
        string memory name,
        string memory symbol,
        uint256 supply,
        uint256 snapshotInterval,
        address initHolder,
        address oraTokenAddress
    ) external returns (address);
} 