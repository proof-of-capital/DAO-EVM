// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "./ExitQueueValidationLibrary.sol";

/// @title ExitQueueProcessingLibrary
/// @notice Internal library for exit queue processing functions
/// @dev This library contains only internal functions to avoid dependencies between external libraries
library ExitQueueProcessingLibrary {
    using SafeERC20 for IERC20;

    /// @notice Process exit queue - internal version for use by other libraries
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config
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
    ) internal returns (uint256 remainingFunds, uint256 newTotalSharesSupply) {
        newTotalSharesSupply = totalSharesSupply;
        remainingFunds = availableFunds;

        if (availableFunds == 0 || ExitQueueValidationLibrary.isExitQueueEmpty(exitQueueStorage)) {
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

            uint256 exitValueUSD = _calculateExitValue(
                vaultStorage,
                exitQueueStorage,
                participantEntries,
                fundraisingConfig,
                request.vaultId,
                shares,
                launchToken,
                getOraclePrice
            );
            uint256 exitValueInTokens = _convertUSDToTokens(exitValueUSD, tokenPriceUSD);

            if (remainingFunds >= exitValueInTokens) {
                newTotalSharesSupply = _executeExit(
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
                if (partialShares > 0 && remainingFunds > 0) {
                    newTotalSharesSupply = _executePartialExit(
                        vaultStorage,
                        daoState,
                        fundraisingConfig,
                        request.vaultId,
                        partialShares,
                        remainingFunds,
                        token,
                        newTotalSharesSupply
                    );
                    remainingFunds = 0;
                }
            }
        }
    }

    /// @notice Calculate exit value for a participant based on vault.depositedUSD
    function _calculateExitValue(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 vaultId,
        uint256 shares,
        address launchToken,
        function(address) external returns (uint256) getOraclePrice
    ) internal returns (uint256) {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        uint256 vaultTotalShares = vault.shares;

        uint256 exitValueUSD = (vault.depositedUSD * shares) / vaultTotalShares;

        DataTypes.ParticipantEntry memory entry = participantEntries[vaultId];
        if (entry.fixedSharePrice == 0) {
            entry.fixedSharePrice = fundraisingConfig.sharePriceStart;
            entry.fixedLaunchPrice = fundraisingConfig.launchPriceStart;
        }

        if (
            entry.depositedMainCollateral > 0 && block.timestamp < entry.entryTimestamp + Constants.EXIT_DISCOUNT_PERIOD
        ) {
            exitValueUSD =
                (exitValueUSD * (Constants.BASIS_POINTS - Constants.EXIT_DISCOUNT_PERCENT)) / Constants.BASIS_POINTS;
        }

        uint256 exitRequestIndex = exitQueueStorage.vaultExitRequestIndex[vaultId];
        if (exitRequestIndex > 0) {
            DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[exitRequestIndex];
            uint256 launchPriceNow = getOraclePrice(launchToken);
            if (launchPriceNow < request.fixedLaunchPriceAtRequest) {
                exitValueUSD = (exitValueUSD * launchPriceNow) / request.fixedLaunchPriceAtRequest;
            }
        }

        return exitValueUSD;
    }

    /// @notice Convert USD amount to token amount
    function _convertUSDToTokens(uint256 usdAmount, uint256 tokenPriceUSD) internal pure returns (uint256) {
        return (usdAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / tokenPriceUSD;
    }

    /// @notice Execute a single exit request
    function _executeExit(
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

        uint256 depositedUSDToReduce = vault.depositedUSD;
        vault.depositedUSD = 0;
        daoState.totalDepositedUSD -= depositedUSDToReduce;

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
        }

        vaultStorage.vaults[vaultId] = vault;
    }

    /// @notice Execute a partial exit
    function _executePartialExit(
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

        uint256 vaultSharesBeforeExit = vault.shares;
        uint256 depositedUSDToReduce = (vault.depositedUSD * shares) / vaultSharesBeforeExit;
        vault.depositedUSD -= depositedUSDToReduce;
        daoState.totalDepositedUSD -= depositedUSDToReduce;

        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        newTotalSharesSupply = totalSharesSupply - shares;

        daoState.totalExitQueueShares -= shares;

        IERC20(token).safeTransfer(vault.primary, payoutAmount);

        if (newTotalSharesSupply > 0) {
            uint256 oldSharePrice = fundraisingConfig.sharePrice;
            uint256 newSharePrice = (oldSharePrice * previousTotalShares) / newTotalSharesSupply;
            fundraisingConfig.sharePrice = newSharePrice;
        }

        vaultStorage.vaults[vaultId] = vault;
    }
}
