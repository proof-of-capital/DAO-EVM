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
import "./VaultLibrary.sol";
import "../internal/VaultValidationLibrary.sol";
import "../internal/RewardsCalculationLibrary.sol";
import "../../interfaces/IProofOfCapital.sol";

/// @title FundraisingLibrary
/// @notice Library for fundraising operations
library FundraisingLibrary {
    using SafeERC20 for IERC20;

    error InvalidAddress();
    error InvalidPercentage();
    error POCAlreadyExists();
    error POCSharesNot100Percent();
    error TokenAlreadyAdded();
    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error NoSharesToClaim();
    error NoShares();
    error NoDepositToWithdraw();
    error NoSharesIssued();
    error POCNotExchanged();
    error AmountMustBeGreaterThanZero();
    error DepositBelowMinimum();
    error SharesCalculationFailed();
    error FundraisingAlreadyExtended();
    error FundraisingNotExpiredYet();
    error TargetNotReached();
    error BelowMinLaunchDeposit();
    error InvalidPrice();
    error InvalidStage();
    error ActiveStageNotSet();
    error CancelPeriodNotPassed();
    error DepositLimitExceeded();

    event SellableCollateralAdded(address indexed token);
    event RewardTokenAdded(address indexed token);
    event POCContractAdded(address indexed pocContract, address indexed collateralToken, uint256 sharePercent);
    event FundraisingWithdrawal(uint256 indexed vaultId, address indexed sender, uint256 mainCollateralAmount);
    event ExchangeFinalized(uint256 accountedLaunchBalance, uint256 sharePrice, uint256 infraLaunches);
    event StageChanged(DataTypes.Stage oldStage, DataTypes.Stage newStage);
    event FundraisingDeposit(uint256 indexed vaultId, address indexed depositor, uint256 amount, uint256 shares);
    event LaunchDeposit(
        uint256 indexed vaultId, address indexed depositor, uint256 launchAmount, uint256 shares, uint256 launchPriceUSD
    );
    event FundraisingExtended(uint256 newDeadline);
    event FundraisingCancelled(uint256 totalCollected);
    event FundraisingCollectionFinalized(uint256 totalCollected, uint256 totalShares);

    /// @notice Initialize POC contracts during DAO initialization
    /// @param pocContracts Array of POC contracts
    /// @param pocIndex Mapping of POC contract address to index
    /// @param isPocContract Mapping to check if address is POC contract
    /// @param rewardsStorage Rewards storage structure
    /// @param sellableCollaterals Mapping of sellable collaterals
    /// @param pocParams Array of POC constructor parameters
    function executeInitializePOCContracts(
        DataTypes.POCInfo[] storage pocContracts,
        mapping(address => uint256) storage pocIndex,
        mapping(address => bool) storage isPocContract,
        DataTypes.RewardsStorage storage rewardsStorage,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCConstructorParams[] memory pocParams
    ) external {
        uint256 totalPOCShare = 0;
        for (uint256 i = 0; i < pocParams.length; ++i) {
            DataTypes.POCConstructorParams memory poc = pocParams[i];

            require(poc.pocContract != address(0), InvalidAddress());
            require(poc.collateralToken != address(0), InvalidAddress());
            require(poc.sharePercent > 0 && poc.sharePercent <= Constants.BASIS_POINTS, InvalidPercentage());
            require(pocIndex[poc.pocContract] == 0, POCAlreadyExists());

            if (!sellableCollaterals[poc.collateralToken].active) {
                sellableCollaterals[poc.collateralToken] =
                    DataTypes.CollateralInfo({token: poc.collateralToken, active: true});
                emit SellableCollateralAdded(poc.collateralToken);
            }

            pocContracts.push(
                DataTypes.POCInfo({
                    pocContract: poc.pocContract,
                    collateralToken: poc.collateralToken,
                    sharePercent: poc.sharePercent,
                    active: true,
                    exchanged: false,
                    exchangedAmount: 0
                })
            );

            pocIndex[poc.pocContract] = pocContracts.length;
            isPocContract[poc.pocContract] = true;
            totalPOCShare += poc.sharePercent;

            if (!rewardsStorage.rewardTokenInfo[poc.collateralToken].active) {
                rewardsStorage.rewardTokens.push(poc.collateralToken);
                rewardsStorage.rewardTokenInfo[poc.collateralToken] =
                    DataTypes.RewardTokenInfo({token: poc.collateralToken, active: true});
                emit RewardTokenAdded(poc.collateralToken);
            }

            emit POCContractAdded(poc.pocContract, poc.collateralToken, poc.sharePercent);
        }
        require(totalPOCShare == Constants.BASIS_POINTS || totalPOCShare == 0, POCSharesNot100Percent());
    }

    /// @notice Initialize reward tokens during DAO initialization
    /// @param rewardsStorage Rewards storage structure
    /// @param rewardTokenParams Array of reward token constructor parameters
    /// @param launchToken Launch token address
    function executeInitializeRewardTokens(
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.RewardTokenConstructorParams[] memory rewardTokenParams,
        address launchToken
    ) external {
        for (uint256 i = 0; i < rewardTokenParams.length; ++i) {
            DataTypes.RewardTokenConstructorParams memory reward = rewardTokenParams[i];

            require(reward.token != address(0), InvalidAddress());
            require(!rewardsStorage.rewardTokenInfo[reward.token].active, TokenAlreadyAdded());

            rewardsStorage.rewardTokens.push(reward.token);
            rewardsStorage.rewardTokenInfo[reward.token] =
                DataTypes.RewardTokenInfo({token: reward.token, active: true});
            emit RewardTokenAdded(reward.token);
        }

        if (!rewardsStorage.rewardTokenInfo[address(launchToken)].active) {
            rewardsStorage.rewardTokens.push(address(launchToken));
            rewardsStorage.rewardTokenInfo[address(launchToken)] =
                DataTypes.RewardTokenInfo({token: address(launchToken), active: true});
            emit RewardTokenAdded(address(launchToken));
        }
    }

    /// @notice Withdraw funds if fundraising was cancelled
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage structure
    /// @param participantEntries Mapping of participant entries
    /// @param mainCollateral Main collateral token address
    /// @param totalSharesSupply Total shares supply
    function executeWithdrawFundraising(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        address mainCollateral,
        uint256 totalSharesSupply
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 shares = vault.shares;
        require(shares > 0, NoSharesToClaim());
        require(totalSharesSupply > 0, NoShares());

        uint256 mainCollateralAmount = (daoState.totalCollectedMainCollateral * shares) / totalSharesSupply;
        require(mainCollateralAmount > 0, NoDepositToWithdraw());

        vault.shares = 0;
        vaultStorage.totalSharesSupply -= shares;
        daoState.totalCollectedMainCollateral -= mainCollateralAmount;

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        entry.depositedMainCollateral = 0;
        vault.mainCollateralDeposit = 0;

        uint256 vaultDepositedUSD = vault.depositedUSD;
        if (vaultDepositedUSD > 0) {
            if (daoState.totalDepositedUSD >= vaultDepositedUSD) {
                daoState.totalDepositedUSD -= vaultDepositedUSD;
            } else {
                daoState.totalDepositedUSD = 0;
            }
            vault.depositedUSD = 0;
        }

        vaultStorage.vaults[vaultId] = vault;

        IERC20(mainCollateral).safeTransfer(msg.sender, mainCollateralAmount);

        emit FundraisingWithdrawal(vaultId, msg.sender, mainCollateralAmount);
    }

    /// @notice Finalize exchange process and calculate share price in launches
    /// @param pocContracts Array of POC contracts
    /// @param daoState DAO state storage
    /// @param fundraisingConfig Fundraising configuration
    /// @param accountedBalance Mapping of accounted balances
    /// @param launchToken Launch token address
    /// @param creator Creator address
    /// @param creatorInfraPercent Creator infrastructure percent
    /// @param totalSharesSupply Total shares supply
    /// @param getOraclePrice Function pointer to get oracle price for a token
    function executeFinalizeExchange(
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        address creator,
        uint256 creatorInfraPercent,
        uint256 totalSharesSupply,
        function(address) external returns (uint256) getOraclePrice
    ) external returns (uint256 waitingForLPStartedAt) {
        for (uint256 i = 0; i < pocContracts.length; ++i) {
            require(pocContracts[i].exchanged, POCNotExchanged());
        }

        require(totalSharesSupply > 0, NoSharesIssued());
        fundraisingConfig.sharePrice =
            (accountedBalance[launchToken] * Constants.PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;

        fundraisingConfig.sharePriceStart = fundraisingConfig.sharePrice;
        fundraisingConfig.launchPriceStart = getOraclePrice(launchToken);

        uint256 infraLaunches = (accountedBalance[launchToken] * creatorInfraPercent) / Constants.BASIS_POINTS;
        if (infraLaunches > 0) {
            IERC20(launchToken).safeTransfer(creator, infraLaunches);
            accountedBalance[address(launchToken)] -= infraLaunches;
        }

        DataTypes.Stage oldStage = daoState.currentStage;
        daoState.currentStage = DataTypes.Stage.WaitingForLP;

        if (daoState.currentStage == DataTypes.Stage.WaitingForLP) {
            waitingForLPStartedAt = block.timestamp;
        }

        emit ExchangeFinalized(accountedBalance[launchToken], fundraisingConfig.sharePrice, infraLaunches);
        emit StageChanged(oldStage, daoState.currentStage);
    }

    /// @notice Deposit mainCollateral during fundraising stage
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage
    /// @param fundraisingConfig Fundraising configuration
    /// @param participantEntries Mapping of participant entries
    /// @param mainCollateral Main collateral token address
    /// @param amount Amount of mainCollateral to deposit
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    /// @param getOraclePrice Function pointer to get oracle price for a token
    /// @param votingContract Address of voting contract to update votes in active proposals
    function executeDepositFundraising(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        address mainCollateral,
        uint256 amount,
        uint256 vaultId,
        function(address) external returns (uint256) getOraclePrice,
        address votingContract
    ) external {
        require(amount > 0, AmountMustBeGreaterThanZero());
        require(amount >= fundraisingConfig.minDeposit, DepositBelowMinimum());

        IERC20(mainCollateral).safeTransferFrom(msg.sender, address(this), amount);

        if (vaultId == 0) {
            vaultId = vaultStorage.addressToVaultId[msg.sender];
        }
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];

        uint256 shares = (amount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        uint256 depositLimit = vault.depositLimit;
        require(vault.shares + shares <= depositLimit, DepositLimitExceeded());

        uint256 mainCollateralPriceUSD = getOraclePrice(mainCollateral);
        uint256 usdDeposit = (amount * mainCollateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

        DataTypes.ParticipantEntry memory entry = participantEntries[vaultId];
        if (entry.depositedMainCollateral == 0) {
            entry.fixedSharePrice = 0;
            entry.fixedLaunchPrice = 0;
            entry.entryTimestamp = 0;
            entry.weightedAvgSharePrice = 0;
            entry.weightedAvgLaunchPrice = 0;
        }
        entry.depositedMainCollateral += amount;
        participantEntries[vaultId] = entry;

        vault.shares += shares;
        vaultStorage.totalSharesSupply += shares;
        daoState.totalCollectedMainCollateral += amount;
        vault.depositedUSD += usdDeposit;
        daoState.totalDepositedUSD += usdDeposit;

        VaultLibrary.executeUpdateDelegateVotingShares(vaultStorage, vaultId, int256(shares), votingContract);

        vault.mainCollateralDeposit += amount;
        vaultStorage.vaults[vaultId] = vault;

        emit FundraisingDeposit(vaultId, msg.sender, amount, shares);
    }

    /// @notice Deposit launch tokens during active stage to receive shares
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage
    /// @param rewardsStorage Rewards storage structure
    /// @param lpTokenStorage LP token storage structure
    /// @param fundraisingConfig Fundraising configuration
    /// @param participantEntries Mapping of participant entries
    /// @param accountedBalance Accounted balance mapping
    /// @param launchToken Launch token address
    /// @param launchAmount Amount of launch tokens to deposit
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    /// @param getOraclePrice Function pointer to get oracle price for a token
    /// @param votingContract Address of voting contract to update votes in active proposals
    function executeDepositLaunches(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        uint256 launchAmount,
        uint256 vaultId,
        function(address) external returns (uint256) getOraclePrice,
        address votingContract
    ) external {
        require(launchAmount >= fundraisingConfig.minLaunchDeposit, BelowMinLaunchDeposit());

        if (vaultId == 0) {
            vaultId = vaultStorage.addressToVaultId[msg.sender];
        }
        VaultValidationLibrary.validateVaultExists(vaultStorage, vaultId);
        IERC20(launchToken).safeTransferFrom(msg.sender, address(this), launchAmount);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];

        uint256 launchPriceUSD = getOraclePrice(launchToken) / 2;
        require(launchPriceUSD > 0, InvalidPrice());

        uint256 shares = (launchAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        uint256 depositLimit = vault.depositLimit;
        require(vault.shares + shares <= depositLimit, DepositLimitExceeded());

        uint256 usdDeposit = (shares * fundraisingConfig.sharePrice * launchPriceUSD)
            / (Constants.PRICE_DECIMALS_MULTIPLIER * Constants.PRICE_DECIMALS_MULTIPLIER);

        DataTypes.ParticipantEntry memory entry = participantEntries[vaultId];

        if (entry.depositedMainCollateral == 0) {
            entry.entryTimestamp = 0;
            entry.fixedSharePrice = fundraisingConfig.sharePriceStart;
            entry.fixedLaunchPrice = fundraisingConfig.launchPriceStart;
        }

        if (vault.shares == 0) {
            entry.weightedAvgLaunchPrice = launchPriceUSD;
            entry.weightedAvgSharePrice = fundraisingConfig.sharePrice;
        } else {
            uint256 totalShares = vault.shares + shares;
            entry.weightedAvgLaunchPrice =
                (entry.weightedAvgLaunchPrice * vault.shares + launchPriceUSD * shares) / totalShares;
            entry.weightedAvgSharePrice =
                (entry.weightedAvgSharePrice * vault.shares + fundraisingConfig.sharePrice * shares) / totalShares;
        }

        participantEntries[vaultId] = entry;

        RewardsCalculationLibrary.updateVaultRewards(vaultStorage, rewardsStorage, lpTokenStorage, vaultId);

        vault.shares += shares;
        vaultStorage.totalSharesSupply += shares;
        vault.depositedUSD += usdDeposit;
        daoState.totalDepositedUSD += usdDeposit;

        VaultLibrary.executeUpdateDelegateVotingShares(vaultStorage, vaultId, int256(shares), votingContract);
        vaultStorage.vaults[vaultId] = vault;

        accountedBalance[launchToken] += launchAmount;

        emit LaunchDeposit(vaultId, msg.sender, launchAmount, shares, launchPriceUSD);
    }

    /// @notice Extend fundraising deadline (only once)
    /// @param fundraisingConfig Fundraising configuration
    function executeExtendFundraising(DataTypes.FundraisingConfig storage fundraisingConfig) external {
        require(!fundraisingConfig.extended, FundraisingAlreadyExtended());
        require(block.timestamp >= fundraisingConfig.deadline, FundraisingNotExpiredYet());

        fundraisingConfig.deadline = block.timestamp + fundraisingConfig.extensionPeriod;
        fundraisingConfig.extended = true;

        emit FundraisingExtended(fundraisingConfig.deadline);
    }

    /// @notice Cancel fundraising
    /// @param daoState DAO state storage
    /// @param fundraisingConfig Fundraising configuration
    function executeCancelFundraising(
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig
    ) external {
        require(daoState.currentStage == DataTypes.Stage.Fundraising, InvalidStage());
        require(block.timestamp >= fundraisingConfig.deadline + 1 days, FundraisingNotExpiredYet());

        daoState.currentStage = DataTypes.Stage.FundraisingCancelled;

        emit FundraisingCancelled(daoState.totalCollectedMainCollateral);
        emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingCancelled);
    }

    /// @notice Finalize fundraising collection and move to exchange stage
    /// @param daoState DAO state storage
    /// @param fundraisingConfig Fundraising configuration
    /// @param totalSharesSupply Total shares supply
    /// @param pocContracts Array of POC contracts
    /// @param daoAddress Address of the DAO contract
    function executeFinalizeFundraisingCollection(
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 totalSharesSupply,
        DataTypes.POCInfo[] storage pocContracts,
        address daoAddress
    ) external {
        require(
            daoState.totalCollectedMainCollateral >= fundraisingConfig.targetAmountMainCollateral, TargetNotReached()
        );

        daoState.currentStage = DataTypes.Stage.FundraisingExchange;

        uint256 pocContractsCount = pocContracts.length;
        for (uint256 i = 0; i < pocContractsCount; ++i) {
            if (pocContracts[i].active) {
                IProofOfCapital(pocContracts[i].pocContract).setMarketMaker(daoAddress, true);
            }
        }

        emit FundraisingCollectionFinalized(daoState.totalCollectedMainCollateral, totalSharesSupply);
        emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingExchange);
    }
}

