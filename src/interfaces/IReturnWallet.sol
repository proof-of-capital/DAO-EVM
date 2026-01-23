// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "../libraries/DataTypes.sol";

/// @title IReturnWallet
/// @notice Interface for ReturnWallet contract
interface IReturnWallet {
    error Unauthorized();
    error InvalidAddress();
    error InvalidPOCIndex();
    error POCNotActive();
    error CollateralMismatch();
    error InsufficientLaunchAmount();
    error RouterNotTrusted();
    error TokenIsCollateral();
    error InvalidPath();
    error InvalidSwapType();

    event LaunchesReturned(uint256 amount, uint256 pocCount);
    event CollateralExchangedForLaunch(
        uint256 indexed pocIndex, address indexed collateral, uint256 collateralAmount, uint256 launchAmount
    );
    event TokenExchangedForLaunch(address indexed tokenIn, uint256 amountIn, uint256 launchOut, address indexed router);
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event RouterAdded(address indexed router);
    event RouterRemoved(address indexed router);

    /// @notice Return launch tokens to all active POC contracts proportionally
    /// @param amount Total amount of launch tokens to return
    function returnLaunches(uint256 amount) external;

    /// @notice Exchange collateral for launch tokens through POC contract
    /// @param pocIndex Index of POC contract in DAO
    /// @param collateral Collateral token address
    /// @param collateralAmount Amount of collateral to exchange
    /// @param minLaunchAmount Minimum launch tokens to receive
    function exchangeCollateralForLaunch(
        uint256 pocIndex,
        address collateral,
        uint256 collateralAmount,
        uint256 minLaunchAmount
    ) external;

    /// @notice Exchange any token for launch tokens through trusted router
    /// @param tokenIn Input token address
    /// @param amountIn Amount of input tokens
    /// @param minLaunchOut Minimum launch tokens to receive
    /// @param router Router address
    /// @param swapType Type of swap
    /// @param swapData Encoded swap parameters
    function exchange(
        address tokenIn,
        uint256 amountIn,
        uint256 minLaunchOut,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external;

    /// @notice Get expected launch amount from swap
    /// @param tokenIn Input token address
    /// @param amountIn Amount of input tokens
    /// @param router Router address
    /// @param swapType Type of swap
    /// @param swapData Encoded swap parameters
    /// @return Expected launch token amount
    function getExpectedLaunchAmount(
        address tokenIn,
        uint256 amountIn,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external view returns (uint256);
}
