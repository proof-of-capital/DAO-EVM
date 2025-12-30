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

/// @title DataTypes
/// @notice Library containing all data structures and enums for DAO system
library DataTypes {
    // ============================================
    // ENUMS
    // ============================================

    /// @notice DAO lifecycle stages
    enum Stage {
        Fundraising, // Initial fundraising - collecting funds
        FundraisingCancelled, // Fundraising was cancelled, users can withdraw
        FundraisingExchange, // Exchanging collected funds for launch tokens
        WaitingForLP, // Waiting for LP tokens from creator
        Active, // Active operation stage
        Closing, // Closing stage when exit queue shares > 50%
        WaitingForLPDissolution, // Waiting for LP tokens dissolution (V2 and V3)
        Dissolved // DAO dissolved stage
    }

    /// @notice Proposal types for voting
    /// @dev Type is auto-determined based on target contract and call data
    enum ProposalType {
        Governance, // Calls to DAO contract itself (settings changes)
        POC, // Calls to POC contracts (external management)
        Financial, // Calls to token contracts (financial operations) - forbidden
        Other, // All other external calls
        Veto, // Veto proposal for multisig (set/remove veto mode)
        Arbitrary, // Arbitrary call proposal (general questions)
        Unanimous // Unanimous vote required (for changing POC contracts, contract upgrades)
    }

    /// @notice Voting thresholds for each category
    /// @dev Both values are percentages (0-100)
    struct VotingThresholds {
        uint256 quorumPercentage; // Minimum participation rate (% of total shares that must vote)
        uint256 approvalThreshold; // Minimum approval rate (% of votes that must be "for")
    }

    /// @notice Proposal execution status
    enum ProposalStatus {
        Active, // Proposal is active and can be voted on
        Executed, // Proposal has been executed
        Defeated, // Proposal was defeated
        Expired // Proposal has expired
    }

    /// @notice Swap router types
    enum SwapType {
        None, // No swap, direct transfer
        UniswapV2ExactTokensForTokens, // Uniswap V2: swapExactTokensForTokens
        UniswapV2TokensForExactTokens, // Uniswap V2: swapTokensForExactTokens
        UniswapV3ExactInputSingle, // Uniswap V3: exactInputSingle
        UniswapV3ExactInput, // Uniswap V3: exactInput (multi-hop)
        UniswapV3ExactOutputSingle, // Uniswap V3: exactOutputSingle
        UniswapV3ExactOutput // Uniswap V3: exactOutput (multi-hop)
    }

    /// @notice LP token types
    enum LPTokenType {
        V2, // Uniswap V2 LP tokens (ERC20)
        V3 // Uniswap V3 LP positions (NFT)
    }

    // ============================================
    // VAULT STRUCTURES
    // ============================================

    /// @notice Vault data structure
    struct Vault {
        address primary; // Primary address with full control
        address backup; // Backup address for recovery
        address emergency; // Emergency address for critical operations
        uint256 shares; // Amount of shares owned
        uint256 votingPausedUntil; // Timestamp until which voting is paused
        uint256 delegateId; // Delegate vault ID for voting (0 means self-delegation)
        uint256 delegateSetAt; // Timestamp when delegate was set
        uint256 votingShares; // Voting shares amount
        uint256 mainCollateralDeposit; // Main collateral deposit amount
        uint256 depositedUSD; // Deposited amount in USD
        uint256 depositLimit; // Deposit limit in shares
    }

    // ============================================
    // ORDERBOOK STRUCTURES
    // ============================================

    /// @notice Orderbook parameters for stepped pricing
    struct OrderbookParams {
        uint256 initialPrice; // Initial price in USD (18 decimals)
        uint256 initialVolume; // Initial volume per level (18 decimals)
        uint256 priceStepPercent; // Price step percentage in basis points (500 = 5%)
        int256 volumeStepPercent; // Volume step percentage in basis points (-100 = -1%, can be negative)
        uint256 proportionalityCoefficient; // Proportionality coefficient (7500 = 0.75, in basis points)
        uint256 totalSupply; // Total supply (1e27 = 1 billion with 18 decimals)
        uint256 totalSold; // Total amount of launch tokens sold
        // Current level cache fields for optimization
        uint256 currentLevel; // Current level
        uint256 currentTotalSold; // Total sold when level was calculated (should equal totalSold)
        uint256 currentCumulativeVolume; // Cumulative volume up to current level
        uint256 cachedPriceAtLevel; // Cached price at currentLevel (for optimization)
        uint256 cachedBaseVolumeAtLevel; // Cached base volume at currentLevel (for optimization)
    }

    /// @notice Collateral information
    struct CollateralInfo {
        address token; // Collateral token address
        address priceFeed; // Chainlink price feed address
        bool active; // Whether collateral is active
    }

    /// @notice Reward token information
    struct RewardTokenInfo {
        address token; // Reward token address
        address priceFeed; // Chainlink price feed address
        bool active; // Whether reward token is active
    }

    /// @notice Parameters for sell operation
    struct SellParams {
        address collateral; // Collateral token address
        uint256 launchTokenAmount; // Amount of launch tokens to sell
        uint256 minCollateralAmount; // Minimum collateral to receive (slippage protection)
        address router; // Router address for swap (if swapType != None)
        SwapType swapType; // Type of swap to execute
        bytes swapData; // Encoded swap parameters
    }

    /// @notice Result of sell operation
    struct SellResult {
        uint256 collateralAmount; // Amount of collateral received
        uint256 currentPrice; // Current price at time of sale
    }

    /// @notice Internal calculation state for orderbook operations (used to avoid stack too deep)
    struct OrderbookCalcState {
        uint256 currentLevel;
        uint256 cumulativeVolumeBeforeLevel;
        uint256 currentBaseVolume;
        uint256 currentPrice;
        uint256 adjustedLevelVolume;
        uint256 levelEndVolume;
        uint256 priceBase;
        uint256 volumeBase;
        uint256 sharesNumerator;
        uint256 sharesDenominator;
    }

    // ============================================
    // VOTING STRUCTURES
    // ============================================

    /// @notice Core proposal data
    struct ProposalCore {
        uint256 id; // Proposal ID
        address proposer; // Address that created the proposal
        ProposalType proposalType; // Type of proposal (auto-determined)
        bytes callData; // Call data for execution
        address targetContract; // Target contract for execution
        uint256 forVotes; // Votes in favor
        uint256 againstVotes; // Votes against
        uint256 startTime; // Proposal start timestamp
        uint256 endTime; // Proposal end timestamp
        bool executed; // Whether proposal has been executed
    }

    // ============================================
    // FUNDRAISING STRUCTURES
    // ============================================

    /// @notice Fundraising configuration parameters
    struct FundraisingConfig {
        uint256 minDeposit; // Minimum deposit amount in USD (18 decimals)
        uint256 minLaunchDeposit; // Minimum launch token deposit (18 decimals), e.g., 10000e18 = 10k launches
        uint256 sharePrice; // Fixed share price in USD (18 decimals)
        uint256 launchPrice; // Fixed launch token price in USD (18 decimals)
        uint256 targetAmountMainCollateral; // Target fundraising amount in main collateral (18 decimals)
        uint256 deadline; // Fundraising deadline timestamp
        uint256 extensionPeriod; // Extension period in seconds (if deadline missed)
        bool extended; // Whether fundraising was already extended once
    }

    /// @notice POC (Proof of Capital) contract information with allocation share
    struct POCInfo {
        address pocContract; // POC contract address
        address collateralToken; // Collateral token accepted by this POC
        address priceFeed; // Chainlink price feed for collateral
        uint256 sharePercent; // Allocation percentage in basis points (10000 = 100%)
        bool active; // Whether this POC is active
        bool exchanged; // Whether funds were already exchanged for this POC
        uint256 exchangedAmount; // Amount of mainCollateral already exchanged (in mainCollateral terms)
    }

    /// @notice Participant entry information for tracking deposits and fixed prices
    struct ParticipantEntry {
        uint256 depositedMainCollateral; // Total mainCollateral deposited by participant
        uint256 fixedSharePrice; // Fixed share price at entry time (USD, 18 decimals)
        uint256 fixedLaunchPrice; // Fixed launch price at entry time (USD, 18 decimals)
        uint256 entryTimestamp; // Timestamp of first entry
        uint256 weightedAvgSharePrice; // Weighted average share price across all deposits (USD, 18 decimals)
        uint256 weightedAvgLaunchPrice; // Weighted average launch price across all deposits (USD, 18 decimals)
    }

    /// @notice Exit request for participant wanting to leave DAO
    struct ExitRequest {
        uint256 vaultId; // Vault ID requesting exit
        uint256 requestTimestamp; // When exit was requested
        uint256 fixedLaunchPriceAtRequest; // Launch price at time of request
        bool processed; // Whether exit has been processed
    }

    /// @notice V3 LP position information
    struct V3LPPositionInfo {
        address positionManager; // Address of NonfungiblePositionManager (same for all V3 positions)
        uint256 tokenId; // NFT token ID of the position
        address token0; // First token in the pair
        address token1; // Second token in the pair
    }

    /// @notice V3 LP position parameters for constructor
    struct V3LPPositionParams {
        address positionManager; // Address of NonfungiblePositionManager
        uint256 tokenId; // NFT token ID of the position
    }

    // ============================================
    // PRICE VALIDATION STRUCTURES
    // ============================================

    /// @notice V2 price path for pool price queries
    struct PricePathV2 {
        address router; // V2 Router address
        address[] path; // Token path [tokenA, tokenB, ...]
    }

    /// @notice V3 price path for pool price queries
    struct PricePathV3 {
        address quoter; // QuoterV2 address
        bytes path; // Encoded path (tokenIn, fee, tokenOut, fee, ...)
    }

    /// @notice V2 price path parameters for constructor (with fixed array workaround)
    struct PricePathV2Params {
        address router; // V2 Router address
        address[] path; // Token path [tokenA, tokenB, ...]
    }

    /// @notice V3 price path parameters for constructor
    struct PricePathV3Params {
        address quoter; // QuoterV2 address
        bytes path; // Encoded path (tokenIn, fee, tokenOut, fee, ...)
    }

    /// @notice Token price paths configuration
    struct TokenPricePathsParams {
        PricePathV2Params[] v2Paths; // Array of V2 paths
        PricePathV3Params[] v3Paths; // Array of V3 paths
        uint256 minLiquidity; // Minimum liquidity threshold (in launch tokens)
    }

    // ============================================
    // CONSTRUCTOR PARAMETERS STRUCTURES
    // ============================================

    /// @notice POC contract parameters for constructor
    struct POCConstructorParams {
        address pocContract;
        address collateralToken;
        address priceFeed;
        uint256 sharePercent;
    }

    /// @notice Reward token parameters for constructor
    struct RewardTokenConstructorParams {
        address token;
        address priceFeed;
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
        address[] tokens; // Deprecated: use rewardTokenParams instead
        POCConstructorParams[] pocParams;
        RewardTokenConstructorParams[] rewardTokenParams; // Additional reward tokens (POC collaterals are added automatically)
        OrderbookConstructorParams orderbookParams;
        LPTokenType primaryLPTokenType; // Primary LP token type (if specified, must be provided)
        V3LPPositionParams[] v3LPPositions; // V3 LP positions for initialization (optional)
        address[] allowedExitTokens; // Tokens allowed for exit payments (global list)
        TokenPricePathsParams launchTokenPricePaths; // Paths for launch token price validation
        address votingContract; // Voting contract address (optional, can be set later)
    }

    // ============================================
    // STORAGE STRUCTURES FOR LIBRARIES
    // ============================================

    /// @notice Storage structure for Vault management
    struct VaultStorage {
        mapping(uint256 => Vault) vaults;
        mapping(address => uint256) addressToVaultId;
        uint256 nextVaultId;
        uint256 totalSharesSupply;
        mapping(uint256 => mapping(address => bool)) vaultAllowedExitTokens; // Vault-specific allowed exit tokens
    }

    /// @notice Storage structure for Rewards system
    struct RewardsStorage {
        address[] rewardTokens;
        mapping(address => RewardTokenInfo) rewardTokenInfo;
        mapping(address => uint256) rewardPerShareStored;
        mapping(uint256 => mapping(address => uint256)) vaultRewardIndex;
        mapping(uint256 => mapping(address => uint256)) earnedRewards;
    }

    /// @notice Storage structure for Exit Queue
    struct ExitQueueStorage {
        ExitRequest[] exitQueue;
        mapping(uint256 => uint256) vaultExitRequestIndex;
        uint256 nextExitQueueIndex;
    }

    /// @notice Storage structure for LP Tokens
    struct LPTokenStorage {
        address[] v2LPTokens;
        mapping(address => bool) isV2LPToken;
        V3LPPositionInfo[] v3LPPositions;
        mapping(uint256 => uint256) v3TokenIdToIndex;
        address v3PositionManager;
        mapping(address => uint256) lastLPDistribution;
        mapping(address => uint256) lpTokenAddedAt;
        mapping(uint256 => uint256) v3LastLPDistribution;
        mapping(uint256 => uint256) v3LPTokenAddedAt;
    }

    /// @notice Storage structure for DAO state
    struct DAOState {
        Stage currentStage;
        address royaltyRecipient;
        uint256 royaltyPercent;
        address creator;
        uint256 creatorProfitPercent;
        uint256 totalCollectedMainCollateral;
        uint256 lastCreatorAllocation;
        uint256 totalExitQueueShares;
        uint256 totalDepositedUSD;
        uint256 lastPOCReturn;
    }

    /// @notice Storage structure for Price Paths
    struct PricePathsStorage {
        PricePathV2[] v2Paths; // Array of V2 paths
        PricePathV3[] v3Paths; // Array of V3 paths
        uint256 minLiquidity; // Minimum liquidity threshold (in launch tokens)
    }
}

