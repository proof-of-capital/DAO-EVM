// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IProofOfCapital.sol";
import "../interfaces/INonfungiblePositionManager.sol";
import "./DataTypes.sol";
import "./Constants.sol";
import "./VaultLibrary.sol";
import "./LPTokenLibrary.sol";

/// @title DissolutionLibrary
/// @notice Library for DAO dissolution operations
library DissolutionLibrary {
    using SafeERC20 for IERC20;

    error NoPOCContractsConfigured();
    error POCLockPeriodNotEnded();
    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error NoSharesToClaim();
    error InvalidAddress();
    error NoRewardsToClaim();
    error InvalidStage();

    event StageChanged(DataTypes.Stage oldStage, DataTypes.Stage newStage);
    event CreatorDissolutionClaimed(address indexed creator, uint256 launchAmount);
    event V2LPTokenDissolved(address indexed lpToken, uint256 amount0, uint256 amount1);
    event V3LPPositionDissolved(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    /// @notice Dissolve DAO if all POC contract locks have ended
    /// @param daoState DAO state storage structure
    /// @param pocContracts Array of POC contracts
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Mapping of accounted balances
    function executeDissolveIfLocksEnded(
        DataTypes.DAOState storage daoState,
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance
    ) external {
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (poc.active) {
                uint256 lockEndTime = IProofOfCapital(poc.pocContract).lockEndTime();
                require(block.timestamp >= lockEndTime, POCLockPeriodNotEnded());

                IProofOfCapital(poc.pocContract).withdrawAllLaunchTokens();
                IProofOfCapital(poc.pocContract).withdrawAllCollateralTokens();
            }
        }

        bool hasLPTokens = LPTokenLibrary.hasLPTokens(lpTokenStorage, accountedBalance);

        if (hasLPTokens) {
            daoState.currentStage = DataTypes.Stage.WaitingForLPDissolution;
            emit StageChanged(DataTypes.Stage.Active, DataTypes.Stage.WaitingForLPDissolution);
        } else {
            daoState.currentStage = DataTypes.Stage.Dissolved;
            emit StageChanged(DataTypes.Stage.Active, DataTypes.Stage.Dissolved);
        }
    }

    /// @notice Dissolve DAO from FundraisingExchange or WaitingForLP stages if all POC contract locks have ended
    /// @param daoState DAO state storage structure
    /// @param pocContracts Array of POC contracts
    function executeDissolveFromFundraisingStages(
        DataTypes.DAOState storage daoState,
        DataTypes.POCInfo[] storage pocContracts
    ) external {
        require(
            daoState.currentStage == DataTypes.Stage.FundraisingExchange
                || daoState.currentStage == DataTypes.Stage.WaitingForLP,
            InvalidStage()
        );
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (poc.active) {
                uint256 lockEndTime = IProofOfCapital(poc.pocContract).lockEndTime();
                require(block.timestamp >= lockEndTime, POCLockPeriodNotEnded());

                IProofOfCapital(poc.pocContract).withdrawAllLaunchTokens();
                IProofOfCapital(poc.pocContract).withdrawAllCollateralTokens();
            }
        }

        DataTypes.Stage oldStage = daoState.currentStage;
        daoState.currentStage = DataTypes.Stage.Dissolved;
        emit StageChanged(oldStage, DataTypes.Stage.Dissolved);
    }

    /// @notice Claim share of assets after dissolution
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage
    /// @param rewardsStorage Rewards storage structure
    /// @param accountedBalance Mapping of accounted balances
    /// @param launchToken Launch token address
    /// @param tokens Array of token addresses to claim
    /// @return shares Shares amount claimed
    function executeClaimDissolution(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        address[] calldata tokens
    ) external returns (uint256 shares) {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultLibrary._validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());
        require(vault.shares > 0, NoSharesToClaim());

        shares = vault.shares;
        vault.shares = 0;

        uint256 vaultDepositedUSD = vault.depositedUSD;
        require(daoState.totalDepositedUSD > 0 || vaultStorage.totalSharesSupply > 0, NoSharesToClaim());

        for (uint256 i = 0; i < tokens.length; ++i) {
            address token = tokens[i];
            require(token != address(0), InvalidAddress());

            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) continue;

            bool isValidToken = token == address(launchToken) || rewardsStorage.rewardTokenInfo[token].active;

            require(isValidToken, InvalidAddress());

            uint256 tokenShare;
            if (daoState.totalDepositedUSD > 0 && vaultDepositedUSD > 0) {
                tokenShare = (tokenBalance * vaultDepositedUSD) / daoState.totalDepositedUSD;
            } else {
                tokenShare = (tokenBalance * shares) / vaultStorage.totalSharesSupply;
            }

            if (tokenShare > 0) {
                IERC20(token).safeTransfer(msg.sender, tokenShare);
                if (token == address(launchToken)) {
                    accountedBalance[address(launchToken)] -= tokenShare;
                }
            }
        }

        vaultStorage.totalSharesSupply -= shares;
        if (vaultDepositedUSD > 0) {
            daoState.totalDepositedUSD -= vaultDepositedUSD;
            vault.depositedUSD = 0;
        }

        vaultStorage.vaults[vaultId] = vault;
    }

    /// @notice Claim creator's share of launch tokens during dissolution
    /// @param accountedBalance Mapping of accounted balances
    /// @param launchToken Launch token address
    /// @param creatorInfraPercent Creator infrastructure percent
    /// @param creator Creator address
    /// @return creatorLaunchShare Creator's launch share amount
    function executeClaimCreatorDissolution(
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        uint256 creatorInfraPercent,
        address creator
    ) external returns (uint256 creatorLaunchShare) {
        uint256 launchBalance = IERC20(launchToken).balanceOf(address(this));
        creatorLaunchShare = (launchBalance * creatorInfraPercent) / Constants.BASIS_POINTS;
        require(creatorLaunchShare > 0, NoRewardsToClaim());
        IERC20(launchToken).safeTransfer(creator, creatorLaunchShare);
        accountedBalance[address(launchToken)] -= creatorLaunchShare;
        emit CreatorDissolutionClaimed(creator, creatorLaunchShare);
    }

    /// @notice Dissolve all LP tokens (V2 and V3) and transition to Dissolved stage
    /// @param daoState DAO state storage
    /// @param lpTokenStorage LP token storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param launchToken Launch token address
    function executeDissolveLPTokens(
        DataTypes.DAOState storage daoState,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        mapping(address => uint256) storage accountedBalance,
        address launchToken
    ) external {
        uint256 v2Length = lpTokenStorage.v2LPTokens.length;
        for (uint256 i = 0; i < v2Length; ++i) {
            address lpToken = lpTokenStorage.v2LPTokens[i];
            if (accountedBalance[lpToken] > 0) {
                (uint256 amount0, uint256 amount1) =
                    LPTokenLibrary.executeDissolveV2LPToken(lpTokenStorage, accountedBalance, lpToken);
                emit V2LPTokenDissolved(lpToken, amount0, amount1);
            }
        }

        uint256 v3Length = lpTokenStorage.v3LPPositions.length;
        for (uint256 i = 0; i < v3Length; ++i) {
            uint256 tokenId = lpTokenStorage.v3LPPositions[i].tokenId;
            DataTypes.V3LPPositionInfo memory positionInfo = lpTokenStorage.v3LPPositions[i];
            INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);
            (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
            if (liquidity > 0) {
                (uint256 amount0, uint256 amount1) =
                    LPTokenLibrary.executeDissolveV3LPPosition(lpTokenStorage, accountedBalance, tokenId);
                emit V3LPPositionDissolved(tokenId, amount0, amount1);
            }
        }

        delete lpTokenStorage.v2LPTokens;
        delete lpTokenStorage.v3LPPositions;

        executeSyncAllTokenBalances(rewardsStorage, accountedBalance, launchToken);

        daoState.currentStage = DataTypes.Stage.Dissolved;
        emit StageChanged(DataTypes.Stage.WaitingForLPDissolution, DataTypes.Stage.Dissolved);
    }

    /// @notice Sync accountedBalance for all reward tokens and launch token with actual contract balances
    /// @param rewardsStorage Rewards storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param launchToken Launch token address
    function executeSyncAllTokenBalances(
        DataTypes.RewardsStorage storage rewardsStorage,
        mapping(address => uint256) storage accountedBalance,
        address launchToken
    ) public {
        uint256 launchTokenBalance = IERC20(launchToken).balanceOf(address(this));
        if (launchTokenBalance > accountedBalance[launchToken]) {
            accountedBalance[launchToken] = launchTokenBalance;
        }

        for (uint256 i = 0; i < rewardsStorage.rewardTokens.length; ++i) {
            address token = rewardsStorage.rewardTokens[i];
            if (rewardsStorage.rewardTokenInfo[token].active) {
                uint256 actualBalance = IERC20(token).balanceOf(address(this));
                if (actualBalance > accountedBalance[token]) {
                    accountedBalance[token] = actualBalance;
                }
            }
        }
    }
}

