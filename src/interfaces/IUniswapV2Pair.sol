// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

/// @title Uniswap V2 Pair Interface
/// @notice Interface for Uniswap V2 Pair contract to interact with LP tokens
interface IUniswapV2Pair {
    /// @notice Returns the address of token0
    /// @return token0 address
    function token0() external view returns (address);

    /// @notice Returns the address of token1
    /// @return token1 address
    function token1() external view returns (address);

    /// @notice Burns LP tokens and returns underlying tokens
    /// @param to Address to receive the underlying tokens
    /// @return amount0 Amount of token0 returned
    /// @return amount1 Amount of token1 returned
    function burn(address to) external returns (uint256 amount0, uint256 amount1);

    /// @notice Returns the reserves of token0 and token1
    /// @return reserve0 Reserve of token0
    /// @return reserve1 Reserve of token1
    /// @return blockTimestampLast Last block timestamp of reserve update
    function getReserves() external view returns (uint112 reserve0, uint112 reserve1, uint32 blockTimestampLast);
}

