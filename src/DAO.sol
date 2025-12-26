// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

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

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IProofOfCapital.sol";
import "./interfaces/INonfungiblePositionManager.sol";
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
    uint256 public constant MIN_EXIT_SHARES = 1e18; // Minimum shares required to exit (1 share)
    uint256 public constant EXIT_DISCOUNT_PERIOD = 365 days; // Period for early exit discount
    uint256 public constant EXIT_DISCOUNT_PERCENT = 2000; // 20% discount for early exit
    uint256 public constant MAX_CREATOR_ALLOCATION_PERCENT = 500; // 5% max launches per period
    uint256 public constant ALLOCATION_PERIOD = 30 days; // Period between allocations
    uint256 public constant LP_DISTRIBUTION_PERIOD = 30 days; // Monthly LP distribution period
    uint256 public constant LP_DISTRIBUTION_PERCENT = 100; // 1% of LP tokens distributed per month
    uint256 public constant MIN_REWARD_PER_SHARE = 10; // Minimum reward per share in minimal units
    uint256 public constant UPGRADE_DELAY = 5 days; // Delay required before upgrade can be authorized
    uint256 public constant CANCEL_AFTER_ACTIVE_PERIOD = 100 days; // Period after Active stage when anyone with shares can cancel

    address public admin;
    address public votingContract;
    IERC20 public launchToken;
    address public mainCollateral;

    DataTypes.Stage public currentStage;
    uint256 public totalSharesSupply;
    uint256 public nextVaultId;

    address public creator;
    uint256 public creatorProfitPercent;
    uint256 public creatorInfraPercent;

    address public royaltyRecipient;
    uint256 public royaltyPercent;

    DataTypes.FundraisingConfig public fundraisingConfig;
    mapping(uint256 => DataTypes.ParticipantEntry) public participantEntries;
    uint256 public totalCollectedMainCollateral;

    DataTypes.POCInfo[] public pocContracts;
    mapping(address => uint256) public pocIndex;
    mapping(address => bool) public isPocContract;

    uint256 public totalLaunchBalance;
    uint256 public sharePriceInLaunches;

    DataTypes.OrderbookParams public orderbookParams;

    mapping(uint256 => DataTypes.Vault) public vaults;
    mapping(address => uint256) public addressToVaultId;
    mapping(uint256 => uint256) public vaultMainCollateralDeposit;

    mapping(address => DataTypes.CollateralInfo) public sellableCollaterals;

    address[] public rewardTokens;
    mapping(address => DataTypes.RewardTokenInfo) public rewardTokenInfo;

    mapping(address => bool) public availableRouterByAdmin;

    mapping(address => uint256) public accountedBalance;
    mapping(address => uint256) public rewardPerShareStored;
    mapping(uint256 => mapping(address => uint256)) public vaultRewardIndex;
    mapping(uint256 => mapping(address => uint256)) public earnedRewards;

    address[] public v2LPTokens;
    mapping(address => bool) public isV2LPToken;

    DataTypes.V3LPPositionInfo[] public v3LPPositions;
    mapping(uint256 => uint256) public v3TokenIdToIndex;

    address public v3PositionManager;

    DataTypes.LPTokenType public primaryLPTokenType;

    DataTypes.ExitRequest[] public exitQueue;
    mapping(uint256 => uint256) public vaultExitRequestIndex;
    uint256 public nextExitQueueIndex;

    uint256 public lastCreatorAllocation;
    mapping(address => uint256) public lastLPDistribution;
    mapping(address => uint256) public lpTokenAddedAt;
    mapping(uint256 => uint256) public v3LastLPDistribution;
    mapping(uint256 => uint256) public v3LPTokenAddedAt;
    uint256 public activeStageTimestamp;

    address public pendingUpgradeFromVoting;
    uint256 public pendingUpgradeFromVotingTimestamp;
    address public pendingUpgradeFromCreator;

    bool public doNotExtendPOCLock;

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

    /// @custom:oz-upgrades-unsafe-allow constructor
    constructor() {
        _disableInitializers();
    }

    /// @notice Initialize the DAO contract (replaces constructor for upgradeable pattern)
    /// @param params Constructor parameters struct
    function initialize(DataTypes.ConstructorParams memory params) public initializer {
        require(params.launchToken != address(0), InvalidLaunchToken());
        require(params.mainCollateral != address(0), InvalidAddress());
        require(params.creator != address(0), InvalidAddress());
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

        for (uint256 i = 0; i < params.routers.length; i++) {
            address router = params.routers[i];
            require(router != address(0), InvalidAddress());
            require(!availableRouterByAdmin[router], RouterAlreadyAdded());

            availableRouterByAdmin[router] = true;

            emit RouterAvailabilityChanged(router, true);
        }

        uint256 totalPOCShare = 0;
        for (uint256 i = 0; i < params.pocParams.length; i++) {
            DataTypes.POCConstructorParams memory poc = params.pocParams[i];

            require(poc.pocContract != address(0), InvalidAddress());
            require(poc.collateralToken != address(0), InvalidAddress());
            require(poc.priceFeed != address(0), InvalidAddress());
            require(poc.sharePercent > 0 && poc.sharePercent <= BASIS_POINTS, InvalidPercentage());
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

            if (!rewardTokenInfo[poc.collateralToken].active) {
                rewardTokens.push(poc.collateralToken);
                rewardTokenInfo[poc.collateralToken] =
                    DataTypes.RewardTokenInfo({token: poc.collateralToken, priceFeed: poc.priceFeed, active: true});
                emit RewardTokenAdded(poc.collateralToken, poc.priceFeed);
            }

            emit POCContractAdded(poc.pocContract, poc.collateralToken, poc.sharePercent);
        }
        require(totalPOCShare == BASIS_POINTS || totalPOCShare == 0, POCSharesNot100Percent());

        for (uint256 i = 0; i < params.rewardTokenParams.length; i++) {
            DataTypes.RewardTokenConstructorParams memory reward = params.rewardTokenParams[i];

            require(reward.token != address(0), InvalidAddress());
            require(reward.priceFeed != address(0), InvalidAddress());
            require(!rewardTokenInfo[reward.token].active, TokenAlreadyAdded());

            rewardTokens.push(reward.token);
            rewardTokenInfo[reward.token] =
                DataTypes.RewardTokenInfo({token: reward.token, priceFeed: reward.priceFeed, active: true});
            emit RewardTokenAdded(reward.token, reward.priceFeed);
        }

        if (!rewardTokenInfo[address(launchToken)].active) {
            rewardTokens.push(address(launchToken));
            rewardTokenInfo[address(launchToken)] =
                DataTypes.RewardTokenInfo({token: address(launchToken), priceFeed: address(0), active: true});
            emit RewardTokenAdded(address(launchToken), address(0));
        }

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

        primaryLPTokenType = params.primaryLPTokenType;

        if (params.v3LPPositions.length > 0) {
            v3PositionManager = params.v3LPPositions[0].positionManager;
            require(v3PositionManager != address(0), InvalidAddress());
            for (uint256 i = 0; i < params.v3LPPositions.length; i++) {
                require(params.v3LPPositions[i].positionManager == v3PositionManager, InvalidAddress());
            }
        }

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
    /// @param delegate Delegate address for voting (if zero, primary is delegate)
    /// @return vaultId The ID of the created vault
    function createVault(address backup, address emergency, address delegate)
        external
        nonReentrant
        returns (uint256 vaultId)
    {
        require(currentStage == DataTypes.Stage.Fundraising || currentStage == DataTypes.Stage.Active, InvalidStage());
        require(backup != address(0) && emergency != address(0), InvalidAddresses());
        require(addressToVaultId[msg.sender] == 0, VaultAlreadyExists());

        vaultId = nextVaultId++;

        // If delegate is zero, set primary as delegate
        address finalDelegate = delegate == address(0) ? msg.sender : delegate;

        vaults[vaultId] = DataTypes.Vault({
            primary: msg.sender,
            backup: backup,
            emergency: emergency,
            shares: 0,
            votingPausedUntil: 0,
            delegate: finalDelegate,
            delegateSetAt: block.timestamp,
            votingShares: 0
        });

        addressToVaultId[msg.sender] = vaultId;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            if (rewardTokenInfo[rewardToken].active) {
                vaultRewardIndex[vaultId][rewardToken] = rewardPerShareStored[rewardToken];
            }
        }

        for (uint256 i = 0; i < v2LPTokens.length; i++) {
            address token = v2LPTokens[i];
            vaultRewardIndex[vaultId][token] = rewardPerShareStored[token];
        }

        vaultMainCollateralDeposit[vaultId] = 0;

        emit VaultCreated(vaultId, msg.sender, 0);
    }

    /// @notice Deposit mainCollateral during fundraising stage
    /// @param amount Amount of mainCollateral to deposit (18 decimals)
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    function depositFundraising(uint256 amount, uint256 vaultId) external nonReentrant fundraisingActive {
        require(amount > 0, AmountMustBeGreaterThanZero());
        require(amount >= fundraisingConfig.minDeposit, DepositBelowMinimum());

        // If vaultId is 0, use sender's vault, otherwise use provided vaultId
        if (vaultId == 0) {
            vaultId = addressToVaultId[msg.sender];
        }
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];

        uint256 shares = (amount * PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

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
        totalSharesSupply += shares;
        totalCollectedMainCollateral += amount;

        // Update voting shares for delegate
        _updateDelegateVotingShares(vaultId, int256(shares));

        vaultMainCollateralDeposit[vaultId] += amount;

        IERC20(mainCollateral).safeTransferFrom(msg.sender, address(this), amount);

        emit FundraisingDeposit(vaultId, msg.sender, amount, shares);
    }

    /// @notice Deposit launch tokens during active stage to receive shares
    /// @dev New participants can enter by depositing launches; price is fixed at entry
    /// @param launchAmount Amount of launch tokens to deposit
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    function depositLaunches(uint256 launchAmount, uint256 vaultId)
        external
        nonReentrant
        atStage(DataTypes.Stage.Active)
    {
        require(launchAmount >= fundraisingConfig.minLaunchDeposit, BelowMinLaunchDeposit());

        // If vaultId is 0, use sender's vault, otherwise use provided vaultId
        if (vaultId == 0) {
            vaultId = addressToVaultId[msg.sender];
        }
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];

        uint256 launchPriceUSD = _getLaunchPriceFromPOC();
        require(launchPriceUSD > 0, InvalidPrice());

        uint256 shares = (launchAmount * PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        require(shares > 0, SharesCalculationFailed());

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];

        _updateWeightedAverages(vaultId, shares, launchPriceUSD / 2);

        if (entry.entryTimestamp == 0) {
            entry.entryTimestamp = block.timestamp;
            entry.fixedSharePrice = fundraisingConfig.sharePrice;
            entry.fixedLaunchPrice = fundraisingConfig.launchPrice;
        }

        _updateVaultRewards(vaultId);

        vault.shares += shares;
        totalSharesSupply += shares;

        // Update voting shares for delegate
        _updateDelegateVotingShares(vaultId, int256(shares));

        launchToken.safeTransferFrom(msg.sender, address(this), launchAmount);
        totalLaunchBalance += launchAmount;
        accountedBalance[address(launchToken)] += launchAmount;

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

    /// @notice Set delegate address for voting (only callable by voting contract)
    /// @param userAddress User address to find vault and set delegate
    /// @param delegate New delegate address (if zero, primary is set as delegate)
    function setDelegate(address userAddress, address delegate) external {
        require(msg.sender == address(votingContract), OnlyVotingContract());
        require(votingContract != address(0), InvalidAddress());
        require(userAddress != address(0), InvalidAddress());

        uint256 vaultId = addressToVaultId[userAddress];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.shares > 0, NoShares());

        // If delegate is zero, set primary as delegate
        address finalDelegate = delegate == address(0) ? vault.primary : delegate;

        address oldDelegate = vault.delegate;
        uint256 vaultShares = vault.shares;

        if (oldDelegate != address(0)) {
            uint256 oldDelegateVaultId = addressToVaultId[oldDelegate];
            if (oldDelegateVaultId > 0 && oldDelegateVaultId < nextVaultId) {
                DataTypes.Vault storage oldDelegateVault = vaults[oldDelegateVaultId];
                if (oldDelegateVault.votingShares >= vaultShares) {
                    oldDelegateVault.votingShares -= vaultShares;
                } else {
                    oldDelegateVault.votingShares = 0;
                }
            }
        }

        vault.delegate = finalDelegate;
        vault.delegateSetAt = block.timestamp;

        if (finalDelegate != address(0) && finalDelegate != vault.primary) {
            uint256 newDelegateVaultId = addressToVaultId[finalDelegate];
            if (newDelegateVaultId > 0 && newDelegateVaultId < nextVaultId) {
                DataTypes.Vault storage newDelegateVault = vaults[newDelegateVaultId];
                newDelegateVault.votingShares += vaultShares;
            }
        }

        emit DelegateUpdated(vaultId, oldDelegate, finalDelegate, block.timestamp);
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

        for (uint256 i = 0; i < v2LPTokens.length; i++) {
            address lpToken = v2LPTokens[i];
            uint256 rewards = earnedRewards[vaultId][lpToken];

            if (rewards > 0) {
                earnedRewards[vaultId][lpToken] = 0;
                accountedBalance[lpToken] -= rewards;

                IERC20(lpToken).safeTransfer(msg.sender, rewards);

                emit RewardClaimed(vaultId, lpToken, rewards);
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
        require(vault.shares >= MIN_EXIT_SHARES, AmountMustBeGreaterThanZero());
        require(vaultExitRequestIndex[vaultId] == 0, AlreadyInExitQueue());

        address delegate = vault.delegate;
        uint256 vaultShares = vault.shares;

        if (delegate != address(0) && delegate != vault.primary) {
            uint256 delegateVaultId = addressToVaultId[delegate];
            if (delegateVaultId > 0 && delegateVaultId < nextVaultId) {
                DataTypes.Vault storage delegateVault = vaults[delegateVaultId];
                if (delegateVault.votingShares >= vaultShares) {
                    delegateVault.votingShares -= vaultShares;
                } else {
                    delegateVault.votingShares = 0;
                }
            }
        }

        uint256 launchPriceNow = _getLaunchPriceFromPOC();

        exitQueue.push(
            DataTypes.ExitRequest({
                vaultId: vaultId,
                requestTimestamp: block.timestamp,
                fixedLaunchPriceAtRequest: launchPriceNow,
                processed: false
            })
        );

        vaultExitRequestIndex[vaultId] = exitQueue.length;

        emit ExitRequested(vaultId, vault.shares, launchPriceNow);
    }

    /// @notice Allocate launch tokens to creator, reducing their profit share proportionally
    /// @dev Can only be done once per ALLOCATION_PERIOD; max MAX_CREATOR_ALLOCATION_PERCENT per period
    /// @param launchAmount Amount of launch tokens to allocate
    function allocateLaunchesToCreator(uint256 launchAmount) external onlyVoting atStage(DataTypes.Stage.Active) {
        require(block.timestamp >= lastCreatorAllocation + ALLOCATION_PERIOD, AllocationTooSoon());
        require(launchAmount > 0, AmountMustBeGreaterThanZero());

        uint256 maxAllocation = (totalLaunchBalance * MAX_CREATOR_ALLOCATION_PERCENT) / BASIS_POINTS;
        require(launchAmount <= maxAllocation, ExceedsMaxAllocation());

        // Calculate how many shares equivalent this represents
        require(sharePriceInLaunches > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (launchAmount * PRICE_DECIMALS_MULTIPLIER) / sharePriceInLaunches;

        // Calculate what % of total shares this represents
        require(totalSharesSupply > 0, NoShares());
        uint256 profitPercentEquivalent = (sharesEquivalent * BASIS_POINTS) / totalSharesSupply;

        require(creatorProfitPercent >= profitPercentEquivalent, CreatorShareTooLow());
        creatorProfitPercent -= profitPercentEquivalent;

        launchToken.safeTransfer(creator, launchAmount);
        totalLaunchBalance -= launchAmount;
        accountedBalance[address(launchToken)] -= launchAmount;
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
            totalSharesSupply,
            fundraisingConfig.sharePrice
        );

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

    /// @notice Withdraw funds if fundraising was cancelled
    function withdrawFundraising() external nonReentrant atStage(DataTypes.Stage.FundraisingCancelled) {
        uint256 vaultId = addressToVaultId[msg.sender];
        require(vaultId > 0 && vaultId < nextVaultId, NoVaultFound());

        DataTypes.Vault storage vault = vaults[vaultId];
        require(vault.primary == msg.sender, OnlyPrimaryCanClaim());

        uint256 shares = vault.shares;
        require(shares > 0, NoSharesToClaim());
        require(totalSharesSupply > 0, NoShares());

        uint256 mainCollateralAmount = (totalCollectedMainCollateral * shares) / totalSharesSupply;
        require(mainCollateralAmount > 0, NoDepositToWithdraw());

        uint256 launchTokenAmount = 0;
        if (totalLaunchBalance > 0) {
            launchTokenAmount = (totalLaunchBalance * shares) / totalSharesSupply;
        }

        vault.shares = 0;
        totalSharesSupply -= shares;
        totalCollectedMainCollateral -= mainCollateralAmount;

        DataTypes.ParticipantEntry storage entry = participantEntries[vaultId];
        entry.depositedMainCollateral = 0;
        vaultMainCollateralDeposit[vaultId] = 0;

        IERC20(mainCollateral).safeTransfer(msg.sender, mainCollateralAmount);

        if (launchTokenAmount > 0) {
            totalLaunchBalance -= launchTokenAmount;
            accountedBalance[address(launchToken)] -= launchTokenAmount;
            launchToken.safeTransfer(msg.sender, launchTokenAmount);
        }

        emit FundraisingWithdrawal(vaultId, msg.sender, mainCollateralAmount);
    }

    /// @notice Extend fundraising deadline (only once)
    function extendFundraising() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        require(!fundraisingConfig.extended, FundraisingAlreadyExtended());
        require(block.timestamp >= fundraisingConfig.deadline, FundraisingNotExpiredYet());

        fundraisingConfig.deadline = block.timestamp + fundraisingConfig.extensionPeriod;
        fundraisingConfig.extended = true;

        emit FundraisingExtended(fundraisingConfig.deadline);
    }

    /// @notice Cancel fundraising
    /// @dev In Fundraising stage: admin or participant can cancel if target not reached after deadline
    /// @dev In Active or Dissolved stage: admin or participant can cancel after 100 days in Active stage
    function cancelFundraising() external onlyParticipantOrAdmin {
        if (currentStage == DataTypes.Stage.Fundraising) {
            require(block.timestamp >= fundraisingConfig.deadline + 1 days, FundraisingNotExpiredYet());

            currentStage = DataTypes.Stage.FundraisingCancelled;

            emit FundraisingCancelled(totalCollectedMainCollateral);
            emit StageChanged(DataTypes.Stage.Fundraising, DataTypes.Stage.FundraisingCancelled);
        } else if (currentStage == DataTypes.Stage.FundraisingExchange || currentStage == DataTypes.Stage.WaitingForLP)
        {
            require(activeStageTimestamp > 0, ActiveStageNotSet());
            require(block.timestamp >= activeStageTimestamp + CANCEL_AFTER_ACTIVE_PERIOD, CancelPeriodNotPassed());

            DataTypes.Stage oldStage = currentStage;
            currentStage = DataTypes.Stage.FundraisingCancelled;

            emit FundraisingCancelled(totalCollectedMainCollateral);
            emit StageChanged(oldStage, DataTypes.Stage.FundraisingCancelled);
        } else {
            revert InvalidStage();
        }
    }

    /// @notice Finalize fundraising collection and move to exchange stage
    function finalizeFundraisingCollection() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        require(totalCollectedMainCollateral >= fundraisingConfig.targetAmountMainCollateral, TargetNotReached());

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
                0,
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
        accountedBalance[address(launchToken)] += launchReceived;

        emit POCExchangeCompleted(pocIdx, poc.pocContract, collateralAmountForPOC, collateralAmount, launchReceived);
    }

    /// @notice Finalize exchange process and calculate share price in launches
    function finalizeExchange() external onlyAdmin atStage(DataTypes.Stage.FundraisingExchange) {
        for (uint256 i = 0; i < pocContracts.length; i++) {
            require(pocContracts[i].exchanged, POCNotExchanged());
        }

        require(totalSharesSupply > 0, NoSharesIssued());
        sharePriceInLaunches = (totalLaunchBalance * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;

        uint256 infraLaunches = (totalLaunchBalance * creatorInfraPercent) / BASIS_POINTS;
        if (infraLaunches > 0) {
            launchToken.safeTransfer(creator, infraLaunches);
            totalLaunchBalance -= infraLaunches;
            accountedBalance[address(launchToken)] -= infraLaunches;
        }

        currentStage = DataTypes.Stage.WaitingForLP;

        emit ExchangeFinalized(totalLaunchBalance, sharePriceInLaunches, infraLaunches);
        emit StageChanged(DataTypes.Stage.FundraisingExchange, DataTypes.Stage.WaitingForLP);
    }

    /// @notice Creator provides LP tokens and moves DAO to active stage
    /// @param v2LPTokenAddresses Array of V2 LP token addresses
    /// @param v2LPAmounts Array of V2 LP token amounts to deposit
    /// @param v3TokenIds Array of V3 LP position token IDs
    function provideLPTokens(
        address[] calldata v2LPTokenAddresses,
        uint256[] calldata v2LPAmounts,
        uint256[] calldata v3TokenIds
    ) external nonReentrant onlyCreator atStage(DataTypes.Stage.WaitingForLP) {
        require(v2LPTokenAddresses.length == v2LPAmounts.length, InvalidAddresses());
        require(v2LPTokenAddresses.length > 0 || v3TokenIds.length > 0, InvalidAddress());

        if (primaryLPTokenType == DataTypes.LPTokenType.V2) {
            require(v2LPTokenAddresses.length > 0, InvalidAddress());
        } else if (primaryLPTokenType == DataTypes.LPTokenType.V3) {
            require(v3TokenIds.length > 0, InvalidAddress());
        }

        for (uint256 i = 0; i < v2LPTokenAddresses.length; i++) {
            address lpToken = v2LPTokenAddresses[i];
            uint256 lpAmount = v2LPAmounts[i];

            require(lpToken != address(0), InvalidAddress());
            require(lpAmount > 0, AmountMustBeGreaterThanZero());

            IERC20(lpToken).safeTransferFrom(msg.sender, address(this), lpAmount);

            if (!isV2LPToken[lpToken]) {
                v2LPTokens.push(lpToken);
                isV2LPToken[lpToken] = true;
            }
            accountedBalance[lpToken] += lpAmount;
            lpTokenAddedAt[lpToken] = block.timestamp;
            lastLPDistribution[lpToken] = block.timestamp;

            emit LPTokensProvided(lpToken, lpAmount);
        }

        if (v3TokenIds.length > 0) {
            require(v3PositionManager != address(0), InvalidAddress());
            INonfungiblePositionManager positionManager = INonfungiblePositionManager(v3PositionManager);

            for (uint256 i = 0; i < v3TokenIds.length; i++) {
                uint256 tokenId = v3TokenIds[i];
                require(v3TokenIdToIndex[tokenId] == 0, TokenAlreadyAdded());

                require(positionManager.ownerOf(tokenId) == address(this), Unauthorized());

                (,, address token0, address token1,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
                require(liquidity > 0, AmountMustBeGreaterThanZero());

                require(rewardTokenInfo[token0].active, TokenNotAdded());
                require(rewardTokenInfo[token1].active, TokenNotAdded());
                v3LPPositions.push(
                    DataTypes.V3LPPositionInfo({
                        positionManager: v3PositionManager, tokenId: tokenId, token0: token0, token1: token1
                    })
                );

                v3TokenIdToIndex[tokenId] = v3LPPositions.length;
                v3LPTokenAddedAt[tokenId] = block.timestamp;
                v3LastLPDistribution[tokenId] = block.timestamp;

                emit V3LPPositionProvided(tokenId, token0, token1);
            }
        }

        currentStage = DataTypes.Stage.Active;
        activeStageTimestamp = block.timestamp;

        emit StageChanged(DataTypes.Stage.WaitingForLP, DataTypes.Stage.Active);
    }

    /// @notice Dissolve DAO if all POC contract locks have ended (callable by any participant or admin without voting)
    /// @dev Checks all active POC contracts to see if their lock periods have ended
    /// @dev If all locks are ended, transitions DAO to Dissolved stage
    function dissolveIfLocksEnded() external {
        require(pocContracts.length > 0, NoPOCContractsConfigured());

        for (uint256 i = 0; i < pocContracts.length; i++) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (poc.active) {
                uint256 lockEndTime = IProofOfCapital(poc.pocContract).lockEndTime();
                require(block.timestamp >= lockEndTime, POCLockPeriodNotEnded());

                IProofOfCapital(poc.pocContract).withdrawAllLaunchTokens();
                IProofOfCapital(poc.pocContract).withdrawAllCollateralTokens();
            }
        }

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

        // Update voting shares for delegate
        _updateDelegateVotingShares(vaultId, -int256(shares));

        for (uint256 i = 0; i < tokens.length; i++) {
            address token = tokens[i];
            require(token != address(0), InvalidAddress());

            uint256 tokenBalance = IERC20(token).balanceOf(address(this));
            if (tokenBalance == 0) continue;

            bool isValidToken = token == address(launchToken) || rewardTokenInfo[token].active;

            require(isValidToken, InvalidAddress());

            uint256 tokenShare = (tokenBalance * shares) / totalSharesSupply;
            if (tokenShare > 0) {
                IERC20(token).safeTransfer(msg.sender, tokenShare);
                if (token == address(launchToken)) {
                    accountedBalance[address(launchToken)] -= tokenShare;
                }
            }
        }

        totalSharesSupply -= shares;
    }

    /// @notice Return launch tokens from POC contract, restoring creator's profit share
    /// @dev POC contract returns launch tokens that were allocated to creator
    /// @param amount Amount of launch tokens to return
    function upgradeOwnerShare(uint256 amount) external {
        require(isPocContract[msg.sender], OnlyPOCContract());
        require(amount > 0, AmountMustBeGreaterThanZero());

        launchToken.safeTransferFrom(msg.sender, address(this), amount);

        // Calculate how many shares equivalent this represents
        require(sharePriceInLaunches > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (amount * PRICE_DECIMALS_MULTIPLIER) / sharePriceInLaunches;

        // Calculate what % of total shares this represents
        require(totalSharesSupply > 0, NoShares());
        uint256 profitPercentEquivalent = (sharesEquivalent * BASIS_POINTS) / totalSharesSupply;

        uint256 newCreatorProfitPercent = creatorProfitPercent + profitPercentEquivalent;
        if (newCreatorProfitPercent > BASIS_POINTS) {
            newCreatorProfitPercent = BASIS_POINTS;
            profitPercentEquivalent = BASIS_POINTS - creatorProfitPercent;
        }
        creatorProfitPercent = newCreatorProfitPercent;

        emit CreatorLaunchesReturned(amount, profitPercentEquivalent, creatorProfitPercent);
    }

    /// @notice Set voting contract address
    /// @param _votingContract Voting contract address
    function setVotingContract(address _votingContract) external onlyAdmin {
        require(_votingContract != address(0), InvalidAddress());
        require(votingContract == address(0), VotingContractAlreadySet());

        votingContract = _votingContract;

        emit VotingContractSet(_votingContract);
    }

    /// @notice Set admin address (only callable by voting)
    /// @param newAdmin New admin address
    function setAdmin(address newAdmin) external onlyVoting {
        require(newAdmin != address(0), InvalidAddress());

        address oldAdmin = admin;
        admin = newAdmin;

        emit AdminSet(oldAdmin, newAdmin);
    }

    /// @notice Set flag indicating DAO does not want to extend lock in POC contract (only callable by voting)
    /// @param value New value for the flag
    function setDoNotExtendPOCLock(bool value) external onlyVoting {
        bool oldValue = doNotExtendPOCLock;
        doNotExtendPOCLock = value;

        emit DoNotExtendPOCLockSet(oldValue, value);
    }

    /// @notice Distribute unaccounted balance of a token as profit
    /// @dev Splits profit into: royalty (10%) -> creator (N%) -> DAO participants (90%-N%)
    /// @dev Token must be a sellable collateral (from POC contracts)
    /// @param token Token address to distribute
    function distributeProfit(address token) external nonReentrant {
        require(totalSharesSupply > 0, NoShares());
        require(rewardTokenInfo[token].active || isV2LPToken[token], TokenNotAdded());

        _distributeProfit(token);
    }

    /// @notice Internal function to distribute royalty share
    /// @param token Token address
    /// @param totalAmount Total amount to distribute
    /// @return royaltyShare Amount distributed as royalty
    function _distributeRoyaltyShare(address token, uint256 totalAmount) internal returns (uint256 royaltyShare) {
        royaltyShare = (totalAmount * royaltyPercent) / BASIS_POINTS;
        if (royaltyShare > 0 && royaltyRecipient != address(0)) {
            IERC20(token).safeTransfer(royaltyRecipient, royaltyShare);
            emit RoyaltyDistributed(token, royaltyRecipient, royaltyShare);
        }
    }

    /// @notice Internal function to distribute creator share
    /// @param token Token address
    /// @param amount Amount to calculate creator share from
    /// @return creatorShare Amount distributed to creator
    function _distributeCreatorShare(address token, uint256 amount) internal returns (uint256 creatorShare) {
        creatorShare = (amount * creatorProfitPercent) / BASIS_POINTS;
        if (creatorShare > 0) {
            IERC20(token).safeTransfer(creator, creatorShare);
            emit CreatorProfitDistributed(token, creator, creatorShare);
        }
    }

    /// @notice Internal function to distribute to participants (process exit queue and update rewards)
    /// @param token Token address
    /// @param participantsShare Amount available for participants
    /// @return remainingForParticipants Amount remaining after exit queue processing
    function _distributeToParticipants(address token, uint256 participantsShare)
        internal
        returns (uint256 remainingForParticipants)
    {
        uint256 usedForExits = 0;

        if (exitQueue.length > 0 && !_isExitQueueEmpty() && participantsShare > 0 && !isV2LPToken[token]) {
            uint256 balanceBefore = IERC20(token).balanceOf(address(this));
            _processExitQueue(participantsShare, token);
            uint256 balanceAfter = IERC20(token).balanceOf(address(this));
            usedForExits = balanceBefore - balanceAfter;
        }

        remainingForParticipants = participantsShare - usedForExits;

        if (remainingForParticipants > 0 && totalSharesSupply > 0) {
            require(
                (remainingForParticipants * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply > MIN_REWARD_PER_SHARE,
                RewardPerShareTooLow()
            );
            rewardPerShareStored[token] += (remainingForParticipants * PRICE_DECIMALS_MULTIPLIER) / totalSharesSupply;
        }
    }

    /// @notice Internal function to distribute unaccounted balance of a token as profit
    /// @param token Token address to distribute
    function _distributeProfit(address token) internal {
        uint256 unaccounted = IERC20(token).balanceOf(address(this)) - accountedBalance[token];
        if (unaccounted == 0) return; // No profit to distribute, skip silently

        uint256 royaltyShare = _distributeRoyaltyShare(token, unaccounted);
        uint256 creatorShare = _distributeCreatorShare(token, unaccounted);

        uint256 participantsShare = unaccounted - royaltyShare - creatorShare;
        uint256 remainingForParticipants = _distributeToParticipants(token, participantsShare);

        accountedBalance[token] += remainingForParticipants;

        emit ProfitDistributed(token, unaccounted);
    }

    /// @notice Distribute 1% of LP tokens as profit (monthly)
    /// @dev Can only be called once per LP_DISTRIBUTION_PERIOD per LP token
    /// @param lpTokenOrTokenId LP token address (V2) or token ID (V3)
    /// @param lpType Type of LP token (V2 or V3)
    function distributeLPProfit(address lpTokenOrTokenId, DataTypes.LPTokenType lpType)
        external
        nonReentrant
        atStage(DataTypes.Stage.Active)
    {
        require(totalSharesSupply > 0, NoShares());

        if (lpType == DataTypes.LPTokenType.V2) {
            address lpToken = lpTokenOrTokenId;
            require(isV2LPToken[lpToken], NotLPToken());
            require(block.timestamp >= lastLPDistribution[lpToken] + LP_DISTRIBUTION_PERIOD, LPDistributionTooSoon());

            uint256 lpBalance = accountedBalance[lpToken];
            require(lpBalance > 0, NoProfitToDistribute());

            uint256 toDistribute = (lpBalance * LP_DISTRIBUTION_PERCENT) / BASIS_POINTS;
            require(toDistribute > 0, NoProfitToDistribute());

            uint256 royaltyShare = _distributeRoyaltyShare(lpToken, toDistribute);

            uint256 creatorShare = _distributeCreatorShare(lpToken, toDistribute);

            uint256 participantsShare = toDistribute - royaltyShare - creatorShare;
            uint256 remainingForParticipants = _distributeToParticipants(lpToken, participantsShare);

            accountedBalance[lpToken] -= (toDistribute - remainingForParticipants);
            lastLPDistribution[lpToken] = block.timestamp;

            emit LPProfitDistributed(lpToken, toDistribute);
        } else if (lpType == DataTypes.LPTokenType.V3) {
            uint256 tokenId = uint256(uint160(lpTokenOrTokenId));
            require(v3TokenIdToIndex[tokenId] > 0, NotLPToken());
            require(block.timestamp >= v3LastLPDistribution[tokenId] + LP_DISTRIBUTION_PERIOD, LPDistributionTooSoon());

            DataTypes.V3LPPositionInfo memory positionInfo = _getV3PositionInfo(tokenId);
            INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

            (,,,,,,, uint128 liquidity,,,,) = positionManager.positions(tokenId);
            require(liquidity > 0, NoProfitToDistribute());

            uint128 liquidityToDecrease = uint128((uint256(liquidity) * LP_DISTRIBUTION_PERCENT) / BASIS_POINTS);
            require(liquidityToDecrease > 0, NoProfitToDistribute());

            (uint256 amount0, uint256 amount1) = _decreaseV3Liquidity(tokenId, liquidityToDecrease);

            (uint256 collected0, uint256 collected1) = _collectV3Tokens(tokenId);

            if (collected0 > 0) {
                _distributeProfit(positionInfo.token0);
            }
            if (collected1 > 0) {
                _distributeProfit(positionInfo.token1);
            }

            v3LastLPDistribution[tokenId] = block.timestamp;

            emit V3LiquidityDecreased(tokenId, liquidityToDecrease, collected0, collected1);
        } else {
            revert InvalidAddress();
        }
    }

    /// @notice Decrease liquidity for a V3 position
    /// @param tokenId NFT token ID of the position
    /// @param liquidity Amount of liquidity to decrease
    /// @return amount0 Amount of token0 accounted for the decrease
    /// @return amount1 Amount of token1 accounted for the decrease
    function _decreaseV3Liquidity(uint256 tokenId, uint128 liquidity)
        internal
        returns (uint256 amount0, uint256 amount1)
    {
        DataTypes.V3LPPositionInfo memory positionInfo = _getV3PositionInfo(tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        INonfungiblePositionManager.DecreaseLiquidityParams memory params =
            INonfungiblePositionManager.DecreaseLiquidityParams({
                tokenId: tokenId, liquidity: liquidity, amount0Min: 0, amount1Min: 0, deadline: block.timestamp
            });

        (amount0, amount1) = positionManager.decreaseLiquidity(params);
    }

    /// @notice Collect tokens from a V3 position
    /// @param tokenId NFT token ID of the position
    /// @return amount0 Amount of token0 collected
    /// @return amount1 Amount of token1 collected
    function _collectV3Tokens(uint256 tokenId) internal returns (uint256 amount0, uint256 amount1) {
        DataTypes.V3LPPositionInfo memory positionInfo = _getV3PositionInfo(tokenId);
        INonfungiblePositionManager positionManager = INonfungiblePositionManager(positionInfo.positionManager);

        INonfungiblePositionManager.CollectParams memory params = INonfungiblePositionManager.CollectParams({
            tokenId: tokenId, recipient: address(this), amount0Max: type(uint128).max, amount1Max: type(uint128).max
        });

        (amount0, amount1) = positionManager.collect(params);
    }

    /// @notice Get V3 position info from array
    /// @param tokenId NFT token ID of the position
    /// @return Position info struct
    function _getV3PositionInfo(uint256 tokenId) internal view returns (DataTypes.V3LPPositionInfo memory) {
        uint256 index = v3TokenIdToIndex[tokenId];
        require(index > 0, NotLPToken());
        return v3LPPositions[index - 1];
    }

    /// @notice Update voting shares for delegate when vault shares change
    /// @param vaultId Vault ID whose shares changed
    /// @param sharesDelta Change in shares (positive for increase, negative for decrease)
    function _updateDelegateVotingShares(uint256 vaultId, int256 sharesDelta) internal {
        DataTypes.Vault storage vault = vaults[vaultId];
        address delegate = vault.delegate;

        if (delegate == address(0) || delegate == vault.primary) {
            return;
        }

        uint256 delegateVaultId = addressToVaultId[delegate];
        if (delegateVaultId == 0 || delegateVaultId >= nextVaultId) {
            return;
        }

        DataTypes.Vault storage delegateVault = vaults[delegateVaultId];

        if (sharesDelta > 0) {
            delegateVault.votingShares += uint256(sharesDelta);
        } else if (sharesDelta < 0) {
            uint256 decreaseAmount = uint256(-sharesDelta);
            if (delegateVault.votingShares >= decreaseAmount) {
                delegateVault.votingShares -= decreaseAmount;
            } else {
                delegateVault.votingShares = 0;
            }
        }
    }

    /// @notice Update vault rewards snapshot for all tokens
    /// @param vaultId Vault ID to update
    function _updateVaultRewards(uint256 vaultId) internal {
        DataTypes.Vault memory vault = vaults[vaultId];
        if (vault.shares == 0) return;

        for (uint256 i = 0; i < rewardTokens.length; i++) {
            address rewardToken = rewardTokens[i];
            if (rewardTokenInfo[rewardToken].active) {
                uint256 pending = _calculatePendingRewards(vaultId, rewardToken);

                if (pending > 0) {
                    earnedRewards[vaultId][rewardToken] += pending;
                }

                vaultRewardIndex[vaultId][rewardToken] = rewardPerShareStored[rewardToken];
            }
        }

        for (uint256 i = 0; i < v2LPTokens.length; i++) {
            address lpToken = v2LPTokens[i];
            uint256 pending = _calculatePendingRewards(vaultId, lpToken);

            if (pending > 0) {
                earnedRewards[vaultId][lpToken] += pending;
            }

            vaultRewardIndex[vaultId][lpToken] = rewardPerShareStored[lpToken];
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
            entry.weightedAvgLaunchPrice = newLaunchPrice;
            entry.weightedAvgSharePrice = fundraisingConfig.sharePrice;
            return;
        }

        uint256 totalShares = vault.shares + newShares;
        entry.weightedAvgLaunchPrice =
            (entry.weightedAvgLaunchPrice * vault.shares + newLaunchPrice * newShares) / totalShares;

        entry.weightedAvgSharePrice =
            (entry.weightedAvgSharePrice * vault.shares + fundraisingConfig.sharePrice * newShares) / totalShares;
    }

    /// @notice Get weighted average launch token price from all active POC contracts
    /// @return Weighted average launch price in USD (18 decimals)
    function _getLaunchPriceFromPOC() internal view returns (uint256) {
        uint256 totalWeightedPrice = 0;
        uint256 totalSharePercent = 0;

        for (uint256 i = 0; i < pocContracts.length; i++) {
            DataTypes.POCInfo storage poc = pocContracts[i];

            if (!poc.active) {
                continue;
            }

            uint256 launchPriceInCollateral = IProofOfCapital(poc.pocContract).currentPrice();

            if (launchPriceInCollateral == 0) {
                continue;
            }

            uint256 collateralPriceUSD = _getPOCCollateralPrice(i);

            if (collateralPriceUSD == 0) {
                continue;
            }

            uint256 launchPriceUSD = (launchPriceInCollateral * collateralPriceUSD) / PRICE_DECIMALS_MULTIPLIER;

            if (launchPriceUSD == 0) {
                continue;
            }

            totalWeightedPrice += (launchPriceUSD * poc.sharePercent);
            totalSharePercent += poc.sharePercent;
        }

        return totalWeightedPrice / totalSharePercent;
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

        if (block.timestamp < entry.entryTimestamp + EXIT_DISCOUNT_PERIOD) {
            shareValue = (shareValue * (BASIS_POINTS - EXIT_DISCOUNT_PERCENT)) / BASIS_POINTS;
        }

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
        return nextExitQueueIndex >= exitQueue.length;
    }

    /// @notice Process exit queue with available funds
    /// @param availableFunds Amount of funds available for buyback
    /// @param token Token used for buyback
    function _processExitQueue(uint256 availableFunds, address token) internal {
        if (availableFunds == 0 || _isExitQueueEmpty()) return;

        for (uint256 i = nextExitQueueIndex; i < exitQueue.length && availableFunds > 0; i++) {
            DataTypes.ExitRequest storage request = exitQueue[i];

            if (request.processed) {
                nextExitQueueIndex = i + 1;
                continue;
            }

            DataTypes.Vault storage vault = vaults[request.vaultId];
            uint256 shares = vault.shares;

            if (shares == 0) {
                nextExitQueueIndex = i + 1;
                continue;
            }

            uint256 exitValue = _calculateExitValue(request.vaultId, shares);

            if (availableFunds >= exitValue) {
                _executeExit(i, exitValue, token);
                availableFunds -= exitValue;
                nextExitQueueIndex = i + 1; // Update index after processing
            } else {
                uint256 partialShares = (availableFunds * shares) / exitValue;
                if (partialShares > 0) {
                    uint256 partialExitValue = _calculateExitValue(request.vaultId, partialShares);
                    if (partialExitValue > 0 && partialExitValue <= availableFunds) {
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

        DataTypes.Vault storage vault = vaults[vaultId];
        uint256 shares = vault.shares;

        vault.shares -= shares;
        uint256 previousTotalShares = totalSharesSupply;
        totalSharesSupply -= shares;

        request.processed = true;
        vaultExitRequestIndex[vaultId] = 0;

        IERC20(token).safeTransfer(vault.primary, exitValue);

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

    /// @notice Get price from Chainlink aggregator and normalize to 18 decimals
    /// @param priceFeed Address of Chainlink price feed aggregator
    /// @return Price in USD (18 decimals)
    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IAggregatorV3 aggregator = IAggregatorV3(priceFeed);
        (, int256 price,,,) = aggregator.latestRoundData();
        require(price > 0, InvalidPrice());

        uint8 decimals = aggregator.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    /// @notice Get oracle price for a collateral token
    /// @param token Collateral token address
    /// @return Price in USD (18 decimals)
    function _getOraclePrice(address token) internal view returns (uint256) {
        DataTypes.CollateralInfo storage info = sellableCollaterals[token];
        require(info.active, CollateralNotActive());
        return _getChainlinkPrice(info.priceFeed);
    }

    /// @notice Get POC collateral price from its oracle
    /// @param pocIdx POC index
    /// @return Price in USD (18 decimals)
    function _getPOCCollateralPrice(uint256 pocIdx) internal view returns (uint256) {
        DataTypes.POCInfo storage poc = pocContracts[pocIdx];
        return _getChainlinkPrice(poc.priceFeed);
    }

    /// @notice Calculate price deviation in basis points
    /// @dev Only checks deviation when actual < expected (unfavorable rate)
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @return Deviation in basis points (0 if actual >= expected)
    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return BASIS_POINTS;
        if (actual >= expected) {
            return 0;
        } else {
            return ((expected - actual) * BASIS_POINTS) / expected;
        }
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, Unauthorized());
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

    /// @notice Claim creator's share of launch tokens during dissolution
    /// @dev Calculates and transfers creator's infrastructure share based on creatorInfraPercent
    /// @dev Only launch tokens can be claimed, other tokens are not available in this function
    function claimCreatorDissolution() external onlyCreator nonReentrant atStage(DataTypes.Stage.Dissolved) {
        uint256 launchBalance = launchToken.balanceOf(address(this));
        uint256 creatorLaunchShare = (launchBalance * creatorInfraPercent) / BASIS_POINTS;
        require(creatorLaunchShare > 0, NoRewardsToClaim());
        launchToken.safeTransfer(creator, creatorLaunchShare);
        accountedBalance[address(launchToken)] -= creatorLaunchShare;
        emit CreatorDissolutionClaimed(creator, creatorLaunchShare);
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
        pendingUpgradeFromVotingTimestamp = block.timestamp;
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
        require(block.timestamp >= pendingUpgradeFromVotingTimestamp + UPGRADE_DELAY, UpgradeDelayNotPassed());
        require(_isExitQueueEmpty(), ExitQueueNotEmpty());

        pendingUpgradeFromVoting = address(0);
        pendingUpgradeFromCreator = address(0);
        pendingUpgradeFromVotingTimestamp = 0;
    }
}

