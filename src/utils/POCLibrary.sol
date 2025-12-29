// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../interfaces/IProofOfCapital.sol";
import "./DataTypes.sol";
import "./Constants.sol";
import "./OrderbookSwapLibrary.sol";
import "./OracleLibrary.sol";

/// @title POCLibrary
/// @notice Library for POC contract operations
library POCLibrary {
    using SafeERC20 for IERC20;

    error InvalidPOCIndex();
    error POCNotActive();
    error POCAlreadyExchanged();
    error AmountMustBeGreaterThanZero();
    error AmountExceedsRemaining();
    error InvalidAddress();
    error RouterNotAvailable();
    error PriceDeviationTooHigh();
    error InvalidPrice();
    error OnlyPOCContract();
    error InvalidSharePrice();
    error NoShares();
    error InvalidPercentage();
    error POCAlreadyExists();
    error TotalShareExceeds100Percent();

    event POCExchangeCompleted(
        uint256 indexed pocIdx,
        address indexed pocContract,
        uint256 collateralAmountForPOC,
        uint256 collateralAmount,
        uint256 launchReceived
    );
    event CreatorLaunchesReturned(uint256 amount, uint256 profitPercentEquivalent, uint256 newCreatorProfitPercent);
    event POCContractAdded(address indexed pocContract, address indexed collateralToken, uint256 sharePercent);
    event SellableCollateralAdded(address indexed token, address indexed priceFeed);

    /// @notice Exchange mainCollateral for launch tokens from a specific POC contract
    /// @param daoState DAO state storage structure
    /// @param pocContracts Array of POC contracts
    /// @param accountedBalance Mapping of accounted balances
    /// @param availableRouterByAdmin Mapping of available routers
    /// @param mainCollateral Main collateral token address
    /// @param launchToken Launch token address
    /// @param totalCollectedMainCollateral Total collected main collateral
    /// @param pocIdx Index of POC contract in pocContracts array
    /// @param amount Amount of mainCollateral to exchange (0 = exchange remaining amount)
    /// @param router Router address for swap (if collateral != mainCollateral)
    /// @param swapType Type of swap to execute
    /// @param swapData Encoded swap parameters
    /// @param getOraclePrice Function pointer to get oracle price
    /// @param getPOCCollateralPriceFunc Function pointer to get POC collateral price
    /// @return launchReceived Amount of launch tokens received
    function executeExchangeForPOC(
        DataTypes.DAOState storage daoState,
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage accountedBalance,
        mapping(address => bool) storage availableRouterByAdmin,
        address mainCollateral,
        address launchToken,
        uint256 totalCollectedMainCollateral,
        uint256 pocIdx,
        uint256 amount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData,
        function(address) external view returns (uint256) getOraclePrice,
        function(uint256) external view returns (uint256) getPOCCollateralPriceFunc
    ) external returns (uint256 launchReceived) {
        require(pocIdx < pocContracts.length, InvalidPOCIndex());

        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        require(poc.active, POCNotActive());
        require(!poc.exchanged, POCAlreadyExchanged());

        uint256 totalAllocationForPOC = (totalCollectedMainCollateral * poc.sharePercent) / Constants.BASIS_POINTS;
        require(totalAllocationForPOC > 0, AmountMustBeGreaterThanZero());

        uint256 remainingAmount = totalAllocationForPOC - poc.exchangedAmount;
        require(remainingAmount > 0, POCAlreadyExchanged());

        uint256 collateralAmountForPOC = amount == 0 ? remainingAmount : amount;
        require(collateralAmountForPOC > 0, AmountMustBeGreaterThanZero());
        require(collateralAmountForPOC <= remainingAmount, AmountExceedsRemaining());

        uint256 collateralAmount;

        if (poc.collateralToken == mainCollateral) {
            collateralAmount = collateralAmountForPOC;
        } else {
            require(router != address(0), InvalidAddress());
            require(availableRouterByAdmin[router], RouterNotAvailable());

            uint256 mainCollateralPrice = getOraclePrice(mainCollateral);
            uint256 collateralPrice = getPOCCollateralPriceFunc(pocIdx);

            uint256 expectedCollateral = (collateralAmountForPOC * mainCollateralPrice) / collateralPrice;

            IERC20(mainCollateral).safeIncreaseAllowance(router, collateralAmountForPOC);

            uint256 balanceBefore = IERC20(poc.collateralToken).balanceOf(address(this));

            collateralAmount = OrderbookSwapLibrary.executeSwap(
                router, swapType, swapData, mainCollateral, poc.collateralToken, collateralAmountForPOC, 0
            );

            uint256 balanceAfter = IERC20(poc.collateralToken).balanceOf(address(this));
            collateralAmount = balanceAfter - balanceBefore;

            uint256 deviation = OracleLibrary.calculateDeviation(expectedCollateral, collateralAmount);
            require(deviation <= Constants.PRICE_DEVIATION_MAX, PriceDeviationTooHigh());
        }

        IERC20(poc.collateralToken).safeIncreaseAllowance(poc.pocContract, collateralAmount);

        uint256 launchBalanceBefore = IERC20(launchToken).balanceOf(address(this));

        IProofOfCapital(poc.pocContract).buyLaunchTokens(collateralAmount);

        uint256 launchBalanceAfter = IERC20(launchToken).balanceOf(address(this));
        launchReceived = launchBalanceAfter - launchBalanceBefore;

        poc.exchangedAmount += collateralAmountForPOC;

        if (poc.exchangedAmount >= totalAllocationForPOC) {
            poc.exchanged = true;
        }

        daoState.totalLaunchBalance += launchReceived;
        accountedBalance[launchToken] += launchReceived;

        emit POCExchangeCompleted(pocIdx, poc.pocContract, collateralAmountForPOC, collateralAmount, launchReceived);
    }

    /// @notice Get weighted average launch token price from all active POC contracts
    /// @param pocContracts Array of POC contracts
    /// @param getPOCCollateralPriceFunc Function pointer to get POC collateral price
    /// @return Weighted average launch price in USD (18 decimals)
    function getLaunchPriceFromPOC(
        DataTypes.POCInfo[] storage pocContracts,
        function(uint256) external view returns (uint256) getPOCCollateralPriceFunc
    ) external view returns (uint256) {
        uint256 totalWeightedPrice = 0;
        uint256 totalSharePercent = 0;

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (!poc.active) {
                continue;
            }

            uint256 launchPriceInCollateral = IProofOfCapital(poc.pocContract).currentPrice();

            if (launchPriceInCollateral == 0) {
                continue;
            }

            uint256 collateralPriceUSD = getPOCCollateralPriceFunc(i);

            if (collateralPriceUSD == 0) {
                continue;
            }

            uint256 launchPriceUSD =
                (launchPriceInCollateral * collateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

            if (launchPriceUSD == 0) {
                continue;
            }

            totalWeightedPrice += (launchPriceUSD * poc.sharePercent);
            totalSharePercent += poc.sharePercent;
        }

        return totalWeightedPrice / totalSharePercent;
    }

    /// @notice Get POC collateral price from its oracle
    /// @param pocContracts Array of POC contracts
    /// @param pocIdx POC index
    /// @return Price in USD (18 decimals)
    function getPOCCollateralPrice(DataTypes.POCInfo[] storage pocContracts, uint256 pocIdx)
        external
        view
        returns (uint256)
    {
        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        return OracleLibrary.getChainlinkPrice(poc.priceFeed);
    }

    /// @notice Return launch tokens from POC contract, restoring creator's profit share
    /// @param isPocContract Mapping to check if address is POC contract
    /// @param daoState DAO state storage
    /// @param launchToken Launch token address
    /// @param sharePriceInLaunches Share price in launches
    /// @param totalSharesSupply Total shares supply
    /// @param amount Amount of launch tokens to return
    /// @return profitPercentEquivalent Profit percent equivalent returned
    function executeUpgradeOwnerShare(
        mapping(address => bool) storage isPocContract,
        DataTypes.DAOState storage daoState,
        address launchToken,
        uint256 sharePriceInLaunches,
        uint256 totalSharesSupply,
        uint256 amount
    ) external returns (uint256 profitPercentEquivalent) {
        address sender = msg.sender;
        require(isPocContract[sender], OnlyPOCContract());
        require(amount > 0, AmountMustBeGreaterThanZero());

        IERC20(launchToken).safeTransferFrom(sender, address(this), amount);

        require(sharePriceInLaunches > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (amount * Constants.PRICE_DECIMALS_MULTIPLIER) / sharePriceInLaunches;

        require(totalSharesSupply > 0, NoShares());
        profitPercentEquivalent = (sharesEquivalent * Constants.BASIS_POINTS) / totalSharesSupply;

        uint256 newCreatorProfitPercent = daoState.creatorProfitPercent + profitPercentEquivalent;
        if (newCreatorProfitPercent > Constants.BASIS_POINTS) {
            newCreatorProfitPercent = Constants.BASIS_POINTS;
            profitPercentEquivalent = Constants.BASIS_POINTS - daoState.creatorProfitPercent;
        }

        uint256 maxCreatorProfitPercent =
            Constants.BASIS_POINTS - Constants.MIN_DAO_PROFIT_SHARE - daoState.royaltyPercent;
        if (newCreatorProfitPercent > maxCreatorProfitPercent) {
            newCreatorProfitPercent = maxCreatorProfitPercent;
            profitPercentEquivalent = maxCreatorProfitPercent - daoState.creatorProfitPercent;
        }

        daoState.creatorProfitPercent = newCreatorProfitPercent;

        emit CreatorLaunchesReturned(amount, profitPercentEquivalent, newCreatorProfitPercent);
    }

    /// @notice Add a POC contract with allocation share
    /// @param pocContracts Array of POC contracts
    /// @param pocIndex Mapping of POC contract address to index
    /// @param isPocContract Mapping to check if address is POC contract
    /// @param sellableCollaterals Mapping of sellable collaterals
    /// @param pocContract POC contract address
    /// @param collateralToken Collateral token for this POC
    /// @param priceFeed Chainlink price feed for the collateral
    /// @param sharePercent Allocation percentage in basis points (10000 = 100%)
    function executeAddPOCContract(
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage pocIndex,
        mapping(address => bool) storage isPocContract,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        address pocContract,
        address collateralToken,
        address priceFeed,
        uint256 sharePercent
    ) external {
        require(pocContract != address(0), InvalidAddress());
        require(collateralToken != address(0), InvalidAddress());
        require(priceFeed != address(0), InvalidAddress());
        require(sharePercent > 0 && sharePercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(pocIndex[pocContract] == 0, POCAlreadyExists());

        uint256 totalShare = sharePercent;
        for (uint256 i = 0; i < pocContracts.length; ++i) {
            totalShare += pocContracts[i].sharePercent;
        }
        require(totalShare <= Constants.BASIS_POINTS, TotalShareExceeds100Percent());

        if (!sellableCollaterals[collateralToken].active) {
            sellableCollaterals[collateralToken] =
                DataTypes.CollateralInfo({token: collateralToken, priceFeed: priceFeed, active: true});
            emit SellableCollateralAdded(collateralToken, priceFeed);
        }

        pocContracts.push(
            DataTypes.POCInfo({
                pocContract: pocContract,
                collateralToken: collateralToken,
                priceFeed: priceFeed,
                sharePercent: sharePercent,
                active: true,
                exchanged: false,
                exchangedAmount: 0
            })
        );

        pocIndex[pocContract] = pocContracts.length;
        isPocContract[pocContract] = true;

        emit POCContractAdded(pocContract, collateralToken, sharePercent);
    }
}

