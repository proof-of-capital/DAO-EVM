// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "./FundraisingLibrary.sol";
import "./OracleLibrary.sol";
import "../../interfaces/IPriceOracle.sol";
import "../../interfaces/IProofOfCapital.sol";

/// @title ConfigLibrary
/// @notice Library for DAO initialization and config setters
library ConfigLibrary {
    error InvalidAddress();
    error InvalidPercentage();
    error InvalidLaunchToken();
    error InvalidSharePrice();
    error InvalidTargetAmount();
    error InvalidInitialPrice();
    error InvalidVolume();
    error InvalidV3PositionManager();
    error V3PositionManagerMismatch();
    error RouterAlreadyAdded();
    error TokenAlreadyAdded();
    error Unauthorized();
    error PriceOracleAlreadySet();

    event RouterAvailabilityChanged(address indexed router, bool isAvailable);
    event VotingContractSet(address indexed votingContract);
    event CreatorSet(address indexed creator, uint256 profitPercent, uint256 infraPercent);
    event FundraisingConfigured(uint256 minDeposit, uint256 sharePrice, uint256 targetAmount, uint256 deadline);
    event OrderbookParamsUpdated(
        uint256 initialPrice,
        uint256 initialVolume,
        uint256 priceStepPercent,
        int256 volumeStepPercent,
        uint256 proportionalityCoefficient,
        uint256 totalSupply
    );
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event IsVetoToCreatorSet(bool oldValue, bool newValue);
    event RoyaltyRecipientSet(address indexed oldRoyaltyRecipient, address indexed newRoyaltyRecipient);
    event PendingUpgradeSetFromVoting(address indexed newImplementation);
    event PendingUpgradeSetFromCreator(address indexed newImplementation);
    event MarketMakerSet(address indexed marketMaker);
    event PrivateSaleRegistered(address indexed privateSaleContract);
    event PriceOracleSet(address indexed priceOracle);

    function executeInitialize(
        DataTypes.CoreConfig storage _coreConfig,
        DataTypes.DAOState storage _daoState,
        DataTypes.VaultStorage storage _vaultStorage,
        DataTypes.LPTokenStorage storage _lpTokenStorage,
        DataTypes.FundraisingConfig storage _fundraisingConfig,
        mapping(address => bool) storage _availableRouterByAdmin,
        mapping(address => bool) storage _allowedExitTokens,
        DataTypes.POCInfo[] storage _pocContracts,
        mapping(address => uint256) storage _pocIndex,
        mapping(address => bool) storage _isPocContract,
        DataTypes.RewardsStorage storage _rewardsStorage,
        mapping(address => DataTypes.CollateralInfo) storage _sellableCollaterals,
        DataTypes.OrderbookParams storage _orderbookParams,
        DataTypes.PricePathsStorage storage _pricePathsStorage,
        DataTypes.ConstructorParams memory params
    ) external {
        require(params.launchToken != address(0), InvalidLaunchToken());
        require(params.mainCollateral != address(0), InvalidAddress());
        require(params.creatorProfitPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.creatorInfraPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.royaltyPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.sharePrice > 0, InvalidSharePrice());
        require(params.targetAmountMainCollateral > 0, InvalidTargetAmount());
        require(params.orderbookParams.initialPrice > 0, InvalidInitialPrice());
        require(params.orderbookParams.initialVolume > 0, InvalidVolume());
        require(params.orderbookParams.totalSupply > 0, InvalidVolume());

        _coreConfig.launchToken = params.launchToken;
        _coreConfig.mainCollateral = params.mainCollateral;
        _coreConfig.priceOracle = params.priceOracle;
        _coreConfig.admin = msg.sender;
        _coreConfig.creator = params.creator;
        _coreConfig.creatorInfraPercent = params.creatorInfraPercent;
        _coreConfig.primaryLPTokenType = params.primaryLPTokenType;
        _coreConfig.votingContract = params.votingContract;

        _daoState.currentStage = DataTypes.Stage.Fundraising;
        _daoState.creator = params.creator;
        _daoState.creatorProfitPercent = params.creatorProfitPercent;
        _daoState.royaltyRecipient = params.royaltyRecipient;
        _daoState.royaltyPercent = params.royaltyPercent;
        _daoState.totalCollectedMainCollateral = 0;
        _daoState.lastCreatorAllocation = 0;
        _daoState.totalDepositedUSD = 0;
        _daoState.pendingExitQueuePayment = 0;
        _daoState.marketMaker = params.marketMaker;

        _vaultStorage.nextVaultId = 1;
        _vaultStorage.totalSharesSupply = 0;

        if (params.v3LPPositions.length > 0) {
            _lpTokenStorage.v3PositionManager = params.v3LPPositions[0].positionManager;
            require(_lpTokenStorage.v3PositionManager != address(0), InvalidV3PositionManager());
            for (uint256 i = 0; i < params.v3LPPositions.length; ++i) {
                require(
                    params.v3LPPositions[i].positionManager == _lpTokenStorage.v3PositionManager,
                    V3PositionManagerMismatch()
                );
            }
        }

        _fundraisingConfig.minDeposit = params.minDeposit;
        _fundraisingConfig.minLaunchDeposit = params.minLaunchDeposit;
        _fundraisingConfig.sharePrice = params.sharePrice;
        _fundraisingConfig.launchPrice = params.launchPrice;
        _fundraisingConfig.sharePriceStart = 0;
        _fundraisingConfig.launchPriceStart = 0;
        _fundraisingConfig.targetAmountMainCollateral = params.targetAmountMainCollateral;
        _fundraisingConfig.deadline = block.timestamp + params.fundraisingDuration;
        _fundraisingConfig.extensionPeriod = params.extensionPeriod;
        _fundraisingConfig.extended = false;

        for (uint256 i = 0; i < params.routers.length; ++i) {
            address router = params.routers[i];
            require(router != address(0), InvalidAddress());
            require(!_availableRouterByAdmin[router], RouterAlreadyAdded());
            _availableRouterByAdmin[router] = true;
            emit RouterAvailabilityChanged(router, true);
        }

        for (uint256 i = 0; i < params.allowedExitTokens.length; ++i) {
            address token = params.allowedExitTokens[i];
            require(token != address(0), InvalidAddress());
            _allowedExitTokens[token] = true;
        }

        FundraisingLibrary.executeInitializePOCContracts(
            _pocContracts, _pocIndex, _isPocContract, _rewardsStorage, _sellableCollaterals, params.pocParams
        );
        FundraisingLibrary.executeInitializeRewardTokens(_rewardsStorage, params.rewardTokenParams, params.launchToken);

        _orderbookParams.initialPrice = params.orderbookParams.initialPrice;
        _orderbookParams.initialVolume = params.orderbookParams.initialVolume;
        _orderbookParams.priceStepPercent = params.orderbookParams.priceStepPercent;
        _orderbookParams.volumeStepPercent = params.orderbookParams.volumeStepPercent;
        _orderbookParams.proportionalityCoefficient = params.orderbookParams.proportionalityCoefficient;
        _orderbookParams.totalSupply = params.orderbookParams.totalSupply;
        _orderbookParams.totalSold = 0;
        _orderbookParams.currentLevel = 0;
        _orderbookParams.currentTotalSold = 0;
        _orderbookParams.currentCumulativeVolume = 0;
        _orderbookParams.cachedPriceAtLevel = params.orderbookParams.initialPrice;
        _orderbookParams.cachedBaseVolumeAtLevel = params.orderbookParams.initialVolume;

        OracleLibrary.initializePricePaths(_pricePathsStorage, params.launchTokenPricePaths);

        if (params.lpDepegParams.length > 0) {
            uint256 totalRatioBps;
            for (uint256 i = 0; i < params.lpDepegParams.length; ++i) {
                DataTypes.LPTokenDepegParams memory p = params.lpDepegParams[i];
                require(p.token != address(0), InvalidAddress());
                DataTypes.CollateralInfo storage info = _sellableCollaterals[p.token];
                info.token = p.token;
                info.ratioBps = p.ratioBps;
                info.depegThresholdMinPrice = p.depegThresholdMinPrice;
                totalRatioBps += p.ratioBps;
            }
            require(totalRatioBps == Constants.BASIS_POINTS, InvalidPercentage());
        }

        require(params.votingContract != address(0), InvalidAddress());
        emit VotingContractSet(params.votingContract);
        emit CreatorSet(params.creator, params.creatorProfitPercent, params.creatorInfraPercent);
        emit FundraisingConfigured(
            params.minDeposit, params.sharePrice, params.targetAmountMainCollateral, _fundraisingConfig.deadline
        );
        emit OrderbookParamsUpdated(
            params.orderbookParams.initialPrice,
            params.orderbookParams.initialVolume,
            params.orderbookParams.priceStepPercent,
            params.orderbookParams.volumeStepPercent,
            params.orderbookParams.proportionalityCoefficient,
            params.orderbookParams.totalSupply
        );
    }

    function executeSetVotingContract(DataTypes.CoreConfig storage _coreConfig, address _votingContractNew) external {
        require(_votingContractNew != address(0), InvalidAddress());
        require(_coreConfig.votingContract != address(0), InvalidAddress());
        _coreConfig.votingContract = _votingContractNew;
        emit VotingContractSet(_votingContractNew);
    }

    function executeSetAdmin(DataTypes.CoreConfig storage _coreConfig, address newAdmin) external {
        require(newAdmin != address(0), InvalidAddress());
        require(msg.sender == address(this) || msg.sender == _coreConfig.admin, Unauthorized());
        require(_coreConfig.votingContract != address(0) || msg.sender == _coreConfig.admin, InvalidAddress());
        address oldAdmin = _coreConfig.admin;
        _coreConfig.admin = newAdmin;
        emit AdminSet(oldAdmin, newAdmin);
    }

    function executeSetIsVetoToCreator(DataTypes.CoreConfig storage _coreConfig, bool value) external {
        bool oldValue = _coreConfig.isVetoToCreator;
        _coreConfig.isVetoToCreator = value;
        emit IsVetoToCreatorSet(oldValue, value);
    }

    function executeSetRoyaltyRecipient(
        DataTypes.DAOState storage _daoState,
        DataTypes.CoreConfig storage _coreConfig,
        address newRoyaltyRecipient
    ) external {
        require(newRoyaltyRecipient != address(0), InvalidAddress());
        require(msg.sender == _daoState.royaltyRecipient, Unauthorized());
        require(_coreConfig.votingContract != address(0) || msg.sender == _daoState.royaltyRecipient, InvalidAddress());
        address oldRoyaltyRecipient = _daoState.royaltyRecipient;
        _daoState.royaltyRecipient = newRoyaltyRecipient;
        emit RoyaltyRecipientSet(oldRoyaltyRecipient, newRoyaltyRecipient);
    }

    function executeSetPendingUpgradeFromVoting(DataTypes.CoreConfig storage _coreConfig, address newImplementation)
        external
    {
        _coreConfig.pendingUpgradeFromVoting = newImplementation;
        _coreConfig.pendingUpgradeFromVotingTimestamp = block.timestamp;
        emit PendingUpgradeSetFromVoting(newImplementation);
    }

    function executeSetPendingUpgradeFromCreator(DataTypes.CoreConfig storage _coreConfig, address newImplementation)
        external
    {
        _coreConfig.pendingUpgradeFromCreator = newImplementation;
        emit PendingUpgradeSetFromCreator(newImplementation);
    }

    function executeSetCreator(
        DataTypes.CoreConfig storage _coreConfig,
        DataTypes.DAOState storage _daoState,
        address newCreator,
        uint256 _creatorProfitPercent,
        uint256 _creatorInfraPercent
    ) external {
        require(newCreator != address(0), InvalidAddress());
        require(_coreConfig.creator == address(0), TokenAlreadyAdded());
        _coreConfig.creator = newCreator;
        _daoState.creator = newCreator;
        emit CreatorSet(newCreator, _creatorProfitPercent, _creatorInfraPercent);
    }

    function executeSetMarketMaker(
        DataTypes.DAOState storage _daoState,
        DataTypes.POCInfo[] storage _pocContracts,
        address newMarketMaker
    ) external {
        require(newMarketMaker != address(0), InvalidAddress());
        address oldMarketMaker = _daoState.marketMaker;
        _daoState.marketMaker = newMarketMaker;
        uint256 pocContractsCount = _pocContracts.length;
        for (uint256 i = 0; i < pocContractsCount; ++i) {
            if (_pocContracts[i].active) {
                if (oldMarketMaker != address(0)) {
                    IProofOfCapital(_pocContracts[i].pocContract).setMarketMaker(oldMarketMaker, false);
                }
                IProofOfCapital(_pocContracts[i].pocContract).setMarketMaker(newMarketMaker, true);
            }
        }
        emit MarketMakerSet(newMarketMaker);
    }

    function executeRegisterPrivateSale(DataTypes.DAOState storage _daoState, address _privateSaleContract) external {
        require(_privateSaleContract != address(0), InvalidAddress());
        require(_daoState.privateSaleContract == address(0), TokenAlreadyAdded());
        _daoState.privateSaleContract = _privateSaleContract;
        emit PrivateSaleRegistered(_privateSaleContract);
    }

    function executeSetPriceOracle(DataTypes.CoreConfig storage _coreConfig, address newPriceOracle) external {
        require(newPriceOracle != address(0), InvalidAddress());
        require(_coreConfig.priceOracle == address(0), PriceOracleAlreadySet());
        _coreConfig.priceOracle = newPriceOracle;
        emit PriceOracleSet(newPriceOracle);
    }
}
