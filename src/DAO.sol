// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/EVM

// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

// This is the third version of the contract. It introduces the following features: the ability to choose any jetcollateral as collateral, build collateral with an offset,
// perform delayed withdrawals (and restrict them if needed), assign multiple market makers, modify royalty conditions, and withdraw profit on request.
pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IProofOfCapital.sol";
import "./utils/Orderbook.sol";
import "./utils/DataTypes.sol";

/// @title DAO Contract
/// @notice Main DAO contract managing vaults, shares, orderbook and collateral trading
contract DAO is IDAO, Initializable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    uint256 public constant VOTING_PAUSE_DURATION = 7 days;
    uint256 public constant PRICE_DECIMALS = 18;
    uint256 public constant PRICE_DECIMALS_MULTIPLIER = 1e18; // 10 ** PRICE_DECIMALS
    uint256 public constant BASIS_POINTS = 10000; // 100% in basis points
    uint256 public constant PRICE_DEVIATION_MAX = 300; // 3% max deviation in basis points
    uint256 public constant MIN_MAIN_COLLATERAL_BALANCE = 1e18; // $1 in 18 decimals
    uint256 public constant BOARD_MEMBER_MIN_SHARES = 10 * 1e18; // Minimum shares to be a board member (10 shares)
    uint256 public constant EXIT_DISCOUNT_PERIOD = 365 days; // Period for early exit discount
    uint256 public constant EXIT_DISCOUNT_PERCENT = 2000; // 20% discount for early exit
    uint256 public constant MAX_CREATOR_ALLOCATION_PERCENT = 500; // 5% max launches per period
    uint256 public constant ALLOCATION_PERIOD = 30 days; // Period between allocations
    uint256 public constant LP_DISTRIBUTION_PERIOD = 30 days; // Monthly LP distribution period
    uint256 public constant LP_DISTRIBUTION_PERCENT = 100; // 1% of LP tokens distributed per month

    address public admin;
    address public votingContract;
    IERC20 public launchToken;
    address public mainCollateral; // Main collateral token for deposits

    DataTypes.Stage public currentStage;
    uint256 public totalSupplyAtFundraising;
    uint256 public totalSharesSupply;
    uint256 public nextVaultId;

    address public creator; // Creator address (receives profit share + infra launches)
    uint256 public creatorProfitPercent; // Creator profit share in basis points (4000 = 40%)
    uint256 public creatorInfraPercent; // % of launches for infrastructure in basis points

    // Royalty configuration
    address public royaltyRecipient; // Address to receive royalty (e.g., POC1)
    uint256 public royaltyPercent; // Royalty percentage in basis points (1000 = 10%)

    DataTypes.FundraisingConfig public fundraisingConfig;
    mapping(uint256 => DataTypes.ParticipantEntry) public participantEntries; // vaultId => entry info
    uint256 public totalCollectedMainCollateral; // Total mainCollateral collected during fundraising

    DataTypes.POCInfo[] public pocContracts;
    mapping(address => uint256) public pocIndex; // poc address => index + 1 (0 means not found)

    uint256 public totalLaunchBalance; // Total launch tokens after exchange
    uint256 public sharePriceInLaunches; // Share price denominated in launch tokens

    DataTypes.OrderbookParams public orderbookParams;

    mapping(uint256 => DataTypes.Vault) public vaults;
    mapping(address => uint256) public addressToVaultId;
    mapping(uint256 => uint256) public vaultMainCollateralDeposit; // vaultId => mainCollateral deposit amount

    mapping(address => DataTypes.CollateralInfo) public sellableCollaterals;

    mapping(address => bool) public availableRouterByAdmin;

    mapping(address => bool) public availableTokensByAdmin;

    mapping(address => uint256) public accountedBalance; // tracked balance per token
    mapping(address => uint256) public rewardPerShareStored; // global reward index per token
    mapping(uint256 => mapping(address => uint256)) public vaultRewardIndex; // vault => token => last claimed index
    mapping(uint256 => mapping(address => uint256)) public earnedRewards; // vault => token => earned rewards

    address[] public rewardTokens;
    mapping(address => bool) public isRewardToken;

    address[] public lpTokens;
    mapping(address => bool) public isLPToken;

    // Exit queue management
    DataTypes.ExitRequest[] public exitQueue;
    mapping(uint256 => uint256) public vaultExitRequestIndex; // vaultId => index + 1 (0 means not in queue)

    // Financial decisions
    uint256 public lastCreatorAllocation; // Timestamp of last launch allocation to creator
    mapping(address => uint256) public lastLPDistribution; // lpToken => timestamp of last distribution
    mapping(address => uint256) public lpTokenAddedAt; // lpToken => timestamp when LP was provided

    // Upgrade authorization - two-factor approval required
    address public pendingUpgradeFromVoting; // New implementation address approved by voting contract
    address public pendingUpgradeFromCreator; // New implementation address approved by creator

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyVoting() {
        _onlyVoting();
        _;
    }

    modifier atStage(DataTypes.Stage stage) {
        _atStage(stage);
        _;
    }

    modifier vaultExists(uint256 vaultId) {
        _vaultExists(vaultId);
        _;
    }

    modifier onlyParticipantOrAdmin() {
        _onlyParticipantOrAdmin();
        _;
    }

    modifier onlyCreatorOrAdmin() {
        _onlyCreatorOrAdmin();
        _;
    }

    modifier onlyCreator() {
        _onlyCreator();
        _;
    }

    modifier onlyBoardMemberOrAdmin() {
        _onlyBoardMemberOrAdmin();
        _;
    }

    modifier fundraisingActive() {
        _fundraisingActive();
        _;
    }

    /// @notice POC contract parameters for constructor
    struct POCConstructorParams {
        address pocContract;
        address collateralToken;
        address priceFeed;
        uint256 sharePercent;
    }

    /// @notice Orderbook parameters for constructor (without cache fields)
    struct OrderbookConstructorParams {
        uint256 initialPrice; // Initial price in USD (18 decimals)
        uint256 initialVolume; // Initial volume per level (18 decimals)
        uint256 priceStepPercent; // Price step percentage in basis points (500 = 5%)
        int256 volumeStepPercent; // Volume step percentage in basis points (-100 = -1%, can be negative)
        uint256 proportionalityCoefficient; // Proportionality coefficient (7500 = 0.75, in basis points)
        uint256 totalSupply; // Total supply (1e27 = 1 billion with 18 decimals)
    }

    /// @notice Constructor parameters struct to avoid stack too deep
    struct ConstructorParams {
        address launchToken;
        address mainCollateral;
        address creator;
        uint256 creatorProfitPercent;
        uint256 creatorInfraPercent;
        address royaltyRecipient; // Address to receive royalty (e.g., POC1)
        uint256 royaltyPercent; // Royalty percentage in basis points (1000 = 10%)
        uint256 minDeposit;
        uint256 minLaunchDeposit; // Minimum launch token deposit for Active stage entry (e.g., 10000e18)
        uint256 sharePrice;
        uint256 launchPrice;
        uint256 targetAmountMainCollateral;
        uint256 fundraisingDuration;
        uint256 extensionPeriod;
        address[] collateralTokens;
        address[] priceFeeds;
        address[] routers;
        address[] tokens;
        POCConstructorParams[] pocParams;
        OrderbookConstructorParams orderbookParams;
    }

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the DAO contract (replaces constructor for upgradeable pattern)
    /// @param params Constructor parameters struct
    function initialize(ConstructorParams memory params) public initializer {
        require(params.launchToken != address(0), InvalidLaunchToken());
        require(params.mainCollateral != address(0), InvalidAddress());
        require(params.creator != address(0), InvalidAddress());
        require(params.collateralTokens.length == params.priceFeeds.length, InvalidAddresses());
        require(params.creatorProfitPercent <= BASIS_POINTS, InvalidPercentage());
        require(params.creatorInfraPercent <= BASIS_POINTS, InvalidPercentage());
        require(params.royaltyPercent <= BASIS_POINTS, InvalidPercentage());
        require(params.sharePrice > 0, InvalidSharePrice());
        require(params.targetAmountMainCollateral > 0, InvalidTargetAmount());
        require(params.orderbookParams.initialPrice > 0, InvalidInitialPrice());
        require(params.orderbookParams.initialVolume > 0, InvalidVolume());
        require(params.orderbookParams.totalSupply > 0, InvalidVolume());

        launchToken = IERC20(params.launchToken);
        mainCollateral = params.mainCollateral;
        admin = msg.sender;
        creator = params.creator;
        creatorProfitPercent = params.creatorProfitPercent;
        creatorInfraPercent = params.creatorInfraPercent;
        royaltyRecipient = params.royaltyRecipient;
        royaltyPercent = params.royaltyPercent;
        currentStage = DataTypes.Stage.Fundraising;
        nextVaultId = 1;

        fundraisingConfig = DataTypes.FundraisingConfig({
            minDeposit: params.minDeposit,
            minLaunchDeposit: params.minLaunchDeposit,
            sharePrice: params.sharePrice,
            launchPrice: params.launchPrice,
            targetAmountMainCollateral: params.targetAmountMainCollateral,
            deadline: block.timestamp + params.fundraisingDuration,
            extensionPeriod: params.extensionPeriod,
            extended: false
        });

        for (uint256 i = 0; i < params.collateralTokens.length; i++) {
            address token = params.collateralTokens[i];
            address priceFeed = params.priceFeeds[i];

            require(token != address(0) && priceFeed != address(0), InvalidAddresses());
            require(!sellableCollaterals[token].active, CollateralAlreadyExists());

            sellableCollaterals[token] = DataTypes.CollateralInfo({token: token, priceFeed: priceFeed, active: true});

            emit SellableCollateralAdded(token, priceFeed);
        }

        for (uint256 i = 0; i < params.routers.length; i++) {
            address router = params.routers[i];
            require(router != address(0), InvalidAddress());
            require(!availableRouterByAdmin[router], RouterAlreadyAdded());

            availableRouterByAdmin[router] = true;

            emit RouterAvailabilityChanged(router, true);
        }

        for (uint256 i = 0; i < params.tokens.length; i++) {
            address token = params.tokens[i];
            require(token != address(0), InvalidAddress());
            require(!availableTokensByAdmin[token], TokenAlreadyAdded());

            availableTokensByAdmin[token] = true;

            emit TokenAvailabilityChanged(token, true);
        }

        uint256 totalPOCShare = 0;
        for (uint256 i = 0; i < params.pocParams.length; i++) {
            POCConstructorParams memory poc = params.pocParams[i];

            require(poc.pocContract != address(0), InvalidAddress());
            require(poc.collateralToken != address(0), InvalidAddress());
            require(poc.priceFeed != address(0), InvalidAddress());
            require(poc.sharePercent > 0 && poc.sharePercent <= BASIS_POINTS, InvalidPercentage());
            require(pocIndex[poc.pocContract] == 0, POCAlreadyExists());

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

            pocIndex[poc.pocContract] = pocContracts.length; // index + 1
            totalPOCShare += poc.sharePercent;

            emit POCContractAdded(poc.pocContract, poc.collateralToken, poc.sharePercent);
        }
        require(totalPOCShare == BASIS_POINTS || totalPOCShare == 0, POCSharesNot100Percent());

        // Initialize orderbook params with cache fields set to zero
        orderbookParams = DataTypes.OrderbookParams({
            initialPrice: params.orderbookParams.initialPrice,
            initialVolume: params.orderbookParams.initialVolume,
            priceStepPercent: params.orderbookParams.priceStepPercent,
            volumeStepPercent: params.orderbookParams.volumeStepPercent,
            proportionalityCoefficient: params.orderbookParams.proportionalityCoefficient,
            totalSupply: params.orderbookParams.totalSupply,
            totalSold: 0,
            currentLevel: 0,
            currentTotalSold: 0,
            currentCumulativeVolume: 0,
            cachedPriceAtLevel: params.orderbookParams.initialPrice,
            cachedBaseVolumeAtLevel: params.orderbookParams.initialVolume
        });

        emit CreatorSet(params.creator, params.creatorProfitPercent, params.creatorInfraPercent);
        emit FundraisingConfigured(
            params.minDeposit, params.sharePrice, params.targetAmountMainCollateral, fundraisingConfig.deadline
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

    /// @notice Create a new vault (without deposit)
    /// @param backup Backup address for recovery
    /// @param emergency Emergency address for recovery
    /// @return vaultId The ID of the created vault
    function createVault(address backup, address emergency) external nonReentrant returns (uint256 vaultId) {
        require(currentStage != DataTypes.Stage.Dissolved, DAOIsDissolved());
        require(backup != address(0) && emergency != address(0), InvalidAddresses());
        require(
            addressToVaultId[msg.sender] == 0 || vaults[addressToVaultId[msg.sender]].shares == 0, VaultAlreadyExists()
        );

        vaultId = nextVaultId++;

        vaults[vaultId] = DataTypes.Vault({
            primary: msg.sender, backup: backup, emergency: emergency, shares: 0, votingPausedUntil: 0
        });

        addressToVaultId[msg.sender] = vaultId;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            vaultRewardIndex[vaultId][token] = rewardPerShareStored[token];
        }

        for (uint256 i = 0; i < lpTokens.length; i++) {
            address token = lpTokens[i];
            vaultRewardIndex[vaultId][token] = rewardPerShareStored[token];
        }

        vaultMainCollateralDeposit[vaultId] = 0;

        emit VaultCreated(vaultId, msg.sender, 0);
    }

    /// @notice Deposit mainCollateral during fundraising stage
    /// @param amount Amount of mainCollateral to deposit (18 decimals)
    function depositFundraising(uint256 amount) external nonReentrant fundraisingActive {
        require(amount > 0, AmountMustBeGreaterThanZero());
        require(amount >= fundraisingConfig.minDeposit, DepositBelowMinimum());

        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 shares = (amount * PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        if (entry.entryTimestamp == 0) {
            entry.fixedSharePrice = fundraisingConfig.sharePrice;
            entry.fixedLaunchPrice = fundraisingConfig.launchPrice;
            entry.entryTimestamp = block.timestamp;
            // Store collateral price at entry (default to $1 if no oracle)
            if (sellableCollaterals[mainCollateral].active) {
                entry.fixedCollateralPrice = Orderbook.getCollateralPrice(sellableCollaterals[mainCollateral]);
            } else {
                entry.fixedCollateralPrice = PRICE_DECIMALS_MULTIPLIER; // Default to $1
            }
            entry.weightedAvgSharePrice = entry.fixedSharePrice;
            entry.weightedAvgLaunchPrice = entry.fixedLaunchPrice;
        }
        entry.depositedMainCollateral += amount;

        vault.shares += shares;
        totalSharesSupply += shares;
        totalCollectedMainCollateral += amount;

        vaultMainCollateralDeposit[vaultId] += amount;

        IERC20(mainCollateral).safeTransferFrom(msg.sender, address(this), amount);

        emit FundraisingDeposit(vaultId, msg.sender, amount, shares);
    }

    /// @notice Deposit mainCollateral during active stage
    /// @param mainCollateralAmount Amount of mainCollateral to deposit
    function depositActive(uint256 mainCollateralAmount) external nonReentrant atStage(DataTypes.Stage.Active) {
        require(mainCollateralAmount > 0, AmountMustBeGreaterThanZero());
        require(mainCollateral != address(0), InvalidAddress());
        require(totalSupplyAtFundraising > 0, InvalidState());

        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 shares = (mainCollateralAmount * totalSharesSupply) / totalSupplyAtFundraising;

        _updateVaultRewards(vaultId);

        vault.shares += shares;
        totalSharesSupply += shares;

        vaultMainCollateralDeposit[vaultId] += mainCollateralAmount;

        IERC20(mainCollateral).safeTransferFrom(msg.sender, address(this), mainCollateralAmount);

        emit VaultDeposited(vaultId, mainCollateralAmount, shares);
    }

    /// @notice Deposit launch tokens during active stage to receive shares
    /// @dev New participants can enter by depositing launches; price is fixed at entry
    /// @param launchAmount Amount of launch tokens to deposit
    function depositLaunches(uint256 launchAmount) external nonReentrant atStage(DataTypes.Stage.Active) {
        require(launchAmount >= fundraisingConfig.minLaunchDeposit, BelowMinLaunchDeposit());
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 launchPriceUSD = _getLaunchPriceFromPOC();
        require(launchPriceUSD > 0, InvalidPrice());

        // Calculate share price in launches (divide by 2 per spec)
        // sharePriceInLaunches = sharePrice / (launchPrice * 2) ???
        uint256 currentSharePriceInLaunches =
            (fundraisingConfig.sharePrice * PRICE_DECIMALS_MULTIPLIER) / (launchPriceUSD * 2);
        require(currentSharePriceInLaunches > 0, InvalidSharePrice());

        // Calculate shares to issue
        uint256 shares = (launchAmount * PRICE_DECIMALS_MULTIPLIER) / currentSharePriceInLaunches;
        require(shares > 0, SharesCalculationFailed());

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];

        // Update weighted averages for existing participants
        _updateWeightedAverages(vaultId, shares, launchPriceUSD);

        // Fix launch price at entry for this active stage deposit
        if (entry.fixedLaunchPriceAtActive == 0) {
            entry.fixedLaunchPriceAtActive = launchPriceUSD;
        }
        if (entry.entryTimestamp == 0) {
            entry.entryTimestamp = block.timestamp;
            entry.fixedSharePrice = fundraisingConfig.sharePrice;
            entry.fixedLaunchPrice = fundraisingConfig.launchPrice;
        }
        entry.depositedLaunches += launchAmount;

        // Update vault rewards to treat new shares as having received past rewards
        _updateVaultRewards(vaultId);

        vault.shares += shares;
        totalSharesSupply += shares;

        launchToken.safeTransferFrom(msg.sender, address(this), launchAmount);
        totalLaunchBalance += launchAmount;

        emit LaunchDeposit(vaultId, msg.sender, launchAmount, shares, launchPriceUSD);
    }

    /// @notice Update primary address
    /// @notice Emergency can change primary, backup can change primary, primary can change itself
    /// @param vaultId Vault ID to update
    /// @param newPrimary New primary address
    function updatePrimaryAddress(uint256 vaultId, address newPrimary) external vaultExists(vaultId) {
        DataTypes.Vault storage vault = vaults[vaultId];
        require(
            msg.sender == vault.primary || msg.sender == vault.backup || msg.sender == vault.emergency, Unauthorized()
        );
        require(newPrimary != address(0), InvalidAddress());
        require(addressToVaultId[newPrimary] == 0, AddressAlreadyUsedInAnotherVault());

        address oldPrimary = vault.primary;
        delete addressToVaultId[oldPrimary];

        vault.primary = newPrimary;
        addressToVaultId[newPrimary] = vaultId;

        emit PrimaryAddressUpdated(vaultId, oldPrimary, newPrimary);
    }

    /// @notice Update backup address
    /// @notice Emergency can change backup, backup can change itself
    /// @param vaultId Vault ID to update
    /// @param newBackup New backup address
    function updateBackupAddress(uint256 vaultId, address newBackup) external vaultExists(vaultId) {
        DataTypes.Vault storage vault = vaults[vaultId];
        require(msg.sender == vault.backup || msg.sender == vault.emergency, Unauthorized());
        require(newBackup != address(0), InvalidAddress());

        address oldBackup = vault.backup;
        vault.backup = newBackup;

        emit BackupAddressUpdated(vaultId, oldBackup, newBackup);
    }

    /// @notice Update emergency address
    /// @notice Emergency can change itself
    /// @param vaultId Vault ID to update
    /// @param newEmergency New emergency address
    function updateEmergencyAddress(uint256 vaultId, address newEmergency) external vaultExists(vaultId) {
        DataTypes.Vault storage vault = vaults[vaultId];
        require(msg.sender == vault.emergency, Unauthorized());
        require(newEmergency != address(0), InvalidAddress());

        address oldEmergency = vault.emergency;
        vault.emergency = newEmergency;

        emit EmergencyAddressUpdated(vaultId, oldEmergency, newEmergency);
    }

    /// @notice Claim accumulated rewards for tokens
    /// @param tokens Array of token addresses to claim
    function claimReward(address[] calldata tokens) external nonReentrant {
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        _updateVaultRewards(vaultId);

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            uint256 rewards = earnedRewards[vaultId][token];

            if (rewards > 0) {
                earnedRewards[vaultId][token] = 0;
                accountedBalance[token] -= rewards;

                IERC20(token).safeTransfer(msg.sender, rewards);

                emit RewardClaimed(vaultId, token, rewards);
            }
        }
    }

    /// @notice Request to exit DAO by selling all shares
    /// @dev Participant exits with all their shares; adds request to exit queue for processing
    function requestExit() external nonReentrant atStage(DataTypes.Stage.Active) {
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());
        require(vault.shares > 0, AmountMustBeGreaterThanZero());
        require(vaultExitRequestIndex[vaultId] == 0, AlreadyInExitQueue());
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        uint256 sharesToExit = vault.shares; // Exit with all shares
        uint256 launchPriceNow = _getLaunchPriceFromPOC();

        exitQueue.push(
            DataTypes.ExitRequest({
                vaultId: vaultId,
                shares: sharesToExit,
                requestTimestamp: block.timestamp,
                fixedLaunchPriceAtRequest: launchPriceNow,
                processed: false
            })
        );

        vaultExitRequestIndex[vaultId] = exitQueue.length; // Store index + 1

        emit ExitRequested(vaultId, sharesToExit, launchPriceNow);
    }

    /// @notice Cancel exit request
    function cancelExitRequest() external nonReentrant atStage(DataTypes.Stage.Active) {
        // ???
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 queueIndex = vaultExitRequestIndex[vaultId];
        require(queueIndex > 0, NotInExitQueue());

        DataTypes.ExitRequest storage request = exitQueue[queueIndex - 1];
        require(!request.processed, ExitAlreadyProcessed());

        // Mark as processed (effectively cancelled)
        request.processed = true;
        vaultExitRequestIndex[vaultId] = 0;

        emit ExitRequestCancelled(vaultId);
    }

    /// @notice Allocate launch tokens to creator, reducing their profit share proportionally
    /// @dev Can only be done once per ALLOCATION_PERIOD; max MAX_CREATOR_ALLOCATION_PERCENT per period
    /// @param launchAmount Amount of launch tokens to allocate
    function allocateLaunchesToCreator(uint256 launchAmount) external onlyAdmin atStage(DataTypes.Stage.Active) {
        require(block.timestamp >= lastCreatorAllocation + ALLOCATION_PERIOD, AllocationTooSoon());
        require(launchAmount > 0, AmountMustBeGreaterThanZero());

        // Calculate max allocation (5% of total launch balance)
        uint256 maxAllocation = (totalLaunchBalance * MAX_CREATOR_ALLOCATION_PERCENT) / BASIS_POINTS;
        require(launchAmount <= maxAllocation, ExceedsMaxAllocation());

        // Calculate how many shares equivalent this represents
        require(sharePriceInLaunches > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (launchAmount * PRICE_DECIMALS_MULTIPLIER) / sharePriceInLaunches;

        // Calculate what % of total shares this represents
        require(totalSharesSupply > 0, NoShares());
        uint256 profitPercentEquivalent = (sharesEquivalent * BASIS_POINTS) / totalSharesSupply;

        // Reduce creator's profit share by this percentage
        require(creatorProfitPercent >= profitPercentEquivalent, CreatorShareTooLow());
        creatorProfitPercent -= profitPercentEquivalent;

        // Transfer launches to creator
        launchToken.safeTransfer(creator, launchAmount);
        totalLaunchBalance -= launchAmount;
        lastCreatorAllocation = block.timestamp;

        emit CreatorLaunchesAllocated(launchAmount, profitPercentEquivalent, creatorProfitPercent);
    }

    /// @notice Sell launch tokens for collateral
    /// @param collateral Collateral token address
    /// @param launchTokenAmount Amount of launch tokens to sell
    /// @param minCollateralAmount Minimum collateral amount to receive (slippage protection)
    /// @param router Router address for swap (address(0) if swapType is None)
    /// @param swapType Type of swap to execute
    /// @param swapData Encoded swap parameters
    function sell(
        address collateral,
        uint256 launchTokenAmount,
        uint256 minCollateralAmount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external nonReentrant atStage(DataTypes.Stage.Active) onlyParticipantOrAdmin {
        require(launchTokenAmount > 0, AmountMustBeGreaterThanZero());

        Orderbook.executeSell(
            DataTypes.SellParams({
                collateral: collateral,
                launchTokenAmount: launchTokenAmount,
                minCollateralAmount: minCollateralAmount,
                seller: msg.sender,
                router: router,
                swapType: swapType,
                swapData: swapData
            }),
            address(this),
            launchToken,
            orderbookParams,
            sellableCollaterals,
            accountedBalance,
            availableRouterByAdmin,
            availableTokensByAdmin,
            totalSharesSupply,
            fundraisingConfig.sharePrice
        );

        // Distribute received collateral as profit
        _distributeProfit(collateral);
    }

    /// @notice Get current price based on orderbook state
    /// @return Current price in USD (18 decimals)
    function getCurrentPrice() public view returns (uint256) {
        return Orderbook.getCurrentPrice(orderbookParams, totalSharesSupply, fundraisingConfig.sharePrice);
    }

    /// @notice Get total launch tokens sold
    /// @return Total amount of launch tokens sold
    function totalLaunchTokensSold() external view returns (uint256) {
        return orderbookParams.totalSold;
    }

    /// @notice Get collateral price from Chainlink oracle
    /// @param collateral Collateral token address
    /// @return Price in USD (18 decimals)
    function getCollateralPrice(address collateral) public view returns (uint256) {
        return Orderbook.getCollateralPrice(sellableCollaterals[collateral]);
    }

    /// @notice Add a POC contract with allocation share
    /// @param pocContract POC contract address
    /// @param collateralToken Collateral token for this POC
    /// @param priceFeed Chainlink price feed for the collateral
    /// @param sharePercent Allocation percentage in basis points (10000 = 100%)
    function addPOCContract(address pocContract, address collateralToken, address priceFeed, uint256 sharePercent)
        external
        onlyVoting
        atStage(DataTypes.Stage.Active)
    {
        require(pocContract != address(0), InvalidAddress());
        require(collateralToken != address(0), InvalidAddress());
        require(priceFeed != address(0), InvalidAddress());
        require(sharePercent > 0 && sharePercent <= BASIS_POINTS, InvalidPercentage());
        require(pocIndex[pocContract] == 0, POCAlreadyExists());

        uint256 totalShare = sharePercent;
        for (uint256 i = 0; i < pocContracts.length; i++) {
            totalShare += pocContracts[i].sharePercent;
        }
        require(totalShare <= BASIS_POINTS, TotalShareExceeds100Percent());

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

        pocIndex[pocContract] = pocContracts.length; // index + 1

        emit POCContractAdded(pocContract, collateralToken, sharePercent);
    }

    /// @notice Withdraw funds if fundraising was cancelled
    function withdrawFundraising() external nonReentrant atStage(DataTypes.Stage.FundraisingCancelled) {
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        uint256 depositedAmount = entry.depositedMainCollateral;
        require(depositedAmount > 0, NoDepositToWithdraw());

        uint256 shares = vault.shares;
        vault.shares = 0;
        totalSharesSupply -= shares;
        totalCollectedMainCollateral -= depositedAmount;
        entry.depositedMainCollateral = 0;
        vaultMainCollateralDeposit[vaultId] = 0;

        IERC20(mainCollateral).safeTransfer(msg.sender, depositedAmount);

        emit FundraisingWithdrawal(vaultId, msg.sender, depositedAmount);
    }

    /// @notice Extend fundraising deadline (only once)
    function extendFundraising() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        require(!fundraisingConfig.extended, FundraisingAlreadyExtended());
        require(block.timestamp >= fundraisingConfig.deadline, FundraisingNotExpiredYet());

        fundraisingConfig.deadline = block.timestamp + fundraisingConfig.extensionPeriod;
        fundraisingConfig.extended = true;

        emit FundraisingExtended(fundraisingConfig.deadline);
    }

    /// @notice Cancel fundraising (admin only, if target not reached after deadline)
    function cancelFundraising() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        require(block.timestamp >= fundraisingConfig.deadline, FundraisingNotExpiredYet());
        require(totalCollectedMainCollateral < fundraisingConfig.targetAmountMainCollateral, TargetAlreadyReached());

        // Add 1 day pause for extension opportunity
        require(block.timestamp >= fundraisingConfig.deadline + 1 days, FundraisingNotExpiredYet());

        currentStage = DataTypes.Stage.FundraisingCancelled;

        emit FundraisingCancelled(totalCollectedMainCollateral);
        emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingCancelled);
    }

    /// @notice Finalize fundraising collection and move to exchange stage
    function finalizeFundraisingCollection() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        require(totalCollectedMainCollateral >= fundraisingConfig.targetAmountMainCollateral, TargetNotReached());
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        totalSupplyAtFundraising = totalSharesSupply;
        currentStage = DataTypes.Stage.FundraisingExchange;

        emit FundraisingCollectionFinalized(totalCollectedMainCollateral, totalSharesSupply);
        emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingExchange);
    }

    /// @notice Exchange mainCollateral for launch tokens from a specific POC contract
    /// @param pocIdx Index of POC contract in pocContracts array
    /// @param amount Amount of mainCollateral to exchange (0 = exchange remaining amount)
    /// @param router Router address for swap (if collateral != mainCollateral)
    /// @param swapType Type of swap to execute
    /// @param swapData Encoded swap parameters
    function exchangeForPOC(
        uint256 pocIdx,
        uint256 amount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external nonReentrant onlyAdmin atStage(DataTypes.Stage.FundraisingExchange) {
        require(pocIdx < pocContracts.length, InvalidPOCIndex());

        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        require(poc.active, POCNotActive());
        require(!poc.exchanged, POCAlreadyExchanged());

        uint256 totalAllocationForPOC = (totalCollectedMainCollateral * poc.sharePercent) / BASIS_POINTS;
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

            uint256 mainCollateralPrice = _getOraclePrice(mainCollateral);
            uint256 collateralPrice = _getPOCCollateralPrice(pocIdx);

            uint256 expectedCollateral = (collateralAmountForPOC * mainCollateralPrice) / collateralPrice;

            IERC20(mainCollateral).safeIncreaseAllowance(router, collateralAmountForPOC);

            uint256 balanceBefore = IERC20(poc.collateralToken).balanceOf(address(this));

            collateralAmount = OrderbookSwapLibrary.executeSwap(
                router,
                swapType,
                swapData,
                mainCollateral,
                poc.collateralToken,
                collateralAmountForPOC,
                0, // minAmount will be checked after with oracle
                address(this)
            );

            uint256 balanceAfter = IERC20(poc.collateralToken).balanceOf(address(this));
            collateralAmount = balanceAfter - balanceBefore;

            uint256 deviation = _calculateDeviation(expectedCollateral, collateralAmount);
            require(deviation <= PRICE_DEVIATION_MAX, PriceDeviationTooHigh());
        }

        IERC20(poc.collateralToken).safeIncreaseAllowance(poc.pocContract, collateralAmount);

        uint256 launchBalanceBefore = launchToken.balanceOf(address(this));

        IProofOfCapital(poc.pocContract).buyLaunchTokens(collateralAmount);

        uint256 launchBalanceAfter = launchToken.balanceOf(address(this));
        uint256 launchReceived = launchBalanceAfter - launchBalanceBefore;

        poc.exchangedAmount += collateralAmountForPOC;

        if (poc.exchangedAmount >= totalAllocationForPOC) {
            poc.exchanged = true;
        }

        totalLaunchBalance += launchReceived;

        emit POCExchangeCompleted(pocIdx, poc.pocContract, collateralAmountForPOC, collateralAmount, launchReceived);
    }

    /// @notice Finalize exchange process and calculate share price in launches
    function finalizeExchange() external onlyAdmin atStage(DataTypes.Stage.FundraisingExchange) {
        for (uint256 i = 0; i < pocContracts.length; i++) {
            require(pocContracts[i].exchanged, POCNotExchanged());
        }

        uint256 remainingCollateral = IERC20(mainCollateral).balanceOf(address(this));
        require(remainingCollateral < MIN_MAIN_COLLATERAL_BALANCE, MainCollateralBalanceNotDepleted());

        require(totalSharesSupply > 0, NoSharesIssued());
        sharePriceInLaunches = (totalLaunchBalance * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;

        uint256 infraLaunches = (totalLaunchBalance * creatorInfraPercent) / BASIS_POINTS;
        if (infraLaunches > 0) {
            launchToken.safeTransfer(creator, infraLaunches);
            totalLaunchBalance -= infraLaunches;

            sharePriceInLaunches = (totalLaunchBalance * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;
        }

        currentStage = DataTypes.Stage.WaitingForLP;

        emit ExchangeFinalized(totalLaunchBalance, sharePriceInLaunches, infraLaunches);
        emit StageChanged(DataTypes.Stage.FundraisingExchange, DataTypes.Stage.WaitingForLP);
    }

    /// @notice Creator provides LP tokens and moves DAO to active stage
    /// @param lpTokenAddresses Array of LP token addresses
    /// @param lpAmounts Array of LP token amounts to deposit
    function provideLPTokens(address[] calldata lpTokenAddresses, uint256[] calldata lpAmounts)
        external
        nonReentrant
        onlyCreator
        atStage(DataTypes.Stage.WaitingForLP)
    {
        require(lpTokenAddresses.length == lpAmounts.length, InvalidAddresses());
        require(lpTokenAddresses.length > 0, InvalidAddress());

        for (uint256 i = 0; i < lpTokenAddresses.length; i++) {
            address lpToken = lpTokenAddresses[i];
            uint256 lpAmount = lpAmounts[i];

            require(lpToken != address(0), InvalidAddress());
            require(lpAmount > 0, AmountMustBeGreaterThanZero());

            IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);

            if (!isLPToken[lpToken]) {
                lpTokens.push(lpToken);
                isLPToken[lpToken] = true;
            }
            accountedBalance[lpToken] += lpAmount;
            lpTokenAddedAt[lpToken] = block.timestamp;
            lastLPDistribution[lpToken] = block.timestamp; // Start distribution timer from now

            emit LPTokensProvided(lpToken, lpAmount);
        }

        currentStage = DataTypes.Stage.Active;

        emit StageChanged(DataTypes.Stage.WaitingForLP, DataTypes.Stage.Active);
    }

    /// @notice Dissolve DAO (only callable by voting)
    function dissolve() external onlyVoting atStage(DataTypes.Stage.Active) {
        currentStage = DataTypes.Stage.Dissolved;
        emit StageChanged(DataTypes.Stage.Active, DataTypes.Stage.Dissolved);
    }

    /// @notice Execute proposal call through DAO (only callable by voting)
    /// @dev Executes a call to targetContract with callData on behalf of DAO
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    function executeProposal(address targetContract, bytes calldata callData) external {
        require(msg.sender == address(votingContract), OnlyVotingContract());
        require(targetContract != address(0), InvalidAddress());
        (bool success, bytes memory returnData) = targetContract.call(callData);
        require(success, ExecutionFailed(_getRevertMsg(returnData)));
    }

    /// @notice Claim share of assets after dissolution
    /// @dev Creator gets additional launch tokens based on creatorInfraPercent
    /// @param tokens Array of token addresses to claim (can include launch token, reward tokens, LP tokens, or sellable collaterals)
    function claimDissolution(address[] calldata tokens) external nonReentrant atStage(DataTypes.Stage.Dissolved) {
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());
        require(vault.shares > 0, NoSharesToClaim());

        uint256 shares = vault.shares;
        vault.shares = 0;

        // If caller is creator, give additional launch tokens share first
        if (msg.sender == creator) {
            uint256 launchBalance = launchToken.balanceOf(address(this));
            uint256 creatorLaunchShare = (launchBalance * creatorInfraPercent) / BASIS_POINTS;
            if (creatorLaunchShare > 0) {
                launchToken.safeTransfer(creator, creatorLaunchShare);
                emit CreatorDissolutionClaimed(creator, creatorLaunchShare);
            }
        }

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            require(token != address(0), InvalidAddress());

            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) continue;

            // Check if token is valid (launch token, reward token, or sellable collateral)
            // LP tokens are excluded from dissolution claims
            bool isValidToken =
                token == address(launchToken) || isRewardToken[token] || sellableCollaterals[token].active;

            require(isValidToken, InvalidAddress());

            uint256 tokenShare = (tokenBalance * shares) / totalSharesSupply;
            if (tokenShare > 0) {
                IERC20(token).safeTransfer(msg.sender, tokenShare);
            }
        }

        totalSharesSupply -= shares;
    }

    /// @notice Set voting contract address
    /// @param _votingContract Voting contract address
    function setVotingContract(address _votingContract) external onlyAdmin {
        require(_votingContract != address(0), InvalidAddress());
        require(votingContract == address(0), VotingContractAlreadySet());

        votingContract = _votingContract;

        emit VotingContractSet(_votingContract);
    }

    /// @notice Distribute unaccounted balance of a token as profit
    /// @dev Splits profit into: royalty (10%) -> creator (N%) -> DAO participants (90%-N%)
    /// @dev If token is not yet accounted and no exits in queue, only admin or board members can add it
    /// @param token Token address to distribute
    function distributeProfit(address token) external nonReentrant {
        require(totalSharesSupply > 0, NoShares());
        require(!isLPToken[token], LPTokenUsesDifferentDistribution());

        require(isRewardToken[token], TokenNotAdded());

        _distributeProfit(token);
    }

    /// @notice Internal function to distribute unaccounted balance of a token as profit
    /// @param token Token address to distribute
    function _distributeProfit(address token) internal {
        uint256 unaccounted = IERC20(token).balanceOf(address(this)) - accountedBalance[token];
        if (unaccounted == 0) return; // No profit to distribute, skip silently

        // 1. Calculate and transfer royalty share (e.g., 10% to POC1)
        uint256 royaltyShare = (unaccounted * royaltyPercent) / BASIS_POINTS;
        if (royaltyShare > 0 && royaltyRecipient != address(0)) {
            IERC20(token).safeTransfer(royaltyRecipient, royaltyShare);
            emit RoyaltyDistributed(token, royaltyRecipient, royaltyShare);
        }

        // 2. Calculate and transfer creator share (N% of remaining after royalty)
        uint256 remainingAfterRoyalty = unaccounted - royaltyShare;
        uint256 creatorShare = (remainingAfterRoyalty * creatorProfitPercent) / BASIS_POINTS;
        if (creatorShare > 0) {
            IERC20(token).safeTransfer(creator, creatorShare);
            emit CreatorProfitDistributed(token, creator, creatorShare);
        }

        // 3. Process exit queue first (buyback shares from exiting participants)
        uint256 participantsShare = remainingAfterRoyalty - creatorShare;
        uint256 usedForExits = 0;

        if (exitQueue.length > 0 && !_isExitQueueEmpty() && participantsShare > 0) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            _processExitQueue(participantsShare, token);
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            usedForExits = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        }

        // 4. Distribute remaining to DAO participants
        uint256 remainingForParticipants = participantsShare - usedForExits;

        if (!isRewardToken[token]) {
            rewardTokens.push(token);
            isRewardToken[token] = true;
        }

        if (remainingForParticipants > 0 && totalSharesSupply > 0) {
            rewardPerShareStored[token] += (remainingForParticipants * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;
        }
        accountedBalance[token] += unaccounted;

        emit ProfitDistributed(token, unaccounted);
    }

    /// @notice Distribute 1% of LP tokens as profit (monthly)
    /// @dev Can only be called once per LP_DISTRIBUTION_PERIOD per LP token
    /// @param lpToken LP token address to distribute
    function distributeLPProfit(address lpToken) external nonReentrant atStage(DataTypes.Stage.Active) {
        require(isLPToken[lpToken], NotLPToken());
        require(block.timestamp >= lastLPDistribution[lpToken] + LP_DISTRIBUTION_PERIOD, LPDistributionTooSoon());
        require(totalSharesSupply > 0, NoShares());

        uint256 lpBalance = accountedBalance[lpToken];
        require(lpBalance > 0, NoProfitToDistribute());

        uint256 toDistribute = (lpBalance * LP_DISTRIBUTION_PERCENT) / BASIS_POINTS;
        require(toDistribute > 0, NoProfitToDistribute());

        // 1. Calculate and transfer royalty share
        uint256 royaltyShare = (toDistribute * royaltyPercent) / BASIS_POINTS;
        if (royaltyShare > 0 && royaltyRecipient != address(0)) {
            IERC20(lpToken).safeTransfer(royaltyRecipient, royaltyShare);
            emit RoyaltyDistributed(lpToken, royaltyRecipient, royaltyShare);
        }

        // 2. Calculate and transfer creator share
        uint256 remainingAfterRoyalty = toDistribute - royaltyShare;
        uint256 creatorShare = (remainingAfterRoyalty * creatorProfitPercent) / BASIS_POINTS;
        if (creatorShare > 0) {
            IERC20(lpToken).safeTransfer(creator, creatorShare);
            emit CreatorProfitDistributed(lpToken, creator, creatorShare);
        }

        // 3. Process exit queue if any
        uint256 participantsShare = remainingAfterRoyalty - creatorShare;
        uint256 usedForExits = 0;

        if (exitQueue.length > 0 && !_isExitQueueEmpty() && participantsShare > 0) {
            uint256 balanceBefore = IERC20(lpToken).balanceOf(address(this));
            _processExitQueue(participantsShare, lpToken);
            uint256 balanceAfter = IERC20(lpToken).balanceOf(address(this));
            usedForExits = balanceBefore > balanceAfter ? balanceBefore - balanceAfter : 0;
        }

        // 4. Distribute remaining to participants
        uint256 remainingForParticipants = participantsShare - usedForExits;
        if (remainingForParticipants > 0) {
            rewardPerShareStored[lpToken] += (remainingForParticipants * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;
        }

        // Update accounting - reduce the tracked balance
        accountedBalance[lpToken] -= toDistribute;
        lastLPDistribution[lpToken] = block.timestamp;

        emit LPProfitDistributed(lpToken, toDistribute);
    }

    /// @notice Update vault rewards snapshot for all tokens
    /// @param vaultId Vault ID to update
    function _updateVaultRewards(uint256 vaultId) internal {
        DataTypes.Vault memory vault = vaults[vaultId];
        if (vault.shares == 0) return;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address token = rewardTokens[i];
            uint256 pending = _calculatePendingRewards(vaultId, token);

            if (pending > 0) {
                earnedRewards[vaultId][token] += pending;
            }

            vaultRewardIndex[vaultId][token] = rewardPerShareStored[token];
        }
    }

    /// @notice Calculate pending rewards for a vault and token
    /// @param vaultId Vault ID
    /// @param token Token address
    /// @return Pending rewards amount
    function _calculatePendingRewards(uint256 vaultId, address token) internal view returns (uint256) {
        DataTypes.Vault memory vault = vaults[vaultId];
        if (vault.shares == 0) return 0;

        uint256 currentIndex = rewardPerShareStored[token];
        uint256 userIndex = vaultRewardIndex[vaultId][token];

        if (currentIndex <= userIndex) return 0;

        uint256 indexDelta = currentIndex - userIndex;
        return (vault.shares * indexDelta) / PRICE_DECIMALS_MULTIPLIER;
    }

    /// @notice Update weighted average prices when participant adds more shares
    /// @param vaultId Vault ID
    /// @param newShares New shares being added
    /// @param newLaunchPrice Launch price for the new deposit
    function _updateWeightedAverages(uint256 vaultId, uint256 newShares, uint256 newLaunchPrice) internal {
        DataTypes.Vault storage vault = vaults[vaultId];
        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];

        if (vault.shares == 0) {
            // First deposit - just set the price
            entry.weightedAvgLaunchPrice = newLaunchPrice;
            entry.weightedAvgSharePrice = fundraisingConfig.sharePrice;
            return;
        }

        // Weighted average = (old_price * old_shares + new_price * new_shares) / total_shares
        uint256 totalShares = vault.shares + newShares;
        entry.weightedAvgLaunchPrice =
            (entry.weightedAvgLaunchPrice * vault.shares + newLaunchPrice * newShares) / totalShares;

        // Calculate weighted average share price
        entry.weightedAvgSharePrice =
            (entry.weightedAvgSharePrice * vault.shares + fundraisingConfig.sharePrice * newShares) / totalShares;
    }

    /// @notice Get launch token price from first POC contract
    /// @return Launch price in USD (18 decimals)
    function _getLaunchPriceFromPOC() internal view returns (uint256) {
        require(pocContracts.length > 0, NoPOCContractsConfigured());
        uint256 launchPriceInCollateral = IProofOfCapital(pocContracts[0].pocContract).currentPrice();
        uint256 collateralPriceUSD = _getPOCCollateralPrice(0);

        return (launchPriceInCollateral * collateralPriceUSD) / PRICE_DECIMALS_MULTIPLIER;
    }

    /// @notice Calculate exit value for a participant
    /// @dev Applies 20% discount if exiting within first year; reduces value if launch price dropped
    /// @param vaultId Vault ID
    /// @param shares Number of shares to exit
    /// @return Exit value in USD (18 decimals)
    function _calculateExitValue(uint256 vaultId, uint256 shares) internal view returns (uint256) {
        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];

        uint256 shareValue = entry.fixedSharePrice;
        if (shareValue == 0) {
            shareValue = fundraisingConfig.sharePrice;
        }

        // Apply 20% discount if exiting within first year
        if (block.timestamp < entry.entryTimestamp + EXIT_DISCOUNT_PERIOD) {
            shareValue = (shareValue * (BASIS_POINTS - EXIT_DISCOUNT_PERCENT)) / BASIS_POINTS;
        }

        // Reduce value if launch price has dropped
        uint256 launchPriceNow = _getLaunchPriceFromPOC();
        uint256 fixedLaunchPrice = entry.fixedLaunchPrice > 0 ? entry.fixedLaunchPrice : fundraisingConfig.launchPrice;

        if (launchPriceNow < fixedLaunchPrice) {
            shareValue = (shareValue * launchPriceNow) / fixedLaunchPrice;
        }

        return (shareValue * shares) / PRICE_DECIMALS_MULTIPLIER;
    }

    /// @notice Check if exit queue is empty (all processed)
    /// @return True if no pending exits
    function _isExitQueueEmpty() internal view returns (bool) {
        for (uint256 i = 0; i < exitQueue.length; i++) {
            if (!exitQueue[i].processed) {
                return false;
            }
        }
        return true;
    }

    /// @notice Process exit queue with available funds
    /// @param availableFunds Amount of funds available for buyback
    /// @param token Token used for buyback
    function _processExitQueue(uint256 availableFunds, address token) internal {
        if (availableFunds == 0 || _isExitQueueEmpty()) return;

        for (uint256 i = 0; i < exitQueue.length && availableFunds > 0; i++) {
            DataTypes.ExitRequest storage request = exitQueue[i];
            if (request.processed) continue;

            uint256 exitValue = _calculateExitValue(request.vaultId, request.shares);

            if (availableFunds >= exitValue) {
                _executeExit(i, exitValue, token);
                availableFunds -= exitValue;
            } else {
                uint256 partialShares = (availableFunds * request.shares) / exitValue;
                if (partialShares > 0) {
                    uint256 partialExitValue = _calculateExitValue(request.vaultId, partialShares);
                    if (partialExitValue > 0 && partialExitValue <= availableFunds) {
                        request.shares -= partialShares;
                        _executePartialExit(request.vaultId, partialShares, partialExitValue, token);
                        availableFunds -= partialExitValue;
                    }
                }
            }
        }
    }

    /// @notice Execute a single exit request
    /// @param exitIndex Index in exit queue
    /// @param exitValue Value to pay out
    /// @param token Token to pay with
    function _executeExit(uint256 exitIndex, uint256 exitValue, address token) internal {
        DataTypes.ExitRequest storage request = exitQueue[exitIndex];
        uint256 vaultId = request.vaultId;
        uint256 shares = request.shares;

        DataTypes.Vault storage vault = vaults[vaultId];

        // Update rewards before changing shares
        _updateVaultRewards(vaultId);

        // Remove shares from vault
        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        totalSharesSupply -= shares;

        // Mark as processed
        request.processed = true;
        vaultExitRequestIndex[vaultId] = 0;

        // Transfer payout to vault owner
        IERC20(token).safeTransfer(vault.primary, exitValue);

        // Increase share price: multiplier = 1 + (exitedShares / remainingShares)
        // This is effectively done by reducing total supply while keeping assets constant
        if (totalSharesSupply > 0) {
            uint256 oldSharePrice = fundraisingConfig.sharePrice;
            uint256 newSharePrice = (oldSharePrice * previousTotalShares) / totalSharesSupply;
            fundraisingConfig.sharePrice = newSharePrice;
            emit SharePriceIncreased(oldSharePrice, newSharePrice, shares);
        }

        emit ExitProcessed(vaultId, shares, exitValue, token);
    }

    function _executePartialExit(uint256 vaultId, uint256 shares, uint256 payoutAmount, address token) internal {
        DataTypes.Vault storage vault = vaults[vaultId];

        _updateVaultRewards(vaultId);

        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        totalSharesSupply -= shares;

        IERC20(token).safeTransfer(vault.primary, payoutAmount);

        if (totalSharesSupply > 0) {
            uint256 oldSharePrice = fundraisingConfig.sharePrice;
            uint256 newSharePrice = (oldSharePrice * previousTotalShares) / totalSharesSupply;
            fundraisingConfig.sharePrice = newSharePrice;
            emit SharePriceIncreased(oldSharePrice, newSharePrice, shares);
        }

        emit PartialExitProcessed(vaultId, shares, payoutAmount, token);
    }

    /// @notice Get oracle price for a collateral token
    /// @param token Collateral token address
    /// @return Price in USD (18 decimals)
    function _getOraclePrice(address token) internal view returns (uint256) {
        DataTypes.CollateralInfo storage info = sellableCollaterals[token];
        require(info.active, CollateralNotActive());
        return Orderbook.getCollateralPrice(info);
    }

    /// @notice Get POC collateral price from its oracle
    /// @param pocIdx POC index
    /// @return Price in USD (18 decimals)
    function _getPOCCollateralPrice(uint256 pocIdx) internal view returns (uint256) {
        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        IAggregatorV3 priceFeed = IAggregatorV3(poc.priceFeed);
        (, int256 price,,,) = priceFeed.latestRoundData();
        require(price > 0, InvalidPrice());

        uint8 decimals = priceFeed.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    /// @notice Calculate price deviation in basis points
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @return Deviation in basis points
    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return BASIS_POINTS;
        if (actual >= expected) {
            return ((actual - expected) * BASIS_POINTS) / expected;
        } else {
            return ((expected - actual) * BASIS_POINTS) / expected;
        }
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin || msg.sender == votingContract, Unauthorized());
    }

    function _onlyVoting() internal view {
        require(msg.sender == address(this), OnlyByDAOVoting());
    }

    function _atStage(DataTypes.Stage stage) internal view {
        require(currentStage == stage, InvalidStage());
    }

    function _vaultExists(uint256 vaultId) internal view {
        require(vaultId < nextVaultId && vaults[vaultId].shares > 0, VaultDoesNotExist());
    }

    function _onlyParticipantOrAdmin() internal view {
        uint256 vaultId = addressToVaultId[msg.sender];
        bool isParticipant = vaultId < nextVaultId && vaults[vaultId].shares > 0;
        bool isAdminUser = msg.sender == admin || msg.sender == votingContract;
        require(isParticipant || isAdminUser, Unauthorized());
    }

    function _onlyCreatorOrAdmin() internal view {
        require(msg.sender == creator || msg.sender == admin || msg.sender == votingContract, Unauthorized());
    }

    function _onlyCreator() internal view {
        require(msg.sender == creator, OnlyCreator());
    }

    function _onlyBoardMemberOrAdmin() internal view {
        uint256 vaultId = addressToVaultId[msg.sender];
        bool isMemberOfBoard = vaultId > 0 && vaults[vaultId].shares >= BOARD_MEMBER_MIN_SHARES;
        require(isMemberOfBoard || msg.sender == admin || msg.sender == votingContract, NotBoardMemberOrAdmin());
    }

    function _fundraisingActive() internal view {
        require(currentStage == DataTypes.Stage.Fundraising, InvalidStage());
        require(block.timestamp < fundraisingConfig.deadline, FundraisingDeadlinePassed());
    }

    /// @notice Extract revert message from return data
    /// @param returnData Return data from failed call
    /// @return Revert message
    function _getRevertMsg(bytes memory returnData) internal pure returns (string memory) {
        if (returnData.length < 68) return "Transaction reverted silently";

        assembly {
            returnData := add(returnData, 0x04)
        }
        return abi.decode(returnData, (string));
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

    /// @notice Check if an account is a board member (has >= 10 shares)
    /// @param account Address to check
    /// @return True if account is a board member
    function isBoardMember(address account) external view returns (bool) {
        uint256 vaultId = addressToVaultId[account];
        return vaultId > 0 && vaults[vaultId].shares >= BOARD_MEMBER_MIN_SHARES;
    }

    /// @notice Set pending upgrade address (only voting contract can call)
    /// @param newImplementation Address of the new implementation to approve
    function setPendingUpgradeFromVoting(address newImplementation) external onlyVoting {
        require(newImplementation != address(0), InvalidAddress());
        pendingUpgradeFromVoting = newImplementation;
        emit PendingUpgradeSetFromVoting(newImplementation);
    }

    /// @notice Set pending upgrade address (only creator can call)
    /// @param newImplementation Address of the new implementation to approve
    function setPendingUpgradeFromCreator(address newImplementation) external onlyCreator {
        require(newImplementation != address(0), InvalidAddress());
        pendingUpgradeFromCreator = newImplementation;
        emit PendingUpgradeSetFromCreator(newImplementation);
    }

    /// @notice Authorize upgrade (requires both voting and creator approval)
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override {
        require(newImplementation != address(0), InvalidAddress());
        require(
            pendingUpgradeFromVoting == newImplementation && pendingUpgradeFromCreator == newImplementation,
            UpgradeNotAuthorized()
        );

        // Reset pending upgrades after successful authorization
        pendingUpgradeFromVoting = address(0);
        pendingUpgradeFromCreator = address(0);
    }
}

