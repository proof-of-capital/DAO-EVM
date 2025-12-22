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
        Dissolved // DAO dissolved stage
    }

    /// @notice Proposal types for voting
    enum ProposalType {
        AdminChange, // Admin change proposal
        Treasury, // Treasury distribution proposal
        Emergency, // Emergency actions (pause, dissolution)
        Arbitrary, // Arbitrary call proposal
        Unanimous // Unanimous vote required (for changing POC contracts, contract upgrades)
    }

    /// @notice Voting categories based on target contract type
    /// @dev Determines which thresholds to apply for voting
    enum VotingCategory {
        Governance, // Calls to DAO contract itself (settings changes)
        POC, // Calls to POC contracts (external management)
        Financial, // Calls to token contracts (financial operations)
        Other // All other external calls
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

    /// @notice Parameters for sell operation
    struct SellParams {
        address collateral; // Collateral token address
        uint256 launchTokenAmount; // Amount of launch tokens to sell
        uint256 minCollateralAmount; // Minimum collateral to receive (slippage protection)
        address seller; // Seller address
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
        ProposalType proposalType; // Type of proposal
        VotingCategory votingCategory; // Category for threshold selection (auto-detected)
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
        uint256 shares; // Number of shares to exit
        uint256 requestTimestamp; // When exit was requested
        uint256 fixedLaunchPriceAtRequest; // Launch price at time of request
        bool processed; // Whether exit has been processed
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
}

