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
import "./ExitQueueLibrary.sol";

/// @title ProfitDistributionLibrary
/// @notice Library for distributing profits (royalty, creator, participants)
library ProfitDistributionLibrary {
    using SafeERC20 for IERC20;

    error RewardPerShareTooLow();
    error NoShares();
    error TokenNotAdded();

    event RoyaltyDistributed(address indexed token, address indexed recipient, uint256 amount);
    event CreatorProfitDistributed(address indexed token, address indexed creator, uint256 amount);
    event ProfitDistributed(address indexed token, uint256 amount);

    /// @notice Distribute unaccounted balance of a token as profit
    /// @param daoState DAO state storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param vaultStorage Vault storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config
    /// @param accountedBalance Accounted balance mapping
    /// @param totalSharesSupply Total shares supply (will be updated)
    /// @param token Token address to distribute
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @return newTotalSharesSupply Updated total shares supply
    function executeDistributeProfit(
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.VaultStorage storage vaultStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        uint256 totalSharesSupply,
        address token,
        address launchToken,
        function(address) external view returns (uint256) getOraclePrice
    ) external returns (uint256 newTotalSharesSupply) {
        require(vaultStorage.totalSharesSupply > 0, NoShares());
        require(rewardsStorage.rewardTokenInfo[token].active || lpTokenStorage.isV2LPToken[token], TokenNotAdded());

        newTotalSharesSupply = totalSharesSupply;
        uint256 unaccounted = IERC20(token).balanceOf(address(this)) - accountedBalance[token];
        if (unaccounted == 0) {
            vaultStorage.totalSharesSupply = newTotalSharesSupply;
            return newTotalSharesSupply;
        }

        uint256 royaltyShare = distributeRoyaltyShare(daoState, token, unaccounted);
        uint256 creatorShare = distributeCreatorShare(daoState, token, unaccounted);

        uint256 participantsShare = unaccounted - royaltyShare - creatorShare;
        uint256 remainingForParticipants;
        (remainingForParticipants, newTotalSharesSupply) = distributeToParticipants(
            daoState,
            rewardsStorage,
            exitQueueStorage,
            lpTokenStorage,
            vaultStorage,
            participantEntries,
            fundraisingConfig,
            totalSharesSupply,
            token,
            participantsShare,
            launchToken,
            getOraclePrice
        );

        accountedBalance[token] += remainingForParticipants;
        vaultStorage.totalSharesSupply = newTotalSharesSupply;

        emit ProfitDistributed(token, unaccounted);
    }

    /// @notice Distribute royalty share
    /// @param daoState DAO state storage structure
    /// @param token Token address
    /// @param totalAmount Total amount to distribute
    /// @return royaltyShare Amount distributed as royalty
    function distributeRoyaltyShare(DataTypes.DAOState storage daoState, address token, uint256 totalAmount)
        internal
        returns (uint256 royaltyShare)
    {
        royaltyShare = (totalAmount * daoState.royaltyPercent) / Constants.BASIS_POINTS;
        if (royaltyShare > 0 && daoState.royaltyRecipient != address(0)) {
            IERC20(token).safeTransfer(daoState.royaltyRecipient, royaltyShare);
            emit RoyaltyDistributed(token, daoState.royaltyRecipient, royaltyShare);
        }
    }

    /// @notice Distribute creator share
    /// @param daoState DAO state storage structure
    /// @param token Token address
    /// @param amount Amount to calculate creator share from
    /// @return creatorShare Amount distributed to creator
    function distributeCreatorShare(DataTypes.DAOState storage daoState, address token, uint256 amount)
        internal
        returns (uint256 creatorShare)
    {
        creatorShare = (amount * daoState.creatorProfitPercent) / Constants.BASIS_POINTS;
        if (creatorShare > 0) {
            IERC20(token).safeTransfer(daoState.creator, creatorShare);
            emit CreatorProfitDistributed(token, daoState.creator, creatorShare);
        }
    }

    /// @notice Distribute to participants (process exit queue and update rewards)
    /// @param daoState DAO state storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param exitQueueStorage Exit queue storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param vaultStorage Vault storage structure
    /// @param participantEntries Participant entries mapping
    /// @param fundraisingConfig Fundraising config
    /// @param totalSharesSupply Total shares supply (will be updated)
    /// @param token Token address
    /// @param participantsShare Amount available for participants
    /// @param launchToken Launch token address
    /// @param getOraclePrice Function to get token price in USD
    /// @return remainingForParticipants Amount remaining after exit queue processing
    /// @return newTotalSharesSupply Updated total shares supply
    function distributeToParticipants(
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.VaultStorage storage vaultStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 totalSharesSupply,
        address token,
        uint256 participantsShare,
        address launchToken,
        function(address) external view returns (uint256) getOraclePrice
    ) internal returns (uint256 remainingForParticipants, uint256 newTotalSharesSupply) {
        newTotalSharesSupply = totalSharesSupply;
        uint256 usedForExits = 0;

        if (
            exitQueueStorage.exitQueue.length > 0 && !ExitQueueLibrary.isExitQueueEmpty(exitQueueStorage)
                && participantsShare > 0 && !lpTokenStorage.isV2LPToken[token]
                && daoState.currentStage != DataTypes.Stage.Closing
        ) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));

            uint256 availableFunds = participantsShare;
            uint256 remainingFunds;
            (remainingFunds, newTotalSharesSupply) = ExitQueueLibrary.processExitQueue(
                vaultStorage,
                exitQueueStorage,
                daoState,
                participantEntries,
                fundraisingConfig,
                totalSharesSupply,
                availableFunds,
                token,
                launchToken,
                getOraclePrice
            );

            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            usedForExits = balanceBefore - balanceAfter;
        }

        remainingForParticipants = participantsShare - usedForExits;

        if (remainingForParticipants > 0 && newTotalSharesSupply > 0) {
            require(
                (remainingForParticipants * Constants.PRICE_DECIMALS_MULTIPLIER) / newTotalSharesSupply
                    > Constants.MIN_REWARD_PER_SHARE,
                RewardPerShareTooLow()
            );
            rewardsStorage.rewardPerShareStored[
                    token
                ] += (remainingForParticipants * Constants.PRICE_DECIMALS_MULTIPLIER) / newTotalSharesSupply;
        }
    }
}

