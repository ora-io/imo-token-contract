// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IORALPToken.sol";

contract ORALPToken is ERC20Permit, ERC20Snapshot, IORALPToken, Ownable {
    
    address public oraTokenAddress;

    address public tokenEmitterAddress;
    /**
     * @dev snapshot number reserved for claimable
     */
    uint256 constant public SNAPSHOT_CLAIMABLE_NUMBER = 2;

    /**
     * @dev last snapshotted timestamp
     */
    uint256 public lastSnapshotTimestamp;

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
     * @notice mapping from user address to the last claimed snapshot id
     * @dev this is used to prevent double claiming
     */
    mapping (address => uint256) public userLastClaimedSnapshotId;

    /**
     * @dev burn pool
     */
    uint256 private _redeemPool;

    modifier onlyTokenEmitter() {
        require(msg.sender == tokenEmitterAddress, "Only token emitter can call this function");
        _;
    }

    /**
     * @dev Constructor for the ERC7641 contract, premint the total supply to the contract creator.
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param initial_supply The initial supply of the token
     * @param _snapshotInterval The minimum interval between 2 snapshots
     */
    constructor(string memory name, string memory symbol, uint256 initial_supply, uint256 _snapshotInterval, address _initHolder, address _oraTokenAddress, address _tokenEmitterAddress) ERC20(name, symbol) ERC20Permit(name) {
        lastSnapshotTimestamp = block.timestamp;
        snapshotInterval = _snapshotInterval;
        oraTokenAddress = _oraTokenAddress;
        tokenEmitterAddress = _tokenEmitterAddress;
        _mint(_initHolder, initial_supply);
    }

    /**
     * @dev A function to calculate the amount of ETH claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return claimable The amount of revenue ETH claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) public view returns (uint256) {
        require(_hasClaimedAtSnapshot[snapshotId][account] == false, "already claimed");
        uint256 currentSnapshotId = _getCurrentSnapshotId();
        require(currentSnapshotId - snapshotId < SNAPSHOT_CLAIMABLE_NUMBER, "snapshot unclaimable");
        uint256 balance = balanceOfAt(account, snapshotId);
        uint256 totalSupply = totalSupplyAt(snapshotId);
        uint256 oraClaimable = _claimableAtSnapshot[snapshotId];
        return balance * oraClaimable / totalSupply;
    }

    /**
     * @dev A function for token holder to claim revenue token based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id 
     */
    function claim(address user, uint256 snapshotId) public returns (uint256) {
        if(snapshotId <= userLastClaimedSnapshotId[user]) {
            revert("Given snapshotId already claimed");
        }

        if(snapshotId > _getCurrentSnapshotId()) {
            revert("Given snapshotId is not yet available");
        }

        uint256 totalClaimableORA = 0;
        if(userLastClaimedSnapshotId[user] == 0) {
            userLastClaimedSnapshotId[user] = 1;
        }

        for(uint256 i = userLastClaimedSnapshotId[user] + 1; i < snapshotId; i++) {
            uint256 claimableORA = claimableRevenue(user, i);
            if(claimableORA == 0) {
                continue;
            }

            _hasClaimedAtSnapshot[snapshotId][user] = true;
            _claimedAtSnapshot[snapshotId] += claimableORA;
            totalClaimableORA += claimableORA;
        }

        userLastClaimedSnapshotId[user] = snapshotId;
        require(totalClaimableORA > 0, "no claimable ORA");
        IERC20(oraTokenAddress).transfer(tokenEmitterAddress, totalClaimableORA);

        return totalClaimableORA;
    }
    
    /**
     * @dev A function to claim by a list of snapshot ids.
     */
    function claim(address user) external returns (uint256) {
        return claim(user, _getCurrentSnapshotId());
    }

    /**
     * @dev A function to calculate claim pool from most recent two snapshots
     * @param currentSnapshotId The current snapshot id
     * @notice modify when SNAPSHOT_CLAIMABLE_NUMBER changes
     */
    function _claimPool(uint256 currentSnapshotId) private view returns (uint256 claimable) {
        claimable = _claimableAtSnapshot[currentSnapshotId] - _claimedAtSnapshot[currentSnapshotId];
        if (currentSnapshotId >= 2) claimable += _claimableAtSnapshot[currentSnapshotId - 1] - _claimedAtSnapshot[currentSnapshotId - 1];
        return claimable;
    }
    
    /**
     * @dev A snapshot function that also records the deposited ETH amount at the time of the snapshot.
     * @return snapshotId The snapshot id
     * @notice 7776000 seconds is approximately 3 months
     */
    function snapshot() external returns (uint256) {
        require(block.timestamp - lastSnapshotTimestamp > snapshotInterval, "snapshot interval is too short");
        uint256 snapshotId = _snapshot();
        lastSnapshotTimestamp = block.timestamp;        
        uint256 newRevenue = IERC20(oraTokenAddress).balanceOf(address(this)) - _redeemPool - _claimPool(snapshotId-1);
        _claimableAtSnapshot[snapshotId] = snapshotId < SNAPSHOT_CLAIMABLE_NUMBER ? newRevenue : newRevenue + _claimableAtSnapshot[snapshotId-SNAPSHOT_CLAIMABLE_NUMBER] - _claimedAtSnapshot[snapshotId-SNAPSHOT_CLAIMABLE_NUMBER];
        return snapshotId;
    }

    /**
     * @dev An internal function to calculate the amount of ORA redeemable in burnPool by a token holder upon burn
     * @param amount The amount of token to burn
     * @return redeemableFromPool The amount of revenue ORA redeemable from the snapshoted redeem pool
     */
    function _redeemableOnBurn(uint256 amount) private view returns (uint256) {
        uint256 totalSupply = totalSupply();
        uint256 redeemableFromPool = amount * _redeemPool / totalSupply;
        return redeemableFromPool;
    }
    
    /**
     * @dev A function to calculate the amount of ETH redeemable by a token holder upon burn
     * @param amount The amount of token to burn
     * @return redeemable The amount of revenue ETH redeemable
     */
    function redeemableOnBurn(uint256 amount) external view returns (uint256) {
        return _redeemableOnBurn(amount);
    }

    function mint(address _to, uint256 _amount) external onlyTokenEmitter {
        _mint(_to, _amount);
    }

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(address from, uint256 amount) external onlyTokenEmitter {
        uint256 redeemableFromPool = _redeemableOnBurn(amount);
        _redeemPool -= redeemableFromPool;
        _burn(from, amount);
        IERC20(oraTokenAddress).transfer(from, redeemableFromPool);
    }

    receive() external payable {}

    /**
     * @dev override _beforeTokenTransfer to update the snapshot
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Snapshot) {
        require(from == address(0) || to == address(0), "Token is non-transferable");
        ERC20Snapshot._beforeTokenTransfer(from, to, amount);
    }

    function setOraTokenAddress(address _oraTokenAddress) external onlyOwner {
        oraTokenAddress = _oraTokenAddress;
    }

    function setTokenEmitterAddress(address _tokenEmitterAddress) external onlyOwner {
        tokenEmitterAddress = _tokenEmitterAddress;
    }
}