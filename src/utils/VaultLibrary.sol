// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "./DataTypes.sol";
import "../interfaces/IDAO.sol";

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

    event VaultCreated(uint256 indexed vaultId, address indexed primary, uint256 shares);
    event PrimaryAddressUpdated(uint256 indexed vaultId, address indexed oldPrimary, address indexed newPrimary);
    event BackupAddressUpdated(uint256 indexed vaultId, address indexed oldBackup, address indexed newBackup);
    event EmergencyAddressUpdated(uint256 indexed vaultId, address indexed oldEmergency, address indexed newEmergency);
    event DelegateUpdated(
        uint256 indexed vaultId, address indexed oldDelegate, address indexed newDelegate, uint256 timestamp
    );

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
    /// @param primary Primary address
    /// @param backup Backup address for recovery
    /// @param emergency Emergency address for recovery
    /// @param delegate Delegate address for voting (if zero, primary is delegate)
    /// @return vaultId The ID of the created vault
    function executeCreateVault(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        address primary,
        address backup,
        address emergency,
        address delegate
    ) external returns (uint256 vaultId) {
        require(backup != address(0) && emergency != address(0), InvalidAddresses());
        require(vaultStorage.addressToVaultId[primary] == 0, VaultAlreadyExists());

        vaultId = vaultStorage.nextVaultId++;

        address finalDelegate = delegate == address(0) ? primary : delegate;

        vaultStorage.vaults[vaultId] = DataTypes.Vault({
            primary: primary,
            backup: backup,
            emergency: emergency,
            shares: 0,
            votingPausedUntil: 0,
            delegate: finalDelegate,
            delegateSetAt: block.timestamp,
            votingShares: 0,
            mainCollateralDeposit: 0,
            depositedUSD: 0,
            depositLimit: 0
        });

        vaultStorage.addressToVaultId[primary] = vaultId;

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

        emit VaultCreated(vaultId, primary, 0);
    }

    /// @notice Update primary address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param sender Sender address (for authorization check)
    /// @param newPrimary New primary address
    function executeUpdatePrimaryAddress(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        address sender,
        address newPrimary
    ) external {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(sender == vault.primary || sender == vault.backup || sender == vault.emergency, Unauthorized());
        require(newPrimary != address(0), InvalidAddress());
        require(vaultStorage.addressToVaultId[newPrimary] == 0, AddressAlreadyUsedInAnotherVault());

        address oldPrimary = vault.primary;
        delete vaultStorage.addressToVaultId[oldPrimary];

        vault.primary = newPrimary;
        vaultStorage.addressToVaultId[newPrimary] = vaultId;

        emit PrimaryAddressUpdated(vaultId, oldPrimary, newPrimary);
    }

    /// @notice Update backup address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param sender Sender address (for authorization check)
    /// @param newBackup New backup address
    function executeUpdateBackupAddress(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        address sender,
        address newBackup
    ) external {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(sender == vault.backup || sender == vault.emergency, Unauthorized());
        require(newBackup != address(0), InvalidAddress());

        address oldBackup = vault.backup;
        vault.backup = newBackup;

        emit BackupAddressUpdated(vaultId, oldBackup, newBackup);
    }

    /// @notice Update emergency address
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to update
    /// @param sender Sender address (for authorization check)
    /// @param newEmergency New emergency address
    function executeUpdateEmergencyAddress(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        address sender,
        address newEmergency
    ) external {
        _validateVaultWithShares(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(sender == vault.emergency, Unauthorized());
        require(newEmergency != address(0), InvalidAddress());

        address oldEmergency = vault.emergency;
        vault.emergency = newEmergency;

        emit EmergencyAddressUpdated(vaultId, oldEmergency, newEmergency);
    }

    /// @notice Set delegate address for voting
    /// @param vaultStorage Vault storage structure
    /// @param userAddress User address to find vault and set delegate
    /// @param delegate New delegate address (if zero, primary is set as delegate)
    /// @param updateVotesCallback Function to update votes in voting contract
    function executeSetDelegate(
        DataTypes.VaultStorage storage vaultStorage,
        address userAddress,
        address delegate,
        function(uint256, int256) external updateVotesCallback
    ) external {
        require(userAddress != address(0), InvalidAddress());

        uint256 vaultId = vaultStorage.addressToVaultId[userAddress];
        _validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.shares > 0, NoShares());

        address finalDelegate = delegate == address(0) ? vault.primary : delegate;

        address oldDelegate = vault.delegate;
        uint256 vaultShares = vault.shares;

        if (oldDelegate != address(0) && oldDelegate != vault.primary) {
            uint256 oldDelegateVaultId = vaultStorage.addressToVaultId[oldDelegate];
            if (oldDelegateVaultId > 0 && oldDelegateVaultId < vaultStorage.nextVaultId) {
                DataTypes.Vault storage oldDelegateVault = vaultStorage.vaults[oldDelegateVaultId];
                if (oldDelegateVault.votingShares >= vaultShares) {
                    oldDelegateVault.votingShares -= vaultShares;
                } else {
                    oldDelegateVault.votingShares = 0;
                }
                updateVotesCallback(oldDelegateVaultId, -int256(vaultShares));
            }
        }

        vault.delegate = finalDelegate;
        vault.delegateSetAt = block.timestamp;

        if (finalDelegate != address(0) && finalDelegate != vault.primary) {
            uint256 newDelegateVaultId = vaultStorage.addressToVaultId[finalDelegate];
            if (newDelegateVaultId > 0 && newDelegateVaultId < vaultStorage.nextVaultId) {
                DataTypes.Vault storage newDelegateVault = vaultStorage.vaults[newDelegateVaultId];
                newDelegateVault.votingShares += vaultShares;
                updateVotesCallback(newDelegateVaultId, int256(vaultShares));
            }
        }

        emit DelegateUpdated(vaultId, oldDelegate, finalDelegate, block.timestamp);
    }

    /// @notice Update voting shares for delegate when vault shares change
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID whose shares changed
    /// @param sharesDelta Change in shares (positive for increase, negative for decrease)
    function executeUpdateDelegateVotingShares(
        DataTypes.VaultStorage storage vaultStorage,
        uint256 vaultId,
        int256 sharesDelta
    ) external {
        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        address delegate = vault.delegate;

        if (delegate == address(0) || delegate == vault.primary) {
            return;
        }

        uint256 delegateVaultId = vaultStorage.addressToVaultId[delegate];
        if (delegateVaultId == 0 || delegateVaultId >= vaultStorage.nextVaultId) {
            return;
        }

        DataTypes.Vault storage delegateVault = vaultStorage.vaults[delegateVaultId];

        if (sharesDelta > 0) {
            delegateVault.votingShares += uint256(sharesDelta);
        } else if (sharesDelta < 0) {
            uint256 decreaseAmount = uint256(-sharesDelta);
            if (delegateVault.votingShares >= decreaseAmount) {
                delegateVault.votingShares -= decreaseAmount;
            } else {
                delegateVault.votingShares = 0;
            }
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
}

