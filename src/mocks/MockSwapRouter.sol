// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/ISwapRouter.sol";

/// @title MockSwapRouter
/// @notice ISwapRouter mock for testing; exactInput/exactInputSingle return amountIn as amountOut, no real swap
contract MockSwapRouter is ISwapRouter {
    function uniswapV3SwapCallback(int256, int256, bytes calldata) external override {}

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256) {
        return params.amountIn;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256) {
        return params.amountIn;
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable override returns (uint256) {
        return params.amountOut;
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256) {
        return params.amountOut;
    }
}
