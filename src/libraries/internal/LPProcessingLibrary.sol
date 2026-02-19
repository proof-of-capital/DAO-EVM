// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IUniswapV2Pair.sol";

/// @title LPProcessingLibrary
/// @notice Internal library for LP token processing operations
/// @dev This library contains functions for dissolving LP tokens and checking their presence
library LPProcessingLibrary {
    using SafeERC20 for IERC20;

    error AmountMustBeGreaterThanZero();
    error NotLPToken();

    /// @notice Check if there are any LP tokens (V2 or V3) that need to be dissolved
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @return true if there are LP tokens, false otherwise
    function hasLPTokens(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance
    ) internal view returns (bool) {
        for (uint256 i = 0; i < lpTokenStorage.v2LPTokens.length; ++i) {
            if (accountedBalance[lpTokenStorage.v2LPTokens[i]] > 0) {
                return true;
            }
        }

        for (uint256 i = 0; i < lpTokenStorage.v3LPPositions.length; ++i) {
            uint256 tokenId = lpTokenStorage.v3LPPositions[i].tokenId;
            INonfungiblePositionManager positionManager =
                INonfungiblePositionManager(lpTokenStorage.v3LPPositions[i].positionManager);
            (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
            if (liquidity > 0) {
                return true;
            }
        }

        return false;
    }

    /// @notice Dissolve a single V2 LP token by burning it and receiving underlying tokens
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param lpToken Address of the V2 LP token (Pair contract)
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function executeDissolveV2LPToken(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 lpBalance = accountedBalance[lpToken];
        require(lpBalance > 0, AmountMustBeGreaterThanZero());

        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();

        IERC20(lpToken).safeTransfer(lpToken, lpBalance);

        (amount0, amount1) = IUniswapV2Pair(lpToken).burn(address(this));

        accountedBalance[lpToken] = 0;
        lpTokenStorage.isV2LPToken[lpToken] = false;

        if (amount0 > 0) {
            accountedBalance[token0] += amount0;
        }
        if (amount1 > 0) {
            accountedBalance[token1] += amount1;
        }
    }

    /// @notice Withdraw configured share of V2 LP tokens (burn) and credit underlying to accountedBalance (depeg recovery)
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param lpToken Address of the V2 LP token (Pair contract)
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function executeWithdrawDepegV2(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken
    ) internal returns (uint256 amount0, uint256 amount1) {
        uint256 lpBalance = accountedBalance[lpToken];
        require(lpBalance > 0, AmountMustBeGreaterThanZero());

        uint256 amountToBurn = (lpBalance * Constants.DEPEG_WITHDRAW_PERCENT) / Constants.BASIS_POINTS;
        require(amountToBurn > 0, AmountMustBeGreaterThanZero());

        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();

        IERC20(lpToken).safeTransfer(lpToken, amountToBurn);
        (amount0, amount1) = IUniswapV2Pair(lpToken).burn(address(this));

        accountedBalance[lpToken] = lpBalance - amountToBurn;

        if (amount0 > 0) {
            accountedBalance[token0] += amount0;
        }
        if (amount1 > 0) {
            accountedBalance[token1] += amount1;
        }
    }

    /// @notice Withdraw configured share of V3 position liquidity, collect tokens and credit to accountedBalance (depeg recovery)
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param tokenId NFT token ID of the V3 position
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function executeWithdrawDepegV3(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        uint256 tokenId
    ) internal returns (uint256 amount0, uint256 amount1) {
        DataTypes.V3LPPositionInfo memory positionInfo = getV3PositionInfo(lpTokenStorage, tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        require(liquidity > 0, AmountMustBeGreaterThanZero());

        uint128 liquidityToDecrease =
            uint128((uint256(liquidity) * Constants.DEPEG_WITHDRAW_PERCENT) / Constants.BASIS_POINTS);
        require(liquidityToDecrease > 0, AmountMustBeGreaterThanZero());

        decreaseV3Liquidity(lpTokenStorage, tokenId, liquidityToDecrease);
        (amount0, amount1) = collectV3Tokens(lpTokenStorage, tokenId);

        if (amount0 > 0) {
            accountedBalance[positionInfo.token0] += amount0;
        }
        if (amount1 > 0) {
            accountedBalance[positionInfo.token1] += amount1;
        }
    }

    /// @notice Dissolve a single V3 LP position by decreasing all liquidity and collecting tokens
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param tokenId NFT token ID of the V3 position
    /// @return amount0 Amount of token0 received
    /// @return amount1 Amount of token1 received
    function executeDissolveV3LPPosition(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        uint256 tokenId
    ) internal returns (uint256 amount0, uint256 amount1) {
        DataTypes.V3LPPositionInfo memory positionInfo = getV3PositionInfo(lpTokenStorage, tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        require(liquidity > 0, AmountMustBeGreaterThanZero());

        decreaseV3Liquidity(lpTokenStorage, tokenId, liquidity);

        (amount0, amount1) = collectV3Tokens(lpTokenStorage, tokenId);

        if (amount0 > 0) {
            accountedBalance[positionInfo.token0] += amount0;
        }
        if (amount1 > 0) {
            accountedBalance[positionInfo.token1] += amount1;
        }

        lpTokenStorage.v3TokenIdToIndex[tokenId] = 0;
    }

    /// @notice Get V3 position info from array
    /// @param lpTokenStorage LP token storage structure
    /// @param tokenId NFT token ID of the position
    /// @return Position info struct
    function getV3PositionInfo(DataTypes.LPTokenStorage storage lpTokenStorage, uint256 tokenId)
        internal
        view
        returns (DataTypes.V3LPPositionInfo memory)
    {
        uint256 index = lpTokenStorage.v3TokenIdToIndex[tokenId];
        require(index > 0, NotLPToken());
        return lpTokenStorage.v3LPPositions[index - 1];
    }

    /// @notice Decrease liquidity for a V3 position
    /// @param lpTokenStorage LP token storage structure
    /// @param tokenId NFT token ID of the position
    /// @param liquidity Amount of liquidity to decrease
    /// @return amount0 Amount of token0 accounted for the decrease
    /// @return amount1 Amount of token1 accounted for the decrease
    function decreaseV3Liquidity(DataTypes.LPTokenStorage storage lpTokenStorage, uint256 tokenId, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        DataTypes.V3LPPositionInfo memory positionInfo = getV3PositionInfo(lpTokenStorage, tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            });

        (amount0, amount1) = positionManager.decreaseLiquidity(params);
    }

    /// @notice Collect tokens from a V3 position
    /// @param lpTokenStorage LP token storage structure
    /// @param tokenId NFT token ID of the position
    /// @return amount0 Amount of token0 collected
    /// @return amount1 Amount of token1 collected
    function collectV3Tokens(DataTypes.LPTokenStorage storage lpTokenStorage, uint256 tokenId)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        DataTypes.V3LPPositionInfo memory positionInfo = getV3PositionInfo(lpTokenStorage, tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        (amount0, amount1) = positionManager.collect(params);
    }
}
