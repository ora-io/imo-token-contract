// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IORAAxonManager {
    function createORALPToken(
        string memory name,
        string memory symbol,
        uint256 supply,
        address initHolder
    ) external returns (address);

    function getTotalClaimableORA(
        address snapshotLPToken,
        address account
    ) external view returns (uint256);

    function setTokenEmitterAddress(address _tokenEmitterAddress) external;
}