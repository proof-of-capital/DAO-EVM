// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./IDAO.sol";

/// @title IRoyaltyWallet
/// @notice Interface for RoyaltyWallet contract
interface IRoyaltyWallet {
    function adminDAO() external view returns (address);
    function launchPriceDAO() external view returns (IDAO);
    function priceOracle() external view returns (address);
    function launchToken() external view returns (address);
    function returnWallet() external view returns (address);
    function admin() external view returns (address);

    function setAdmin(address newAdmin) external;
    function setReturnWallet(address newReturnWallet) external;
    function approveReturnWalletLaunch(uint256 amount) external;
    function approveToken(address token, address spender, uint256 amount) external;
    function executeWithPriceCheck(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 minOut,
        address target,
        bytes calldata callData
    ) external returns (uint256 amountIn, uint256 amountOut);
}
