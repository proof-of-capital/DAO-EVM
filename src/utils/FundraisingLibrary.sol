// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DataTypes.sol";
import "./Constants.sol";
import "./VaultLibrary.sol";
import "./RewardsLibrary.sol";

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

    event SellableCollateralAdded(address indexed token, address indexed priceFeed);
    event RewardTokenAdded(address indexed token, address indexed priceFeed);
    event POCContractAdded(address indexed pocContract, address indexed collateralToken, uint256 sharePercent);
    event FundraisingWithdrawal(uint256 indexed vaultId, address indexed sender, uint256 mainCollateralAmount);
    event ExchangeFinalized(uint256 totalLaunchBalance, uint256 sharePriceInLaunches, uint256 infraLaunches);
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
            require(poc.priceFeed != address(0), InvalidAddress());
            require(poc.sharePercent > 0 && poc.sharePercent <= Constants.BASIS_POINTS, InvalidPercentage());
            require(pocIndex[poc.pocContract] == 0, POCAlreadyExists());

            if (!sellableCollaterals[poc.collateralToken].active) {
                sellableCollaterals[poc.collateralToken] =
                    DataTypes.CollateralInfo({token: poc.collateralToken, priceFeed: poc.priceFeed, active: true});
                emit SellableCollateralAdded(poc.collateralToken, poc.priceFeed);
            }

            pocContracts.push(
                DataTypes.POCInfo({
                    pocContract: poc.pocContract,
                    collateralToken: poc.collateralToken,
                    priceFeed: poc.priceFeed,
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
                    DataTypes.RewardTokenInfo({token: poc.collateralToken, priceFeed: poc.priceFeed, active: true});
                emit RewardTokenAdded(poc.collateralToken, poc.priceFeed);
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
            require(reward.priceFeed != address(0), InvalidAddress());
            require(!rewardsStorage.rewardTokenInfo[reward.token].active, TokenAlreadyAdded());

            rewardsStorage.rewardTokens.push(reward.token);
            rewardsStorage.rewardTokenInfo[reward.token] =
                DataTypes.RewardTokenInfo({token: reward.token, priceFeed: reward.priceFeed, active: true});
            emit RewardTokenAdded(reward.token, reward.priceFeed);
        }

        if (!rewardsStorage.rewardTokenInfo[address(launchToken)].active) {
            rewardsStorage.rewardTokens.push(address(launchToken));
            rewardsStorage.rewardTokenInfo[address(launchToken)] =
                DataTypes.RewardTokenInfo({token: address(launchToken), priceFeed: address(0), active: true});
            emit RewardTokenAdded(address(launchToken), address(0));
        }
    }

    /// @notice Withdraw funds if fundraising was cancelled
    /// @param vaultStorage Vault storage structure
    /// @param daoState DAO state storage structure
    /// @param participantEntries Mapping of participant entries
    /// @param accountedBalance Mapping of accounted balances
    /// @param mainCollateral Main collateral token address
    /// @param launchToken Launch token address
    /// @param totalSharesSupply Total shares supply
    /// @param sender Sender address
    function executeWithdrawFundraising(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        mapping(address => uint256) storage accountedBalance,
        address mainCollateral,
        address launchToken,
        uint256 totalSharesSupply,
        address sender
    ) external {
        uint256 vaultId = vaultStorage.addressToVaultId[sender];
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(vault.primary == sender, OnlyPrimaryCanClaim());

        uint256 shares = vault.shares;
        require(shares > 0, NoSharesToClaim());
        require(totalSharesSupply > 0, NoShares());

        uint256 mainCollateralAmount = (daoState.totalCollectedMainCollateral * shares) / totalSharesSupply;
        require(mainCollateralAmount > 0, NoDepositToWithdraw());

        uint256 launchTokenAmount = 0;
        if (daoState.totalLaunchBalance > 0) {
            launchTokenAmount = (daoState.totalLaunchBalance * shares) / totalSharesSupply;
        }

        vault.shares = 0;
        vaultStorage.totalSharesSupply -= shares;
        daoState.totalCollectedMainCollateral -= mainCollateralAmount;
        if (launchTokenAmount > 0) {
            daoState.totalLaunchBalance -= launchTokenAmount;
        }

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        entry.depositedMainCollateral = 0;
        vaultStorage.vaultMainCollateralDeposit[vaultId] = 0;

        uint256 vaultDepositedUSD = vaultStorage.vaultDepositedUSD[vaultId];
        if (vaultDepositedUSD > 0) {
            daoState.totalDepositedUSD -= vaultDepositedUSD;
            vaultStorage.vaultDepositedUSD[vaultId] = 0;
        }

        IERC20(mainCollateral).safeTransfer(sender, mainCollateralAmount);

        if (launchTokenAmount > 0) {
            accountedBalance[address(launchToken)] -= launchTokenAmount;
            IERC20(launchToken).safeTransfer(sender, launchTokenAmount);
        }

        emit FundraisingWithdrawal(vaultId, sender, mainCollateralAmount);
    }

    /// @notice Finalize exchange process and calculate share price in launches
    /// @param pocContracts Array of POC contracts
    /// @param daoState DAO state storage
    /// @param accountedBalance Mapping of accounted balances
    /// @param launchToken Launch token address
    /// @param creator Creator address
    /// @param creatorInfraPercent Creator infrastructure percent
    /// @param totalSharesSupply Total shares supply
    function executeFinalizeExchange(
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.DAOState storage daoState,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        address creator,
        uint256 creatorInfraPercent,
        uint256 totalSharesSupply
    ) external {
        for (uint256 i = 0; i < pocContracts.length; ++i) {
            require(pocContracts[i].exchanged, POCNotExchanged());
        }

        require(totalSharesSupply > 0, NoSharesIssued());
        daoState.sharePriceInLaunches =
            (daoState.totalLaunchBalance * Constants.PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;

        uint256 infraLaunches = (daoState.totalLaunchBalance * creatorInfraPercent) / Constants.BASIS_POINTS;
        if (infraLaunches > 0) {
            IERC20(launchToken).safeTransfer(creator, infraLaunches);
            accountedBalance[address(launchToken)] -= infraLaunches;
        }

        daoState.totalLaunchBalance -= infraLaunches;
        DataTypes.Stage oldStage = daoState.currentStage;
        daoState.currentStage = DataTypes.Stage.WaitingForLP;

        emit ExchangeFinalized(daoState.totalLaunchBalance, daoState.sharePriceInLaunches, infraLaunches);
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
    function executeDepositFundraising(
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        address mainCollateral,
        uint256 amount,
        uint256 vaultId,
        function(address) external view returns (uint256) getOraclePrice
    ) external {
        require(amount > 0, AmountMustBeGreaterThanZero());
        require(amount >= fundraisingConfig.minDeposit, DepositBelowMinimum());

        address sender = msg.sender;
        if (vaultId == 0) {
            vaultId = vaultStorage.addressToVaultId[sender];
        }
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];

        uint256 shares = (amount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        uint256 depositLimit = vaultStorage.vaultDepositLimit[vaultId];
        require(vault.shares + shares <= depositLimit, DepositLimitExceeded());

        uint256 mainCollateralPriceUSD = getOraclePrice(mainCollateral);
        uint256 usdDeposit = (amount * mainCollateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        if (entry.entryTimestamp == 0) {
            entry.fixedSharePrice = fundraisingConfig.sharePrice;
            entry.fixedLaunchPrice = fundraisingConfig.launchPrice;
            entry.entryTimestamp = block.timestamp;
            entry.weightedAvgSharePrice = entry.fixedSharePrice;
            entry.weightedAvgLaunchPrice = entry.fixedLaunchPrice;
        }
        entry.depositedMainCollateral += amount;

        vault.shares += shares;
        vaultStorage.totalSharesSupply += shares;
        daoState.totalCollectedMainCollateral += amount;
        vaultStorage.vaultDepositedUSD[vaultId] += usdDeposit;
        daoState.totalDepositedUSD += usdDeposit;

        VaultLibrary.executeUpdateDelegateVotingShares(vaultStorage, vaultId, int256(shares));

        vaultStorage.vaultMainCollateralDeposit[vaultId] += amount;

        IERC20(mainCollateral).safeTransferFrom(sender, address(this), amount);

        emit FundraisingDeposit(vaultId, sender, amount, shares);
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
    /// @param getLaunchPriceFromPOC Function pointer to get launch price from POC
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
        function() external view returns (uint256) getLaunchPriceFromPOC
    ) external {
        require(launchAmount >= fundraisingConfig.minLaunchDeposit, BelowMinLaunchDeposit());

        address sender = msg.sender;
        if (vaultId == 0) {
            vaultId = vaultStorage.addressToVaultId[sender];
        }
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];

        uint256 launchPriceUSD = getLaunchPriceFromPOC();
        require(launchPriceUSD > 0, InvalidPrice());

        uint256 shares = (launchAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        uint256 depositLimit = vaultStorage.vaultDepositLimit[vaultId];
        require(vault.shares + shares <= depositLimit, DepositLimitExceeded());

        uint256 usdDeposit = (launchAmount * launchPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];

        DataTypes.Vault storage vaultForAvg = vaultStorage.vaults[vaultId];
        DataTypes.ParticipantEntry storage entryForAvg = participantEntries[vaultId];

        if (vaultForAvg.shares == 0) {
            entryForAvg.weightedAvgLaunchPrice = launchPriceUSD / 2;
            entryForAvg.weightedAvgSharePrice = fundraisingConfig.sharePrice;
        } else {
            uint256 totalShares = vaultForAvg.shares + shares;
            entryForAvg.weightedAvgLaunchPrice =
                (entryForAvg.weightedAvgLaunchPrice * vaultForAvg.shares + (launchPriceUSD / 2) * shares) / totalShares;
            entryForAvg.weightedAvgSharePrice =
                (entryForAvg.weightedAvgSharePrice * vaultForAvg.shares + fundraisingConfig.sharePrice * shares)
                    / totalShares;
        }

        if (entry.entryTimestamp == 0) {
            entry.entryTimestamp = block.timestamp;
            entry.fixedSharePrice = fundraisingConfig.sharePrice;
            entry.fixedLaunchPrice = fundraisingConfig.launchPrice;
        }

        RewardsLibrary.executeUpdateVaultRewards(vaultStorage, rewardsStorage, lpTokenStorage, vaultId);

        vault.shares += shares;
        vaultStorage.totalSharesSupply += shares;
        vaultStorage.vaultDepositedUSD[vaultId] += usdDeposit;
        daoState.totalDepositedUSD += usdDeposit;

        VaultLibrary.executeUpdateDelegateVotingShares(vaultStorage, vaultId, int256(shares));

        IERC20(launchToken).safeTransferFrom(sender, address(this), launchAmount);
        daoState.totalLaunchBalance += launchAmount;
        accountedBalance[launchToken] += launchAmount;

        emit LaunchDeposit(vaultId, sender, launchAmount, shares, launchPriceUSD);
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
    function executeFinalizeFundraisingCollection(
        DataTypes.DAOState storage daoState,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 totalSharesSupply
    ) external {
        require(
            daoState.totalCollectedMainCollateral >= fundraisingConfig.targetAmountMainCollateral, TargetNotReached()
        );

        daoState.currentStage = DataTypes.Stage.FundraisingExchange;

        emit FundraisingCollectionFinalized(daoState.totalCollectedMainCollateral, totalSharesSupply);
        emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingExchange);
    }
}

