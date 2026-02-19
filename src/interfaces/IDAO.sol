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

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "../libraries/DataTypes.sol";
import "./IMultisig.sol";

/// @title IDAO Interface
/// @notice Interface for the DAO contract managing vaults, shares, orderbook and collaterals
interface IDAO {
    // ============================================
    // CUSTOM ERRORS
    // ============================================

    // General errors
    error Unauthorized();
    error OnlyVotingContract();
    error OnlyByDAOVoting();
    error InvalidStage();
    error VaultDoesNotExist();
    error InvalidLaunchToken();
    error DAOIsDissolved();
    error AmountMustBeGreaterThanZero();
    error InvalidAddresses();
    error VaultAlreadyExists();
    error InvalidState();
    error SenderHasNoVault();
    error OnlyPrimaryCanTransfer();
    error AddressAlreadyUsedInAnotherVault();
    error InvalidAddress();
    error InvalidV3PositionManager();
    error V3PositionManagerMismatch();
    error NoVaultFound();
    error OnlyPrimaryCanClaim();
    error NoRewardsToClaim();
    error CollateralNotSellable();
    error OrderbookNotInitialized();
    error InvalidCollateralPrice();
    error SlippageExceeded();
    error CollateralNotActive();
    error InvalidPrice();
    error NoSharesIssued();
    error NoSharesToClaim();
    error CollateralAlreadyExists();
    error VotingContractAlreadySet();
    error MainCollateralAlreadySet();
    error RouterAlreadyAdded();
    error TokenAlreadyAdded();
    error InvalidInitialPrice();
    error InvalidVolume();
    error NoProfitToDistribute();
    error NoShares();
    error RewardPerShareTooLow();
    error LPTokenUsesDifferentDistribution();
    error NotBoardMemberOrAdmin();
    error BelowMinLaunchDeposit();
    error AlreadyInExitQueue();
    error NotInExitQueue();
    error ExitAlreadyProcessed();
    error ExitQueueNotEmpty();
    error AllocationTooSoon();
    error ExceedsMaxAllocation();
    error CreatorShareTooLow();
    error NotLPToken();
    error LPDistributionTooSoon();
    error DepositLimitExceeded();
    error DepositLimitBelowCurrentShares();
    error LoanNotActive();
    error LoanActive();
    error RepayAmountTooHigh();
    error DropTooSoon();
    error ExceedsDropLimit();

    // Fundraising errors
    error FundraisingDeadlinePassed();
    error DepositBelowMinimum();
    error SharesCalculationFailed();
    error FundraisingAlreadyExtended();
    error FundraisingNotExpiredYet();
    error TargetAlreadyReached();
    error TargetNotReached();
    error NoPOCContractsConfigured();
    error POCSharesNot100Percent();
    error NoDepositToWithdraw();
    error InvalidPercentage();
    error InvalidSharePrice();
    error InvalidTargetAmount();
    error POCAlreadyExists();
    error TotalShareExceeds100Percent();
    error ActiveStageNotSet();
    error CancelPeriodNotPassed();

    // Exchange errors
    error InvalidPOCIndex();
    error POCNotActive();
    error POCAlreadyExchanged();
    error POCNotExchanged();
    error RouterNotAvailable();
    error PriceDeviationTooHigh();
    error MainCollateralBalanceNotDepleted();
    error OnlyCreator();
    error OnlyPOCContract();
    error AmountExceedsRemaining();
    error ExecutionFailed(string reason);
    error UpgradeNotAuthorized();
    error UpgradeDelayNotPassed();
    error TokenNotAdded();
    error POCLockPeriodNotEnded();
    error POCIsActive();
    error POCStillHasBalances();
    error POCNotFound();

    // POC return errors
    error POCReturnTooSoon();
    error POCReturnExceedsMaxAmount();
    error NoPOCContractsActive();
    error NoDepegCondition();

    error PriceOracleNotSet();
    error PriceOracleAlreadySet();

    // ============================================
    // EVENTS
    // ============================================

