// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../DataTypes.sol";
import "../../interfaces/IDAO.sol";
import "../../interfaces/IVoting.sol";

/// @title VaultLibrary
/// @notice Library for managing vaults, addresses, and delegate voting shares
library VaultLibrary {
    error VaultAlreadyExists();
    error InvalidAddresses();
    error InvalidAddress();
    error AddressAlreadyUsedInAnotherVault();
    error NoVaultFound();
    error VaultDoesNotExist();
    error NoShares();
    error OnlyVotingContract();
    error Unauthorized();
    error CannotChangeDelegateInExitQueue();
    error DepositLimitBelowCurrentShares();
    error InvalidStage();

    event VaultCreated(uint256 indexed vaultId, address indexed primary, uint256 shares);
    event PrimaryAddressUpdated(uint256 indexed vaultId, address indexed oldPrimary, address indexed newPrimary);
    event BackupAddressUpdated(uint256 indexed vaultId, address indexed oldBackup, address indexed newBackup);
    event EmergencyAddressUpdated(uint256 indexed vaultId, address indexed oldEmergency, address indexed newEmergency);
    event DelegateUpdated(
        uint256 indexed vaultId, uint256 indexed oldDelegateId, uint256 indexed newDelegateId, uint256 timestamp
    );
    event VaultDepositLimitSet(uint256 indexed vaultId, uint256 limit);

    /// @notice Validate that vault exists (vaultId > 0 && vaultId < nextVaultId)
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to validate
    function _validateVaultExists(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId) internal view {
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, NoVaultFound());
    }

    /// @notice Validate that vault exists and has shares (vaultId > 0 && vaultId < nextVaultId && shares > 0)
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to validate
    function _validateVaultWithShares(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId) internal view {
        require(
            vaultId > 0 && vaultId < vaultStorage.nextVaultId && vaultStorage.vaults[vaultId].shares > 0,
            VaultDoesNotExist()
        );
    }

    /// @notice Create a new vault (without deposit)
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure (for initializing reward indices)
    /// @param lpTokenStorage LP token storage structure (for initializing reward indices)
    /// @param backup Backup address for recovery
    /// @param emergency Emergency address for recovery
    /// @param delegate Delegate address for voting (if zero, self-delegation)
    /// @return vaultId The ID of the created vault
    function executeCreateVault(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        address backup,
        address emergency,
        address delegate
    ) external returns (uint256 vaultId) {
        require(backup != address(0) && emergency != address(0), InvalidAddresses());
        require(vaultStorage.addressToVaultId[msg.sender] == 0, VaultAlreadyExists());

        vaultId = vaultStorage.nextVaultId++;

        uint256 delegateId = delegate == address(0) ? 0 : vaultStorage.addressToVaultId[delegate];

        vaultStorage.vaults[vaultId] = DataTypes.Vault({
            primary: msg.sender,
            backup: backup,
            emergency: emergency,
            shares: 0,
            votingPausedUntil: 0,
            delegateId: delegateId,
            delegateSetAt: block.timestamp,
            votingShares: 0,
            mainCollateralDeposit: 0,
            depositedUSD: 0,
            depositLimit: 0
        });

        vaultStorage.addressToVaultId[msg.sender] = vaultId;

        for (uint256 i = 0; i < rewardsStorage.rewardTokens.length; ++i) {
            address rewardToken = rewardsStorage.rewardTokens[i];
            if (rewardsStorage.rewardTokenInfo[rewardToken].active) {
                rewardsStorage.vaultRewardIndex[vaultId][rewardToken] = rewardsStorage.rewardPerShareStored[rewardToken];
            }
        }

        for (uint256 i = 0; i < lpTokenStorage.v2LPTokens.length; ++i) {
            address token = lpTokenStorage.v2LPTokens[i];
            rewardsStorage.vaultRewardIndex[vaultId][token] = rewardsStorage.rewardPerShareStored[token];
        }

        emit VaultCreated(vaultId, msg.sender, 0);
    }

    /// @notice Update primary address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param newPrimary New primary address
    function executeUpdatePrimaryAddress(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        address newPrimary
    ) external {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(
            msg.sender == vault.primary || msg.sender == vault.backup || msg.sender == vault.emergency, Unauthorized()
        );
        require(newPrimary != address(0), InvalidAddress());
        require(vaultStorage.addressToVaultId[newPrimary] == 0, AddressAlreadyUsedInAnotherVault());

        address oldPrimary = vault.primary;
        delete vaultStorage.addressToVaultId[oldPrimary];

        vault.primary = newPrimary;
        vaultStorage.vaults[vaultId] = vault;
        vaultStorage.addressToVaultId[newPrimary] = vaultId;

        emit PrimaryAddressUpdated(vaultId, oldPrimary, newPrimary);
    }

    /// @notice Update backup address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param newBackup New backup address
    function executeUpdateBackupAddress(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId, address newBackup)
        external
    {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(msg.sender == vault.backup || msg.sender == vault.emergency, Unauthorized());
        require(newBackup != address(0), InvalidAddress());

        address oldBackup = vault.backup;
        vault.backup = newBackup;
        vaultStorage.vaults[vaultId] = vault;

        emit BackupAddressUpdated(vaultId, oldBackup, newBackup);
    }

    /// @notice Update emergency address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param newEmergency New emergency address
    function executeUpdateEmergencyAddress(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        address newEmergency
    ) external {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(msg.sender == vault.emergency, Unauthorized());
        require(newEmergency != address(0), InvalidAddress());

        address oldEmergency = vault.emergency;
        vault.emergency = newEmergency;
        vaultStorage.vaults[vaultId] = vault;

        emit EmergencyAddressUpdated(vaultId, oldEmergency, newEmergency);
    }

    /// @notice Set delegate address for voting
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param userAddress User address to find vault and set delegate
    /// @param delegate New delegate address (if zero, self-delegation)
    /// @param votingContract Address of voting contract
    function executeSetDelegate(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        address userAddress,
        address delegate,
        address votingContract
    ) external {
        require(msg.sender == votingContract, OnlyVotingContract());
        require(votingContract != address(0), InvalidAddress());
        require(userAddress != address(0), InvalidAddress());

        uint256 vaultId = vaultStorage.addressToVaultId[userAddress];
        _validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.shares > 0, NoShares());
        require(exitQueueStorage.vaultExitRequestIndex[vaultId] == 0, CannotChangeDelegateInExitQueue());

        uint256 newDelegateId = delegate == address(0) ? 0 : vaultStorage.addressToVaultId[delegate];

        uint256 oldDelegateId = vault.delegateId;
        uint256 vaultShares = vault.shares;

        if (oldDelegateId != 0 && oldDelegateId != vaultId) {
            if (oldDelegateId > 0 && oldDelegateId < vaultStorage.nextVaultId) {
                DataTypes.Vault memory oldDelegateVault = vaultStorage.vaults[oldDelegateId];
                if (oldDelegateVault.votingShares >= vaultShares) {
                    oldDelegateVault.votingShares -= vaultShares;
                } else {
                    oldDelegateVault.votingShares = 0;
                }
                vaultStorage.vaults[oldDelegateId] = oldDelegateVault;
                IVoting(votingContract).updateVotesForVault(oldDelegateId, -int256(vaultShares));
            }
        }

        vault.delegateId = newDelegateId;
        vault.delegateSetAt = block.timestamp;

        if (newDelegateId != 0 && newDelegateId != vaultId) {
            if (newDelegateId > 0 && newDelegateId < vaultStorage.nextVaultId) {
                DataTypes.Vault memory newDelegateVault = vaultStorage.vaults[newDelegateId];
                newDelegateVault.votingShares += vaultShares;
                vaultStorage.vaults[newDelegateId] = newDelegateVault;
                IVoting(votingContract).updateVotesForVault(newDelegateId, int256(vaultShares));
            }
        }

        vaultStorage.vaults[vaultId] = vault;

        emit DelegateUpdated(vaultId, oldDelegateId, newDelegateId, block.timestamp);
    }

    /// @notice Update voting shares for delegate when vault shares change; updates vault in storage
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID whose shares changed
    /// @param sharesDelta Change in shares (positive for increase, negative for decrease)
    /// @param votingContract Address of voting contract to update votes in active proposals
    function executeUpdateDelegateVotingShares(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        int256 sharesDelta,
        address votingContract
    ) external {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        uint256 delegateId = vault.delegateId;

        uint256 targetVaultId = (delegateId == 0 || delegateId == vaultId) ? vaultId : delegateId;

        if (targetVaultId >= vaultStorage.nextVaultId) {
            return;
        }

        DataTypes.Vault memory targetVault = vaultStorage.vaults[targetVaultId];

        if (sharesDelta > 0) {
            targetVault.votingShares += uint256(sharesDelta);
        } else if (sharesDelta < 0) {
            uint256 decreaseAmount = uint256(-sharesDelta);
            if (targetVault.votingShares >= decreaseAmount) {
                targetVault.votingShares -= decreaseAmount;
            } else {
                targetVault.votingShares = 0;
            }
        }

        vaultStorage.vaults[targetVaultId] = targetVault;

        if (votingContract != address(0)) {
            IVoting(votingContract).updateVotesForVault(targetVaultId, sharesDelta);
        }
    }

    /// @notice Set allowed exit token for a vault
    /// @param vaultStorage Vault storage structure
    /// @param token Token address to set
    /// @param allowed Whether the token is allowed
    function executeSetVaultAllowedExitToken(DataTypes.VaultStorage storage vaultStorage, address token, bool allowed)
        external
    {
        require(token != address(0), InvalidAddress());

        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        _validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, Unauthorized());

        vaultStorage.vaultAllowedExitTokens[vaultId][token] = allowed;
    }

    /// @notice Set vault deposit limit
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID
    /// @param limit New deposit limit
    function executeSetVaultDepositLimit(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId, uint256 limit)
        external
    {
        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(limit >= vault.shares, DepositLimitBelowCurrentShares());
        vault.depositLimit = limit;
        emit VaultDepositLimitSet(vaultId, limit);
    }
}

