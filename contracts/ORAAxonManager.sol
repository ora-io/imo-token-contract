// SPDX-License-Identifier: MIT
pragma solidity 0.8.24;

import "./ORALPToken.sol";
import "@openzeppelin/contracts/access/Ownable.sol";
import "./IORAAxonManager.sol";

contract ORAAxonManager is IORAAxonManager, Ownable {
    address public tokenEmitter;

    constructor(address _tokenEmitter) {
        tokenEmitter = _tokenEmitter;
    }

    modifier onlyTokenEmitter() {
        require(msg.sender == tokenEmitter, "Caller is not the token emitter");
        _;
    }

    function createORALPToken(
        string memory name,
        string memory symbol,
        uint256 supply,
        uint256 snapshotInterval,
        address initHolder
    ) external onlyTokenEmitter returns (address) {
        ORALPToken newToken = new ORALPToken(
            name,
            symbol,
            supply,
            snapshotInterval,
            initHolder,
            tokenEmitter
        );
        
        return address(newToken);
    }

    function setTokenEmitter(address _tokenEmitter) external onlyOwner {
        tokenEmitter = _tokenEmitter;
    }

    function getTotalClaimableORA(address snapshotLPToken,address account) external view returns (uint256) {
        return IORALPToken(snapshotLPToken).claimableRevenue(account);    
    }
}