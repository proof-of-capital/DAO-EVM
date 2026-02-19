// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

/// @title IERC20Burnable
/// @notice Interface for ERC20 tokens that support burning from the caller's balance
interface IERC20Burnable {
    /// @notice Burns `amount` tokens from the caller
    /// @param amount Amount of tokens to burn
    function burn(uint256 amount) external;
}
