// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IPriceOracle.sol";
import "../DataTypes.sol";
import "../internal/SwapLibrary.sol";
import "../Constants.sol";

/// @title Orderbook Library
/// @notice Library for handling orderbook sell operations with storage parameters
library Orderbook {
    using SafeERC20 for IERC20;

    error CollateralNotSellable();
    error InvalidCollateralPrice();
    error SlippageExceeded();
    error OrderbookNotInitialized();
    error InvalidPrice();
    error StalePrice();
    error InsufficientCollateralReceived(uint256 expected, uint256 received);

    event LaunchTokenSold(
        address indexed seller, address indexed collateral, uint256 launchTokenAmount, uint256 collateralAmount
    );

    /// @notice Execute sell operation
    /// @dev Directly works with contract storage, updates orderbookParams.totalSold and current level
    /// @param params Sell operation parameters
    /// @param coreConfig DAO core config (launchToken, priceOracle)
    /// @param orderbookParams Orderbook parameters from storage (totalSold will be updated)
    /// @param sellableCollaterals Collaterals mapping from storage
    /// @param accountedBalance Accounted balance mapping from storage
    /// @param availableRouterByAdmin Router whitelist mapping from storage
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    function executeSell(
        DataTypes.SellParams memory params,
        DataTypes.CoreConfig storage coreConfig,
        DataTypes.OrderbookParams storage orderbookParams,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        mapping(address => uint256) storage accountedBalance,
        mapping(address => bool) storage availableRouterByAdmin,
        uint256 totalShares,
        uint256 sharePrice
    ) external {
        DataTypes.CollateralInfo storage collateralInfo = sellableCollaterals[params.collateral];

        require(collateralInfo.active, CollateralNotSellable());
        require(orderbookParams.initialPrice > 0, OrderbookNotInitialized());
        uint256 collateralPriceUSD = IPriceOracle(coreConfig.priceOracle).getAssetPrice(params.collateral);
        require(collateralPriceUSD > 0, InvalidCollateralPrice());

        require(availableRouterByAdmin[params.router], SwapLibrary.RouterNotAvailable());
        uint256 balanceBefore = IERC20(params.collateral).balanceOf(address(this));
        SwapLibrary.executeSwap(
            params.router,
            params.swapType,
            params.swapData,
            coreConfig.launchToken,
            params.collateral,
            params.launchTokenAmount,
            params.minCollateralAmount
        );

        uint256 balanceAfter = IERC20(params.collateral).balanceOf(address(this));
        uint256 receivedCollateral = balanceAfter - balanceBefore;

        uint256 receivedCollateralInUsd =
            (receivedCollateral * collateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

        orderbookParams.totalSold += params.launchTokenAmount;

        accountedBalance[coreConfig.launchToken] -= params.launchTokenAmount;

        updateCurrentLevel(orderbookParams, receivedCollateralInUsd, params.launchTokenAmount, totalShares, sharePrice);

        emit LaunchTokenSold(msg.sender, params.collateral, params.launchTokenAmount, receivedCollateral);
    }

    /// @notice Update current level after selling launch tokens
    /// @dev Calculates expected USD from selling tokens across levels and validates received amount
    /// @param orderbookParams Orderbook parameters from storage (will be updated)
    /// @param receivedCollateralInUsd Amount of USD received from the sale
    /// @param launchTokenAmount Amount of launch tokens sold
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD with 18 decimals
    function updateCurrentLevel(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256 receivedCollateralInUsd,
        uint256 launchTokenAmount,
        uint256 totalShares,
        uint256 sharePrice
    ) internal {
        uint256 proportionalityCoefficient = orderbookParams.proportionalityCoefficient; // in basis points (7500 = 0.75)
        uint256 totalSupply = orderbookParams.totalSupply; // total supply
        uint256 priceStepPercent = orderbookParams.priceStepPercent; // in basis points (500 = 5%)
        int256 volumeStepPercent = orderbookParams.volumeStepPercent; // in basis points (-100 = -1%)

        // Current level state
        uint256 currentLevel = orderbookParams.currentLevel;
        uint256 currentPrice = orderbookParams.cachedPriceAtLevel; // price at current level
        uint256 currentBaseVolume = orderbookParams.cachedBaseVolumeAtLevel; // base volume at current level

        // Track expected USD and remaining tokens to process
        uint256 expectedUsd = 0;
        uint256 remainingTokens = launchTokenAmount;

        uint256 soldOnCurrentLevel = orderbookParams.currentCumulativeVolume;
        while (remainingTokens > 0) {
            // Calculate adjusted level volume
            // All values need to be scaled properly:
            // - currentBaseVolume is in token units (18 decimals)
            // - proportionalityCoefficient is in basis points (10000 = 100%)
            // - sharePrice is in USD (18 decimals)
            // - totalSupply is in token units (18 decimals)
            uint256 adjustedLevelVolume = currentBaseVolume * proportionalityCoefficient * totalShares
                / (totalSupply * Constants.BASIS_POINTS) * sharePrice / Constants.PRICE_DECIMALS_MULTIPLIER;

            uint256 tokensRemainingOnLevel =
                adjustedLevelVolume > soldOnCurrentLevel ? adjustedLevelVolume - soldOnCurrentLevel : 0;

            if (remainingTokens <= tokensRemainingOnLevel) {
                expectedUsd += (remainingTokens * currentPrice) / Constants.PRICE_DECIMALS_MULTIPLIER;
                soldOnCurrentLevel += remainingTokens;
                remainingTokens = 0;
            } else {
                if (tokensRemainingOnLevel > 0) {
                    expectedUsd += (tokensRemainingOnLevel * currentPrice) / Constants.PRICE_DECIMALS_MULTIPLIER;
                    remainingTokens -= tokensRemainingOnLevel;
                }

                currentLevel += 1;
                soldOnCurrentLevel = 0;

                // Update price: price1 = price0 * (1 + priceStepPercent) = price0 * (10000 + priceStepPercent) / 10000
                currentPrice = (currentPrice * (Constants.BASIS_POINTS + priceStepPercent)) / Constants.BASIS_POINTS;

                // Update base volume: volume1 = volume0 * (1 + volumeStepPercent)
                // Note: volumeStepPercent can be negative
                if (volumeStepPercent >= 0) {
                    currentBaseVolume = (currentBaseVolume * (Constants.BASIS_POINTS + uint256(volumeStepPercent)))
                        / Constants.BASIS_POINTS;
                } else {
                    uint256 absVolumeStep = uint256(-volumeStepPercent);
                    currentBaseVolume =
                        (currentBaseVolume * (Constants.BASIS_POINTS - absVolumeStep)) / Constants.BASIS_POINTS;
                }
            }
        }

        require(
            receivedCollateralInUsd >= expectedUsd, InsufficientCollateralReceived(expectedUsd, receivedCollateralInUsd)
        );

        orderbookParams.currentLevel = currentLevel;
        orderbookParams.currentCumulativeVolume = soldOnCurrentLevel;
        orderbookParams.cachedPriceAtLevel = currentPrice;
        orderbookParams.cachedBaseVolumeAtLevel = currentBaseVolume;
        orderbookParams.currentTotalSold = orderbookParams.totalSold;
    }
}

