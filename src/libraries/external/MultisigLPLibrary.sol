// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";
import {IDAO} from "../../interfaces/IDAO.sol";
import {INonfungiblePositionManager} from "../../interfaces/INonfungiblePositionManager.sol";
import {IProofOfCapital} from "../../interfaces/IProofOfCapital.sol";
import {IMultisig} from "../../interfaces/IMultisig.sol";
import {DataTypes} from "../DataTypes.sol";
import {Constants} from "../Constants.sol";
import {MultisigSwapLibrary} from "./MultisigSwapLibrary.sol";

/// @title MultisigLPLibrary
/// @notice Library for creating Uniswap V3 LP positions and calling dao.provideLPTokens / extendLock (Multisig context)
library MultisigLPLibrary {
    event LPCreated(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    function executeSwapCollateralToMainAndCreateLPIfReady(
        mapping(address => IMultisig.CollateralInfo) storage collaterals,
        address collateral,
        uint256 collateralBalance,
        address mainCollateral,
        uint256 targetCollateralAmount,
        IDAO dao,
        address positionManager,
        IMultisig.LPPoolConfig[] storage lpPools
    ) external {
        uint256 mainCollateralBalanceAfter = MultisigSwapLibrary.executeSwapCollateralToMain(
            collaterals, collateral, collateralBalance, mainCollateral
        );
        if (mainCollateralBalanceAfter >= targetCollateralAmount) {
            uint256 launchBalance = IERC20(dao.coreConfig().launchToken).balanceOf(address(this));
            _executeCreateUniswapV3LP(dao, positionManager, lpPools, launchBalance, targetCollateralAmount);
        }
    }

    function executeCreateUniswapV3LP(
        IDAO dao,
        address positionManager,
        IMultisig.LPPoolConfig[] storage lpPools,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) external {
        _executeCreateUniswapV3LP(dao, positionManager, lpPools, amount0Desired, amount1Desired);
    }

    function _executeCreateUniswapV3LP(
        IDAO dao,
        address positionManager,
        IMultisig.LPPoolConfig[] storage lpPools,
        uint256 amount0Desired,
        uint256 amount1Desired
    ) internal {
        address token0 = dao.coreConfig().launchToken;
        address token1 = dao.coreConfig().mainCollateral;

        IERC20(token0).approve(positionManager, amount0Desired);
        IERC20(token1).approve(positionManager, amount1Desired);

        uint256 poolsCount = lpPools.length;
        uint256[] memory v3TokenIds = new uint256[](poolsCount);
        uint256 amount0Used;
        uint256 amount1Used;

        for (uint256 i = 0; i < poolsCount; ++i) {
            IMultisig.LPPoolConfig memory config = lpPools[i];
            uint256 amount0;
            uint256 amount1;
            if (i == poolsCount - 1) {
                amount0 = amount0Desired - amount0Used;
                amount1 = amount1Desired - amount1Used;
            } else {
                amount0 = (amount0Desired * config.shareBps) / 10_000;
                amount1 = (amount1Desired * config.shareBps) / 10_000;
                amount0Used += amount0;
                amount1Used += amount1;
            }

            INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
                token0: token0,
                token1: token1,
                fee: config.params.fee,
                tickLower: config.params.tickLower,
                tickUpper: config.params.tickUpper,
                amount0Desired: amount0,
                amount1Desired: amount1,
                amount0Min: config.params.amount0Min,
                amount1Min: config.params.amount1Min,
                recipient: address(this),
                deadline: block.timestamp + 1 hours
            });

            (uint256 tokenId,, uint256 amount0Minted, uint256 amount1Minted) =
                INonfungiblePositionManager(positionManager).mint(params);

            emit LPCreated(tokenId, amount0Minted, amount1Minted);
            IERC721(positionManager).safeTransferFrom(address(this), address(dao), tokenId);
            v3TokenIds[i] = tokenId;
        }

        address[] memory emptyV2Addresses = new address[](0);
        uint256[] memory emptyV2Amounts = new uint256[](0);
        DataTypes.PricePathV2Params[] memory emptyV2Paths = new DataTypes.PricePathV2Params[](0);
        DataTypes.PricePathV3Params[] memory emptyV3Paths = new DataTypes.PricePathV3Params[](0);

        dao.provideLPTokens(emptyV2Addresses, emptyV2Amounts, v3TokenIds, emptyV2Paths, emptyV3Paths);

        uint256 pocContractsCount = dao.getPOCContractsCount();
        uint256 newLockTimestamp = block.timestamp + Constants.LP_EXTEND_LOCK_PERIOD;

        for (uint256 i = 0; i < pocContractsCount; ++i) {
            DataTypes.POCInfo memory pocInfo = dao.getPOCContract(i);
            if (pocInfo.active) {
                IProofOfCapital pocContract = IProofOfCapital(pocInfo.pocContract);
                pocContract.extendLock(newLockTimestamp);
            }
        }
    }
}