    // Vault events
    event VaultCreated(uint256 indexed vaultId, address indexed primary, uint256 shares);
    event VaultDeposited(uint256 indexed vaultId, uint256 mainCollateralAmount, uint256 shares);
    event SharesTransferred(uint256 indexed fromVaultId, uint256 indexed toVaultId, uint256 amount);
    event PrimaryAddressUpdated(uint256 indexed vaultId, address oldPrimary, address newPrimary);
    event BackupAddressUpdated(uint256 indexed vaultId, address oldBackup, address newBackup);
    event EmergencyAddressUpdated(uint256 indexed vaultId, address oldEmergency, address newEmergency);
    event DelegateUpdated(uint256 indexed vaultId, uint256 oldDelegateId, uint256 newDelegateId, uint256 delegateSetAt);
    event RewardClaimed(uint256 indexed vaultId, address indexed token, uint256 amount);
    event VaultDepositLimitSet(uint256 indexed vaultId, uint256 limit);

    // Trading events
    event LaunchTokenSold(
        address indexed seller, address indexed collateral, uint256 launchAmount, uint256 collateralAmount
    );
    event SellableCollateralAdded(address indexed token);
    event RewardTokenAdded(address indexed token);
    event ProfitDistributed(address indexed token, uint256 amount);
    event RoyaltyDistributed(address indexed token, address indexed recipient, uint256 amount);
    event CreatorProfitDistributed(address indexed token, address indexed creator, uint256 amount);

    // Lifecycle events
    event StageChanged(DataTypes.Stage oldStage, DataTypes.Stage newStage);
    event VotingContractSet(address indexed votingContract);
    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event MainCollateralSet(address indexed mainCollateral);
    event IsVetoToCreatorSet(bool oldValue, bool newValue);
    event RoyaltyRecipientSet(address indexed oldRoyaltyRecipient, address indexed newRoyaltyRecipient);
    event RouterAvailabilityChanged(address indexed router, bool isAvailable);
    event TokenAvailabilityChanged(address indexed token, bool isAvailable);
    event MultisigExecutionPushed(uint256 indexed proposalId, address indexed pusher);
    event MarketMakerSet(address indexed marketMaker);
    event OrderbookParamsUpdated(
        uint256 initialPrice,
        uint256 initialVolume,
        uint256 priceStepPercent,
        int256 volumeStepPercent,
        uint256 proportionalityCoefficient,
        uint256 totalSupply
    );

    // Fundraising events
    event CreatorSet(address indexed creator, uint256 profitPercent, uint256 infraPercent);
    event CreatorDissolutionClaimed(address indexed creator, uint256 launchAmount);
    event FundraisingConfigured(uint256 minDeposit, uint256 sharePrice, uint256 targetAmount, uint256 deadline);
    event FundraisingDeposit(uint256 indexed vaultId, address indexed depositor, uint256 amount, uint256 shares);
    event LaunchDeposit(
        uint256 indexed vaultId, address indexed depositor, uint256 launchAmount, uint256 shares, uint256 launchPriceUSD
    );
    event FundraisingWithdrawal(uint256 indexed vaultId, address indexed withdrawer, uint256 amount);
    event FundraisingExtended(uint256 newDeadline);
    event FundraisingCancelled(uint256 totalCollected);
    event FundraisingCollectionFinalized(uint256 totalCollected, uint256 totalShares);
    event POCContractAdded(address indexed pocContract, address indexed collateralToken, uint256 sharePercent);
    event POCContractRemoved(address indexed pocContract);
    event PrivateSaleRegistered(address indexed privateSaleContract);
    event POCExchangeCompleted(
        uint256 indexed pocIndex,
        address indexed pocContract,
        uint256 mainCollateralAmount,
        uint256 collateralAmount,
        uint256 launchReceived
    );
    event ExchangeFinalized(uint256 totalLaunches, uint256 sharePrice, uint256 creatorInfraLaunches);
    event LPTokensProvided(address indexed lpToken, uint256 amount);
    event V3LPPositionProvided(uint256 indexed tokenId, address token0, address token1);
    event V3LiquidityDecreased(uint256 indexed tokenId, uint128 liquidity, uint256 amount0, uint256 amount1);

    // Exit queue events
    event ExitRequested(uint256 indexed vaultId, uint256 shares, uint256 launchPriceAtRequest);
    event ExitRequestCancelled(uint256 indexed vaultId);
    event ExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event PartialExitProcessed(uint256 indexed vaultId, uint256 shares, uint256 payoutAmount, address token);
    event SharePriceIncreased(uint256 oldPrice, uint256 newPrice, uint256 exitedShares);

