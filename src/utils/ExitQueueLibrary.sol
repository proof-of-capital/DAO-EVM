// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DataTypes.sol";
import "./Constants.sol";
import "./VaultLibrary.sol";

/// @title ExitQueueLibrary
/// @notice Library for managing exit queue operations
library ExitQueueLibrary {
    using SafeERC20 for IERC20;

    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error AmountMustBeGreaterThanZero();
    error AlreadyInExitQueue();
    error NotInExitQueue();

    event ExitRequested(uint256 indexed vaultId, uint256 shares, uint256 launchPriceAtRequest);
    event ExitRequestCancelled(uint256 indexed vaultId);
    event ExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event PartialExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event SharePriceIncreased(uint256 oldPrice, uint256 newPrice, uint256 exitedShares);

    /// @notice Request to exit DAO by selling all shares
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @param updateVotesCallback Function to update votes in voting contract
    function executeRequestExit(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState,
        address launchToken,
        function(address) external returns (uint256) getOraclePrice,
        function(uint256, int256) external updateVotesCallback
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultLibrary._validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());
        require(vault.shares >= Constants.MIN_EXIT_SHARES, AmountMustBeGreaterThanZero());
        require(exitQueueStorage.vaultExitRequestIndex[vaultId] == 0, AlreadyInExitQueue());

        address delegate = vault.delegate;
        uint256 vaultShares = vault.shares;

        if (delegate != address(0) && delegate != vault.primary) {
            uint256 delegateVaultId = vaultStorage.addressToVaultId[delegate];
            if (delegateVaultId > 0 && delegateVaultId < vaultStorage.nextVaultId) {
                DataTypes.Vault memory delegateVault = vaultStorage.vaults[delegateVaultId];
                if (delegateVault.votingShares >= vaultShares) {
                    delegateVault.votingShares -= vaultShares;
                } else {
                    delegateVault.votingShares = 0;
                }
                vaultStorage.vaults[delegateVaultId] = delegateVault;
            }
        }

        vault.delegate = vault.primary;

        updateVotesCallback(vaultId, -int256(vaultShares));

        uint256 launchPriceNow = getOraclePrice(launchToken);

        exitQueueStorage.exitQueue
            .push(
                DataTypes.ExitRequest({
                    vaultId: vaultId,
                    requestTimestamp: block.timestamp,
                    fixedLaunchPriceAtRequest: launchPriceNow,
                    processed: false
                })
            );

        exitQueueStorage.vaultExitRequestIndex[vaultId] = exitQueueStorage.exitQueue.length;

        daoState.totalExitQueueShares += vault.shares;

        vaultStorage.vaults[vaultId] = vault;

        emit ExitRequested(vaultId, vault.shares, launchPriceNow);
    }

    /// @notice Process exit queue with available funds
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config (for share price)
    /// @param totalSharesSupply Total shares supply (will be updated)
    /// @param availableFunds Amount of funds available for buyback (in tokens)
    /// @param token Token used for buyback
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @param allowedExitTokens Global mapping of allowed exit tokens
    /// @param vaultAllowedExitTokens Vault-specific mapping of allowed exit tokens
    /// @return remainingFunds Remaining funds after processing (in tokens)
    /// @return newTotalSharesSupply Updated total shares supply
    function processExitQueue(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 totalSharesSupply,
        uint256 availableFunds,
        address token,
        address launchToken,
        function(address) external returns (uint256) getOraclePrice,
        mapping(address => bool) storage allowedExitTokens,
        mapping(uint256 => mapping(address => bool)) storage vaultAllowedExitTokens
    ) external returns (uint256 remainingFunds, uint256 newTotalSharesSupply) {
        newTotalSharesSupply = totalSharesSupply;
        remainingFunds = availableFunds;

        if (availableFunds == 0 || isExitQueueEmpty(exitQueueStorage)) {
            return (remainingFunds, newTotalSharesSupply);
        }

        uint256 tokenPriceUSD = getOraclePrice(token);

        for (
            uint256 i = exitQueueStorage.nextExitQueueIndex;
            i < exitQueueStorage.exitQueue.length && remainingFunds > 0;
            ++i
        ) {
            DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[i];

            if (request.processed) {
                if (exitQueueStorage.nextExitQueueIndex == i) {
                    exitQueueStorage.nextExitQueueIndex = i + 1;
                }
                continue;
            }

            DataTypes.Vault storage vault = vaultStorage.vaults[request.vaultId];
            uint256 shares = vault.shares;

            if (shares == 0) {
                if (exitQueueStorage.nextExitQueueIndex == i) {
                    exitQueueStorage.nextExitQueueIndex = i + 1;
                }
                continue;
            }

            if (!allowedExitTokens[token] && !vaultAllowedExitTokens[request.vaultId][token]) {
                continue;
            }

            uint256 exitValueUSD = calculateExitValue(
                participantEntries, fundraisingConfig, request.vaultId, shares, launchToken, getOraclePrice
            );
            uint256 exitValueInTokens = convertUSDToTokens(exitValueUSD, tokenPriceUSD);

            if (remainingFunds >= exitValueInTokens) {
                newTotalSharesSupply = executeExit(
                    vaultStorage,
                    exitQueueStorage,
                    daoState,
                    fundraisingConfig,
                    i,
                    exitValueInTokens,
                    token,
                    newTotalSharesSupply
                );
                remainingFunds -= exitValueInTokens;
                if (exitQueueStorage.nextExitQueueIndex == i) {
                    exitQueueStorage.nextExitQueueIndex = i + 1;
                }
            } else {
                uint256 partialShares = (remainingFunds * shares) / exitValueInTokens;
                if (partialShares > 0) {
                    uint256 partialExitValueUSD = calculateExitValue(
                        participantEntries,
                        fundraisingConfig,
                        request.vaultId,
                        partialShares,
                        launchToken,
                        getOraclePrice
                    );
                    uint256 partialExitValueInTokens = convertUSDToTokens(partialExitValueUSD, tokenPriceUSD);
                    if (partialExitValueInTokens > 0 && partialExitValueInTokens <= remainingFunds) {
                        newTotalSharesSupply = executePartialExit(
                            vaultStorage,
                            daoState,
                            fundraisingConfig,
                            request.vaultId,
                            partialShares,
                            partialExitValueInTokens,
                            token,
                            newTotalSharesSupply
                        );
                        remainingFunds -= partialExitValueInTokens;
                    }
                }
            }
        }
    }

    /// @notice Execute a single exit request
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param fundraisingConfig Fundraising config (for share price update)
    /// @param exitIndex Index in exit queue
    /// @param exitValue Value to pay out (in tokens)
    /// @param token Token to pay with
    /// @param totalSharesSupply Total shares supply (before exit)
    /// @return newTotalSharesSupply Updated total shares supply
    function executeExit(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 exitIndex,
        uint256 exitValue,
        address token,
        uint256 totalSharesSupply
    ) internal returns (uint256 newTotalSharesSupply) {
        DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[exitIndex];
        uint256 vaultId = request.vaultId;

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        uint256 shares = vault.shares;

        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        newTotalSharesSupply = totalSharesSupply - shares;

        request.processed = true;
        exitQueueStorage.exitQueue[exitIndex] = request;
        exitQueueStorage.vaultExitRequestIndex[vaultId] = 0;

        daoState.totalExitQueueShares -= shares;

        IERC20(token).safeTransfer(vault.primary, exitValue);

        if (newTotalSharesSupply > 0) {
            uint256 oldSharePrice = fundraisingConfig.sharePrice;
            uint256 newSharePrice = (oldSharePrice * previousTotalShares) / newTotalSharesSupply;
            fundraisingConfig.sharePrice = newSharePrice;
            emit SharePriceIncreased(oldSharePrice, newSharePrice, shares);
        }

        vaultStorage.vaults[vaultId] = vault;

        emit ExitProcessed(vaultId, shares, exitValue, token);
    }

    /// @notice Execute a partial exit
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage structure
    /// @param fundraisingConfig Fundraising config (for share price update)
    /// @param vaultId Vault ID
    /// @param shares Shares to exit
    /// @param payoutAmount Amount to pay out (in tokens)
    /// @param token Token to pay with
    /// @param totalSharesSupply Total shares supply (before exit)
    /// @return newTotalSharesSupply Updated total shares supply
    function executePartialExit(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 vaultId,
        uint256 shares,
        uint256 payoutAmount,
        address token,
        uint256 totalSharesSupply
    ) internal returns (uint256 newTotalSharesSupply) {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];

        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        newTotalSharesSupply = totalSharesSupply - shares;

        daoState.totalExitQueueShares -= shares;

        IERC20(token).safeTransfer(vault.primary, payoutAmount);

        if (newTotalSharesSupply > 0) {
            uint256 oldSharePrice = fundraisingConfig.sharePrice;
            uint256 newSharePrice = (oldSharePrice * previousTotalShares) / newTotalSharesSupply;
            fundraisingConfig.sharePrice = newSharePrice;
            emit SharePriceIncreased(oldSharePrice, newSharePrice, shares);
        }

        vaultStorage.vaults[vaultId] = vault;

        emit PartialExitProcessed(vaultId, shares, payoutAmount, token);
    }

    /// @notice Calculate exit value for a participant
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config
    /// @param vaultId Vault ID
    /// @param shares Number of shares to exit
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @return Exit value in USD (18 decimals)
    function calculateExitValue(
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 vaultId,
        uint256 shares,
        address launchToken,
        function(address) external returns (uint256) getOraclePrice
    ) internal returns (uint256) {
        DataTypes.ParticipantEntry memory entry = participantEntries[vaultId];

        uint256 shareValue = entry.fixedSharePrice;
        if (shareValue == 0) {
            shareValue = fundraisingConfig.sharePrice;
        }

        if (block.timestamp < entry.entryTimestamp + Constants.EXIT_DISCOUNT_PERIOD) {
            shareValue =
                (shareValue * (Constants.BASIS_POINTS - Constants.EXIT_DISCOUNT_PERCENT)) / Constants.BASIS_POINTS;
        }

        uint256 launchPriceNow = getOraclePrice(launchToken);
        uint256 fixedLaunchPrice = entry.fixedLaunchPrice > 0 ? entry.fixedLaunchPrice : fundraisingConfig.launchPrice;

        if (launchPriceNow < fixedLaunchPrice) {
            shareValue = (shareValue * launchPriceNow) / fixedLaunchPrice;
        }

        return (shareValue * shares) / Constants.PRICE_DECIMALS_MULTIPLIER;
    }

    /// @notice Convert USD amount to token amount
    /// @param usdAmount Amount in USD (18 decimals)
    /// @param tokenPriceUSD Token price in USD (18 decimals)
    /// @return Token amount
    function convertUSDToTokens(uint256 usdAmount, uint256 tokenPriceUSD) internal pure returns (uint256) {
        return (usdAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / tokenPriceUSD;
    }

    /// @notice Check if exit queue is empty (all processed)
    /// @param exitQueueStorage Exit queue storage structure
    /// @return True if no pending exits
    function isExitQueueEmpty(DataTypes.ExitQueueStorage storage exitQueueStorage) internal view returns (bool) {
        return exitQueueStorage.nextExitQueueIndex >= exitQueueStorage.exitQueue.length;
    }

    /// @notice Cancel exit request from queue
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    function executeCancelExit(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultLibrary._validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 exitRequestIndex = exitQueueStorage.vaultExitRequestIndex[vaultId];
        require(exitRequestIndex != 0, NotInExitQueue());

        uint256 arrayIndex = exitRequestIndex - 1;
        DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[arrayIndex];
        require(!request.processed, NotInExitQueue());

        uint256 vaultShares = vault.shares;

        address delegate = vault.delegate;

        if (delegate != address(0) && delegate != vault.primary) {
            uint256 delegateVaultId = vaultStorage.addressToVaultId[delegate];
            if (delegateVaultId > 0 && delegateVaultId < vaultStorage.nextVaultId) {
                DataTypes.Vault memory delegateVault = vaultStorage.vaults[delegateVaultId];
                delegateVault.votingShares += vaultShares;
                vaultStorage.vaults[delegateVaultId] = delegateVault;
            }
        }

        request.processed = true;
        exitQueueStorage.exitQueue[arrayIndex] = request;
        exitQueueStorage.vaultExitRequestIndex[vaultId] = 0;

        daoState.totalExitQueueShares -= vaultShares;

        emit ExitRequestCancelled(vaultId);
    }
}

