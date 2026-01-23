// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "../../interfaces/IAggregatorV3.sol";
import "../../interfaces/IProofOfCapital.sol";
import "../../interfaces/IQuoterV2.sol";
import "../../interfaces/IUniswapV2Router01.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IUniswapV2Factory.sol";
import "../DataTypes.sol";
import "../Constants.sol";

/// @title OracleLibrary
/// @notice Library for oracle price operations and pool price validation
library OracleLibrary {
    error InvalidPrice();
    error StalePrice();
    error CollateralNotActive();
    error NoPOCContracts();
    error PriceDeviationTooHigh();
    error InvalidPricePath();

    event PriceValidated(uint256 oraclePrice, uint256 poolPrice, uint256 deviationBp);

    /// @notice Get price from Chainlink aggregator and normalize to 18 decimals (internal)
    /// @param priceFeed Address of Chainlink price feed aggregator
    /// @return Price in USD (18 decimals)
    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IAggregatorV3 aggregator = IAggregatorV3(priceFeed);
        (, int256 price,, uint256 updatedAt,) = aggregator.latestRoundData();
        require(price > 0, InvalidPrice());
        require(block.timestamp - updatedAt <= Constants.ORACLE_MAX_AGE, StalePrice());

        uint8 decimals = aggregator.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    /// @notice Get price from Chainlink aggregator and normalize to 18 decimals (external)
    /// @param priceFeed Address of Chainlink price feed aggregator
    /// @return Price in USD (18 decimals)
    function getChainlinkPrice(address priceFeed) external view returns (uint256) {
        return _getChainlinkPrice(priceFeed);
    }

    /// @notice Get oracle price for a collateral token
    /// @param sellableCollaterals Mapping of collateral info
    /// @param token Collateral token address
    /// @return Price in USD (18 decimals)
    function getOraclePrice(mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals, address token)
        external
        view
        returns (uint256)
    {
        DataTypes.CollateralInfo storage info = sellableCollaterals[token];
        require(info.active, CollateralNotActive());
        return _getChainlinkPrice(info.priceFeed);
    }

    /// @notice Get weighted average launch token price from all active POC contracts with pool validation
    /// @param pocContracts Array of POC contracts
    /// @param pricePathsStorage Price paths storage for pool validation
    /// @param launchToken Launch token address
    /// @param sellableCollaterals Mapping of collateral info
    /// @return Weighted average launch price in USD (18 decimals)
    function _getLaunchPriceFromPOC(
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        address launchToken,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals
    ) internal returns (uint256) {
        uint256 totalWeightedPrice = 0;
        uint256 totalSharePercent = 0;

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (!poc.active) {
                continue;
            }

            uint256 launchPriceInCollateral = IProofOfCapital(poc.pocContract).currentPrice();

            if (launchPriceInCollateral == 0) {
                continue;
            }

            uint256 collateralPriceUSD = _getChainlinkPrice(poc.priceFeed);

            if (collateralPriceUSD == 0) {
                continue;
            }

            uint256 launchPriceUSD =
                (launchPriceInCollateral * collateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

            if (launchPriceUSD == 0) {
                continue;
            }

            totalWeightedPrice += (launchPriceUSD * poc.sharePercent);
            totalSharePercent += poc.sharePercent;
        }

        require(totalSharePercent > 0, NoPOCContracts());
        uint256 oraclePrice = totalWeightedPrice / totalSharePercent;

        _validatePoolPriceInternal(pricePathsStorage, launchToken, sellableCollaterals, oraclePrice);

        return oraclePrice;
    }

    /// @notice Get price for any token - handles launch token via POC and collaterals via Chainlink
    /// @param sellableCollaterals Mapping of collateral info
    /// @param pocContracts Array of POC contracts
    /// @param pricePathsStorage Price paths storage for pool validation
    /// @param launchToken Launch token address
    /// @param token Token address to get price for
    /// @return Price in USD (18 decimals)
    function getPrice(
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        address launchToken,
        address token
    ) external returns (uint256) {
        if (token == launchToken) {
            return _getLaunchPriceFromPOC(pocContracts, pricePathsStorage, launchToken, sellableCollaterals);
        }

        DataTypes.CollateralInfo storage info = sellableCollaterals[token];
        require(info.active, CollateralNotActive());
        return _getChainlinkPrice(info.priceFeed);
    }

    /// @notice Calculate price deviation in basis points
    /// @dev Only checks deviation when actual < expected (unfavorable rate)
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @return Deviation in basis points (0 if actual >= expected)
    function calculateDeviation(uint256 expected, uint256 actual) external pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) {
            return 0;
        } else {
            return ((expected - actual) * Constants.BASIS_POINTS) / expected;
        }
    }

    /// @notice Get price from V2 pool via router getAmountsOut
    function getPoolPriceV2(address router, address[] memory path, uint256 amountIn)
        internal
        view
        returns (uint256 amountOut)
    {
        if (path.length < 2) {
            return 0;
        }

        try IUniswapV2Router01(router).getAmountsOut(amountIn, path) returns (uint256[] memory amounts) {
            amountOut = amounts[amounts.length - 1];
        } catch {
            amountOut = 0;
        }
    }

    /// @notice Get price from V3 pool via QuoterV2 quoteExactInput
    function getPoolPriceV3(address quoter, bytes memory path, uint256 amountIn) internal returns (uint256 amountOut) {
        if (path.length == 0) {
            return 0;
        }

        try IQuoterV2(quoter).quoteExactInput(path, amountIn) returns (
            uint256 _amountOut, uint160[] memory, uint32[] memory, uint256
        ) {
            amountOut = _amountOut;
        } catch {
            amountOut = 0;
        }
    }

    /// @notice Get V2 pair liquidity in terms of launch token
    function getLiquidityV2(address router, address tokenA, address tokenB, address launchToken)
        internal
        view
        returns (uint256 liquidity)
    {
        address factory = IUniswapV2Router01(router).factory();
        address pair = IUniswapV2Factory(factory).getPair(tokenA, tokenB);

        if (pair == address(0)) {
            return 0;
        }

        (uint112 reserve0, uint112 reserve1,) = IUniswapV2Pair(pair).getReserves();
        address token0 = IUniswapV2Pair(pair).token0();

        if (token0 == launchToken) {
            liquidity = uint256(reserve0);
        } else if (tokenA == launchToken || tokenB == launchToken) {
            liquidity = uint256(reserve1);
        } else {
            liquidity = 0;
        }
    }

    /// @notice Calculate weighted average pool price from all configured paths (internal version)
    function _getWeightedPoolPriceInternal(
        DataTypes.PricePathsStorage storage pricePathsStorage,
        address launchToken,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals
    ) internal returns (uint256 weightedPrice, uint256 totalWeight) {
        uint256 quoteAmount = Constants.PRICE_QUOTE_AMOUNT;

        for (uint256 i = 0; i < pricePathsStorage.v2Paths.length; ++i) {
            DataTypes.PricePathV2 storage v2Path = pricePathsStorage.v2Paths[i];

            if (v2Path.path.length < 2) {
                continue;
            }

            uint256 liquidity = getLiquidityV2(v2Path.router, v2Path.path[0], v2Path.path[1], launchToken);

            if (liquidity < pricePathsStorage.minLiquidity) {
                continue;
            }

            uint256 amountOut = getPoolPriceV2(v2Path.router, v2Path.path, quoteAmount);

            if (amountOut == 0) {
                continue;
            }

            address outputToken = v2Path.path[v2Path.path.length - 1];
            uint256 collateralPrice = _getCollateralPriceFromChainlink(sellableCollaterals, outputToken);

            if (collateralPrice == 0) {
                continue;
            }

            uint256 priceUSD = (amountOut * collateralPrice) / Constants.PRICE_DECIMALS_MULTIPLIER;

            weightedPrice += priceUSD * liquidity;
            totalWeight += liquidity;
        }

        for (uint256 i = 0; i < pricePathsStorage.v3Paths.length; ++i) {
            DataTypes.PricePathV3 storage v3Path = pricePathsStorage.v3Paths[i];

            if (v3Path.path.length == 0) {
                continue;
            }

            uint256 amountOut = getPoolPriceV3(v3Path.quoter, v3Path.path, quoteAmount);

            if (amountOut == 0) {
                continue;
            }

            address outputToken = _decodeLastTokenFromV3Path(v3Path.path);
            uint256 collateralPrice = _getCollateralPriceFromChainlink(sellableCollaterals, outputToken);

            if (collateralPrice == 0) {
                continue;
            }

            uint256 priceUSD = (amountOut * collateralPrice) / Constants.PRICE_DECIMALS_MULTIPLIER;
            uint256 weight = pricePathsStorage.minLiquidity;

            weightedPrice += priceUSD * weight;
            totalWeight += weight;
        }

        if (totalWeight > 0) {
            weightedPrice = weightedPrice / totalWeight;
        }
    }

    /// @notice Get collateral price directly from Chainlink (returns 0 on error)
    function _getCollateralPriceFromChainlink(
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        address token
    ) internal view returns (uint256 price) {
        DataTypes.CollateralInfo storage info = sellableCollaterals[token];
        if (info.active && info.priceFeed != address(0)) {
            try IAggregatorV3(info.priceFeed).latestRoundData() returns (
                uint80, int256 _price, uint256, uint256 updatedAt, uint80
            ) {
                if (_price > 0 && block.timestamp - updatedAt <= Constants.ORACLE_MAX_AGE) {
                    uint8 decimals = IAggregatorV3(info.priceFeed).decimals();
                    if (decimals < 18) {
                        price = uint256(_price) * (10 ** (18 - decimals));
                    } else if (decimals > 18) {
                        price = uint256(_price) / (10 ** (decimals - 18));
                    } else {
                        price = uint256(_price);
                    }
                }
            } catch {
                price = 0;
            }
        }
    }

    /// @notice Validate that pool price does not deviate from oracle price by more than MAX_PRICE_DEVIATION_BP
    /// @param pricePathsStorage Price paths storage
    /// @param launchToken Launch token address
    /// @param sellableCollaterals Mapping of collateral info
    /// @param oraclePrice Oracle price to validate against
    function _validatePoolPriceInternal(
        DataTypes.PricePathsStorage storage pricePathsStorage,
        address launchToken,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        uint256 oraclePrice
    ) internal {
        if (pricePathsStorage.v2Paths.length == 0 && pricePathsStorage.v3Paths.length == 0) {
            return;
        }

        (uint256 poolPrice, uint256 totalWeight) =
            _getWeightedPoolPriceInternal(pricePathsStorage, launchToken, sellableCollaterals);

        if (totalWeight == 0 || poolPrice == 0) {
            return;
        }

        uint256 deviation = _calculateDeviationInternal(oraclePrice, poolPrice);

        require(deviation <= Constants.MAX_PRICE_DEVIATION_BP, PriceDeviationTooHigh());

        emit PriceValidated(oraclePrice, poolPrice, deviation);
    }

    /// @notice Add V2 price path to storage
    function addV2Path(DataTypes.PricePathsStorage storage pricePathsStorage, address router, address[] memory path)
        external
    {
        require(router != address(0), InvalidPricePath());
        require(path.length >= 2, InvalidPricePath());

        pricePathsStorage.v2Paths.push(DataTypes.PricePathV2({router: router, path: path}));
    }

    /// @notice Add V3 price path to storage
    function addV3Path(DataTypes.PricePathsStorage storage pricePathsStorage, address quoter, bytes memory path)
        external
    {
        require(quoter != address(0), InvalidPricePath());
        require(path.length >= 43, InvalidPricePath());

        pricePathsStorage.v3Paths.push(DataTypes.PricePathV3({quoter: quoter, path: path}));
    }

    /// @notice Initialize price paths from constructor params
    function initializePricePaths(
        DataTypes.PricePathsStorage storage pricePathsStorage,
        DataTypes.TokenPricePathsParams memory params
    ) external {
        pricePathsStorage.minLiquidity = params.minLiquidity;

        for (uint256 i = 0; i < params.v2Paths.length; ++i) {
            if (params.v2Paths[i].router != address(0) && params.v2Paths[i].path.length >= 2) {
                pricePathsStorage.v2Paths
                    .push(DataTypes.PricePathV2({router: params.v2Paths[i].router, path: params.v2Paths[i].path}));
            }
        }

        for (uint256 i = 0; i < params.v3Paths.length; ++i) {
            if (params.v3Paths[i].quoter != address(0) && params.v3Paths[i].path.length >= 43) {
                pricePathsStorage.v3Paths
                    .push(DataTypes.PricePathV3({quoter: params.v3Paths[i].quoter, path: params.v3Paths[i].path}));
            }
        }
    }

    /// @notice Decode last token address from V3 encoded path
    function _decodeLastTokenFromV3Path(bytes memory path) internal pure returns (address token) {
        if (path.length < 20) {
            return address(0);
        }

        assembly {
            token := mload(add(add(path, 20), sub(mload(path), 20)))
        }
    }

    /// @notice Calculate price deviation in basis points (internal)
    function _calculateDeviationInternal(uint256 oraclePrice, uint256 poolPrice)
        internal
        pure
        returns (uint256 deviation)
    {
        if (oraclePrice == 0) {
            return Constants.BASIS_POINTS;
        }

        if (poolPrice >= oraclePrice) {
            deviation = ((poolPrice - oraclePrice) * Constants.BASIS_POINTS) / oraclePrice;
        } else {
            deviation = ((oraclePrice - poolPrice) * Constants.BASIS_POINTS) / oraclePrice;
        }
    }
}

