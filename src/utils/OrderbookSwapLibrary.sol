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
import "../interfaces/IUniswapV2Router02.sol";
import "../interfaces/ISwapRouter.sol";
import "./DataTypes.sol";

/// @title OrderbookSwapLibrary
/// @dev Library for swap operations in Orderbook
library OrderbookSwapLibrary {
    using SafeERC20 for IERC20;

    // Custom Errors
    error RouterNotAvailable();
    error TokenNotAvailable();
    error ZeroAmountNotAllowed();
    error InvalidSwapType();
    error InvalidSwapData();

    /// @dev Execute swap based on swap type
    /// @param router The router address
    /// @param swapType Type of swap to execute
    /// @param swapData Encoded swap parameters
    /// @param tokenIn Input token address
    /// @param tokenOut Output token address
    /// @param amountIn Amount of input tokens
    /// @param amountOutMin Minimum amount of output tokens
    /// @param contractAddress Address of the contract executing the swap
    /// @return amountOut Amount of tokens received
    function executeSwap(
        address router,
        DataTypes.SwapType swapType,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address contractAddress
    ) external returns (uint256 amountOut) {
        require(amountIn > 0, ZeroAmountNotAllowed());

        if (swapType == DataTypes.SwapType.UniswapV2ExactTokensForTokens) {
            return _executeUniswapV2ExactTokensForTokens(
                router, swapData, tokenIn, tokenOut, amountIn, amountOutMin, contractAddress
            );
        } else if (swapType == DataTypes.SwapType.UniswapV2TokensForExactTokens) {
            return _executeUniswapV2TokensForExactTokens(
                router, swapData, tokenIn, tokenOut, amountOutMin, amountIn, contractAddress
            );
        } else if (swapType == DataTypes.SwapType.UniswapV3ExactInputSingle) {
            return _executeUniswapV3ExactInputSingle(
                router, swapData, tokenIn, tokenOut, amountIn, amountOutMin, contractAddress
            );
        } else if (swapType == DataTypes.SwapType.UniswapV3ExactInput) {
            return
                _executeUniswapV3ExactInput(
                    router, swapData, tokenIn, tokenOut, amountIn, amountOutMin, contractAddress
                );
        } else if (swapType == DataTypes.SwapType.UniswapV3ExactOutputSingle) {
            return _executeUniswapV3ExactOutputSingle(
                router, swapData, tokenIn, tokenOut, amountOutMin, amountIn, contractAddress
            );
        } else if (swapType == DataTypes.SwapType.UniswapV3ExactOutput) {
            return
                _executeUniswapV3ExactOutput(
                    router, swapData, tokenIn, tokenOut, amountOutMin, amountIn, contractAddress
                );
        } else {
            revert InvalidSwapType();
        }
    }

    /// @dev Execute Uniswap V2 swapExactTokensForTokens
    function _executeUniswapV2ExactTokensForTokens(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address contractAddress
    ) internal returns (uint256 amountOut) {
        // Decode swap data: (address[] path, uint256 deadline)
        (address[] memory path, uint256 deadline) = abi.decode(swapData, (address[], uint256));

        require(path.length >= 2, InvalidSwapData());
        require(path[0] == tokenIn && path[path.length - 1] == tokenOut, InvalidSwapData());

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountIn) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        uint256[] memory amounts = IUniswapV2Router02(router)
            .swapExactTokensForTokens(amountIn, amountOutMin, path, contractAddress, deadline);

        return amounts[amounts.length - 1];
    }

    /// @dev Execute Uniswap V2 swapTokensForExactTokens
    function _executeUniswapV2TokensForExactTokens(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address contractAddress
    ) internal returns (uint256 amountOutReceived) {
        // Decode swap data: (address[] path, uint256 deadline)
        (address[] memory path, uint256 deadline) = abi.decode(swapData, (address[], uint256));

        require(path.length >= 2, InvalidSwapData());
        require(path[0] == tokenIn && path[path.length - 1] == tokenOut, InvalidSwapData());

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountInMax) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        IUniswapV2Router02(router).swapTokensForExactTokens(amountOut, amountInMax, path, contractAddress, deadline);

        return amountOut;
    }

    /// @dev Execute Uniswap V3 exactInputSingle
    function _executeUniswapV3ExactInputSingle(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address contractAddress
    ) internal returns (uint256 amountOut) {
        // Decode swap data: (uint24 fee, uint256 deadline, uint160 sqrtPriceLimitX96)
        (uint24 fee, uint256 deadline, uint160 sqrtPriceLimitX96) = abi.decode(swapData, (uint24, uint256, uint160));

        // Create router params
        ISwapRouter.ExactInputSingleParams memory routerParams = ISwapRouter.ExactInputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: contractAddress,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountIn) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        amountOut = ISwapRouter(router).exactInputSingle(routerParams);

        return amountOut;
    }

    /// @dev Execute Uniswap V3 exactInput
    function _executeUniswapV3ExactInput(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin,
        address contractAddress
    ) internal returns (uint256 amountOut) {
        // Decode swap data: (bytes path, uint256 deadline)
        (bytes memory path, uint256 deadline) = abi.decode(swapData, (bytes, uint256));

        // Verify path starts with tokenIn and ends with tokenOut
        address firstToken;
        address lastToken;

        assembly {
            firstToken := mload(add(path, 32))
            firstToken := shr(96, firstToken)
        }

        uint256 lastTokenPos = path.length - 20;
        assembly {
            lastToken := mload(add(add(path, 32), lastTokenPos))
            lastToken := shr(96, lastToken)
        }

        require(firstToken == tokenIn && lastToken == tokenOut, InvalidSwapData());

        // Create router params
        ISwapRouter.ExactInputParams memory routerParams = ISwapRouter.ExactInputParams({
            path: path,
            recipient: contractAddress,
            deadline: deadline,
            amountIn: amountIn,
            amountOutMinimum: amountOutMin
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountIn) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        amountOut = ISwapRouter(router).exactInput(routerParams);

        return amountOut;
    }

    /// @dev Execute Uniswap V3 exactOutputSingle
    function _executeUniswapV3ExactOutputSingle(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address contractAddress
    ) internal returns (uint256 amountOutReceived) {
        // Decode swap data: (uint24 fee, uint256 deadline, uint160 sqrtPriceLimitX96)
        (uint24 fee, uint256 deadline, uint160 sqrtPriceLimitX96) = abi.decode(swapData, (uint24, uint256, uint160));

        // Create router params
        ISwapRouter.ExactOutputSingleParams memory routerParams = ISwapRouter.ExactOutputSingleParams({
            tokenIn: tokenIn,
            tokenOut: tokenOut,
            fee: fee,
            recipient: contractAddress,
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMax,
            sqrtPriceLimitX96: sqrtPriceLimitX96
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountInMax) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        ISwapRouter(router).exactOutputSingle(routerParams);

        return amountOut;
    }

    /// @dev Execute Uniswap V3 exactOutput
    function _executeUniswapV3ExactOutput(
        address router,
        bytes memory swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountOut,
        uint256 amountInMax,
        address contractAddress
    ) internal returns (uint256 amountOutReceived) {
        // Decode swap data: (bytes path, uint256 deadline)
        (bytes memory path, uint256 deadline) = abi.decode(swapData, (bytes, uint256));

        // Verify path starts with tokenOut and ends with tokenIn (reversed for exactOutput)
        address firstToken; // Output token
        address lastToken; // Input token

        assembly {
            firstToken := mload(add(path, 32))
            firstToken := shr(96, firstToken)
        }

        uint256 lastTokenPos = path.length - 20;
        assembly {
            lastToken := mload(add(add(path, 32), lastTokenPos))
            lastToken := shr(96, lastToken)
        }

        require(firstToken == tokenOut && lastToken == tokenIn, InvalidSwapData());

        // Create router params
        ISwapRouter.ExactOutputParams memory routerParams = ISwapRouter.ExactOutputParams({
            path: path,
            recipient: contractAddress,
            deadline: deadline,
            amountOut: amountOut,
            amountInMaximum: amountInMax
        });

        // Set token allowance if needed
        IERC20 inputToken = IERC20(tokenIn);
        uint256 currentAllowance = inputToken.allowance(contractAddress, router);
        if (currentAllowance < amountInMax) {
            inputToken.safeIncreaseAllowance(router, type(uint256).max);
        }

        // Execute the swap
        ISwapRouter(router).exactOutput(routerParams);

        return amountOut;
    }
}

