// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM

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

// This is the third version of the contract. It introduces the following features: the ability to choose any jetcollateral as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
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

    // Constants
    uint256 public constant PRICE_DECIMALS = 18;
    uint256 public constant PRICE_DECIMALS_MULTIPLIER = 1e18; // 10 ** PRICE_DECIMALS

    // Custom errors
    error CollateralNotSellable();
    error InvalidCollateralPrice();
    error SlippageExceeded();
    error OrderbookNotInitialized();
    error InvalidPrice();

    // Events
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
    /// @return result Sell operation result
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
    ) internal returns (DataTypes.SellResult memory result) {
        // Get collateral info from storage
        DataTypes.CollateralInfo storage collateralInfo = sellableCollaterals[params.collateral];

        // Validate collateral is active
        require(collateralInfo.active, CollateralNotSellable());
        require(orderbookParams.initialPrice > 0, OrderbookNotInitialized());

        // Get collateral price in USD
        uint256 collateralPriceUSD = getCollateralPrice(collateralInfo);
        require(collateralPriceUSD > 0, InvalidCollateralPrice());

        // Calculate collateral amount considering different prices at each level
        uint256 collateralAmount = calculateCollateralAmountWithLevels(
            orderbookParams,
            orderbookParams.totalSold,
            params.launchTokenAmount,
            collateralPriceUSD,
            totalShares,
            sharePrice
        );

        require(collateralAmount >= params.minCollateralAmount, SlippageExceeded());

        // Transfer launch tokens from seller
        launchToken.safeTransferFrom(params.seller, contractAddress, params.launchTokenAmount);

        // Verify router is available before swap
        require(availableRouterByAdmin[params.router], OrderbookSwapLibrary.RouterNotAvailable());

        // Execute swap using router
        uint256 receivedCollateral = OrderbookSwapLibrary.executeSwap(
            params.router,
            params.swapType,
            params.swapData,
            address(launchToken),
            params.collateral,
            params.launchTokenAmount,
            params.minCollateralAmount,
            contractAddress
        );

        // Track accounted balance (will be distributed via distributeProfit)
        accountedBalance[params.collateral] += receivedCollateral;

        // Update total sold and current level (all in one place)
        orderbookParams.totalSold += params.launchTokenAmount;
        updateCurrentLevel(orderbookParams, orderbookParams.totalSold, totalShares, sharePrice);

        // Emit event
        emit LaunchTokenSold(params.seller, params.collateral, params.launchTokenAmount, receivedCollateral);

        // Return result with actual collateral amount received
        result = DataTypes.SellResult({
            collateralAmount: receivedCollateral,
            currentPrice: 0 // Price is not relevant, we return collateral amount
        });

        return result;
    }

    /// @notice Calculate collateral amount considering different prices at each level
    /// @dev Optimized to O(L) where L is number of levels traversed (uses incremental calculation)
    /// @param orderbookParams Orderbook parameters from storage
    /// @param totalSold Total amount of tokens sold before this operation
    /// @param launchTokenAmount Amount of launch tokens to sell
    /// @param collateralPriceUSD Price of collateral in USD (18 decimals)
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    /// @return Total collateral amount that can be received (considering all levels)
    function calculateCollateralAmountWithLevels(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256 totalSold,
        uint256 launchTokenAmount,
        uint256 collateralPriceUSD,
        uint256 totalShares,
        uint256 sharePrice
    ) internal view returns (uint256) {
        // Use struct to avoid stack too deep
        DataTypes.OrderbookCalcState memory state = _initCalcState(orderbookParams, totalSold, totalShares, sharePrice);

        uint256 remainingTokens = launchTokenAmount;
        uint256 totalValueUSD = 0;
        uint256 currentSold = totalSold;

        // Advance to correct starting level if needed (incremental, not from scratch)
        while (currentSold >= state.levelEndVolume && remainingTokens > 0) {
            _advanceToNextLevel(state);
        }

        // Iterate through levels until all tokens are sold
        while (remainingTokens > 0) {
            // Calculate how many tokens can be sold at this level
            uint256 tokensSoldAtCurrentLevel =
                currentSold > state.cumulativeVolumeBeforeLevel ? currentSold - state.cumulativeVolumeBeforeLevel : 0;
            uint256 availableAtLevel = state.adjustedLevelVolume - tokensSoldAtCurrentLevel;
            uint256 tokensAtCurrentLevel = remainingTokens < availableAtLevel ? remainingTokens : availableAtLevel;

            // Calculate value in USD for tokens at this level
            totalValueUSD += (tokensAtCurrentLevel * state.currentPrice) / PRICE_DECIMALS_MULTIPLIER;

            remainingTokens -= tokensAtCurrentLevel;
            currentSold += tokensAtCurrentLevel;

            // Move to next level if current level is exhausted
            if (currentSold >= state.levelEndVolume && remainingTokens > 0) {
                _advanceToNextLevel(state);
            }
        }

        // Convert total USD value to collateral amount
        return (totalValueUSD * PRICE_DECIMALS_MULTIPLIER) / collateralPriceUSD;
    }

    /// @notice Initialize calculation state from cached values or from scratch
    function _initCalcState(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256 totalSold,
        uint256 totalShares,
        uint256 sharePrice
    ) internal view returns (DataTypes.OrderbookCalcState memory state) {
        // Prepare multipliers for incremental calculation
        int256 volumeStep = orderbookParams.volumeStepPercent;
        state.priceBase = 10000 + orderbookParams.priceStepPercent;
        state.volumeBase = volumeStep >= 0 ? 10000 + uint256(volumeStep) : uint256(int256(10000) + volumeStep);

        // Shares adjustment factor (calculated once)
        state.sharesNumerator = orderbookParams.proportionalityCoefficient * totalShares * sharePrice;
        state.sharesDenominator = orderbookParams.totalSupply * 10000;

        // Try to use cached values if available and valid
        if (orderbookParams.currentTotalSold > 0 && totalSold >= orderbookParams.currentCumulativeVolume) {
            state.currentLevel = orderbookParams.currentLevel;
            state.cumulativeVolumeBeforeLevel = orderbookParams.currentCumulativeVolume;
            state.currentBaseVolume = orderbookParams.cachedBaseVolumeAtLevel;
            state.currentPrice = orderbookParams.cachedPriceAtLevel;

            // If cache is not initialized, calculate from scratch
            if (state.currentBaseVolume == 0 || state.currentPrice == 0) {
                state.currentBaseVolume = getVolumeAtLevel(orderbookParams, state.currentLevel);
                state.currentPrice = getPriceAtLevel(orderbookParams, state.currentLevel);
            }
        } else {
            // Start from level 0
            state.currentLevel = 0;
            state.cumulativeVolumeBeforeLevel = 0;
            state.currentBaseVolume = orderbookParams.initialVolume;
            state.currentPrice = orderbookParams.initialPrice;
        }

        state.adjustedLevelVolume = (state.currentBaseVolume * state.sharesNumerator) / state.sharesDenominator;
        state.levelEndVolume = state.cumulativeVolumeBeforeLevel + state.adjustedLevelVolume;

        return state;
    }

    /// @notice Advance calculation state to next level (incremental O(1) calculation)
    function _advanceToNextLevel(DataTypes.OrderbookCalcState memory state) internal pure {
        state.cumulativeVolumeBeforeLevel = state.levelEndVolume;
        state.currentLevel++;
        state.currentBaseVolume = (state.currentBaseVolume * state.volumeBase) / 10000;
        state.currentPrice = (state.currentPrice * state.priceBase) / 10000;
        state.adjustedLevelVolume = (state.currentBaseVolume * state.sharesNumerator) / state.sharesDenominator;
        state.levelEndVolume = state.cumulativeVolumeBeforeLevel + state.adjustedLevelVolume;
    }

    /// @notice Get current price based on orderbook state
    /// @param orderbookParams Orderbook parameters from storage
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    /// @return Current price in USD (18 decimals)
    function getCurrentPrice(DataTypes.OrderbookParams storage orderbookParams, uint256 totalShares, uint256 sharePrice)
        internal
        view
        returns (uint256)
    {
        if (orderbookParams.initialPrice == 0) return 0;

        // Use cached level if totalSold matches currentTotalSold, otherwise recalculate
        uint256 currentLevel = getCurrentLevel(orderbookParams, orderbookParams.totalSold, totalShares, sharePrice);
        return getPriceAtLevel(orderbookParams, currentLevel);
    }

    /// @notice Get collateral price from Chainlink oracle
    /// @param collateralInfo Information about the collateral from storage
    /// @return Price in USD (18 decimals)
    function getCollateralPrice(DataTypes.CollateralInfo storage collateralInfo) internal view returns (uint256) {
        IAggregatorV3 priceFeed = IAggregatorV3(collateralInfo.priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, InvalidPrice());

        uint8 decimals = priceFeed.decimals();

        // Normalize to 18 decimals
        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    /// @notice Get current level based on total sold (uses cached value if totalSold matches currentTotalSold)
    /// @dev Optimized to O(levels_advanced) using incremental calculation from cached values
    /// @param orderbookParams Orderbook parameters from storage
    /// @param totalSold Total amount of tokens sold (should match currentTotalSold for cache hit)
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    /// @return Current level
    function getCurrentLevel(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256 totalSold,
        uint256 totalShares,
        uint256 sharePrice
    ) internal view returns (uint256) {
        if (orderbookParams.initialVolume == 0) return 0;

        // If currentTotalSold is set and matches totalSold, return cached level - O(1)
        if (orderbookParams.currentTotalSold > 0 && totalSold == orderbookParams.currentTotalSold) {
            return orderbookParams.currentLevel;
        }

        // Initialize from cached values or from scratch
        uint256 level;
        uint256 cumulativeVolume;
        uint256 currentBaseVolume;

        if (orderbookParams.currentTotalSold > 0 && totalSold > orderbookParams.currentTotalSold) {
            // Continue from cached position - O(levels_advanced) instead of O(total_levels)
            level = orderbookParams.currentLevel;
            cumulativeVolume = orderbookParams.currentCumulativeVolume;
            currentBaseVolume = orderbookParams.cachedBaseVolumeAtLevel;
            if (currentBaseVolume == 0) {
                currentBaseVolume = getVolumeAtLevel(orderbookParams, level);
            }
        } else {
            // Start from beginning
            level = 0;
            cumulativeVolume = 0;
            currentBaseVolume = orderbookParams.initialVolume;
        }

        // Prepare multipliers for incremental calculation
        int256 volumeStep = orderbookParams.volumeStepPercent;
        uint256 volumeBase = volumeStep >= 0 ? 10000 + uint256(volumeStep) : uint256(int256(10000) + volumeStep);

        // Shares adjustment factor
        uint256 sharesNumerator = orderbookParams.proportionalityCoefficient * totalShares * sharePrice;
        uint256 sharesDenominator = orderbookParams.totalSupply * 10000;

        // Calculate level using incremental volume calculation - O(levels_advanced)
        while (cumulativeVolume < totalSold) {
            uint256 adjustedLevelVolume = (currentBaseVolume * sharesNumerator) / sharesDenominator;
            if (cumulativeVolume + adjustedLevelVolume > totalSold) {
                break;
            }
            cumulativeVolume += adjustedLevelVolume;
            level++;
            // Calculate next base volume incrementally: O(1) per iteration
            currentBaseVolume = (currentBaseVolume * volumeBase) / 10000;
        }

        return level;
    }

    /// @notice Update current level (should be called after totalSold changes)
    /// @dev Optimized to O(levels_advanced) using incremental calculation from cached values
    /// @param orderbookParams Orderbook parameters from storage
    /// @param totalSold Total amount of tokens sold (should equal orderbookParams.totalSold)
    /// @param totalShares Total shares supply
    /// @param sharePrice Share price in USD (18 decimals)
    function updateCurrentLevel(
        DataTypes.OrderbookParams storage orderbookParams,
        uint256 totalSold,
        uint256 totalShares,
        uint256 sharePrice
    ) internal {
        if (orderbookParams.initialVolume == 0) {
            orderbookParams.currentLevel = 0;
            orderbookParams.currentTotalSold = totalSold;
            orderbookParams.currentCumulativeVolume = 0;
            orderbookParams.cachedBaseVolumeAtLevel = 0;
            orderbookParams.cachedPriceAtLevel = 0;
            return;
        }

        uint256 level;
        uint256 cumulativeVolume;
        uint256 currentBaseVolume;
        uint256 currentPrice;

        // Prepare multipliers for incremental calculation
        int256 volumeStep = orderbookParams.volumeStepPercent;
        uint256 volumeBase = volumeStep >= 0 ? 10000 + uint256(volumeStep) : uint256(int256(10000) + volumeStep);
        uint256 priceBase = 10000 + orderbookParams.priceStepPercent;

        // Shares adjustment factor
        uint256 sharesNumerator = orderbookParams.proportionalityCoefficient * totalShares * sharePrice;
        uint256 sharesDenominator = orderbookParams.totalSupply * 10000;

        // Use existing current level if valid to optimize calculation - O(levels_advanced)
        if (orderbookParams.currentTotalSold > 0 && totalSold >= orderbookParams.currentTotalSold) {
            level = orderbookParams.currentLevel;
            cumulativeVolume = orderbookParams.currentCumulativeVolume;
            currentBaseVolume = orderbookParams.cachedBaseVolumeAtLevel;
            currentPrice = orderbookParams.cachedPriceAtLevel;

            if (currentBaseVolume == 0) {
                currentBaseVolume = getVolumeAtLevel(orderbookParams, level);
            }
            if (currentPrice == 0) {
                currentPrice = getPriceAtLevel(orderbookParams, level);
            }

            // Continue from current position using incremental calculation
            while (cumulativeVolume < totalSold) {
                uint256 adjustedLevelVolume = (currentBaseVolume * sharesNumerator) / sharesDenominator;
                if (cumulativeVolume + adjustedLevelVolume > totalSold) {
                    break;
                }
                cumulativeVolume += adjustedLevelVolume;
                level++;
                // Calculate next values incrementally: O(1) per iteration
                currentBaseVolume = (currentBaseVolume * volumeBase) / 10000;
                currentPrice = (currentPrice * priceBase) / 10000;
            }
        } else {
            // Current level is invalid or not initialized, calculate from scratch
            level = 0;
            cumulativeVolume = 0;
            currentBaseVolume = orderbookParams.initialVolume;
            currentPrice = orderbookParams.initialPrice;

            while (cumulativeVolume < totalSold) {
                uint256 adjustedLevelVolume = (currentBaseVolume * sharesNumerator) / sharesDenominator;
                if (cumulativeVolume + adjustedLevelVolume > totalSold) {
                    break;
                }
                cumulativeVolume += adjustedLevelVolume;
                level++;
                // Calculate next values incrementally: O(1) per iteration
                currentBaseVolume = (currentBaseVolume * volumeBase) / 10000;
                currentPrice = (currentPrice * priceBase) / 10000;
            }
        }

        // Update current level - ensure currentTotalSold always equals totalSold for synchronization
        orderbookParams.currentLevel = level;
        orderbookParams.currentTotalSold = totalSold;
        orderbookParams.currentCumulativeVolume = cumulativeVolume;

        // Store cached values for O(1) access - already calculated in the loop above
        orderbookParams.cachedBaseVolumeAtLevel = currentBaseVolume;
        orderbookParams.cachedPriceAtLevel = currentPrice;
    }

    /// @notice Get price at specific level
    /// @dev Multiplicative formula: priceAtLevel(level) = initialPrice * (1 + priceStepPercent)^level
    ///      Optimized to calculate from previous level if cached
    /// @param orderbookParams Orderbook parameters from storage
    /// @param level Level number
    /// @return Price at the level
    function getPriceAtLevel(DataTypes.OrderbookParams storage orderbookParams, uint256 level)
        internal
        view
        returns (uint256)
    {
        if (level == 0) {
            return orderbookParams.initialPrice;
        }

        // Prepare base multiplier for price step
        uint256 priceBase = 10000 + orderbookParams.priceStepPercent;

        // Optimization: use cached value if available and calculating next level
        if (level == orderbookParams.currentLevel + 1 && orderbookParams.cachedPriceAtLevel > 0) {
            // Calculate from previous level: priceAtLevel(level) = priceAtLevel(level-1) * (1 + priceStepPercent)
            return (orderbookParams.cachedPriceAtLevel * priceBase) / 10000;
        }

        // Optimization: use cached value if calculating same level
        if (level == orderbookParams.currentLevel && orderbookParams.cachedPriceAtLevel > 0) {
            return orderbookParams.cachedPriceAtLevel;
        }

        // Calculate from cached level if possible (level > currentLevel)
        if (level > orderbookParams.currentLevel && orderbookParams.cachedPriceAtLevel > 0) {
            uint256 price = orderbookParams.cachedPriceAtLevel;
            for (uint256 i = orderbookParams.currentLevel; i < level; i++) {
                price = (price * priceBase) / 10000;
            }
            return price;
        }

        // Fallback: calculate from scratch
        // Calculate (1 + priceStepPercent)^level
        // priceStepPercent is in basis points (500 = 5%)
        // Formula: initialPrice * (10000 + priceStepPercent)^level / 10000^level
        uint256 multiplier = PRICE_DECIMALS_MULTIPLIER;

        for (uint256 i = 0; i < level; i++) {
            multiplier = (multiplier * priceBase) / 10000;
        }

        return (orderbookParams.initialPrice * multiplier) / PRICE_DECIMALS_MULTIPLIER;
    }

    /// @notice Get base volume at specific level (without shares adjustment)
    /// @dev Multiplicative formula: baseLevelVolume(level) = initialVolume * (1 + volumeStepPercent)^level
    ///      Optimized to calculate from previous level if cached
    /// @param orderbookParams Orderbook parameters from storage
    /// @param level Level number
    /// @return Base volume at the level
    function getVolumeAtLevel(DataTypes.OrderbookParams storage orderbookParams, uint256 level)
        internal
        view
        returns (uint256)
    {
        if (level == 0) {
            return orderbookParams.initialVolume;
        }

        // Prepare base multiplier for volume step
        int256 volumeStep = orderbookParams.volumeStepPercent;
        uint256 base;
        if (volumeStep >= 0) {
            base = 10000 + uint256(volumeStep);
        } else {
            // For negative, we need to handle it carefully
            // (10000 + (-100)) = 9900, which represents 0.99
            base = uint256(int256(10000) + volumeStep);
        }

        // Optimization: use cached value if available and calculating next level
        if (level == orderbookParams.currentLevel + 1 && orderbookParams.cachedBaseVolumeAtLevel > 0) {
            // Calculate from previous level: baseLevelVolume(level) = baseLevelVolume(level-1) * (1 + volumeStepPercent)
            return (orderbookParams.cachedBaseVolumeAtLevel * base) / 10000;
        }

        // Optimization: use cached value if calculating same level
        if (level == orderbookParams.currentLevel && orderbookParams.cachedBaseVolumeAtLevel > 0) {
            return orderbookParams.cachedBaseVolumeAtLevel;
        }

        // Calculate from cached level if possible (level > currentLevel)
        if (level > orderbookParams.currentLevel && orderbookParams.cachedBaseVolumeAtLevel > 0) {
            uint256 volume = orderbookParams.cachedBaseVolumeAtLevel;
            for (uint256 i = orderbookParams.currentLevel; i < level; i++) {
                volume = (volume * base) / 10000;
            }
            return volume;
        }

        // Fallback: calculate from scratch
        // Calculate (1 + volumeStepPercent)^level
        // volumeStepPercent is in basis points and can be negative (-100 = -1%)
        // Formula: initialVolume * (10000 + volumeStepPercent)^level / 10000^level
        uint256 multiplier = PRICE_DECIMALS_MULTIPLIER;

        for (uint256 i = 0; i < level; i++) {
            multiplier = (multiplier * base) / 10000;
        }

        return (orderbookParams.initialVolume * multiplier) / PRICE_DECIMALS_MULTIPLIER;
    }
}

