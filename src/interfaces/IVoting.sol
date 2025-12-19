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

import "../utils/DataTypes.sol";

/// @title IVoting Interface
/// @notice Interface for the voting contract managing proposals and votes
interface IVoting {
    // Events
    event ProposalCreated(
        uint256 indexed proposalId,
        address indexed proposer,
        DataTypes.ProposalType proposalType,
        address targetContract,
        bytes callData
    );
    event VoteCast(uint256 indexed proposalId, uint256 indexed vaultId, bool support, uint256 weight);
    event ProposalExecuted(uint256 indexed proposalId);
    event VotingParametersUpdated(uint256 votingPeriod, uint256 quorumPercentage, uint256 approvalThreshold);
    event ProposalCategoryDetected(uint256 indexed proposalId, DataTypes.VotingCategory category);
    event CategoryThresholdsUpdated(
        DataTypes.VotingCategory indexed category, uint256 quorumPercentage, uint256 approvalThreshold
    );

    // Proposal Management Functions
    function createProposal(DataTypes.ProposalType proposalType, address targetContract, bytes calldata callData)
        external
        returns (uint256 proposalId);

    function vote(uint256 proposalId, bool support) external;
    function execute(uint256 proposalId) external;

    // Admin Functions
    // Note: Category thresholds are set only in constructor and cannot be changed

    // View functions
    function getProposal(uint256 proposalId) external view returns (DataTypes.ProposalCore memory);
    function getProposalStatus(uint256 proposalId) external view returns (DataTypes.ProposalStatus);
    function hasVoted(uint256 proposalId, uint256 vaultId) external view returns (bool);
    function getVotingParameters()
        external
        view
        returns (uint256 votingPeriod, uint256 quorumPercentage, uint256 approvalThreshold);

    function getCategoryThresholds(DataTypes.VotingCategory category)
        external
        view
        returns (uint256 quorumPct, uint256 approvalPct);

    function getAllCategoryThresholds()
        external
        view
        returns (
            DataTypes.VotingThresholds memory governanceThresholds,
            DataTypes.VotingThresholds memory pocThresholds,
            DataTypes.VotingThresholds memory financialThresholds,
            DataTypes.VotingThresholds memory otherThresholds
        );

    function getProposalCategory(uint256 proposalId) external view returns (DataTypes.VotingCategory);

    function determineCategory(address targetContract) external view returns (DataTypes.VotingCategory);
}

