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

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/Initializable.sol";
import "@openzeppelin/contracts-upgradeable/proxy/utils/UUPSUpgradeable.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IVoting.sol";
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IProofOfCapital.sol";
import "./interfaces/INonfungiblePositionManager.sol";
import "./interfaces/IUniswapV2Pair.sol";
import "./interfaces/IMultisig.sol";
import "./utils/Orderbook.sol";
import "./utils/DataTypes.sol";
import "./utils/Constants.sol";
import "./utils/VaultLibrary.sol";
import "./utils/RewardsLibrary.sol";
import "./utils/ExitQueueLibrary.sol";
import "./utils/LPTokenLibrary.sol";
import "./utils/ProfitDistributionLibrary.sol";
import "./utils/OracleLibrary.sol";
import "./utils/POCLibrary.sol";
import "./utils/FundraisingLibrary.sol";
import "./utils/DissolutionLibrary.sol";
import "./utils/CreatorLibrary.sol";

/// @title DAO Contract
/// @notice Main DAO contract managing vaults, shares, orderbook and collateral trading
contract DAO is IDAO, Initializable, UUPSUpgradeable, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public admin;
    address public votingContract;
    IERC20 public launchToken;
    address public mainCollateral;

    address public creator;
    uint256 public creatorInfraPercent;

    DataTypes.FundraisingConfig public fundraisingConfig;
    mapping(uint256 => DataTypes.ParticipantEntry) public participantEntries;

    DataTypes.POCInfo[] public pocContracts;
    mapping(address => uint256) public pocIndex;
    mapping(address => bool) public isPocContract;

    DataTypes.OrderbookParams public orderbookParams;

    DataTypes.VaultStorage private vaultStorage;
    DataTypes.RewardsStorage private rewardsStorage;
    DataTypes.ExitQueueStorage private exitQueueStorage;
    DataTypes.LPTokenStorage private lpTokenStorage;
    DataTypes.DAOState private daoState;

    mapping(address => DataTypes.CollateralInfo) public sellableCollaterals;

    mapping(address => bool) public availableRouterByAdmin;

    mapping(address => uint256) public accountedBalance;

    mapping(address => bool) public allowedExitTokens;

    DataTypes.LPTokenType public primaryLPTokenType;

    uint256 public activeStageTimestamp;
    uint256 public waitingForLPStartedAt;

    address public pendingUpgradeFromVoting;
    uint256 public pendingUpgradeFromVotingTimestamp;
    address public pendingUpgradeFromCreator;

    bool public isVetoToCreator;

    DataTypes.PricePathsStorage private pricePathsStorage;

    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyViaGovernanceExecution() {
        _onlyViaGovernanceExecution();
        _;
    }

    modifier atStage(DataTypes.Stage stage) {
        _atStage(stage);
        _;
    }

    modifier atActiveOrClosingStage() {
        _atActiveOrClosingStage();
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
    function initialize(DataTypes.ConstructorParams memory params) external initializer {
        require(params.launchToken != address(0), InvalidLaunchToken());
        require(params.mainCollateral != address(0), InvalidAddress());
        require(params.creator != address(0), InvalidAddress());
        require(params.creatorProfitPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.creatorInfraPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.royaltyPercent <= Constants.BASIS_POINTS, InvalidPercentage());
        require(params.sharePrice > 0, InvalidSharePrice());
        require(params.targetAmountMainCollateral > 0, InvalidTargetAmount());
        require(params.orderbookParams.initialPrice > 0, InvalidInitialPrice());
        require(params.orderbookParams.initialVolume > 0, InvalidVolume());
        require(params.orderbookParams.totalSupply > 0, InvalidVolume());

        launchToken = IERC20(params.launchToken);
        mainCollateral = params.mainCollateral;
        admin = msg.sender;
        creator = params.creator;
        creatorInfraPercent = params.creatorInfraPercent;
        daoState.currentStage = DataTypes.Stage.Fundraising;
        daoState.creator = params.creator;
        daoState.creatorProfitPercent = params.creatorProfitPercent;
        daoState.royaltyRecipient = params.royaltyRecipient;
        daoState.royaltyPercent = params.royaltyPercent;
        daoState.totalCollectedMainCollateral = 0;
        daoState.lastCreatorAllocation = 0;
        daoState.totalDepositedUSD = 0;

        vaultStorage.nextVaultId = 1;
        vaultStorage.totalSharesSupply = 0;

        if (params.v3LPPositions.length > 0) {
            lpTokenStorage.v3PositionManager = params.v3LPPositions[0].positionManager;
            require(lpTokenStorage.v3PositionManager != address(0), InvalidV3PositionManager());
            for (uint256 i = 0; i < params.v3LPPositions.length; ++i) {
                require(
                    params.v3LPPositions[i].positionManager == lpTokenStorage.v3PositionManager,
                    V3PositionManagerMismatch()
                );
            }
        }

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

        for (uint256 i = 0; i < params.routers.length; ++i) {
            address router = params.routers[i];
            require(router != address(0), InvalidAddress());
            require(!availableRouterByAdmin[router], RouterAlreadyAdded());

            availableRouterByAdmin[router] = true;

            emit RouterAvailabilityChanged(router, true);
        }

        for (uint256 i = 0; i < params.allowedExitTokens.length; ++i) {
            address token = params.allowedExitTokens[i];
            require(token != address(0), InvalidAddress());
            allowedExitTokens[token] = true;
        }

        FundraisingLibrary.executeInitializePOCContracts(
            pocContracts, pocIndex, isPocContract, rewardsStorage, sellableCollaterals, params.pocParams
        );

        FundraisingLibrary.executeInitializeRewardTokens(rewardsStorage, params.rewardTokenParams, address(launchToken));

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

        OracleLibrary.initializePricePaths(pricePathsStorage, params.launchTokenPricePaths);

        require(params.votingContract != address(0), InvalidAddress());
        votingContract = params.votingContract;
        emit VotingContractSet(params.votingContract);

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
        require(
            daoState.currentStage == DataTypes.Stage.Fundraising || daoState.currentStage == DataTypes.Stage.Active
                || daoState.currentStage == DataTypes.Stage.Closing,
            InvalidStage()
        );

        vaultId =
            VaultLibrary.executeCreateVault(vaultStorage, rewardsStorage, lpTokenStorage, backup, emergency, delegate);
    }

    /// @notice Deposit mainCollateral during fundraising stage
    /// @param amount Amount of mainCollateral to deposit (18 decimals)
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    function depositFundraising(uint256 amount, uint256 vaultId) external nonReentrant fundraisingActive {
        FundraisingLibrary.executeDepositFundraising(
            vaultStorage,
            daoState,
            fundraisingConfig,
            participantEntries,
            mainCollateral,
            amount,
            vaultId,
            this.getOraclePrice
        );
    }

    /// @notice Deposit launch tokens during active stage to receive shares
    /// @dev New participants can enter by depositing launches; price is fixed at entry
    /// @param launchAmount Amount of launch tokens to deposit
    /// @param vaultId Vault ID to deposit to (0 = use sender's vault)
    function depositLaunches(uint256 launchAmount, uint256 vaultId) external nonReentrant atActiveOrClosingStage {
        FundraisingLibrary.executeDepositLaunches(
            vaultStorage,
            daoState,
            rewardsStorage,
            lpTokenStorage,
            fundraisingConfig,
            participantEntries,
            accountedBalance,
            address(launchToken),
            launchAmount,
            vaultId,
            this.getOraclePrice
        );
    }

    /// @notice Update primary address
    /// @notice Emergency can change primary, backup can change primary, primary can change itself
    /// @param vaultId Vault ID to update
    /// @param newPrimary New primary address
    function updatePrimaryAddress(uint256 vaultId, address newPrimary) external vaultExists(vaultId) {
        VaultLibrary.executeUpdatePrimaryAddress(vaultStorage, vaultId, newPrimary);
    }

    /// @notice Update backup address
    /// @notice Emergency can change backup, backup can change itself
    /// @param vaultId Vault ID to update
    /// @param newBackup New backup address
    function updateBackupAddress(uint256 vaultId, address newBackup) external vaultExists(vaultId) {
        VaultLibrary.executeUpdateBackupAddress(vaultStorage, vaultId, newBackup);
    }

    /// @notice Update emergency address
    /// @notice Emergency can change itself
    /// @param vaultId Vault ID to update
    /// @param newEmergency New emergency address
    function updateEmergencyAddress(uint256 vaultId, address newEmergency) external vaultExists(vaultId) {
        VaultLibrary.executeUpdateEmergencyAddress(vaultStorage, vaultId, newEmergency);
    }

    /// @notice Set delegate address for voting (only callable by voting contract)
    /// @param userAddress User address to find vault and set delegate
    /// @param delegate New delegate address (if zero, primary is set as delegate)
    function setDelegate(address userAddress, address delegate) external {
        require(msg.sender == address(votingContract), OnlyVotingContract());
        require(votingContract != address(0), InvalidAddress());
        VaultLibrary.executeSetDelegate(vaultStorage, userAddress, delegate, votingContract);
    }

    /// @notice Set deposit limit for a vault (in shares)
    /// @param vaultId Vault ID to set limit for
    /// @param limit Deposit limit in shares (0 = deposits forbidden)
    function setVaultDepositLimit(uint256 vaultId, uint256 limit) external onlyBoardMemberOrAdmin vaultExists(vaultId) {
        DataTypes.Vault storage vault = vaultStorage.vaults[vaultId];
        require(limit >= vault.shares, DepositLimitBelowCurrentShares());
        vault.depositLimit = limit;
        emit VaultDepositLimitSet(vaultId, limit);
    }

    /// @notice Set allowed exit token for caller's vault
    /// @param token Token address to set
    /// @param allowed Whether the token is allowed for exit payments
    function setVaultAllowedExitToken(address token, bool allowed) external {
        VaultLibrary.executeSetVaultAllowedExitToken(vaultStorage, token, allowed);
    }

    /// @notice Claim accumulated rewards for tokens
    /// @param tokens Array of token addresses to claim
    function claimReward(address[] calldata tokens) external nonReentrant {
        RewardsLibrary.executeClaimReward(vaultStorage, rewardsStorage, lpTokenStorage, accountedBalance, tokens);
    }

    /// @notice Request to exit DAO by selling all shares
    /// @dev Participant exits with all their shares; adds request to exit queue for processing
    function requestExit() external nonReentrant atActiveOrClosingStage {
        ExitQueueLibrary.executeRequestExit(
            vaultStorage, exitQueueStorage, daoState, address(launchToken), this.getOraclePrice, votingContract
        );
    }

    /// @notice Cancel exit request from queue
    /// @dev Participant can cancel their exit request before it's processed
    function cancelExit() external nonReentrant atActiveOrClosingStage {
        ExitQueueLibrary.executeCancelExit(vaultStorage, exitQueueStorage, daoState);
    }

    /// @notice Enter closing stage if exit queue shares >= dynamic threshold
    /// @dev Can be called by any participant or admin when in Active stage
    function enterClosingStage() external onlyParticipantOrAdmin {
        require(daoState.currentStage == DataTypes.Stage.Active, InvalidStage());
        require(vaultStorage.totalSharesSupply > 0, NoShares());

        uint256 exitQueuePercentage =
            (daoState.totalExitQueueShares * Constants.BASIS_POINTS) / vaultStorage.totalSharesSupply;
        uint256 closingThreshold = _getClosingThreshold();
        require(exitQueuePercentage >= closingThreshold, InvalidStage());

        daoState.currentStage = DataTypes.Stage.Closing;
        emit StageChanged(DataTypes.Stage.Active, DataTypes.Stage.Closing);
    }

    /// @notice Return to active stage if exit queue shares < dynamic threshold
    /// @dev Can be called by any participant or admin when in Closing stage
    function returnToActiveStage() external onlyParticipantOrAdmin {
        require(daoState.currentStage == DataTypes.Stage.Closing, InvalidStage());
        require(vaultStorage.totalSharesSupply > 0, NoShares());

        uint256 exitQueuePercentage =
            (daoState.totalExitQueueShares * Constants.BASIS_POINTS) / vaultStorage.totalSharesSupply;
        uint256 closingThreshold = _getClosingThreshold();
        require(exitQueuePercentage < closingThreshold, InvalidStage());

        daoState.currentStage = DataTypes.Stage.Active;
        emit StageChanged(DataTypes.Stage.Closing, DataTypes.Stage.Active);
    }

    /// @notice Allocate launch tokens to creator, reducing their profit share proportionally
    /// @dev Can only be done once per ALLOCATION_PERIOD; max MAX_CREATOR_ALLOCATION_PERCENT per period
    /// @param launchAmount Amount of launch tokens to allocate
    function allocateLaunchesToCreator(uint256 launchAmount)
        external
        onlyViaGovernanceExecution
        atStage(DataTypes.Stage.Active)
    {
        CreatorLibrary.executeAllocateLaunchesToCreator(
            daoState,
            fundraisingConfig,
            accountedBalance,
            address(launchToken),
            creator,
            vaultStorage.totalSharesSupply,
            launchAmount
        );
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
    ) external nonReentrant atActiveOrClosingStage onlyParticipantOrAdmin {
        require(launchTokenAmount > 0, AmountMustBeGreaterThanZero());

        Orderbook.executeSell(
            DataTypes.SellParams({
                collateral: collateral,
                launchTokenAmount: launchTokenAmount,
                minCollateralAmount: minCollateralAmount,
                router: router,
                swapType: swapType,
                swapData: swapData
            }),
            launchToken,
            orderbookParams,
            sellableCollaterals,
            accountedBalance,
            availableRouterByAdmin,
            vaultStorage.totalSharesSupply,
            fundraisingConfig.sharePrice
        );
    }

    /// @notice Get total launch tokens sold
    /// @return Total amount of launch tokens sold
    function totalLaunchTokensSold() external view returns (uint256) {
        return orderbookParams.totalSold;
    }

    /// @notice Get total collected main collateral
    /// @return Total amount of main collateral collected
    function totalCollectedMainCollateral() external view returns (uint256) {
        return daoState.totalCollectedMainCollateral;
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
        onlyViaGovernanceExecution
        atStage(DataTypes.Stage.Active)
    {
        POCLibrary.executeAddPOCContract(
            pocContracts,
            pocIndex,
            isPocContract,
            sellableCollaterals,
            pocContract,
            collateralToken,
            priceFeed,
            sharePercent
        );
    }

    /// @notice Remove an inactive POC contract from the list
    /// @param pocContract POC contract address to remove
    function removePOCContract(address pocContract) external onlyParticipantOrAdmin {
        POCLibrary.executeRemovePOCContract(pocContracts, pocIndex, isPocContract, pocContract);
    }

    /// @notice Withdraw funds if fundraising was cancelled
    function withdrawFundraising() external nonReentrant atStage(DataTypes.Stage.FundraisingCancelled) {
        FundraisingLibrary.executeWithdrawFundraising(
            vaultStorage, daoState, participantEntries, mainCollateral, vaultStorage.totalSharesSupply
        );
    }

    /// @notice Extend fundraising deadline (only once)
    function extendFundraising() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        FundraisingLibrary.executeExtendFundraising(fundraisingConfig);
    }

    /// @notice Cancel fundraising
    /// @dev In Fundraising stage: admin or participant can cancel if target not reached after deadline
    function cancelFundraising() external onlyParticipantOrAdmin {
        FundraisingLibrary.executeCancelFundraising(daoState, fundraisingConfig);
    }

    /// @notice Finalize fundraising collection and move to exchange stage
    function finalizeFundraisingCollection() external onlyAdmin atStage(DataTypes.Stage.Fundraising) {
        FundraisingLibrary.executeFinalizeFundraisingCollection(
            daoState, fundraisingConfig, vaultStorage.totalSharesSupply
        );
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
        POCLibrary.executeExchangeForPOC(
            daoState,
            pocContracts,
            accountedBalance,
            availableRouterByAdmin,
            sellableCollaterals,
            mainCollateral,
            address(launchToken),
            daoState.totalCollectedMainCollateral,
            pocIdx,
            amount,
            router,
            swapType,
            swapData
        );
    }

    /// @notice Finalize exchange process and calculate share price in launches
    function finalizeExchange() external onlyAdmin atStage(DataTypes.Stage.FundraisingExchange) {
        FundraisingLibrary.executeFinalizeExchange(
            pocContracts,
            daoState,
            fundraisingConfig,
            accountedBalance,
            address(launchToken),
            creator,
            creatorInfraPercent,
            vaultStorage.totalSharesSupply
        );

        if (daoState.currentStage == DataTypes.Stage.WaitingForLP) {
            waitingForLPStartedAt = block.timestamp;
        }
    }

    /// @notice Creator provides LP tokens and moves DAO to active stage
    /// @param v2LPTokenAddresses Array of V2 LP token addresses
    /// @param v2LPAmounts Array of V2 LP token amounts to deposit
    /// @param v3TokenIds Array of V3 LP position token IDs
    /// @param newV2PricePaths Array of new V2 price paths to add
    /// @param newV3PricePaths Array of new V3 price paths to add
    function provideLPTokens(
        address[] calldata v2LPTokenAddresses,
        uint256[] calldata v2LPAmounts,
        uint256[] calldata v3TokenIds,
        DataTypes.PricePathV2Params[] calldata newV2PricePaths,
        DataTypes.PricePathV3Params[] calldata newV3PricePaths
    ) external nonReentrant onlyCreator atStage(DataTypes.Stage.WaitingForLP) {
        activeStageTimestamp = LPTokenLibrary.executeProvideLPTokens(
            lpTokenStorage,
            rewardsStorage,
            daoState,
            pricePathsStorage,
            accountedBalance,
            v2LPTokenAddresses,
            v2LPAmounts,
            v3TokenIds,
            newV2PricePaths,
            newV3PricePaths,
            primaryLPTokenType
        );
    }

    /// @notice Dissolve DAO if all POC contract locks have ended (callable by any participant or admin without voting)
    /// @dev Checks all active POC contracts to see if their lock periods have ended
    /// @dev If all locks are ended, transitions DAO to WaitingForLPDissolution if LP tokens exist, otherwise to Dissolved
    function dissolveIfLocksEnded() external {
        require(
            daoState.currentStage == DataTypes.Stage.Active || daoState.currentStage == DataTypes.Stage.Closing,
            InvalidStage()
        );
        DissolutionLibrary.executeDissolveIfLocksEnded(daoState, pocContracts, lpTokenStorage, accountedBalance);
    }

    /// @notice Dissolve DAO from FundraisingExchange or WaitingForLP stages if all POC contract locks have ended
    /// @dev Checks all active POC contracts to see if their lock periods have ended
    /// @dev Withdraws all launch tokens and collateral tokens from POC contracts and transitions to Dissolved
    function dissolveFromFundraisingStages() external nonReentrant onlyParticipantOrAdmin {
        require(
            daoState.currentStage == DataTypes.Stage.FundraisingExchange
                || daoState.currentStage == DataTypes.Stage.WaitingForLP,
            InvalidStage()
        );
        DissolutionLibrary.executeDissolveFromFundraisingStages(daoState, pocContracts);
    }

    /// @notice Execute proposal call through DAO (only callable by voting)
    /// @dev Executes a call to targetContract with callData on behalf of DAO
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    function executeProposal(address targetContract, bytes calldata callData) external {
        require(msg.sender == address(votingContract), OnlyVotingContract());
        require(targetContract != address(0), InvalidAddress());
        Address.functionCall(targetContract, callData);
    }

    /// @notice Dissolve all LP tokens (V2 and V3) and transition to Dissolved stage
    /// @dev Can be called by any participant or admin when in WaitingForLPDissolution stage
    /// @dev Dissolves all V2 LP tokens and V3 LP positions, then transitions to Dissolved
    function dissolveLPTokens()
        external
        nonReentrant
        onlyParticipantOrAdmin
        atStage(DataTypes.Stage.WaitingForLPDissolution)
    {
        DissolutionLibrary.executeDissolveLPTokens(
            daoState, lpTokenStorage, rewardsStorage, accountedBalance, address(launchToken)
        );
    }

    /// @notice Claim share of assets after dissolution
    /// @dev Creator gets additional launch tokens based on creatorInfraPercent
    /// @param tokens Array of token addresses to claim (can include launch token, reward tokens, LP tokens, or sellable collaterals)
    function claimDissolution(address[] calldata tokens) external nonReentrant atStage(DataTypes.Stage.Dissolved) {
        DissolutionLibrary.executeClaimDissolution(
            vaultStorage, daoState, rewardsStorage, accountedBalance, address(launchToken), tokens
        );
    }

    /// @notice Return launch tokens from POC contract, restoring creator's profit share
    /// @dev POC contract returns launch tokens that were allocated to creator
    /// @param amount Amount of launch tokens to return
    function upgradeOwnerShare(uint256 amount) external {
        POCLibrary.executeUpgradeOwnerShare(
            isPocContract, daoState, fundraisingConfig.sharePrice, vaultStorage.totalSharesSupply, amount
        );
    }

    /// @notice Set voting contract address
    /// @notice Only the current voting contract can replace itself through voting
    /// @param _votingContract Voting contract address
    function setVotingContract(address _votingContract) external onlyViaGovernanceExecution {
        require(_votingContract != address(0), InvalidAddress());
        require(votingContract != address(0), InvalidAddress());

        votingContract = _votingContract;

        emit VotingContractSet(_votingContract);
    }

    /// @notice Set admin address (callable by voting or current admin)
    /// @param newAdmin New admin address
    function setAdmin(address newAdmin) external {
        require(newAdmin != address(0), InvalidAddress());
        require(msg.sender == address(this) || msg.sender == admin, Unauthorized());
        require(votingContract != address(0) || msg.sender == admin, InvalidAddress());

        address oldAdmin = admin;
        admin = newAdmin;

        emit AdminSet(oldAdmin, newAdmin);
    }

    /// @notice Set flag indicating creator has veto power (only callable by voting)
    /// @param value New value for the flag
    function setIsVetoToCreator(bool value) external onlyViaGovernanceExecution {
        bool oldValue = isVetoToCreator;
        isVetoToCreator = value;

        emit IsVetoToCreatorSet(oldValue, value);
    }

    /// @notice Set royalty recipient address (callable by current royalty recipient)
    /// @param newRoyaltyRecipient New royalty recipient address
    function setRoyaltyRecipient(address newRoyaltyRecipient) external {
        require(newRoyaltyRecipient != address(0), InvalidAddress());
        require(msg.sender == daoState.royaltyRecipient, Unauthorized());
        require(votingContract != address(0) || msg.sender == daoState.royaltyRecipient, InvalidAddress());

        address oldRoyaltyRecipient = daoState.royaltyRecipient;
        daoState.royaltyRecipient = newRoyaltyRecipient;

        emit RoyaltyRecipientSet(oldRoyaltyRecipient, newRoyaltyRecipient);
    }

    /// @notice Set pending upgrade address (only voting contract can call)
    /// @param newImplementation Address of the new implementation to approve (address(0) to cancel)
    function setPendingUpgradeFromVoting(address newImplementation) external onlyViaGovernanceExecution {
        pendingUpgradeFromVoting = newImplementation;
        pendingUpgradeFromVotingTimestamp = block.timestamp;
        emit PendingUpgradeSetFromVoting(newImplementation);
    }

    /// @notice Set pending upgrade address (only creator can call)
    /// @param newImplementation Address of the new implementation to approve (address(0) to cancel)
    function setPendingUpgradeFromCreator(address newImplementation) external onlyCreator {
        pendingUpgradeFromCreator = newImplementation;
        emit PendingUpgradeSetFromCreator(newImplementation);
    }

    /// @notice Push multisig to execute a proposal
    /// @dev Any participant or admin can trigger multisig execution
    /// @param proposalId Proposal ID to execute on multisig
    /// @param calls Array of calls to execute
    function pushMultisigExecution(uint256 proposalId, IMultisig.ProposalCall[] calldata calls)
        external
        onlyParticipantOrAdmin
    {
        require(creator != address(0), InvalidAddress());

        IMultisig(creator).executeTransaction(proposalId, calls);

        emit MultisigExecutionPushed(proposalId, msg.sender);
    }

    /// @notice Claim creator's share of launch tokens during dissolution
    /// @dev Calculates and transfers creator's infrastructure share based on creatorInfraPercent
    /// @dev Only launch tokens can be claimed, other tokens are not available in this function
    function claimCreatorDissolution() external onlyCreator nonReentrant atStage(DataTypes.Stage.Dissolved) {
        DissolutionLibrary.executeClaimCreatorDissolution(
            accountedBalance, address(launchToken), creatorInfraPercent, creator
        );
    }

    /// @notice Distribute unaccounted balance of a token as profit
    /// @dev Splits profit into: royalty (10%) -> creator (N%) -> DAO participants (90%-N%)
    /// @dev Token must be a sellable collateral (from POC contracts)
    /// @param token Token address to distribute
    /// @param amount Amount to distribute (0 means distribute all unaccounted)
    function distributeProfit(address token, uint256 amount) external nonReentrant {
        ProfitDistributionLibrary.executeDistributeProfit(
            daoState,
            rewardsStorage,
            exitQueueStorage,
            lpTokenStorage,
            vaultStorage,
            participantEntries,
            fundraisingConfig,
            accountedBalance,
            vaultStorage.totalSharesSupply,
            token,
            address(launchToken),
            this.getOraclePrice,
            allowedExitTokens,
            vaultStorage.vaultAllowedExitTokens,
            amount
        );
    }

    /// @notice Distribute 1% of LP tokens as profit (monthly)
    /// @dev Can only be called once per LP_DISTRIBUTION_PERIOD per LP token
    /// @param lpTokenOrTokenId LP token address (V2) or token ID (V3)
    /// @param lpType Type of LP token (V2 or V3)
    function distributeLPProfit(address lpTokenOrTokenId, DataTypes.LPTokenType lpType)
        external
        nonReentrant
        atActiveOrClosingStage
    {
        LPTokenLibrary.executeDistributeLPProfit(
            lpTokenStorage, accountedBalance, vaultStorage.totalSharesSupply, lpTokenOrTokenId, lpType
        );
    }

    /// @notice Get oracle price for any token (external wrapper for library calls)
    /// @dev For launch token returns weighted average from POC contracts with pool validation, for collaterals returns Chainlink price
    /// @param token Token address
    /// @return Price in USD (18 decimals)
    function getOraclePrice(address token) external returns (uint256) {
        return OracleLibrary.getPrice(sellableCollaterals, pocContracts, pricePathsStorage, address(launchToken), token);
    }

    /// @notice Get POC collateral price from its oracle (external wrapper for library calls)
    /// @param pocIdx POC index
    /// @return Price in USD (18 decimals)
    function getPOCCollateralPrice(uint256 pocIdx) external view returns (uint256) {
        return POCLibrary.getPOCCollateralPrice(pocContracts, pocIdx);
    }

    /// @notice Get DAO profit share percentage
    /// @return DAO profit share in basis points (10000 = 100%)
    function getDAOProfitShare() external view returns (uint256) {
        uint256 daoShare = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;
        if (daoShare < Constants.MIN_DAO_PROFIT_SHARE) {
            return Constants.MIN_DAO_PROFIT_SHARE;
        }
        return daoShare;
    }

    /// @notice Get dynamic veto threshold based on DAO profit share
    /// @return Veto threshold in basis points (10000 = 100%)
    function getVetoThreshold() external view returns (uint256) {
        uint256 daoShare = this.getDAOProfitShare();
        return Constants.BASIS_POINTS - daoShare;
    }

    /// @notice Get dynamic closing threshold based on DAO profit share
    /// @return Closing threshold in basis points (10000 = 100%), not less than CLOSING_EXIT_QUEUE_MIN_THRESHOLD
    function getClosingThreshold() external view returns (uint256) {
        return _getClosingThreshold();
    }

    /// @notice Check if an account is a board member (has >= 10 shares)
    /// @param account Address to check
    /// @return True if account is a board member
    function isBoardMember(address account) external view returns (bool) {
        uint256 vaultId = vaultStorage.addressToVaultId[account];
        return vaultId > 0 && vaultStorage.vaults[vaultId].votingShares >= Constants.BOARD_MEMBER_MIN_SHARES;
    }

    /// @notice Check if a vault is in exit queue
    /// @param vaultId Vault ID to check
    /// @return True if vault is in exit queue
    function isVaultInExitQueue(uint256 vaultId) external view returns (bool) {
        return exitQueueStorage.vaultExitRequestIndex[vaultId] > 0;
    }

    /// @notice Getter for vaults (backward compatibility)
    function vaults(uint256 vaultId) external view returns (DataTypes.Vault memory) {
        return vaultStorage.vaults[vaultId];
    }

    /// @notice Getter for addressToVaultId (backward compatibility)
    function addressToVaultId(address addr) external view returns (uint256) {
        return vaultStorage.addressToVaultId[addr];
    }

    /// @notice Getter for nextVaultId (backward compatibility)
    function nextVaultId() external view returns (uint256) {
        return vaultStorage.nextVaultId;
    }

    /// @notice Getter for totalSharesSupply (backward compatibility)
    function totalSharesSupply() external view returns (uint256) {
        return vaultStorage.totalSharesSupply;
    }

    /// @notice Getter for DAO state
    function getDaoState() external view returns (DataTypes.DAOState memory) {
        return daoState;
    }

    /// @notice Getter for rewardTokens (backward compatibility)
    function rewardTokens(uint256 index) external view returns (address) {
        return rewardsStorage.rewardTokens[index];
    }

    /// @notice Getter for rewardTokenInfo (backward compatibility)
    function rewardTokenInfo(address token) external view returns (DataTypes.RewardTokenInfo memory) {
        return rewardsStorage.rewardTokenInfo[token];
    }

    /// @notice Getter for v2LPTokens (backward compatibility)
    function v2LPTokens(uint256 index) external view returns (address) {
        return lpTokenStorage.v2LPTokens[index];
    }

    /// @notice Getter for isV2LPToken (backward compatibility)
    function isV2LPToken(address token) external view returns (bool) {
        return lpTokenStorage.isV2LPToken[token];
    }

    /// @notice Getter for v3LPPositions (backward compatibility)
    function v3LPPositions(uint256 index) external view returns (DataTypes.V3LPPositionInfo memory) {
        return lpTokenStorage.v3LPPositions[index];
    }

    /// @notice Getter for v3TokenIdToIndex (backward compatibility)
    function v3TokenIdToIndex(uint256 tokenId) external view returns (uint256) {
        return lpTokenStorage.v3TokenIdToIndex[tokenId];
    }

    /// @notice Getter for v3PositionManager (backward compatibility)
    function v3PositionManager() external view returns (address) {
        return lpTokenStorage.v3PositionManager;
    }

    /// @notice Getter for vaultMainCollateralDeposit (backward compatibility)
    function vaultMainCollateralDeposit(uint256 vaultId) external view returns (uint256) {
        return vaultStorage.vaults[vaultId].mainCollateralDeposit;
    }

    /// @notice Getter for rewardPerShareStored (backward compatibility)
    function rewardPerShareStored(address token) external view returns (uint256) {
        return rewardsStorage.rewardPerShareStored[token];
    }

    /// @notice Getter for vaultRewardIndex (backward compatibility)
    function vaultRewardIndex(uint256 vaultId, address token) external view returns (uint256) {
        return rewardsStorage.vaultRewardIndex[vaultId][token];
    }

    /// @notice Getter for earnedRewards (backward compatibility)
    function earnedRewards(uint256 vaultId, address token) external view returns (uint256) {
        return rewardsStorage.earnedRewards[vaultId][token];
    }

    /// @notice Getter for v3LastLPDistribution (backward compatibility)
    function v3LastLPDistribution(uint256 tokenId) external view returns (uint256) {
        return lpTokenStorage.v3LastLPDistribution[tokenId];
    }

    /// @notice Getter for v3LPTokenAddedAt (backward compatibility)
    function v3LPTokenAddedAt(uint256 tokenId) external view returns (uint256) {
        return lpTokenStorage.v3LPTokenAddedAt[tokenId];
    }

    /// @notice Getter for lastLPDistribution (backward compatibility)
    function lastLPDistribution(address lpToken) external view returns (uint256) {
        return lpTokenStorage.lastLPDistribution[lpToken];
    }

    /// @notice Getter for lpTokenAddedAt (backward compatibility)
    function lpTokenAddedAt(address lpToken) external view returns (uint256) {
        return lpTokenStorage.lpTokenAddedAt[lpToken];
    }

    /// @notice Getter for POC contracts count
    function getPOCContractsCount() external view returns (uint256) {
        return pocContracts.length;
    }

    /// @notice Getter for POC contract by index
    function getPOCContract(uint256 index) external view returns (DataTypes.POCInfo memory) {
        return pocContracts[index];
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, Unauthorized());
    }

    function _onlyViaGovernanceExecution() internal view {
        require(msg.sender == address(this), OnlyByDAOVoting());
    }

    function _atStage(DataTypes.Stage stage) internal view {
        require(daoState.currentStage == stage, InvalidStage());
    }

    function _atActiveOrClosingStage() internal view {
        require(
            daoState.currentStage == DataTypes.Stage.Active || daoState.currentStage == DataTypes.Stage.Closing,
            InvalidStage()
        );
    }

    function _vaultExists(uint256 vaultId) internal view {
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, VaultDoesNotExist());
    }

    function _onlyParticipantOrAdmin() internal view {
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        bool isParticipant =
            vaultId > 0 && vaultId < vaultStorage.nextVaultId && vaultStorage.vaults[vaultId].shares > 0;
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
        uint256 vaultId = vaultStorage.addressToVaultId[msg.sender];
        bool isMemberOfBoard = vaultId > 0 && vaultId < vaultStorage.nextVaultId
            && vaultStorage.vaults[vaultId].votingShares >= Constants.BOARD_MEMBER_MIN_SHARES;
        require(isMemberOfBoard || msg.sender == admin || msg.sender == votingContract, NotBoardMemberOrAdmin());
    }

    function _fundraisingActive() internal view {
        require(daoState.currentStage == DataTypes.Stage.Fundraising, InvalidStage());
        require(block.timestamp < fundraisingConfig.deadline, FundraisingDeadlinePassed());
    }

    /// @notice Internal function to calculate dynamic closing threshold
    /// @return Closing threshold in basis points (10000 = 100%), not less than CLOSING_EXIT_QUEUE_MIN_THRESHOLD
    function _getClosingThreshold() internal view returns (uint256) {
        uint256 daoShare = _getDAOProfitShare();
        uint256 vetoThreshold = Constants.BASIS_POINTS - daoShare;
        if (vetoThreshold < Constants.CLOSING_EXIT_QUEUE_MIN_THRESHOLD) {
            return Constants.CLOSING_EXIT_QUEUE_MIN_THRESHOLD;
        }
        return vetoThreshold;
    }

    /// @notice Internal function to calculate DAO profit share
    /// @return DAO profit share in basis points (10000 = 100%)
    function _getDAOProfitShare() internal view returns (uint256) {
        uint256 daoShare = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;
        if (daoShare < Constants.MIN_DAO_PROFIT_SHARE) {
            return Constants.MIN_DAO_PROFIT_SHARE;
        }
        return daoShare;
    }

    /// @notice Authorize upgrade (requires both voting and creator approval)
    /// @param newImplementation Address of the new implementation
    function _authorizeUpgrade(address newImplementation) internal override {
        require(newImplementation != address(0), InvalidAddress());
        require(
            pendingUpgradeFromVoting == newImplementation && pendingUpgradeFromCreator == newImplementation,
            UpgradeNotAuthorized()
        );
        require(block.timestamp >= pendingUpgradeFromVotingTimestamp + Constants.UPGRADE_DELAY, UpgradeDelayNotPassed());
        require(exitQueueStorage.nextExitQueueIndex >= exitQueueStorage.exitQueue.length, ExitQueueNotEmpty());

        pendingUpgradeFromVoting = address(0);
        pendingUpgradeFromCreator = address(0);
        pendingUpgradeFromVotingTimestamp = 0;
    }
}

