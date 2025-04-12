// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Snapshot.sol";
import "@openzeppelin/contracts/token/ERC20/extensions/ERC20Permit.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./IORALPToken.sol";

contract ORALPToken is ERC20Permit, ERC20Snapshot, IORALPToken, Ownable {
    
    address public tokenEmitterAddress;

    /**
     * @dev mapping from snapshot id to the amount of ORA claimable at the snapshot.
     */
    mapping (uint256 => uint256) private _claimableAtSnapshot;

    /**
     * @dev mapping from snapshot id to amount of ORA claimed at the snapshot.
     */
    mapping (uint256 => uint256) private _claimedAtSnapshot;

    /**
     * @dev mapping from snapshot id to a boolean indicating whORAer the address has claimed the revenue.
     */
    mapping (uint256 => mapping (address => bool)) private _hasClaimedAtSnapshot;

    /**
     * @notice mapping from user address to the last claimed snapshot id
     * @dev this is used to prevent double claiming
     */
    mapping (address => uint256) public userLastClaimedSnapshotId;

    modifier onlyTokenEmitter() {
        require(msg.sender == tokenEmitterAddress, "Only token emitter can call this function");
        _;
    }

    /**
     * @dev Constructor for the ERC7641 contract, premint the total supply to the contract creator.
     * @param name The name of the token
     * @param symbol The symbol of the token
     * @param initial_supply The initial supply of the token
     */
    constructor(string memory name, string memory symbol, uint256 initial_supply, address _initHolder, address _tokenEmitterAddress) ERC20(name, symbol) ERC20Permit(name) {
        tokenEmitterAddress = _tokenEmitterAddress;
        _mint(_initHolder, initial_supply);
    }

    /**
     * @dev A function to calculate the amount of ORA claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @return claimable The amount of revenue ORA claimable
     */
    function claimableRevenue(address account) public view returns (uint256) {
        uint256 currentSnapshotId = _getCurrentSnapshotId();
        uint256 _userLastClaimedSnapshotId = userLastClaimedSnapshotId[account];

        uint256 totalClaimableORA = 0;

        for(uint256 i = _userLastClaimedSnapshotId + 1; i <= currentSnapshotId; i++) {
            totalClaimableORA += _claimableRevenue(account, i);
        }

        return totalClaimableORA;
    }

    /**
     * @dev A function to calculate the amount of ORA claimable by a token holder at certain snapshot.
     * @param account The address of the token holder
     * @param snapshotId The snapshot id
     * @return claimable The amount of revenue ORA claimable
     */
    function claimableRevenue(address account, uint256 snapshotId) external view returns (uint256) {
        return _claimableRevenue(account, snapshotId);
    }

    function _claimableRevenue(address account, uint256 snapshotId) internal view returns (uint256) {
        require(_hasClaimedAtSnapshot[snapshotId][account] == false, "Given snapshotId has already claimed");
        require(snapshotId <= _getCurrentSnapshotId(), "Given snapshotId is not yet available");
        uint256 balance = balanceOfAt(account, snapshotId);
        uint256 totalSupply = totalSupplyAt(snapshotId);
        uint256 oraClaimable = _claimableAtSnapshot[snapshotId];
        return balance * oraClaimable / totalSupply;
    }

    /**
     * @dev A function for token holder to claim revenue token based on the token balance at certain snapshot.
     * @param snapshotId The snapshot id 
     */
    function claim(address user, uint256 snapshotId) public onlyTokenEmitter returns (uint256) {
        if(snapshotId <= userLastClaimedSnapshotId[user]) {
            revert("Given snapshotId already claimed");
        }

        if(snapshotId > _getCurrentSnapshotId()) {
            revert("Given snapshotId is not yet available");
        }

        uint256 totalClaimableORA = 0;

        for(uint256 i = userLastClaimedSnapshotId[user] + 1; i <= snapshotId; i++) {
            uint256 claimableORA = _claimableRevenue(user, i);
            _hasClaimedAtSnapshot[i][user] = true;
            _claimedAtSnapshot[i] += claimableORA;
            totalClaimableORA += claimableORA;
        }

        userLastClaimedSnapshotId[user] = snapshotId;
        require(totalClaimableORA > 0, "no claimable ORA");

        return totalClaimableORA;
    }
    
    /**
     * @dev A function to claim by a list of snapshot ids.
     */
    function claim(address user) external onlyTokenEmitter returns (uint256) {
        return claim(user, _getCurrentSnapshotId());
    }
    
    /**
     * @dev A snapshot function that also records the deposited ORA amount at the time of the snapshot.
     * @return snapshotId The snapshot id
     * @notice 7776000 seconds is approximately 3 months
     */
    function snapshot(uint256 rewardAmount) external onlyTokenEmitter returns (uint256) {
        uint256 snapshotId = _snapshot();
        _claimableAtSnapshot[snapshotId] = rewardAmount;
        return snapshotId;
    }
    

    function mint(address _to, uint256 _amount) external onlyTokenEmitter {
        if(balanceOf(_to) == 0 && userLastClaimedSnapshotId[_to] == 0) {
            // update user last claimed snapshot id
            userLastClaimedSnapshotId[_to] = _getCurrentSnapshotId();
        }
        _mint(_to, _amount);
    }

    /**
     * @dev A function to burn tokens and redeem the corresponding amount of revenue token
     * @param amount The amount of token to burn
     */
    function burn(address from, uint256 amount) external onlyTokenEmitter {
        _burn(from, amount);
        if(balanceOf(from) == 0 && userLastClaimedSnapshotId[from] == _getCurrentSnapshotId()) {
            delete userLastClaimedSnapshotId[from];
        }
    }

    receive() external payable {}

    /**
     * @dev override _beforeTokenTransfer to update the snapshot
     */
    function _beforeTokenTransfer(address from, address to, uint256 amount) internal virtual override(ERC20, ERC20Snapshot) {
        require(from == address(0) || to == address(0), "Token is non-transferable");
        ERC20Snapshot._beforeTokenTransfer(from, to, amount);
    }
}