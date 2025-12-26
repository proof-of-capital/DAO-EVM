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

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IAggregatorV3.sol";
import "./DataTypes.sol";
import "./OrderbookSwapLibrary.sol";

/// @title Orderbook Library
/// @notice Library for handling orderbook sell operations with storage parameters
library Orderbook {
    using SafeERC20 for IERC20;

    uint256 public constant PRICE_DECIMALS = 18;
    uint256 public constant PRICE_DECIMALS_MULTIPLIER = 1e18;
    uint256 public constant BASIS_POINTS = 10000;

    error CollateralNotSellable();
    error InvalidCollateralPrice();
    error SlippageExceeded();
    error OrderbookNotInitialized();
    error InvalidPrice();
    error InsufficientCollateralReceived(uint256 expected, uint256 received);

    event LaunchTokenSold(
        address indexed seller, address indexed collateral, uint256 launchTokenAmount, uint256 collateralAmount
    );

    /// @notice Execute sell operation
    /// @dev Directly works with contract storage, updates orderbookParams.totalSold and current level
    /// @param params Sell operation parameters
    /// @param contractAddress Address of the contract executing the swap (for library context)
    /// @param launchToken Launch token reference from storage
    /// @param orderbookParams Orderbook parameters from storage (totalSold will be updated)
    /// @param sellableCollaterals Collaterals mapping from storage
    /// @param accountedBalance Accounted balance mapping from storage
    /// @param availableRouterByAdmin Router whitelist mapping from storage
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    function executeSell(
        DataTypes.SellParams memory params,
        address contractAddress,
        IERC20 launchToken,
        DataTypes.OrderbookParams storage orderbookParams,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        mapping(address => uint256) storage accountedBalance,
        mapping(address => bool) storage availableRouterByAdmin,
        uint256 totalShares,
        uint256 sharePrice
    ) internal {
        DataTypes.CollateralInfo storage collateralInfo = sellableCollaterals[params.collateral];

        require(collateralInfo.active, CollateralNotSellable());
        require(orderbookParams.initialPrice > 0, OrderbookNotInitialized());
        uint256 collateralPriceUSD = getCollateralPrice(collateralInfo);
        require(collateralPriceUSD > 0, InvalidCollateralPrice());

        require(availableRouterByAdmin[params.router], OrderbookSwapLibrary.RouterNotAvailable());
        uint256 balanceBefore = IERC20(params.collateral).balanceOf(address(this));
        OrderbookSwapLibrary.executeSwap(
            params.router,
            params.swapType,
            params.swapData,
            address(launchToken),
            params.collateral,
            params.launchTokenAmount,
            params.minCollateralAmount,
            contractAddress
        );

        uint256 balanceAfter = IERC20(params.collateral).balanceOf(address(this));
        uint256 receivedCollateral = balanceAfter - balanceBefore;

        accountedBalance[params.collateral] += receivedCollateral;

        uint256 receivedCollateralInUsd = (receivedCollateral * collateralPriceUSD) / PRICE_DECIMALS_MULTIPLIER;

        orderbookParams.totalSold += params.launchTokenAmount;

        accountedBalance[address(launchToken)] -= params.launchTokenAmount;

        updateCurrentLevel(orderbookParams, receivedCollateralInUsd, params.launchTokenAmount, totalShares, sharePrice);

        emit LaunchTokenSold(params.seller, params.collateral, params.launchTokenAmount, receivedCollateral);
    }

    /// @notice Get collateral price from Chainlink oracle
    /// @param collateralInfo Information about the collateral from storage
    /// @return Price in USD (18 decimals)
    function getCollateralPrice(DataTypes.CollateralInfo storage collateralInfo) internal view returns (uint256) {
        IAggregatorV3 priceFeed = IAggregatorV3(collateralInfo.priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, InvalidPrice());

        uint8 decimals = priceFeed.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
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
        uint256 proportionalityCoefficient = orderbookParams.proportionalityCoefficient; // КП in basis points (7500 = 0.75)
        uint256 totalSupply = orderbookParams.totalSupply; // С - total supply
        uint256 priceStepPercent = orderbookParams.priceStepPercent; // ШПЦ in basis points (500 = 5%)
        int256 volumeStepPercent = orderbookParams.volumeStepPercent; // ШПРУ in basis points (-100 = -1%)

        // Current level state
        uint256 currentLevel = orderbookParams.currentLevel;
        uint256 cumulativeVolume = orderbookParams.currentCumulativeVolume;
        uint256 currentPrice = orderbookParams.cachedPriceAtLevel; // ЦУ - price at current level
        uint256 currentBaseVolume = orderbookParams.cachedBaseVolumeAtLevel; // ТРУ - base volume at current level

        // Track expected USD and remaining tokens to process
        uint256 expectedUsd = 0;
        uint256 remainingTokens = launchTokenAmount;

        uint256 totalSoldBeforeSale = orderbookParams.totalSold - launchTokenAmount;
        uint256 soldOnCurrentLevel = totalSoldBeforeSale > cumulativeVolume ? totalSoldBeforeSale - cumulativeVolume : 0;

        while (remainingTokens > 0) {
            // Calculate adjusted level volume: вТРУ = ТРУ * КП * КШ * СШ / С
            // All values need to be scaled properly:
            // - currentBaseVolume is in token units (18 decimals)
            // - proportionalityCoefficient is in basis points (10000 = 100%)
            // - sharePrice is in USD (18 decimals)
            // - totalSupply is in token units (18 decimals)
            uint256 adjustedLevelVolume = (currentBaseVolume * proportionalityCoefficient * totalShares * sharePrice)
                / (totalSupply * BASIS_POINTS * PRICE_DECIMALS_MULTIPLIER);

            uint256 tokensRemainingOnLevel =
                adjustedLevelVolume > soldOnCurrentLevel ? adjustedLevelVolume - soldOnCurrentLevel : 0;

            if (remainingTokens <= tokensRemainingOnLevel) {
                expectedUsd += (remainingTokens * currentPrice) / PRICE_DECIMALS_MULTIPLIER;
                soldOnCurrentLevel += remainingTokens;
                remainingTokens = 0;
            } else {
                if (tokensRemainingOnLevel > 0) {
                    expectedUsd += (tokensRemainingOnLevel * currentPrice) / PRICE_DECIMALS_MULTIPLIER;
                    remainingTokens -= tokensRemainingOnLevel;
                }

                currentLevel += 1;
                cumulativeVolume += adjustedLevelVolume;
                soldOnCurrentLevel = 0;

                // Update price: ЦУ1 = ЦУ0 * (1 + ШПЦ) = ЦУ0 * (10000 + priceStepPercent) / 10000
                currentPrice = (currentPrice * (BASIS_POINTS + priceStepPercent)) / BASIS_POINTS;

                // Update base volume: ТРУ1 = ТРУ0 * (1 + ШПРУ)
                // Note: volumeStepPercent can be negative
                if (volumeStepPercent >= 0) {
                    currentBaseVolume = (currentBaseVolume * (BASIS_POINTS + uint256(volumeStepPercent))) / BASIS_POINTS;
                } else {
                    uint256 absVolumeStep = uint256(-volumeStepPercent);
                    currentBaseVolume = (currentBaseVolume * (BASIS_POINTS - absVolumeStep)) / BASIS_POINTS;
                }
            }
        }

        require(
            receivedCollateralInUsd >= expectedUsd, InsufficientCollateralReceived(expectedUsd, receivedCollateralInUsd)
        );

        orderbookParams.currentLevel = currentLevel;
        orderbookParams.currentCumulativeVolume = cumulativeVolume;
        orderbookParams.cachedPriceAtLevel = currentPrice;
        orderbookParams.cachedBaseVolumeAtLevel = currentBaseVolume;
        orderbookParams.currentTotalSold = orderbookParams.totalSold;
    }

    /// @notice Get current price based on orderbook state
    /// @dev Returns cached price at current level, which is updated on each sale
    /// @param orderbookParams Orderbook parameters from storage
    /// @return Current price in USD (18 decimals)
    function getCurrentPrice(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256,
        /* totalShares */
        uint256 /* sharePrice */
    )
        internal
        view
        returns (uint256)
    {
        require(orderbookParams.initialPrice > 0, OrderbookNotInitialized());
        return orderbookParams.cachedPriceAtLevel;
    }
}

