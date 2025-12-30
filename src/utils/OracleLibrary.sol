// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "../interfaces/IAggregatorV3.sol";
import "../interfaces/IProofOfCapital.sol";
import "./DataTypes.sol";
import "./Constants.sol";

/// @title OracleLibrary
/// @notice Library for oracle price operations
library OracleLibrary {
    error InvalidPrice();
    error CollateralNotActive();
    error NoPOCContracts();

    /// @notice Get price from Chainlink aggregator and normalize to 18 decimals (internal)
    /// @param priceFeed Address of Chainlink price feed aggregator
    /// @return Price in USD (18 decimals)
    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IAggregatorV3 aggregator = IAggregatorV3(priceFeed);
        (, int256 price,,,) = aggregator.latestRoundData();
        require(price > 0, InvalidPrice());

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

    /// @notice Get weighted average launch token price from all active POC contracts
    /// @param pocContracts Array of POC contracts
    /// @return Weighted average launch price in USD (18 decimals)
    function _getLaunchPriceFromPOC(DataTypes.POCInfo[] storage pocContracts) internal view returns (uint256) {
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
        return totalWeightedPrice / totalSharePercent;
    }

    /// @notice Get price for any token - handles launch token via POC and collaterals via Chainlink
    /// @param sellableCollaterals Mapping of collateral info
    /// @param pocContracts Array of POC contracts
    /// @param launchToken Launch token address
    /// @param token Token address to get price for
    /// @return Price in USD (18 decimals)
    function getPrice(
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCInfo[] storage pocContracts,
        address launchToken,
        address token
    ) external view returns (uint256) {
        if (token == launchToken) {
            return _getLaunchPriceFromPOC(pocContracts);
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
}

