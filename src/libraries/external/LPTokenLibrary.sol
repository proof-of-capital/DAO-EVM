// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "../../interfaces/INonfungiblePositionManager.sol";
import "../../interfaces/IUniswapV2Pair.sol";
import "../../interfaces/IUniswapV2Router01.sol";
import "../../interfaces/IProofOfCapital.sol";
import "../../interfaces/IPriceOracle.sol";
import "../internal/LPProcessingLibrary.sol";
import "../internal/SwapLibrary.sol";
import "./OracleLibrary.sol";

/// @title LPTokenLibrary
/// @notice Library for managing LP tokens (V2 and V3)
library LPTokenLibrary {
    using SafeERC20 for IERC20;

    error InvalidAddresses();
    error InvalidAddress();
    error AmountMustBeGreaterThanZero();
    error TokenAlreadyAdded();
    error Unauthorized();
    error TokenNotAdded();
    error NotLPToken();
    error LPDistributionTooSoon();
    error NoProfitToDistribute();
    error NoShares();
    error AlreadyInDepeg();
    error NotInDepeg();
    error InsufficientAccountedBalance();
    error DepegGracePeriodNotPassed();
    error NoDepegCondition();

    event LPTokensProvided(address indexed lpToken, uint256 amount);
    event V3LPPositionProvided(uint256 indexed tokenId, address token0, address token1);
    event V2LPTokenDissolved(address indexed lpToken, uint256 amount0, uint256 amount1);
    event V3LPPositionDissolved(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event LPProfitDistributed(address indexed lpToken, uint256 amount);
    event V3LiquidityDecreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event StageChanged(DataTypes.Stage oldStage, DataTypes.Stage newStage);
    event MarketMakerSet(address indexed marketMaker);
    event DepegDeclared(
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType,
        uint256 timestamp,
        uint256 amount0,
        uint256 amount1
    );

    struct AddLiquidityBackParams {
        address router;
        uint256 amount0;
        uint256 amount1;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    struct AddLiquidityResult {
        address token0;
        address token1;
        uint256 used0;
        uint256 used1;
        uint256 liquidity;
    }

    /// @notice Provide V2 LP tokens
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param lpToken LP token address
    /// @param lpAmount LP token amount
    /// @param sender Sender address
    function executeProvideV2LPToken(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        uint256 lpAmount,
        address sender
    ) external {
        require(lpToken != address(0), InvalidAddress());
        require(lpAmount > 0, AmountMustBeGreaterThanZero());

        IERC20(lpToken).safeTransferFrom(sender, address(this), lpAmount);

        if (!lpTokenStorage.isV2LPToken[lpToken]) {
            lpTokenStorage.v2LPTokens.push(lpToken);
            lpTokenStorage.isV2LPToken[lpToken] = true;
        }
        accountedBalance[lpToken] += lpAmount;
        lpTokenStorage.lpTokenAddedAt[lpToken] = block.timestamp;
        lpTokenStorage.lastLPDistribution[lpToken] = block.timestamp;

        emit LPTokensProvided(lpToken, lpAmount);
    }

    /// @notice Provide V3 LP position
    /// @param lpTokenStorage LP token storage structure
    /// @param rewardsStorage Rewards storage structure (for checking token validity)
    /// @param tokenId NFT token ID
    function executeProvideV3LPPosition(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        uint256 tokenId
    ) external {
        require(lpTokenStorage.v3PositionManager != address(0), InvalidAddress());
        require(lpTokenStorage.v3TokenIdToIndex[tokenId] == 0, TokenAlreadyAdded());

        INonfungiblePositionManager positionManager = INonfungiblePositionManager(lpTokenStorage.v3PositionManager);
        require(positionManager.ownerOf(tokenId) == address(this), Unauthorized());

        (,, address token0, address token1,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        require(liquidity > 0, AmountMustBeGreaterThanZero());

        require(rewardsStorage.rewardTokenInfo[token0].active, TokenNotAdded());
        require(rewardsStorage.rewardTokenInfo[token1].active, TokenNotAdded());

        lpTokenStorage.v3LPPositions
            .push(
                DataTypes.V3LPPositionInfo({
                    positionManager: lpTokenStorage.v3PositionManager, tokenId: tokenId, token0: token0, token1: token1
                })
            );

        lpTokenStorage.v3TokenIdToIndex[tokenId] = lpTokenStorage.v3LPPositions.length;
        lpTokenStorage.v3LPTokenAddedAt[tokenId] = block.timestamp;
        lpTokenStorage.v3LastLPDistribution[tokenId] = block.timestamp;

        emit V3LPPositionProvided(tokenId, token0, token1);
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
    ) external returns (uint256 amount0, uint256 amount1) {
        return LPProcessingLibrary.executeDissolveV2LPToken(lpTokenStorage, accountedBalance, lpToken);
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
    ) external returns (uint256 amount0, uint256 amount1) {
        return LPProcessingLibrary.executeDissolveV3LPPosition(lpTokenStorage, accountedBalance, tokenId);
    }

    /// @notice Declare depeg with threshold check: verify at least one token is below depeg threshold, then withdraw 99% and record DepegInfo
    function executeDeclareDepegWithCheck(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        IPriceOracle priceOracle
    ) external {
        address token0;
        address token1;
        if (lpType == DataTypes.LPTokenType.V2) {
            require(lpToken != address(0), InvalidAddress());
            require(tokenId == 0, InvalidAddress());
            token0 = IUniswapV2Pair(lpToken).token0();
            token1 = IUniswapV2Pair(lpToken).token1();
        } else {
            require(lpToken == address(0) && tokenId != 0, InvalidAddress());
            DataTypes.V3LPPositionInfo memory pos =
                lpTokenStorage.v3LPPositions[lpTokenStorage.v3TokenIdToIndex[tokenId] - 1];
            token0 = pos.token0;
            token1 = pos.token1;
        }
        bool depegTriggered;
        if (sellableCollaterals[token0].depegThresholdMinPrice > 0) {
            uint256 price0 = priceOracle.getAssetPrice(token0);
            if (price0 < sellableCollaterals[token0].depegThresholdMinPrice) depegTriggered = true;
        }
        if (!depegTriggered && sellableCollaterals[token1].depegThresholdMinPrice > 0) {
            uint256 price1 = priceOracle.getAssetPrice(token1);
            if (price1 < sellableCollaterals[token1].depegThresholdMinPrice) depegTriggered = true;
        }
        require(depegTriggered, NoDepegCondition());
        _executeDeclareDepeg(lpTokenStorage, accountedBalance, lpToken, tokenId, lpType);
    }

    /// @notice Declare depeg: withdraw 99% of LP liquidity and record DepegInfo (caller must have verified depeg threshold)
    function executeDeclareDepeg(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType
    ) external {
        _executeDeclareDepeg(lpTokenStorage, accountedBalance, lpToken, tokenId, lpType);
    }

    function _executeDeclareDepeg(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType
    ) internal {
        uint256 amount0;
        uint256 amount1;
        address token0;
        address token1;

        if (lpType == DataTypes.LPTokenType.V2) {
            require(lpToken != address(0), InvalidAddress());
            require(tokenId == 0, InvalidAddress());
            require(lpTokenStorage.depegInfoV2[lpToken].timestamp == 0, AlreadyInDepeg());
            token0 = IUniswapV2Pair(lpToken).token0();
            token1 = IUniswapV2Pair(lpToken).token1();
            (amount0, amount1) = LPProcessingLibrary.executeWithdrawDepegV2(lpTokenStorage, accountedBalance, lpToken);
            lpTokenStorage.depegInfoV2[lpToken] = DataTypes.DepegInfo({
                timestamp: block.timestamp,
                amountToken0: amount0,
                amountToken1: amount1,
                token0: token0,
                token1: token1,
                returnedToken0: 0,
                returnedToken1: 0,
                lpUnused: false
            });
        } else if (lpType == DataTypes.LPTokenType.V3) {
            require(lpToken == address(0), InvalidAddress());
            require(tokenId != 0, InvalidAddress());
            require(lpTokenStorage.depegInfoV3[tokenId].timestamp == 0, AlreadyInDepeg());
            DataTypes.V3LPPositionInfo memory positionInfo =
                LPProcessingLibrary.getV3PositionInfo(lpTokenStorage, tokenId);
            token0 = positionInfo.token0;
            token1 = positionInfo.token1;
            (amount0, amount1) = LPProcessingLibrary.executeWithdrawDepegV3(lpTokenStorage, accountedBalance, tokenId);
            lpTokenStorage.depegInfoV3[tokenId] = DataTypes.DepegInfo({
                timestamp: block.timestamp,
                amountToken0: amount0,
                amountToken1: amount1,
                token0: token0,
                token1: token1,
                returnedToken0: 0,
                returnedToken1: 0,
                lpUnused: false
            });
        } else {
            revert InvalidAddress();
        }

        emit DepegDeclared(lpToken, tokenId, lpType, block.timestamp, amount0, amount1);
    }

    /// @notice Add liquidity back to a V2 pool (depeg recovery); updates depeg returned amounts and clears depeg if >= 99% restored
    function executeAddLiquidityBackV2(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        AddLiquidityBackParams memory p,
        DataTypes.CoreConfig storage coreConfig,
        mapping(address => bool) storage availableRouterByAdmin,
        DataTypes.PricePathsStorage storage pricePathsStorage
    ) external {
        require(availableRouterByAdmin[p.router], SwapLibrary.RouterNotAvailable());
        require(lpToken != address(0) && p.router != address(0), InvalidAddress());
        DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV2[lpToken];
        require(info.timestamp != 0, NotInDepeg());

        address token0 = IUniswapV2Pair(lpToken).token0();
        address token1 = IUniswapV2Pair(lpToken).token1();
        require(
            accountedBalance[token0] >= p.amount0 && accountedBalance[token1] >= p.amount1,
            InsufficientAccountedBalance()
        );

        accountedBalance[token0] -= p.amount0;
        accountedBalance[token1] -= p.amount1;

        IERC20(token0).forceApprove(p.router, p.amount0);
        IERC20(token1).forceApprove(p.router, p.amount1);
        (uint256 used0, uint256 used1, uint256 liquidity) = IUniswapV2Router01(p.router)
            .addLiquidity(
                token0, token1, p.amount0, p.amount1, p.amount0Min, p.amount1Min, address(this), block.timestamp
            );
        IERC20(token0).forceApprove(p.router, 0);
        IERC20(token1).forceApprove(p.router, 0);

        AddLiquidityResult memory res =
            AddLiquidityResult({token0: token0, token1: token1, used0: used0, used1: used1, liquidity: liquidity});
        _applyAddLiquidityResult(accountedBalance, lpToken, p, res);

        info.returnedToken0 += res.used0;
        info.returnedToken1 += res.used1;
        _clearDepegIfRestored(lpTokenStorage, lpToken, 0, DataTypes.LPTokenType.V2);
        OracleLibrary.validatePoolPriceWithOracle(
            IPriceOracle(coreConfig.priceOracle),
            pricePathsStorage,
            coreConfig.launchToken,
            IPriceOracle(coreConfig.priceOracle).getAssetPrice(coreConfig.launchToken)
        );
    }

    /// @notice Add liquidity back to a V3 position (depeg recovery); updates depeg returned amounts and clears depeg if >= 99% restored
    function executeAddLiquidityBackV3(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        uint256 tokenId,
        AddLiquidityBackParams memory p,
        DataTypes.CoreConfig storage coreConfig,
        DataTypes.PricePathsStorage storage pricePathsStorage
    ) external {
        require(tokenId != 0, InvalidAddress());
        DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV3[tokenId];
        require(info.timestamp != 0, NotInDepeg());

        DataTypes.V3LPPositionInfo memory positionInfo = LPProcessingLibrary.getV3PositionInfo(lpTokenStorage, tokenId);
        require(
            accountedBalance[positionInfo.token0] >= p.amount0 && accountedBalance[positionInfo.token1] >= p.amount1,
            InsufficientAccountedBalance()
        );

        accountedBalance[positionInfo.token0] -= p.amount0;
        accountedBalance[positionInfo.token1] -= p.amount1;

        AddLiquidityResult memory res = _increaseLiquidityV3(positionInfo, tokenId, p);
        _applyAddLiquidityResultV3(accountedBalance, p, res);

        info.returnedToken0 += res.used0;
        info.returnedToken1 += res.used1;
        _clearDepegIfRestored(lpTokenStorage, address(0), tokenId, DataTypes.LPTokenType.V3);
        OracleLibrary.validatePoolPriceWithOracle(
            IPriceOracle(coreConfig.priceOracle),
            pricePathsStorage,
            coreConfig.launchToken,
            IPriceOracle(coreConfig.priceOracle).getAssetPrice(coreConfig.launchToken)
        );
    }

    function _increaseLiquidityV3(
        DataTypes.V3LPPositionInfo memory positionInfo,
        uint256 tokenId,
        AddLiquidityBackParams memory p
    ) private returns (AddLiquidityResult memory res) {
        INonfungiblePositionManager pm = INonfungiblePositionManager(positionInfo.positionManager);
        IERC20(positionInfo.token0).forceApprove(address(pm), p.amount0);
        IERC20(positionInfo.token1).forceApprove(address(pm), p.amount1);
        INonfungiblePositionManager.IncreaseLiquidityParams memory params =
            INonfungiblePositionManager.IncreaseLiquidityParams({
                tokenId: tokenId,
                amount0Desired: p.amount0,
                amount1Desired: p.amount1,
                amount0Min: p.amount0Min,
                amount1Min: p.amount1Min,
                deadline: block.timestamp
            });
        (, uint256 used0, uint256 used1) = pm.increaseLiquidity(params);
        IERC20(positionInfo.token0).forceApprove(address(pm), 0);
        IERC20(positionInfo.token1).forceApprove(address(pm), 0);
        res = AddLiquidityResult({
            token0: positionInfo.token0, token1: positionInfo.token1, used0: used0, used1: used1, liquidity: 0
        });
    }

    function _applyAddLiquidityResult(
        mapping(address => uint256) storage accountedBalance,
        address lpToken,
        AddLiquidityBackParams memory p,
        AddLiquidityResult memory res
    ) private {
        if (p.amount0 - res.used0 > 0) accountedBalance[res.token0] += (p.amount0 - res.used0);
        if (p.amount1 - res.used1 > 0) accountedBalance[res.token1] += (p.amount1 - res.used1);
        if (lpToken != address(0)) accountedBalance[lpToken] += res.liquidity;
    }

    function _applyAddLiquidityResultV3(
        mapping(address => uint256) storage accountedBalance,
        AddLiquidityBackParams memory p,
        AddLiquidityResult memory res
    ) private {
        if (p.amount0 - res.used0 > 0) {
            accountedBalance[res.token0] += (p.amount0 - res.used0);
        }
        if (p.amount1 - res.used1 > 0) accountedBalance[res.token1] += (p.amount1 - res.used1);
    }

    /// @notice Clear depeg record if returned amounts >= 99% of withdrawn
    function _clearDepegIfRestored(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType
    ) internal {
        if (lpType == DataTypes.LPTokenType.V2) {
            DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV2[lpToken];
            if (info.amountToken0 == 0 && info.amountToken1 == 0) return;
            bool restored0 = info.amountToken0 == 0
                || (info.returnedToken0 * Constants.BASIS_POINTS
                        >= info.amountToken0 * Constants.DEPEG_RESTORE_THRESHOLD_BP);
            bool restored1 = info.amountToken1 == 0
                || (info.returnedToken1 * Constants.BASIS_POINTS
                        >= info.amountToken1 * Constants.DEPEG_RESTORE_THRESHOLD_BP);
            if (restored0 && restored1) {
                info.timestamp = 0;
            }
        } else {
            DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV3[tokenId];
            if (info.amountToken0 == 0 && info.amountToken1 == 0) return;
            bool restored0 = info.amountToken0 == 0
                || (info.returnedToken0 * Constants.BASIS_POINTS
                        >= info.amountToken0 * Constants.DEPEG_RESTORE_THRESHOLD_BP);
            bool restored1 = info.amountToken1 == 0
                || (info.returnedToken1 * Constants.BASIS_POINTS
                        >= info.amountToken1 * Constants.DEPEG_RESTORE_THRESHOLD_BP);
            if (restored0 && restored1) {
                info.timestamp = 0;
            }
        }
    }

    /// @notice Rebalance from launch only: swap at most half of accounted launch for collateral (depeg recovery)
    /// @notice Rebalance: swap at most half of source token for destination (depeg recovery). Direction selects launch->collateral or collateral->launch.
    function executeRebalance(
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        address collateral,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData,
        DataTypes.RebalanceDirection direction,
        uint256 amountIn,
        uint256 minOut,
        mapping(address => bool) storage availableRouterByAdmin
    ) external {
        require(availableRouterByAdmin[router], SwapLibrary.RouterNotAvailable());
        (address tokenIn, address tokenOut) = direction == DataTypes.RebalanceDirection.LaunchToCollateral
            ? (launchToken, collateral)
            : (collateral, launchToken);
        uint256 maxIn = (accountedBalance[tokenIn] * Constants.DEPEG_REBALANCE_HALF_BP) / Constants.BASIS_POINTS;
        require(amountIn <= maxIn && amountIn > 0, InvalidAddress());
        require(accountedBalance[tokenIn] >= amountIn, InsufficientAccountedBalance());
        accountedBalance[tokenIn] -= amountIn;
        IERC20(tokenIn).forceApprove(router, amountIn);
        uint256 out = SwapLibrary.executeSwap(router, swapType, swapData, tokenIn, tokenOut, amountIn, minOut);
        IERC20(tokenIn).forceApprove(router, 0);
        accountedBalance[tokenOut] += out;
    }

    /// @notice Finalize depeg after grace period: mark LP as unused (anyone can call after 7 days)
    /// @param lpTokenStorage LP token storage structure
    /// @param lpToken V2 LP token address; address(0) for V3
    /// @param tokenId V3 position id; 0 for V2
    /// @param lpType V2 or V3
    function executeFinalizeDepegAfterGracePeriod(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        address lpToken,
        uint256 tokenId,
        DataTypes.LPTokenType lpType
    ) external {
        if (lpType == DataTypes.LPTokenType.V2) {
            require(lpToken != address(0), InvalidAddress());
            DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV2[lpToken];
            require(info.timestamp != 0, NotInDepeg());
            require(block.timestamp >= info.timestamp + Constants.DEPEG_GRACE_PERIOD, DepegGracePeriodNotPassed());
            require(!info.lpUnused, InvalidAddress());
            info.lpUnused = true;
        } else {
            require(lpToken == address(0) && tokenId != 0, InvalidAddress());
            DataTypes.DepegInfo storage info = lpTokenStorage.depegInfoV3[tokenId];
            require(info.timestamp != 0, NotInDepeg());
            require(block.timestamp >= info.timestamp + Constants.DEPEG_GRACE_PERIOD, DepegGracePeriodNotPassed());
            require(!info.lpUnused, InvalidAddress());
            info.lpUnused = true;
        }
    }

    /// @notice Check if there are any LP tokens (V2 or V3) that need to be dissolved
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @return true if there are LP tokens, false otherwise
    function hasLPTokens(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance
    ) external view returns (bool) {
        return LPProcessingLibrary.hasLPTokens(lpTokenStorage, accountedBalance);
    }

    /// @notice Distribute 1% of LP tokens as profit (monthly)
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param totalSharesSupply Total shares supply
    /// @param lpTokenOrTokenId LP token address (V2) or token ID (V3)
    /// @param lpType Type of LP token (V2 or V3)
    function executeDistributeLPProfit(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        uint256 totalSharesSupply,
        address lpTokenOrTokenId,
        DataTypes.LPTokenType lpType
    ) external {
        require(totalSharesSupply > 0, NoShares());

        if (lpType == DataTypes.LPTokenType.V2) {
            address lpToken = lpTokenOrTokenId;
            distributeV2LPProfit(lpTokenStorage, accountedBalance, lpToken);
        } else if (lpType == DataTypes.LPTokenType.V3) {
            uint256 tokenId = uint256(uint160(lpTokenOrTokenId));
            distributeV3LPProfit(lpTokenStorage, tokenId);
        } else {
            revert InvalidAddress();
        }
    }

    /// @notice Distribute 1% of V2 LP tokens as profit (monthly)
    /// @param lpTokenStorage LP token storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param lpToken LP token address
    /// @return toDistribute Amount distributed
    function distributeV2LPProfit(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        mapping(address => uint256) storage accountedBalance,
        address lpToken
    ) internal returns (uint256 toDistribute) {
        require(lpTokenStorage.isV2LPToken[lpToken], NotLPToken());
        require(!lpTokenStorage.depegInfoV2[lpToken].lpUnused, NotLPToken());
        require(
            block.timestamp >= lpTokenStorage.lastLPDistribution[lpToken] + Constants.LP_DISTRIBUTION_PERIOD,
            LPDistributionTooSoon()
        );

        uint256 lpBalance = accountedBalance[lpToken];
        require(lpBalance > 0, NoProfitToDistribute());

        toDistribute = (lpBalance * Constants.LP_DISTRIBUTION_PERCENT) / Constants.BASIS_POINTS;
        require(toDistribute > 0, NoProfitToDistribute());

        lpTokenStorage.lastLPDistribution[lpToken] = block.timestamp;

        emit LPProfitDistributed(lpToken, toDistribute);
    }

    /// @notice Distribute 1% of V3 LP position as profit (monthly)
    /// @param lpTokenStorage LP token storage structure
    /// @param tokenId NFT token ID
    /// @return collected0 Amount of token0 collected
    /// @return collected1 Amount of token1 collected
    function distributeV3LPProfit(DataTypes.LPTokenStorage storage lpTokenStorage, uint256 tokenId)
        internal
        returns (uint256 collected0, uint256 collected1)
    {
        require(lpTokenStorage.v3TokenIdToIndex[tokenId] > 0, NotLPToken());
        require(!lpTokenStorage.depegInfoV3[tokenId].lpUnused, NotLPToken());
        require(
            block.timestamp >= lpTokenStorage.v3LastLPDistribution[tokenId] + Constants.LP_DISTRIBUTION_PERIOD,
            LPDistributionTooSoon()
        );

        DataTypes.V3LPPositionInfo memory positionInfo = LPProcessingLibrary.getV3PositionInfo(lpTokenStorage, tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
        require(liquidity > 0, NoProfitToDistribute());

        uint128 liquidityToDecrease =
            uint128((uint256(liquidity) * Constants.LP_DISTRIBUTION_PERCENT) / Constants.BASIS_POINTS);
        require(liquidityToDecrease > 0, NoProfitToDistribute());

        LPProcessingLibrary.decreaseV3Liquidity(lpTokenStorage, tokenId, liquidityToDecrease);

        (collected0, collected1) = LPProcessingLibrary.collectV3Tokens(lpTokenStorage, tokenId);

        lpTokenStorage.v3LastLPDistribution[tokenId] = block.timestamp;

        emit V3LiquidityDecreased(tokenId, liquidityToDecrease, collected0, collected1);
    }

    /// @notice Creator provides LP tokens and moves DAO to active stage
    /// @param lpTokenStorage LP token storage structure
    /// @param rewardsStorage Rewards storage structure
    /// @param daoState DAO state storage
    /// @param pricePathsStorage Price paths storage structure
    /// @param accountedBalance Accounted balance mapping
    /// @param params ProvideLPTokensParams (arrays and scalars in memory to avoid stack too deep)
    /// @param pocContracts Array of POC contracts
    function executeProvideLPTokens(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.ProvideLPTokensParams memory params,
        DataTypes.POCInfo[] storage pocContracts
    ) external {
        require(params.v2LPTokenAddresses.length == params.v2LPAmounts.length, InvalidAddresses());
        require(params.v2LPTokenAddresses.length > 0 || params.v3TokenIds.length > 0, InvalidAddress());

        for (uint256 i = 0; i < params.newV2PricePaths.length; ++i) {
            if (params.newV2PricePaths[i].router != address(0) && params.newV2PricePaths[i].path.length >= 2) {
                pricePathsStorage.v2Paths
                    .push(
                        DataTypes.PricePathV2({
                            router: params.newV2PricePaths[i].router, path: params.newV2PricePaths[i].path
                        })
                    );
            }
        }

        for (uint256 i = 0; i < params.newV3PricePaths.length; ++i) {
            if (params.newV3PricePaths[i].quoter != address(0) && params.newV3PricePaths[i].path.length >= 43) {
                pricePathsStorage.v3Paths
                    .push(
                        DataTypes.PricePathV3({
                            quoter: params.newV3PricePaths[i].quoter, path: params.newV3PricePaths[i].path
                        })
                    );
            }
        }

        if (params.primaryLPTokenType == DataTypes.LPTokenType.V2) {
            require(params.v2LPTokenAddresses.length > 0, InvalidAddress());
        } else if (params.primaryLPTokenType == DataTypes.LPTokenType.V3) {
            require(params.v3TokenIds.length > 0, InvalidAddress());
        }

        for (uint256 i = 0; i < params.v2LPTokenAddresses.length; ++i) {
            address lpToken = params.v2LPTokenAddresses[i];
            uint256 lpAmount = params.v2LPAmounts[i];

            require(lpToken != address(0), InvalidAddress());
            require(lpAmount > 0, AmountMustBeGreaterThanZero());

            IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);

            if (!lpTokenStorage.isV2LPToken[lpToken]) {
                lpTokenStorage.v2LPTokens.push(lpToken);
                lpTokenStorage.isV2LPToken[lpToken] = true;
            }
            accountedBalance[lpToken] += lpAmount;
            lpTokenStorage.lpTokenAddedAt[lpToken] = block.timestamp;
            lpTokenStorage.lastLPDistribution[lpToken] = block.timestamp;

            emit LPTokensProvided(lpToken, lpAmount);
        }

        if (params.v3TokenIds.length > 0) {
            require(lpTokenStorage.v3PositionManager != address(0), InvalidAddress());

            for (uint256 i = 0; i < params.v3TokenIds.length; ++i) {
                uint256 tokenId = params.v3TokenIds[i];
                require(lpTokenStorage.v3TokenIdToIndex[tokenId] == 0, TokenAlreadyAdded());

                INonfungiblePositionManager positionManager =
                    INonfungiblePositionManager(lpTokenStorage.v3PositionManager);
                require(positionManager.ownerOf(tokenId) == address(this), Unauthorized());

                (,, address token0, address token1,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
                require(liquidity > 0, AmountMustBeGreaterThanZero());

                require(rewardsStorage.rewardTokenInfo[token0].active, TokenNotAdded());
                require(rewardsStorage.rewardTokenInfo[token1].active, TokenNotAdded());

                lpTokenStorage.v3LPPositions
                    .push(
                        DataTypes.V3LPPositionInfo({
                            positionManager: lpTokenStorage.v3PositionManager,
                            tokenId: tokenId,
                            token0: token0,
                            token1: token1
                        })
                    );

                lpTokenStorage.v3TokenIdToIndex[tokenId] = lpTokenStorage.v3LPPositions.length;
                lpTokenStorage.v3LPTokenAddedAt[tokenId] = block.timestamp;
                lpTokenStorage.v3LastLPDistribution[tokenId] = block.timestamp;

                emit V3LPPositionProvided(tokenId, token0, token1);
            }
        }

        DataTypes.Stage oldStage = daoState.currentStage;
        daoState.currentStage = DataTypes.Stage.Active;

        uint256 pocContractsCount = pocContracts.length;
        for (uint256 i = 0; i < pocContractsCount; ++i) {
            if (pocContracts[i].active) {
                IProofOfCapital(pocContracts[i].pocContract).setMarketMaker(params.daoAddress, false);
                if (daoState.marketMaker != address(0)) {
                    IProofOfCapital(pocContracts[i].pocContract).setMarketMaker(daoState.marketMaker, true);
                }
            }
        }

        if (daoState.marketMaker != address(0)) {
            emit MarketMakerSet(daoState.marketMaker);
        }

        emit StageChanged(oldStage, DataTypes.Stage.Active);
    }
}

