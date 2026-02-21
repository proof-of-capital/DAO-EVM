// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {ISwapRouter} from "../../interfaces/ISwapRouter.sol";
import {IAggregatorV3} from "../../interfaces/IAggregatorV3.sol";
import {IMultisig} from "../../interfaces/IMultisig.sol";
import {Constants} from "../Constants.sol";

/// @title MultisigSwapLibrary
/// @notice Library for executing collateral-to-main swap with deviation check (Multisig context)
library MultisigSwapLibrary {
    using SafeERC20 for IERC20;

    error InvalidCollateralAddress();
    error InvalidRouterAddress();
    error InvalidAddress();
    error InsufficientBalance();
    error PriceDeviationTooHigh();
    error InvalidPrice();
    error StalePrice();

    event CollateralChanged(address indexed collateral, address router);

    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IAggregatorV3 aggregator = IAggregatorV3(priceFeed);
        (, int256 price,, uint256 updatedAt,) = aggregator.latestRoundData();
        if (price <= 0) revert InvalidPrice();
        if (block.timestamp - updatedAt > Constants.ORACLE_MAX_AGE) revert StalePrice();

        uint8 decimals = aggregator.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) return 0;
        return ((expected - actual) * Constants.BASIS_POINTS) / expected;
    }

    /// @notice Execute swap from collateral to main collateral and validate deviation
    /// @param collaterals Storage reference to collaterals mapping
    /// @param collateral Collateral token address
    /// @param collateralBalance Amount of collateral to swap
    /// @param mainCollateral Main collateral token address
    /// @return mainCollateralBalanceAfter Main collateral balance of caller after swap
    function executeSwapCollateralToMain(
        mapping(address => IMultisig.CollateralInfo) storage collaterals,
        address collateral,
        uint256 collateralBalance,
        address mainCollateral
    ) external returns (uint256 mainCollateralBalanceAfter) {
        if (collateral == address(0)) revert InvalidCollateralAddress();
        if (collateralBalance == 0) revert InvalidAddress();

        IMultisig.CollateralInfo storage collateralInfo = collaterals[collateral];
        if (!collateralInfo.active) revert InvalidCollateralAddress();
        if (collateralInfo.router == address(0)) revert InvalidRouterAddress();
        if (collateralInfo.swapPath.length == 0) revert InvalidAddress();

        IMultisig.CollateralInfo storage mainCollateralInfo = collaterals[mainCollateral];
        if (!mainCollateralInfo.active) revert InvalidCollateralAddress();

        uint256 collateralPrice = _getChainlinkPrice(collateralInfo.priceFeed);
        uint256 mainCollateralPrice = _getChainlinkPrice(mainCollateralInfo.priceFeed);

        IERC20 collateralToken = IERC20(collateral);
        if (collateralToken.balanceOf(address(this)) < collateralBalance) revert InsufficientBalance();

        uint256 expectedMainCollateral = (collateralBalance * collateralPrice) / mainCollateralPrice;
        uint256 mainCollateralBalanceBefore = IERC20(mainCollateral).balanceOf(address(this));

        collateralToken.safeIncreaseAllowance(collateralInfo.router, collateralBalance);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: collateralInfo.swapPath,
            recipient: address(this),
            deadline: block.timestamp + 1 hours,
            amountIn: collateralBalance,
            amountOutMinimum: 0
        });

        ISwapRouter(collateralInfo.router).exactInput(params);

        mainCollateralBalanceAfter = IERC20(mainCollateral).balanceOf(address(this));
        uint256 actualMainCollateral = mainCollateralBalanceAfter - mainCollateralBalanceBefore;

        uint256 deviation = _calculateDeviation(expectedMainCollateral, actualMainCollateral);
        if (deviation > Constants.PRICE_DEVIATION_MAX) revert PriceDeviationTooHigh();

        emit CollateralChanged(collateral, collateralInfo.router);
    }
}
