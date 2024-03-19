// SPDX-License-Identifier: MIT
pragma solidity ^0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "./IERC7641.sol";

contract ERC7641 is ERC20Permit, ERC20Snapshot, IERC7641 {
    /**
     * @dev last snapshotted block
     */
    uint256 public lastSnapshotBlock;

    /**
     * @dev percentage claimable
     */
    uint256 immutable public percentClaimable;

    /**
     * @dev snapshot interval
     */
    uint256 immutable public snapshotInterval;

    /**
     * @dev mapping from snapshot id to the amount of ETH claimable at the snapshot.
     */
    mapping (uint256 => uint256) private _claimableAtSnapshot;

    /**
     * @dev mapping from snapshot id to amount of ETH claimed at the snapshot.
     */
    mapping (uint256 => uint256) private _claimedAtSnapshot;

    /**
     * @dev mapping from snapshot id to a boolean indicating whether the address has claimed the revenue.
     */
    mapping (uint256 => mapping (address => bool)) private _hasClaimedAtSnapshot;

    /**
     * @dev burn pool
     */
    uint256 private _burnPool;

    /**
     * @dev burned from new revenue
     */
    uint256 private _burned;

    /**
     * @dev Constructor for the ERC7641 contract, premint the total supply to the contract creator.
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param supply The total supply of the token
     */
    constructor(string memory name, string memory symbol, uint256 supply, uint256 _percentClaimable, uint256 _snapshotInterval) ERC20(name, symbol) ERC20Permit(name) {
        require(_percentClaimable <= 100, "percentage claimable should be less than 100");
        lastSnapshotBlock = block.number;
        percentClaimable = _percentClaimable;
        snapshotInterval = _snapshotInterval;
        _mint(msg.sender, supply);
    }

    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return The amount of revenue token claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) public view returns (uint256) {
        uint256 currentSnapshotId = _getCurrentSnapshotId();
        require(currentSnapshotId - snapshotId < 3, "snapshot unclaimable");
        uint256 balance = balanceOfAt(account, snapshotId);
        uint256 totalSupply = totalSupplyAt(snapshotId);
        uint256 ethClaimable = _claimableAtSnapshot[snapshotId];
        return _hasClaimedAtSnapshot[snapshotId][account] ? 0 : balance * ethClaimable / totalSupply;
    }

    /**
     * @dev A function for token holder to claim revenue token based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id
     */
    function claim(uint256 snapshotId) public {
        uint256 claimableETH = claimableRevenue(msg.sender, snapshotId);
        require(claimableETH > 0, "no claimable ETH");

        _hasClaimedAtSnapshot[snapshotId][msg.sender] = true;
        _claimedAtSnapshot[snapshotId] += claimableETH;
        (bool success, ) = msg.sender.call{value: claimableETH}("");
        require(success, "claim failed");
    }
    
    /**
     * @dev A function to claim by a list of snapshot ids.
     * @param snapshotIds The list of snapshot ids
     */
    function claimBatch(uint256[] memory snapshotIds) external {
        for (uint256 i = 0; i < snapshotIds.length; i++) {
            claim(snapshotIds[i]);
        }
    }

    /**
     * @dev A function to calculate claim pool from most recent three snapshots
     * @param currentSnapshotId The current snapshot id
     */
    function _claimPool(uint256 currentSnapshotId) public view returns (uint256 claimable) {
        claimable = _claimableAtSnapshot[currentSnapshotId] - _claimedAtSnapshot[currentSnapshotId];
        if (currentSnapshotId > 1) claimable += _claimableAtSnapshot[currentSnapshotId - 1] - _claimedAtSnapshot[currentSnapshotId - 1];
        if (currentSnapshotId > 2) claimable += _claimableAtSnapshot[currentSnapshotId - 2] - _claimedAtSnapshot[currentSnapshotId - 2];
        return claimable;
    }
    
    /**
     * @dev A snapshot function that also records the deposited ETH amount at the time of the snapshot.
     * @return The snapshot id
     * @notice 648000 blocks is approximately 3 months
     */
    function snapshot() external returns (uint256) {
        require(block.number - lastSnapshotBlock > snapshotInterval, "snapshot interval is too short");
        uint256 snapshotId = _snapshot();
        lastSnapshotBlock = block.number;
        
        uint256 newRevenue = address(this).balance + _burned - _burnPool - _claimPool(snapshotId-1);

        uint256 claimableETH = newRevenue * percentClaimable / 100;
        _claimableAtSnapshot[snapshotId] = snapshotId < 3 ? claimableETH : claimableETH + _claimableAtSnapshot[snapshotId-3] - _claimedAtSnapshot[snapshotId-3];
        _burnPool += newRevenue - claimableETH - _burned;
        _burned = 0;

        return snapshotId;
    }

    /**
     * @dev An internal function to calculate the amount of ETH redeemable in both the newRevenue and burnPool by a token holder upon burn
     * @param amount The amount of token to burn
     * @return The amount of revenue ETH redeemable
     */
    function _redeemableOnBurn(uint256 amount) internal view returns (uint256, uint256) {
        uint256 totalSupply = totalSupply();
        uint256 currentSnapshotId = _getCurrentSnapshotId();
        uint256 newRevenue = address(this).balance + _burned - _burnPool - _claimPool(currentSnapshotId);
        uint256 burnableFromNewRevenue = amount * ((newRevenue * (100 - percentClaimable)) / 100 - _burned) / totalSupply;
        uint256 burnableFromPool = amount * _burnPool / totalSupply;
        return (burnableFromNewRevenue, burnableFromPool);
    }
        /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint256 amount) external view returns (uint256) {
        (uint256 burnableFromNewRevenue, uint256 burnableFromPool) = _redeemableOnBurn(amount);
        return burnableFromNewRevenue + burnableFromPool;
    }

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(uint256 amount) external {
        (uint256 burnableFromNewRevenue, uint256 burnableFromPool) = _redeemableOnBurn(amount);
        _burnPool -= burnableFromPool;
        _burned += burnableFromNewRevenue;
        _burn(msg.sender, amount);
        (bool success, ) = msg.sender.call{value: burnableFromNewRevenue + burnableFromPool}("");
        require(success, "burn failed");
    }

    receive() external payable {}

    //override _beforeTokenTransfer to update the snapshot
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Snapshot) {
        ERC20Snapshot._beforeTokenTransfer(from, to, amount);
    }
}