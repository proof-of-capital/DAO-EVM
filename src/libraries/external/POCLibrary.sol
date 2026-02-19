// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../../interfaces/IPriceOracle.sol";
import "../../interfaces/IProofOfCapital.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "../internal/SwapLibrary.sol";
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
    error MaxPOCContractsReached();
    error POCIsActive();
    error POCStillHasBalances();
    error POCNotFound();
    error POCReturnTooSoon();
    error POCReturnExceedsMaxAmount();
    error NoPOCContractsActive();

    event POCExchangeCompleted(
        uint256 indexed pocIdx,
        address indexed pocContract,
        uint256 collateralAmountForPOC,
        uint256 collateralAmount,
        uint256 launchReceived
    );
    event CreatorLaunchesReturned(uint256 amount, uint256 profitPercentEquivalent, uint256 newCreatorProfitPercent);
    event POCContractAdded(address indexed pocContract, address indexed collateralToken, uint256 sharePercent);
    event POCContractRemoved(address indexed pocContract);
    event SellableCollateralAdded(address indexed token);
    event LaunchesReturnedToPOC(uint256 totalAmount, uint256 pocCount);

    struct ExecuteExchangeForPOCParams {
        uint256 pocIdx;
        uint256 amount;
        address router;
        DataTypes.SwapType swapType;
        IPriceOracle priceOracle;
        address mainCollateral;
        address launchToken;
        uint256 totalCollectedMainCollateral;
    }

    /// @notice Exchange mainCollateral for launch tokens from a specific POC contract
    /// @param pocContracts Array of POC contracts
    /// @param accountedBalance Mapping of accounted balances
    /// @param availableRouterByAdmin Mapping of available routers
    /// @param sellableCollaterals Mapping of sellable collaterals
    /// @param coreConfig DAO core config (mainCollateral, launchToken, priceOracle)
    /// @param totalCollectedMainCollateral Total collected main collateral
    /// @param params POC exchange parameters (pocIdx, amount, router, swapType)
    /// @param swapData Encoded swap parameters
    /// @return launchReceived Amount of launch tokens received
    function executeExchangeForPOC(
        DataTypes.DAOState storage,
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage accountedBalance,
        mapping(address => bool) storage availableRouterByAdmin,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.CoreConfig storage coreConfig,
        uint256 totalCollectedMainCollateral,
        DataTypes.POCExchangeParams memory params,
        bytes calldata swapData
    ) external returns (uint256 launchReceived) {
        require(params.pocIdx < pocContracts.length, InvalidPOCIndex());

        DataTypes.POCInfo memory poc = pocContracts[params.pocIdx];
        require(poc.active, POCNotActive());
        require(!poc.exchanged, POCAlreadyExchanged());

        uint256 totalAllocationForPOC = (totalCollectedMainCollateral * poc.sharePercent) / Constants.BASIS_POINTS;
        require(totalAllocationForPOC > 0, AmountMustBeGreaterThanZero());

        uint256 remainingAmount = totalAllocationForPOC - poc.exchangedAmount;
        require(remainingAmount > 0, POCAlreadyExchanged());

        uint256 collateralAmountForPOC = params.amount == 0 ? remainingAmount : params.amount;
        require(collateralAmountForPOC > 0, AmountMustBeGreaterThanZero());
        require(collateralAmountForPOC <= remainingAmount, AmountExceedsRemaining());

        uint256 collateralAmount;

        if (poc.collateralToken == coreConfig.mainCollateral) {
            collateralAmount = collateralAmountForPOC;
        } else {
            require(params.router != address(0), InvalidAddress());
            require(availableRouterByAdmin[params.router], RouterNotAvailable());

            uint256 mainCollateralPrice = OracleLibrary.getOraclePrice(
                IPriceOracle(coreConfig.priceOracle), sellableCollaterals, coreConfig.mainCollateral
            );
            uint256 collateralPrice = IPriceOracle(coreConfig.priceOracle).getAssetPrice(poc.collateralToken);

            uint256 expectedCollateral = (collateralAmountForPOC * mainCollateralPrice) / collateralPrice;

            IERC20(coreConfig.mainCollateral).safeIncreaseAllowance(params.router, collateralAmountForPOC);

            uint256 balanceBefore = IERC20(poc.collateralToken).balanceOf(address(this));

            SwapLibrary.executeSwap(
                params.router,
                params.swapType,
                swapData,
                coreConfig.mainCollateral,
                poc.collateralToken,
                collateralAmountForPOC,
                0
            );

            uint256 balanceAfter = IERC20(poc.collateralToken).balanceOf(address(this));
            collateralAmount = balanceAfter - balanceBefore;

            uint256 deviation = OracleLibrary.calculateDeviation(expectedCollateral, collateralAmount);
            require(deviation <= Constants.PRICE_DEVIATION_MAX, PriceDeviationTooHigh());
        }

        IERC20(poc.collateralToken).safeIncreaseAllowance(poc.pocContract, collateralAmount);

        uint256 launchBalanceBefore = IERC20(coreConfig.launchToken).balanceOf(address(this));

        IProofOfCapital(poc.pocContract).buyLaunchTokens(collateralAmount);

        uint256 launchBalanceAfter = IERC20(coreConfig.launchToken).balanceOf(address(this));
        launchReceived = launchBalanceAfter - launchBalanceBefore;

        poc.exchangedAmount += collateralAmountForPOC;

        if (poc.exchangedAmount >= totalAllocationForPOC) {
            poc.exchanged = true;
        }

        pocContracts[params.pocIdx] = poc;

        accountedBalance[coreConfig.launchToken] += launchReceived;

        emit POCExchangeCompleted(
            params.pocIdx, poc.pocContract, collateralAmountForPOC, collateralAmount, launchReceived
        );
    }

    /// @notice Get POC collateral price from price oracle
    /// @param priceOracle Price oracle contract
    /// @param pocContracts Array of POC contracts
    /// @param pocIdx POC index
    /// @return Price in USD (18 decimals)
    function getPOCCollateralPrice(IPriceOracle priceOracle, DataTypes.POCInfo[] storage pocContracts, uint256 pocIdx)
        external
        view
        returns (uint256)
    {
        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        return priceOracle.getAssetPrice(poc.collateralToken);
    }

    /// @notice Return launch tokens from POC contract, restoring creator's profit share
    /// @param isPocContract Mapping to check if address is POC contract
    /// @param daoState DAO state storage
    /// @param sharePrice Share price
    /// @param totalSharesSupply Total shares supply
    /// @param amount Amount of launch tokens to return
    /// @return profitPercentEquivalent Profit percent equivalent returned
    function executeUpgradeOwnerShare(
        mapping(address => bool) storage isPocContract,
        DataTypes.DAOState storage daoState,
        uint256 sharePrice,
        uint256 totalSharesSupply,
        uint256 amount
    ) external returns (uint256 profitPercentEquivalent) {
        require(isPocContract[msg.sender], OnlyPOCContract());
        require(amount > 0, AmountMustBeGreaterThanZero());

        require(sharePrice > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (amount * Constants.PRICE_DECIMALS_MULTIPLIER) / sharePrice;

        require(totalSharesSupply > 0, NoShares());

        uint256 daoProfitPercent = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;

        profitPercentEquivalent = (sharesEquivalent * daoProfitPercent) / totalSharesSupply;

        uint256 newDaoProfitPercent =
            (daoProfitPercent * Constants.BASIS_POINTS) / (Constants.BASIS_POINTS + profitPercentEquivalent);

        if (newDaoProfitPercent < Constants.MIN_DAO_PROFIT_SHARE) {
            newDaoProfitPercent = Constants.MIN_DAO_PROFIT_SHARE;
            profitPercentEquivalent =
                ((daoProfitPercent - newDaoProfitPercent) * Constants.BASIS_POINTS) / daoProfitPercent;
        }

        uint256 newCreatorProfitPercent = Constants.BASIS_POINTS - newDaoProfitPercent - daoState.royaltyPercent;

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
    /// @param sharePercent Allocation percentage in basis points (10000 = 100%)
    function executeAddPOCContract(
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage pocIndex,
        mapping(address => bool) storage isPocContract,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        address pocContract,
        address collateralToken,
        uint256 sharePercent
    ) external {
        require(pocContracts.length < Constants.MAX_POC_CONTRACTS, MaxPOCContractsReached());
        require(pocContract != address(0), InvalidAddress());
        require(collateralToken != address(0), InvalidAddress());
        require(sharePercent > 0 && sharePercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(pocIndex[pocContract] == 0, POCAlreadyExists());

        uint256 totalShare = sharePercent;
        for (uint256 i = 0; i < pocContracts.length; ++i) {
            totalShare += pocContracts[i].sharePercent;
        }
        require(totalShare <= Constants.BASIS_POINTS, TotalShareExceeds100Percent());

        if (!sellableCollaterals[collateralToken].active) {
            sellableCollaterals[collateralToken] = DataTypes.CollateralInfo({
                token: collateralToken, active: true, ratioBps: 0, depegThresholdMinPrice: 0
            });
            emit SellableCollateralAdded(collateralToken);
        }

        pocContracts.push(
            DataTypes.POCInfo({
                pocContract: pocContract,
                collateralToken: collateralToken,
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

    /// @notice Remove an inactive POC contract from the list
    /// @param pocContracts Array of POC contracts
    /// @param pocIndex Mapping of POC contract address to index
    /// @param isPocContract Mapping to check if address is POC contract
    /// @param pocContract POC contract address to remove
    function executeRemovePOCContract(
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage pocIndex,
        mapping(address => bool) storage isPocContract,
        address pocContract
    ) external {
        require(pocContract != address(0), InvalidAddress());
        require(pocIndex[pocContract] != 0, POCNotFound());

        IProofOfCapital poc = IProofOfCapital(pocContract);
        require(!poc.isActive(), POCIsActive());
        require(poc.launchBalance() == 0, POCStillHasBalances());
        require(poc.contractCollateralBalance() == 0, POCStillHasBalances());

        uint256 idx = pocIndex[pocContract] - 1;
        uint256 lastIdx = pocContracts.length - 1;

        if (idx != lastIdx) {
            DataTypes.POCInfo storage lastPoc = pocContracts[lastIdx];
            pocContracts[idx] = lastPoc;
            pocIndex[lastPoc.pocContract] = idx + 1;
        }

        pocContracts.pop();
        pocIndex[pocContract] = 0;
        isPocContract[pocContract] = false;

        emit POCContractRemoved(pocContract);
    }

    /// @notice Return launch tokens to POC contracts proportionally to their share percentages
    /// @param pocContracts Array of POC contracts
    /// @param daoState DAO state storage
    /// @param accountedBalance Mapping of accounted balances
    /// @param launchToken Launch token address
    /// @param amount Total amount of launch tokens to return
    function executeReturnLaunchesToPOC(
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.DAOState storage daoState,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        uint256 amount
    ) external {
        require(block.timestamp >= daoState.lastPOCReturn + Constants.POC_RETURN_PERIOD, POCReturnTooSoon());
        require(amount > 0, AmountMustBeGreaterThanZero());

        uint256 maxReturn = (accountedBalance[launchToken] * Constants.POC_RETURN_MAX_PERCENT) / Constants.BASIS_POINTS;
        require(amount <= maxReturn, POCReturnExceedsMaxAmount());

        uint256 totalActiveSharePercent = 0;
        uint256 activePocCount = 0;

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            if (pocContracts[i].active) {
                totalActiveSharePercent += pocContracts[i].sharePercent;
                ++activePocCount;
            }
        }

        require(activePocCount > 0, NoPOCContractsActive());

        uint256 distributed = 0;

        for (uint256 i = 0; i < pocContracts.length; ++i) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (!poc.active) {
                continue;
            }

            uint256 pocAmount;
            if (
                i == pocContracts.length - 1 || (i < pocContracts.length - 1 && !_hasMoreActivePOC(pocContracts, i + 1))
            ) {
                pocAmount = amount - distributed;
            } else {
                pocAmount = (amount * poc.sharePercent) / totalActiveSharePercent;
            }

            if (pocAmount == 0) {
                continue;
            }

            IERC20(launchToken).safeIncreaseAllowance(poc.pocContract, pocAmount);
            IProofOfCapital(poc.pocContract).depositLaunch(pocAmount);

            distributed += pocAmount;
        }

        accountedBalance[launchToken] -= distributed;
        daoState.lastPOCReturn = block.timestamp;

        emit LaunchesReturnedToPOC(distributed, activePocCount);
    }

    /// @notice Check if there are more active POC contracts after given index
    /// @param pocContracts Array of POC contracts
    /// @param startIdx Starting index to check from
    /// @return hasMore True if there are more active POC contracts
    function _hasMoreActivePOC(DataTypes.POCInfo[] storage pocContracts, uint256 startIdx)
        private
        view
        returns (bool hasMore)
    {
        for (uint256 i = startIdx; i < pocContracts.length; ++i) {
            if (pocContracts[i].active) {
                return true;
            }
        }
        return false;
    }
}

