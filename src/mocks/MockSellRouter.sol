// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/ISwapRouter.sol";

/// @title MockSellRouter
/// @notice ISwapRouter mock for sell tests: pulls tokenIn from caller, sends tokenOut to recipient
contract MockSellRouter is ISwapRouter {
    using SafeERC20 for IERC20;

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external override {}

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        IERC20(params.tokenOut).safeTransfer(params.recipient, params.amountOutMinimum);
        return params.amountOutMinimum;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouter: exactInput not used");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouter: exactOutputSingle not used");
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouter: exactOutput not used");
    }
}

/// @title MockSellRouterLowOutput
/// @notice Same as MockSellRouter but sends a fixed amount (for InsufficientCollateralReceived tests)
contract MockSellRouterLowOutput is ISwapRouter {
    using SafeERC20 for IERC20;

    uint256 public outputAmount = 1e18;

    function setOutputAmount(uint256 amount) external {
        outputAmount = amount;
    }

    function uniswapV3SwapCallback(int256, int256, bytes calldata) external override {}

    function exactInputSingle(ExactInputSingleParams calldata params) external payable override returns (uint256) {
        IERC20(params.tokenIn).safeTransferFrom(msg.sender, address(this), params.amountIn);
        uint256 out = outputAmount <= IERC20(params.tokenOut).balanceOf(address(this)) ? outputAmount : 0;
        if (out > 0) {
            IERC20(params.tokenOut).safeTransfer(params.recipient, out);
        }
        return out;
    }

    function exactInput(ExactInputParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouterLowOutput: exactInput not used");
    }

    function exactOutputSingle(ExactOutputSingleParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouterLowOutput: exactOutputSingle not used");
    }

    function exactOutput(ExactOutputParams calldata params) external payable override returns (uint256) {
        revert("MockSellRouterLowOutput: exactOutput not used");
    }
}