    // Financial decisions events
    event CreatorLaunchesAllocated(
        uint256 launchAmount, uint256 profitPercentReduction, uint256 newCreatorProfitPercent
    );
    event CreatorLaunchesReturned(uint256 launchAmount, uint256 profitPercentIncrease, uint256 newCreatorProfitPercent);
    event LoanTaken(
        uint256 launchAmount,
        bool reservedForExitQueue,
        uint256 newPrincipal,
        uint256 newInterestAccrued,
        uint256 newCreatorProfitPercent
    );
    event LoanRepaid(
        uint256 paidAmount,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 remainingPrincipal,
        uint256 remainingInterestAccrued,
        uint256 newCreatorProfitPercent
    );
    event CreatorVaultSet(uint256 indexed vaultId, address indexed creator);
    event LaunchDropDistributed(uint256 amount);
    event LPProfitDistributed(address indexed lpToken, uint256 amount);
    event LaunchesReturnedToPOC(uint256 totalAmount, uint256 pocCount);

    // LP dissolution events
    event V2LPTokenDissolved(address indexed lpToken, uint256 amount0, uint256 amount1);
    event V3LPPositionDissolved(uint256 indexed tokenId, uint256 amount0, uint256 amount1);

    // Upgrade events
    event PendingUpgradeSetFromVoting(address indexed newImplementation);
    event PendingUpgradeSetFromCreator(address indexed newImplementation);

    // ============================================
    // VAULT MANAGEMENT
    // ============================================

    function createVault(address backup, address emergency, address delegate) external returns (uint256 vaultId);
    function depositFundraising(uint256 amount, uint256 vaultId) external;
    function depositLaunches(uint256 launchAmount, uint256 vaultId) external;
    function updatePrimaryAddress(uint256 vaultId, address newPrimary) external;
    function updateBackupAddress(uint256 vaultId, address newBackup) external;
    function updateEmergencyAddress(uint256 vaultId, address newEmergency) external;
    function setDelegate(address userAddress, address delegate) external;
    function claimReward(address[] calldata tokens) external;
    function requestExit() external;
    function cancelExit() external;
    function takeLoanInLaunches(uint256 launchAmount, bool reserveForExitQueue) external;
    function repayLoanInLaunches(uint256 amount) external;
    function dropLaunchesAsProfit(uint256 amount) external;
    function upgradeOwnerShare(uint256 amount) external;
    function returnLaunchesToPOC(uint256 amount) external;

    // ============================================
    // ORDERBOOK OPERATIONS
    // ============================================

