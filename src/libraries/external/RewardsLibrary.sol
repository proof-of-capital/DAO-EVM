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
import "../internal/RewardsCalculationLibrary.sol";
import "../internal/SwapLibrary.sol";

/// @title RewardsLibrary
/// @notice Library for managing rewards system
library RewardsLibrary {
    using SafeERC20 for IERC20;

    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error RouterNotAvailable();

    event RewardClaimed(uint256 indexed vaultId, address indexed token, uint256 amount);
    event RewardClaimedAndSwapped(
        uint256 indexed vaultId, address indexed token, uint256 rewardAmount, uint256 collateralReceived
    );

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
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        RewardsCalculationLibrary.updateVaultRewards(vaultStorage, rewardsStorage, lpTokenStorage, vaultId);

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

    /// @notice Claim accumulated rewards and swap to main collateral
    /// @param vaultStorage Vault storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param availableRouterByAdmin Router whitelist mapping
    /// @param mainCollateral Main collateral token address
    /// @param swapParams Array of claim and swap parameters
    function executeClaimRewardAndSwap(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        mapping(address => bool) storage availableRouterByAdmin,
        address mainCollateral,
        DataTypes.ClaimSwapParams[] calldata swapParams
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        RewardsCalculationLibrary.updateVaultRewards(vaultStorage, rewardsStorage, lpTokenStorage, vaultId);

        uint256 totalCollateralReceived = 0;

        for (uint256 i = 0; i < swapParams.length; ++i) {
            DataTypes.ClaimSwapParams calldata params = swapParams[i];
            uint256 rewards = rewardsStorage.earnedRewards[vaultId][params.token];

            if (rewards > 0) {
                require(availableRouterByAdmin[params.router], RouterNotAvailable());

                rewardsStorage.earnedRewards[vaultId][params.token] = 0;
                accountedBalance[params.token] -= rewards;

                uint256 balanceBefore = IERC20(mainCollateral).balanceOf(address(this));

                SwapLibrary.executeSwap(
                    params.router,
                    params.swapType,
                    params.swapData,
                    params.token,
                    mainCollateral,
                    rewards,
                    params.minCollateralAmount
                );

                uint256 balanceAfter = IERC20(mainCollateral).balanceOf(address(this));
                uint256 collateralReceived = balanceAfter - balanceBefore;

                totalCollateralReceived += collateralReceived;

                emit RewardClaimedAndSwapped(vaultId, params.token, rewards, collateralReceived);
            }
        }

        if (totalCollateralReceived > 0) {
            IERC20(mainCollateral).safeTransfer(msg.sender, totalCollateralReceived);
        }
    }
}

