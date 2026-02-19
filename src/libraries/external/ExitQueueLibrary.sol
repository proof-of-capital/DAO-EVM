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
import "./VaultLibrary.sol";
import "../internal/VaultValidationLibrary.sol";
import "../../interfaces/IVoting.sol";

/// @title ExitQueueLibrary
/// @notice Library for managing exit queue operations
library ExitQueueLibrary {
    using SafeERC20 for IERC20;

    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error AmountMustBeGreaterThanZero();
    error AlreadyInExitQueue();
    error NotInExitQueue();
    error InvalidStage();

    event ExitRequested(uint256 indexed vaultId, uint256 shares, uint256 launchPriceAtRequest);
    event ExitRequestCancelled(uint256 indexed vaultId);
    event ExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event PartialExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event SharePriceIncreased(uint256 oldPrice, uint256 newPrice, uint256 exitedShares);
    event StageChanged(DataTypes.Stage from, DataTypes.Stage to);

    /// @notice Request to exit DAO by selling all shares
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @param votingContract Address of voting contract
    function executeRequestExit(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState,
        address launchToken,
        function(address) external returns (uint256) getOraclePrice,
        address votingContract
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());
        require(vault.shares >= Constants.MIN_EXIT_SHARES, AmountMustBeGreaterThanZero());
        require(exitQueueStorage.vaultExitRequestIndex[vaultId] == 0, AlreadyInExitQueue());

        uint256 delegateId = vault.delegateId;
        uint256 vaultShares = vault.shares;

        uint256 targetVaultId = vaultId;
        if (delegateId != 0 && delegateId != vaultId) {
            if (delegateId > 0 && delegateId < vaultStorage.nextVaultId) {
                DataTypes.Vault memory delegateVault = vaultStorage.vaults[delegateId];
                if (delegateVault.votingShares >= vaultShares) {
                    delegateVault.votingShares -= vaultShares;
                } else {
                    delegateVault.votingShares = 0;
                }
                vaultStorage.vaults[delegateId] = delegateVault;
                targetVaultId = delegateId;
            }
        }

        vault.delegateId = 0;

        IVoting(votingContract).updateVotesForVault(targetVaultId, -int256(vaultShares));

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
            emit SharePriceIncreased(oldSharePrice, newSharePrice, shares);
        }

        vaultStorage.vaults[vaultId] = vault;

        emit PartialExitProcessed(vaultId, shares, payoutAmount, token);
    }

    /// @notice Calculate exit value for a participant based on vault.depositedUSD
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising configuration for start prices
    /// @param vaultId Vault ID
    /// @param shares Number of shares to exit
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @return Exit value in USD (18 decimals)
    function calculateExitValue(
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
            DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[exitRequestIndex - 1];
            uint256 launchPriceNow = getOraclePrice(launchToken);
            if (launchPriceNow < request.fixedLaunchPriceAtRequest) {
                exitValueUSD = (exitValueUSD * launchPriceNow) / request.fixedLaunchPriceAtRequest;
            }
        }

        return exitValueUSD;
    }

    /// @notice Convert USD amount to token amount
    /// @param usdAmount Amount in USD (18 decimals)
    /// @param tokenPriceUSD Token price in USD (18 decimals)
    /// @return Token amount
    function convertUSDToTokens(uint256 usdAmount, uint256 tokenPriceUSD) internal pure returns (uint256) {
        return (usdAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / tokenPriceUSD;
    }

    /// @notice Check if exit queue is empty (all processed) - internal version
    /// @param exitQueueStorage Exit queue storage structure
    /// @return True if no pending exits
    function _isExitQueueEmpty(DataTypes.ExitQueueStorage storage exitQueueStorage) internal view returns (bool) {
        return exitQueueStorage.nextExitQueueIndex >= exitQueueStorage.exitQueue.length;
    }

    /// @notice Check if exit queue is empty (all processed) - public version for external libraries
    /// @param exitQueueStorage Exit queue storage structure
    /// @return True if no pending exits
    function isExitQueueEmpty(DataTypes.ExitQueueStorage storage exitQueueStorage) external view returns (bool) {
        return _isExitQueueEmpty(exitQueueStorage);
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
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 exitRequestIndex = exitQueueStorage.vaultExitRequestIndex[vaultId];
        require(exitRequestIndex != 0, NotInExitQueue());

        uint256 arrayIndex = exitRequestIndex - 1;
        DataTypes.ExitRequest memory request = exitQueueStorage.exitQueue[arrayIndex];
        require(!request.processed, NotInExitQueue());

        uint256 vaultShares = vault.shares;

        request.processed = true;
        exitQueueStorage.exitQueue[arrayIndex] = request;
        exitQueueStorage.vaultExitRequestIndex[vaultId] = 0;

        daoState.totalExitQueueShares -= vaultShares;

        emit ExitRequestCancelled(vaultId);
    }

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
    function _processExitQueue(
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

        if (availableFunds == 0 || _isExitQueueEmpty(exitQueueStorage)) {
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
                vaultStorage,
                exitQueueStorage,
                participantEntries,
                fundraisingConfig,
                request.vaultId,
                shares,
                launchToken,
                getOraclePrice
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
                if (partialShares > 0 && remainingFunds > 0) {
                    newTotalSharesSupply = executePartialExit(
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

    /// @notice Process exit queue - public version for DAO
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
    ) public returns (uint256 remainingFunds, uint256 newTotalSharesSupply) {
        return _processExitQueue(
            vaultStorage,
            exitQueueStorage,
            daoState,
            participantEntries,
            fundraisingConfig,
            totalSharesSupply,
            availableFunds,
            token,
            launchToken,
            getOraclePrice,
            allowedExitTokens,
            vaultAllowedExitTokens
        );
    }

    /// @notice Process pending exit queue payment in parts
    /// @param vaultStorage Vault storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param daoState DAO state storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config
    /// @param allowedExitTokens Global mapping of allowed exit tokens
    /// @param vaultAllowedExitTokens Vault-specific mapping of allowed exit tokens
    /// @param amount Amount of launch tokens to use for processing exit queue
    /// @param coreConfig DAO core config (launchToken, creator)
    /// @param getOraclePrice Function to get token price in USD
    /// @return newTotalSharesSupply Updated total shares supply
    function processPendingExitQueuePayment(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.DAOState storage daoState,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => bool) storage allowedExitTokens,
        mapping(uint256 => mapping(address => bool)) storage vaultAllowedExitTokens,
        uint256 amount,
        DataTypes.CoreConfig storage coreConfig,
        function(address) external returns (uint256) getOraclePrice
    ) external returns (uint256 newTotalSharesSupply) {
        uint256 amountToUse = amount;
        if (amountToUse > daoState.pendingExitQueuePayment) {
            amountToUse = daoState.pendingExitQueuePayment;
        }

        uint256 remainingFunds;
        (remainingFunds, newTotalSharesSupply) = _processExitQueue(
            vaultStorage,
            exitQueueStorage,
            daoState,
            participantEntries,
            fundraisingConfig,
            vaultStorage.totalSharesSupply,
            amountToUse,
            coreConfig.launchToken,
            coreConfig.launchToken,
            getOraclePrice,
            allowedExitTokens,
            vaultAllowedExitTokens
        );

        uint256 usedForExits = amountToUse - remainingFunds;
        if (usedForExits > daoState.pendingExitQueuePayment) {
            usedForExits = daoState.pendingExitQueuePayment;
        }
        daoState.pendingExitQueuePayment -= usedForExits;

        bool queueEmpty = _isExitQueueEmpty(exitQueueStorage);

        if (queueEmpty && daoState.pendingExitQueuePayment > 0) {
            uint256 remainingForCreator = daoState.pendingExitQueuePayment;
            daoState.pendingExitQueuePayment = 0;
            IERC20(coreConfig.launchToken).safeTransfer(coreConfig.creator, remainingForCreator);
        }
    }

    /// @notice Calculate closing threshold based on DAO profit share
    /// @param daoState DAO state storage structure
    /// @return Closing threshold in basis points
    function getClosingThreshold(DataTypes.DAOState storage daoState) internal view returns (uint256) {
        uint256 daoShare = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;
        if (daoShare < Constants.MIN_DAO_PROFIT_SHARE) {
            daoShare = Constants.MIN_DAO_PROFIT_SHARE;
        }
        uint256 vetoThreshold = Constants.BASIS_POINTS - daoShare;
        if (vetoThreshold < Constants.CLOSING_EXIT_QUEUE_MIN_THRESHOLD) {
            return Constants.CLOSING_EXIT_QUEUE_MIN_THRESHOLD;
        }
        return vetoThreshold;
    }

    /// @notice Execute transition to Closing stage
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage structure
    function executeEnterClosingStage(DataTypes.VaultStorage storage vaultStorage, DataTypes.DAOState storage daoState)
        external
    {
        uint256 exitQueuePercentage =
            (daoState.totalExitQueueShares * Constants.BASIS_POINTS) / vaultStorage.totalSharesSupply;
        uint256 closingThreshold = getClosingThreshold(daoState);
        require(exitQueuePercentage >= closingThreshold, InvalidStage());

        daoState.currentStage = DataTypes.Stage.Closing;
        emit StageChanged(DataTypes.Stage.Active, DataTypes.Stage.Closing);
    }

    /// @notice Execute transition to Active stage
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage structure
    function executeReturnToActiveStage(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState
    ) external {
        uint256 exitQueuePercentage =
            (daoState.totalExitQueueShares * Constants.BASIS_POINTS) / vaultStorage.totalSharesSupply;
        uint256 closingThreshold = getClosingThreshold(daoState);
        require(exitQueuePercentage < closingThreshold, InvalidStage());

        daoState.currentStage = DataTypes.Stage.Active;
        emit StageChanged(DataTypes.Stage.Closing, DataTypes.Stage.Active);
    }
}

