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

/// @title Constants
/// @notice Library containing all constants used across the DAO system
library Constants {
    // ============================================
    // COMMON CONSTANTS
    // ============================================

    uint256 public constant PRICE_DECIMALS = 18;
    uint256 public constant PRICE_DECIMALS_MULTIPLIER = 1e18;
    uint256 public constant BASIS_POINTS = 10000;

    // ============================================
    // DAO CONSTANTS
    // ============================================

    uint256 public constant VOTING_PAUSE_DURATION = 7 days;
    uint256 public constant PRICE_DEVIATION_MAX = 300;
    uint256 public constant MIN_MAIN_COLLATERAL_BALANCE = 1e18;
    uint256 public constant BOARD_MEMBER_MIN_SHARES = 10 * 1e18;
    uint256 public constant MIN_EXIT_SHARES = 1e18;
    uint256 public constant EXIT_DISCOUNT_PERIOD = 365 days;
    uint256 public constant EXIT_DISCOUNT_PERCENT = 2000;
    uint256 public constant MAX_CREATOR_ALLOCATION_PERCENT = 500;
    uint256 public constant ALLOCATION_PERIOD = 30 days;
    uint256 public constant LP_DISTRIBUTION_PERIOD = 30 days;
    uint256 public constant LP_DISTRIBUTION_PERCENT = 100;
    uint256 public constant MIN_REWARD_PER_SHARE = 10;
    uint256 public constant UPGRADE_DELAY = 5 days;
    uint256 public constant CANCEL_AFTER_ACTIVE_PERIOD = 100 days;

    // ============================================
    // VOTING CONSTANTS
    // ============================================

    uint256 public constant DEFAULT_VOTING_PERIOD = 7 days;
    uint256 public constant DEFAULT_QUORUM_PERCENTAGE = 30;
    uint256 public constant DEFAULT_APPROVAL_THRESHOLD = 51;
    uint256 public constant DEFAULT_GOVERNANCE_QUORUM = 40;
    uint256 public constant DEFAULT_GOVERNANCE_APPROVAL = 66;
    uint256 public constant DEFAULT_POC_QUORUM = 35;
    uint256 public constant DEFAULT_POC_APPROVAL = 60;
    uint256 public constant DEFAULT_FINANCIAL_QUORUM = 35;
    uint256 public constant DEFAULT_FINANCIAL_APPROVAL = 60;
    uint256 public constant DEFAULT_OTHER_QUORUM = 30;
    uint256 public constant DEFAULT_OTHER_APPROVAL = 51;
}

