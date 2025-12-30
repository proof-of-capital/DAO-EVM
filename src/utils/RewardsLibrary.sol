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

/// @title RewardsLibrary
/// @notice Library for managing rewards system
library RewardsLibrary {
    using SafeERC20 for IERC20;

    error NoVaultFound();
    error OnlyPrimaryCanClaim();

    event RewardClaimed(uint256 indexed vaultId, address indexed token, uint256 amount);

    /// @notice Claim accumulated rewards for tokens
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param tokens Array of token addresses to claim
    function executeClaimReward(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address[] calldata tokens
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultLibrary._validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        executeUpdateVaultRewards(vaultStorage, rewardsStorage, lpTokenStorage, vaultId);

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            uint256 rewards = rewardsStorage.earnedRewards[vaultId][token];

            if (rewards > 0) {
                rewardsStorage.earnedRewards[vaultId][token] = 0;
                accountedBalance[token] -= rewards;

                IERC20(token).safeTransfer(msg.sender, rewards);

                emit RewardClaimed(vaultId, token, rewards);
            }
        }

        for (uint256 i = 0; i < lpTokenStorage.v2LPTokens.length; ++i) {
            address lpToken = lpTokenStorage.v2LPTokens[i];
            uint256 rewards = rewardsStorage.earnedRewards[vaultId][lpToken];

            if (rewards > 0) {
                rewardsStorage.earnedRewards[vaultId][lpToken] = 0;
                accountedBalance[lpToken] -= rewards;

                IERC20(lpToken).safeTransfer(msg.sender, rewards);

                emit RewardClaimed(vaultId, lpToken, rewards);
            }
        }
    }

    /// @notice Update vault rewards snapshot for all tokens
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param vaultId Vault ID to update
    function executeUpdateVaultRewards(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        uint256 vaultId
    ) internal {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        if (vault.shares == 0) return;

        for (uint256 i = 0; i < rewardsStorage.rewardTokens.length; ++i) {
            address rewardToken = rewardsStorage.rewardTokens[i];
            if (rewardsStorage.rewardTokenInfo[rewardToken].active) {
                uint256 pending = calculatePendingRewards(vaultStorage, rewardsStorage, vaultId, rewardToken);

                if (pending > 0) {
                    rewardsStorage.earnedRewards[vaultId][rewardToken] += pending;
                }

                rewardsStorage.vaultRewardIndex[vaultId][rewardToken] = rewardsStorage.rewardPerShareStored[rewardToken];
            }
        }

        for (uint256 i = 0; i < lpTokenStorage.v2LPTokens.length; ++i) {
            address lpToken = lpTokenStorage.v2LPTokens[i];
            uint256 pending = calculatePendingRewards(vaultStorage, rewardsStorage, vaultId, lpToken);

            if (pending > 0) {
                rewardsStorage.earnedRewards[vaultId][lpToken] += pending;
            }

            rewardsStorage.vaultRewardIndex[vaultId][lpToken] = rewardsStorage.rewardPerShareStored[lpToken];
        }
    }

    /// @notice Calculate pending rewards for a vault and token
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param vaultId Vault ID
    /// @param token Token address
    /// @return Pending rewards amount
    function calculatePendingRewards(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        uint256 vaultId,
        address token
    ) internal view returns (uint256) {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        if (vault.shares == 0) return 0;

        uint256 currentIndex = rewardsStorage.rewardPerShareStored[token];
        uint256 userIndex = rewardsStorage.vaultRewardIndex[vaultId][token];

        if (currentIndex <= userIndex) return 0;

        uint256 indexDelta = currentIndex - userIndex;
        return (vault.shares * indexDelta) / Constants.PRICE_DECIMALS_MULTIPLIER;
    }
}

