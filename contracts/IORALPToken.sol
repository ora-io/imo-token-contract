// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

interface IORALPToken {
    function claimableRevenue(address account) external view returns (uint256);
    function claim(address user, uint256 snapshotId) external returns(uint256);
    function claim(address user) external returns (uint256);
    function snapshot(uint256 rewardAmount) external returns (uint256);
    function redeemableOnBurn(uint256 amount) external view returns (uint256);
    function burn(address user, uint256 amount) external;
    function mint(address _to, uint256 _amount) external;
} 