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
import "../../interfaces/IProofOfCapital.sol";
import "../internal/LPProcessingLibrary.sol";

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

    event LPTokensProvided(address indexed lpToken, uint256 amount);
    event V3LPPositionProvided(uint256 indexed tokenId, address token0, address token1);
    event V2LPTokenDissolved(address indexed lpToken, uint256 amount0, uint256 amount1);
    event V3LPPositionDissolved(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event LPProfitDistributed(address indexed lpToken, uint256 amount);
    event V3LiquidityDecreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);
    event StageChanged(DataTypes.Stage oldStage, DataTypes.Stage newStage);
    event MarketMakerSet(address indexed marketMaker);

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
    /// @param v2LPTokenAddresses Array of V2 LP token addresses
    /// @param v2LPAmounts Array of V2 LP token amounts to deposit
    /// @param v3TokenIds Array of V3 LP position token IDs
    /// @param newV2PricePaths Array of new V2 price paths to add
    /// @param newV3PricePaths Array of new V3 price paths to add
    /// @param primaryLPTokenType Primary LP token type
    /// @param pocContracts Array of POC contracts
    /// @param daoAddress Address of the DAO contract
    function executeProvideLPTokens(
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        mapping(address => uint256) storage accountedBalance,
        address[] calldata v2LPTokenAddresses,
        uint256[] calldata v2LPAmounts,
        uint256[] calldata v3TokenIds,
        DataTypes.PricePathV2Params[] calldata newV2PricePaths,
        DataTypes.PricePathV3Params[] calldata newV3PricePaths,
        DataTypes.LPTokenType primaryLPTokenType,
        DataTypes.POCInfo[] storage pocContracts,
        address daoAddress
    ) external {
        require(v2LPTokenAddresses.length == v2LPAmounts.length, InvalidAddresses());
        require(v2LPTokenAddresses.length > 0 || v3TokenIds.length > 0, InvalidAddress());

        for (uint256 i = 0; i < newV2PricePaths.length; ++i) {
            if (newV2PricePaths[i].router != address(0) && newV2PricePaths[i].path.length >= 2) {
                pricePathsStorage.v2Paths
                    .push(DataTypes.PricePathV2({router: newV2PricePaths[i].router, path: newV2PricePaths[i].path}));
            }
        }

        for (uint256 i = 0; i < newV3PricePaths.length; ++i) {
            if (newV3PricePaths[i].quoter != address(0) && newV3PricePaths[i].path.length >= 43) {
                pricePathsStorage.v3Paths
                    .push(DataTypes.PricePathV3({quoter: newV3PricePaths[i].quoter, path: newV3PricePaths[i].path}));
            }
        }

        if (primaryLPTokenType == DataTypes.LPTokenType.V2) {
            require(v2LPTokenAddresses.length > 0, InvalidAddress());
        } else if (primaryLPTokenType == DataTypes.LPTokenType.V3) {
            require(v3TokenIds.length > 0, InvalidAddress());
        }

        for (uint256 i = 0; i < v2LPTokenAddresses.length; ++i) {
            address lpToken = v2LPTokenAddresses[i];
            uint256 lpAmount = v2LPAmounts[i];

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

        if (v3TokenIds.length > 0) {
            require(lpTokenStorage.v3PositionManager != address(0), InvalidAddress());

            for (uint256 i = 0; i < v3TokenIds.length; ++i) {
                uint256 tokenId = v3TokenIds[i];
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
                IProofOfCapital(pocContracts[i].pocContract).setMarketMaker(daoAddress, false);
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

