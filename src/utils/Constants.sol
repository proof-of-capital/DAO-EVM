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
    uint256 public constant CLOSING_EXIT_QUEUE_THRESHOLD = 5000; // 50% in basis points
    uint256 public constant MIN_DAO_PROFIT_SHARE = 2500; // 25% in basis points
    uint256 public constant CLOSING_EXIT_QUEUE_MIN_THRESHOLD = 3000; // 30% in basis points

    // ============================================
    // PRICE VALIDATION CONSTANTS
    // ============================================

    uint256 public constant MAX_PRICE_DEVIATION_BP = 500; // 5% max deviation allowed
    uint256 public constant MIN_POOL_LIQUIDITY = 1000e18; // Min 1000 launch tokens in pool
    uint256 public constant PRICE_QUOTE_AMOUNT = 1e18; // 1 token for price query

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
    uint256 public constant PERCENTAGE_MULTIPLIER = 100;
    uint256 public constant PROPOSAL_EXPIRY_PERIOD = 30 days;
    uint256 public constant PROPOSAL_CREATION_COOLDOWN = 1 days;

    // ============================================
    // PROPOSAL TYPE SPECIFIC CONSTANTS
    // ============================================

    uint256 public constant VETO_QUORUM = 50; // 50% in percentage
    uint256 public constant VETO_APPROVAL = 80; // 80% in percentage
    uint256 public constant ARBITRARY_QUORUM = 30; // 30% in percentage
    uint256 public constant ARBITRARY_APPROVAL = 80; // 80% in percentage
    uint256 public constant ARBITRARY_EARLY_REJECT_THRESHOLD = 20; // 20% in percentage
    uint256 public constant UNANIMOUS_QUORUM = 50; // 50% in percentage
    uint256 public constant UNANIMOUS_APPROVAL = 95; // 95% in percentage
    uint256 public constant UNANIMOUS_EARLY_REJECT_THRESHOLD = 5; // 5% in percentage

    // ============================================
    // MULTISIG CONSTANTS
    // ============================================

    uint256 public constant MULTISIG_VOTING_PERIOD = 10 days;
    uint256 public constant MULTISIG_TRANSACTION_EXPIRY_PERIOD = 7 days;
    uint256 public constant MULTISIG_MAX_COUNT_VOTE_PERIOD = 1 days;
    uint256 public constant MULTISIG_DEFAULT_MAX_COUNT_VOTE_PER_PERIOD = 6;
    uint256 public constant MULTISIG_GENERAL_PARTICIPATION_THRESHOLD = 60;
    uint256 public constant MULTISIG_GENERAL_APPROVAL_THRESHOLD = 80;
    uint256 public constant MULTISIG_TRANSFER_THRESHOLD_COUNT = 7;
    bytes32 public constant MULTISIG_BACKUP_ADMIN_ROLE = keccak256("BACKUP_ADMIN_ROLE");
    bytes32 public constant MULTISIG_EMERGENCY_INVESTOR_ROLE = keccak256("EMERGENCY_INVESTOR_ROLE");
    bytes32 public constant MULTISIG_EMERGENCY_ADMIN_ROLE = keccak256("EMERGENCY_ADMIN_ROLE");

    bytes4 public constant TRANSFER_OWNERSHIP_SELECTOR = 0xf2fde38b;
    bytes4 public constant RENOUNCE_OWNERSHIP_SELECTOR = 0x715018a6;
    bytes4 public constant GRANT_ROLE_SELECTOR = 0x2f2ff15d;
    bytes4 public constant REVOKE_ROLE_SELECTOR = 0xd547741f;
    bytes4 public constant CHANGE_EMERGENCY_ADDRESS_SELECTOR = 0xd6ac0667;
    bytes4 public constant SET_COMMON_BACKUP_ADMIN_SELECTOR = 0x1b556ca0;
    bytes4 public constant SET_COMMON_EMERGENCY_ADMIN_SELECTOR = 0xa5862a58;
    bytes4 public constant SET_MAX_COUNT_VOTE_PER_PERIOD_SELECTOR = 0x09f0a353;
    bytes4 public constant SET_COMMON_EMERGENCY_INVESTOR_SELECTOR = 0x7024e081;
    uint256 public constant MULTISIG_WAITING_FOR_LP_TIMEOUT = 14 days;
    uint256 public constant LP_EXTEND_LOCK_PERIOD = 180 days;
}

