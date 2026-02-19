// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "../DataTypes.sol";
import "../Constants.sol";

/// @title RewardsCalculationLibrary
/// @notice Internal library for rewards calculation functions
/// @dev This library contains only internal functions to avoid dependencies between external libraries
library RewardsCalculationLibrary {
    /// @notice Update vault rewards snapshot for all tokens
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param vaultId Vault ID to update
    function updateVaultRewards(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        uint256 vaultId
    ) internal {
        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];

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