    function sell(
        address collateral,
        uint256 launchTokenAmount,
        uint256 minCollateralAmount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external;
    function getCollateralPrice(address collateral) external view returns (uint256);

    // ============================================
    // FUNDRAISING MANAGEMENT
    // ============================================

    function addPOCContract(address pocContract, address collateralToken, uint256 sharePercent) external;
    function removePOCContract(address pocContract) external;
    function withdrawFundraising() external;
    function extendFundraising() external;
    function cancelFundraising() external;
    function finalizeFundraisingCollection() external;

    // ============================================
    // FUNDRAISING EXCHANGE
    // ============================================

    function exchangeForPOC(
        uint256 pocIdx,
        uint256 amount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external;
    function finalizeExchange() external;

    // ============================================
    // LIFECYCLE MANAGEMENT
    // ============================================

    function dissolveIfLocksEnded() external;
    function claimDissolution(address[] calldata tokens) external;
    function claimCreatorDissolution() external;
    function declareDepeg(address lpToken, uint256 tokenId, DataTypes.LPTokenType lpType) external;
    function addLiquidityBackV2(
        address lpToken,
        address router,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external;
    function addLiquidityBackV3(
        uint256 tokenId,
        uint256 amount0,
        uint256 amount1,
        uint256 amount0Min,
        uint256 amount1Min
    ) external;
    function rebalance(
        address collateral,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData,
        DataTypes.RebalanceDirection direction,
        uint256 amountIn,
        uint256 minOut
    ) external;
    function finalizeDepegAfterGracePeriod(address lpToken, uint256 tokenId, DataTypes.LPTokenType lpType) external;
    function executeProposal(address targetContract, bytes calldata callData) external;
    function provideLPTokens(
        address[] calldata v2LPTokenAddresses,
        uint256[] calldata v2LPAmounts,
        uint256[] calldata v3TokenIds,
        DataTypes.PricePathV2Params[] calldata newV2PricePaths,
        DataTypes.PricePathV3Params[] calldata newV3PricePaths
    ) external;

    // ============================================
    // ADMINISTRATION
    // ============================================

    function setVotingContract(address votingContract) external;
    function setAdmin(address newAdmin) external;
    function setIsVetoToCreator(bool value) external;
    function setRoyaltyRecipient(address newRoyaltyRecipient) external;
    function setPriceOracle(address newPriceOracle) external;
    function setPendingUpgradeFromVoting(address newImplementation) external;
    function pushMultisigExecution(uint256 proposalId, IMultisig.ProposalCall[] calldata calls) external;

    // ============================================
    // PROFIT DISTRIBUTION
    // ============================================

    function distributeProfit(address token, uint256 amount) external;
    function distributeLPProfit(address lpTokenOrTokenId, DataTypes.LPTokenType lpType) external;

    // ============================================
    // VIEW FUNCTIONS - Public variables getters
    // ============================================
    // Note: Public variables automatically generate getters
    // These are declared here for interface compatibility

    // Core state
    function coreConfig() external view returns (DataTypes.CoreConfig memory);
    function getDaoState() external view returns (DataTypes.DAOState memory);
    function waitingForLPStartedAt() external view returns (uint256);

    // Shares and supply
    function totalSharesSupply() external view returns (uint256);
    function nextVaultId() external view returns (uint256);

    // Fundraising
    // Note: fundraisingConfig, participantEntries, pocContracts, orderbookParams, vaults, sellableCollaterals
    // are public structs/mappings - accessible automatically via public getters
    function totalCollectedMainCollateral() external view returns (uint256);

    // POC contracts
    function pocIndex(address) external view returns (uint256);
    function getPOCContractsCount() external view returns (uint256);
    function getPOCContract(uint256 index) external view returns (DataTypes.POCInfo memory);

    // Vaults
    function vaults(uint256 vaultId) external view returns (DataTypes.Vault memory);
    function addressToVaultId(address) external view returns (uint256);
    function vaultMainCollateralDeposit(uint256) external view returns (uint256);

    // Routers and tokens
    function availableRouterByAdmin(address) external view returns (bool);
    function sellableCollaterals(address)
        external
        view
        returns (address token, bool active, uint256 ratioBps, uint256 depegThresholdMinPrice);
    function rewardTokens(uint256) external view returns (address);
    function rewardTokenInfo(address) external view returns (DataTypes.RewardTokenInfo memory);

    // Rewards - mappings need separate getters
    function accountedBalance(address) external view returns (uint256);
    function rewardPerShareStored(address) external view returns (uint256);
    function vaultRewardIndex(uint256, address) external view returns (uint256);
    function earnedRewards(uint256, address) external view returns (uint256);

    // V2 LP tokens
    function v2LPTokens(uint256) external view returns (address);
    function isV2LPToken(address) external view returns (bool);
    function lastLPDistribution(address) external view returns (uint256);
    function lpTokenAddedAt(address) external view returns (uint256);

    // Depeg
    function depegInfoV2(address) external view returns (DataTypes.DepegInfo memory);
    function depegInfoV3(uint256) external view returns (DataTypes.DepegInfo memory);

    // V3 LP positions
    function v3LPPositions(uint256) external view returns (DataTypes.V3LPPositionInfo memory);
    function v3TokenIdToIndex(uint256) external view returns (uint256);
    function v3PositionManager() external view returns (address);
    function v3LastLPDistribution(uint256) external view returns (uint256);
    function v3LPTokenAddedAt(uint256) external view returns (uint256);

    // Board member functions
    function isBoardMember(address account) external view returns (bool);
    function isVaultInExitQueue(uint256 vaultId) external view returns (bool);

    // Dynamic threshold functions
    function getDAOProfitShare() external view returns (uint256);
    function getVetoThreshold() external view returns (uint256);
    function getClosingThreshold() external view returns (uint256);
    function getLaunchPriceFromDAO() external view returns (uint256);
}
