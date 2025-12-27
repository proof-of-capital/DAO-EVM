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

import "./interfaces/IVoting.sol";
import "./interfaces/IDAO.sol";
import "./utils/DataTypes.sol";
import "./utils/Constants.sol";

/// @title Voting Contract
/// @notice Manages proposals and voting for DAO governance
contract Voting is IVoting {
    // Custom errors
    error NotAdmin();
    error NotDAO();
    error ProposalDoesNotExist();
    error InvalidDAOAddress();
    error InsufficientSharesToCreateProposal();
    error NotAuthorizedToCreateProposal();
    error InvalidTarget();
    error VotingNotStarted();
    error VotingEnded();
    error ProposalAlreadyExecuted();
    error NoVaultFound();
    error NoVotingPower();
    error OnlyPrimaryCanVote();
    error VotingIsPaused();
    error AlreadyVoted();
    error OnlyAdminOrCreatorCanExecute();
    error VotingNotEnded();
    error AlreadyExecuted();
    error ProposalNotSuccessful();
    error ExecutionFailed(string reason);
    error InvalidVotingPeriod();
    error InvalidQuorum();
    error InvalidThreshold();
    error InvalidAddress();
    error InvalidCategory();

    // State variables
    IDAO public immutable dao;

    uint256 public votingPeriod;
    uint256 public quorumPercentage;
    uint256 public approvalThreshold;
    mapping(DataTypes.VotingCategory => DataTypes.VotingThresholds) public categoryThresholds;

    uint256 public nextProposalId;

    mapping(uint256 => DataTypes.ProposalCore) public proposals;
    mapping(uint256 => mapping(uint256 => bool)) public hasVotedMapping;

    modifier onlyDAO() {
        _onlyDAO();
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        _proposalExists(proposalId);
        _;
    }

    modifier onlyAdminOrCreatorOrParticipant() {
        _onlyAdminOrCreatorOrParticipant();
        _;
    }

    constructor(address _dao) {
        require(_dao != address(0), InvalidDAOAddress());
        dao = IDAO(_dao);

        votingPeriod = Constants.DEFAULT_VOTING_PERIOD;
        quorumPercentage = Constants.DEFAULT_QUORUM_PERCENTAGE;
        approvalThreshold = Constants.DEFAULT_APPROVAL_THRESHOLD;

        categoryThresholds[DataTypes.VotingCategory.Governance] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_GOVERNANCE_QUORUM,
            approvalThreshold: Constants.DEFAULT_GOVERNANCE_APPROVAL
        });

        categoryThresholds[DataTypes.VotingCategory.POC] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_POC_QUORUM, approvalThreshold: Constants.DEFAULT_POC_APPROVAL
        });

        categoryThresholds[DataTypes.VotingCategory.Financial] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_FINANCIAL_QUORUM,
            approvalThreshold: Constants.DEFAULT_FINANCIAL_APPROVAL
        });

        categoryThresholds[DataTypes.VotingCategory.Other] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_OTHER_QUORUM, approvalThreshold: Constants.DEFAULT_OTHER_APPROVAL
        });
    }

    /// @notice Create a new proposal
    /// @dev Only admin, creator, or board members (>= 10 shares) can create proposals
    /// @dev Voting category is auto-detected based on target contract
    /// @param proposalType Type of proposal
    /// @param targetContract Target contract for the call
    /// @param callData Encoded call data
    /// @return proposalId ID of created proposal
    function createProposal(DataTypes.ProposalType proposalType, address targetContract, bytes calldata callData)
        external
        returns (uint256 proposalId)
    {
        bool isAdminUser = msg.sender == dao.admin();
        bool isCreator = msg.sender == dao.creator();
        uint256 vaultId = dao.addressToVaultId(msg.sender);

        if (vaultId > 0) {
            DataTypes.Vault memory vault = dao.vaults(vaultId);
            require(
                isAdminUser || isCreator || vault.shares >= Constants.BOARD_MEMBER_MIN_SHARES,
                InsufficientSharesToCreateProposal()
            );
        } else {
            require(isAdminUser || isCreator, NotAuthorizedToCreateProposal());
        }

        require(targetContract != address(0), InvalidTarget());

        DataTypes.VotingCategory category = _determineCategory(targetContract);

        proposalId = nextProposalId++;

        proposals[proposalId] = DataTypes.ProposalCore({
            id: proposalId,
            proposer: msg.sender,
            proposalType: proposalType,
            votingCategory: category,
            callData: callData,
            targetContract: targetContract,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + votingPeriod,
            executed: false
        });

        emit ProposalCreated(proposalId, msg.sender, proposalType, targetContract, callData);
        emit ProposalCategoryDetected(proposalId, category);
    }

    /// @notice Vote on a proposal
    /// @param proposalId Proposal ID
    /// @param support True for yes, false for no
    function vote(uint256 proposalId, bool support) external proposalExists(proposalId) {
        DataTypes.ProposalCore storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.startTime, VotingNotStarted());
        require(block.timestamp < proposal.endTime, VotingEnded());
        require(!proposal.executed, ProposalAlreadyExecuted());

        uint256 vaultId = dao.addressToVaultId(msg.sender);
        require(vaultId > 0, NoVaultFound());
        DataTypes.Vault memory vault = dao.vaults(vaultId);
        require(vault.shares > 0, NoVotingPower());
        require(vault.primary == msg.sender, OnlyPrimaryCanVote());
        require(block.timestamp >= vault.votingPausedUntil, VotingIsPaused());
        require(!hasVotedMapping[proposalId][vaultId], AlreadyVoted());

        uint256 votingPower = vault.shares;
        require(votingPower > 0, NoVotingPower());

        hasVotedMapping[proposalId][vaultId] = true;

        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(proposalId, vaultId, support, votingPower);
    }

    /// @notice Execute a successful proposal
    /// @dev Only admin, creator, or participant can execute proposals
    /// @param proposalId Proposal ID
    function execute(uint256 proposalId) external proposalExists(proposalId) onlyAdminOrCreatorOrParticipant {
        DataTypes.ProposalCore storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.endTime, VotingNotEnded());
        require(!proposal.executed, AlreadyExecuted());

        DataTypes.ProposalStatus status = getProposalStatus(proposalId);
        require(status == DataTypes.ProposalStatus.Active, ProposalNotSuccessful());

        proposal.executed = true;

        dao.executeProposal(proposal.targetContract, proposal.callData);

        emit ProposalExecuted(proposalId);
    }

    /// @notice Get proposal details
    /// @param proposalId Proposal ID
    /// @return Proposal details
    function getProposal(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (DataTypes.ProposalCore memory)
    {
        return proposals[proposalId];
    }

    /// @notice Get proposal status
    /// @dev Unanimous proposals require 100% forVotes and 0 againstVotes
    /// @dev Exit queue shares are counted: for veto proposals they go to forVotes, for others to againstVotes
    /// @param proposalId Proposal ID
    /// @return Current status of the proposal
    function getProposalStatus(uint256 proposalId)
        public
        view
        proposalExists(proposalId)
        returns (DataTypes.ProposalStatus)
    {
        DataTypes.ProposalCore memory proposal = proposals[proposalId];

        if (proposal.executed) {
            return DataTypes.ProposalStatus.Executed;
        }

        uint256 totalShares = dao.totalSharesSupply();
        uint256 exitQueueShares = dao.daoState().totalExitQueueShares;
        bool isVeto = _isVetoProposal(proposal.targetContract, proposal.callData);

        uint256 adjustedForVotes = proposal.forVotes;
        uint256 adjustedAgainstVotes = proposal.againstVotes;
        uint256 adjustedTotalShares = totalShares + exitQueueShares;

        if (isVeto) {
            adjustedForVotes += exitQueueShares;
        } else {
            adjustedAgainstVotes += exitQueueShares;
        }

        if (proposal.proposalType == DataTypes.ProposalType.Unanimous) {
            if (adjustedAgainstVotes > 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (block.timestamp < proposal.endTime) {
                if (adjustedForVotes >= adjustedTotalShares) {
                    return DataTypes.ProposalStatus.Active;
                }
                return DataTypes.ProposalStatus.Active;
            }

            if (adjustedForVotes < adjustedTotalShares) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (block.timestamp > proposal.endTime + Constants.PROPOSAL_EXPIRY_PERIOD) {
                return DataTypes.ProposalStatus.Expired;
            }

            return DataTypes.ProposalStatus.Active;
        }

        if (block.timestamp < proposal.endTime) {
            return DataTypes.ProposalStatus.Active;
        }

        uint256 totalVotes = adjustedForVotes + adjustedAgainstVotes;

        DataTypes.VotingThresholds memory thresholds = categoryThresholds[proposal.votingCategory];

        if (totalVotes * Constants.PERCENTAGE_MULTIPLIER < adjustedTotalShares * thresholds.quorumPercentage) {
            return DataTypes.ProposalStatus.Defeated;
        }

        if (adjustedForVotes * Constants.PERCENTAGE_MULTIPLIER < totalVotes * thresholds.approvalThreshold) {
            return DataTypes.ProposalStatus.Defeated;
        }

        if (block.timestamp > proposal.endTime + Constants.PROPOSAL_EXPIRY_PERIOD) {
            return DataTypes.ProposalStatus.Expired;
        }

        return DataTypes.ProposalStatus.Active;
    }

    /// @notice Check if a vault has voted on a proposal
    /// @param proposalId Proposal ID
    /// @param vaultId Vault ID
    /// @return True if voted
    function hasVoted(uint256 proposalId, uint256 vaultId) external view returns (bool) {
        return hasVotedMapping[proposalId][vaultId];
    }

    /// @notice Get voting parameters (legacy)
    /// @return Current voting parameters
    function getVotingParameters() external view returns (uint256, uint256, uint256) {
        return (votingPeriod, quorumPercentage, approvalThreshold);
    }

    /// @notice Get voting thresholds for a specific category
    /// @param category Voting category
    /// @return quorumPct Quorum percentage (participation rate)
    /// @return approvalPct Approval threshold (approval rate)
    function getCategoryThresholds(DataTypes.VotingCategory category)
        external
        view
        returns (uint256 quorumPct, uint256 approvalPct)
    {
        DataTypes.VotingThresholds memory thresholds = categoryThresholds[category];
        return (thresholds.quorumPercentage, thresholds.approvalThreshold);
    }

    /// @notice Get all category thresholds
    /// @return governanceThresholds Governance category thresholds
    /// @return pocThresholds POC category thresholds
    /// @return financialThresholds Financial category thresholds
    /// @return otherThresholds Other category thresholds
    function getAllCategoryThresholds()
        external
        view
        returns (
            DataTypes.VotingThresholds memory governanceThresholds,
            DataTypes.VotingThresholds memory pocThresholds,
            DataTypes.VotingThresholds memory financialThresholds,
            DataTypes.VotingThresholds memory otherThresholds
        )
    {
        return (
            categoryThresholds[DataTypes.VotingCategory.Governance],
            categoryThresholds[DataTypes.VotingCategory.POC],
            categoryThresholds[DataTypes.VotingCategory.Financial],
            categoryThresholds[DataTypes.VotingCategory.Other]
        );
    }

    /// @notice Get proposal's voting category
    /// @param proposalId Proposal ID
    /// @return Voting category of the proposal
    function getProposalCategory(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (DataTypes.VotingCategory)
    {
        return proposals[proposalId].votingCategory;
    }

    /// @notice Determine what category a target contract would fall into
    /// @param targetContract Target contract address to check
    /// @return Voting category for the target
    function determineCategory(address targetContract) external view returns (DataTypes.VotingCategory) {
        return _determineCategory(targetContract);
    }

    /// @notice Determine voting category based on target contract
    /// @dev Categories: Governance (DAO itself), POC (POC contracts), Financial (tokens), Other
    /// @param targetContract Target contract address
    /// @return Voting category for the target
    function _determineCategory(address targetContract) internal view returns (DataTypes.VotingCategory) {
        if (targetContract == address(dao)) {
            return DataTypes.VotingCategory.Governance;
        }

        if (_isPOCContract(targetContract)) {
            return DataTypes.VotingCategory.POC;
        }

        if (_isTokenContract(targetContract)) {
            return DataTypes.VotingCategory.Financial;
        }

        return DataTypes.VotingCategory.Other;
    }

    /// @notice Check if address is a registered POC contract
    /// @param target Address to check
    /// @return True if target is a POC contract
    function _isPOCContract(address target) internal view returns (bool) {
        uint256 pocIdx = dao.pocIndex(target);
        return pocIdx > 0;
    }

    /// @notice Check if address is a known token contract (launch, reward, or LP token)
    /// @param target Address to check
    /// @return True if target is a token contract
    function _isTokenContract(address target) internal view returns (bool) {
        if (target == address(dao.launchToken())) {
            return true;
        }

        if (dao.isV2LPToken(target)) {
            return true;
        }

        if (target == dao.mainCollateral()) {
            return true;
        }

        DataTypes.RewardTokenInfo memory rewardInfo = dao.rewardTokenInfo(target);
        if (rewardInfo.active) {
            return true;
        }

        return false;
    }

    /// @notice Check if proposal is a veto proposal (calls setIsVetoToCreator(true))
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return True if proposal calls setIsVetoToCreator(true) on DAO contract
    function _isVetoProposal(address targetContract, bytes memory callData) internal view returns (bool) {
        if (targetContract != address(dao)) {
            return false;
        }

        bytes4 setIsVetoToCreatorSelector = IDAO.setIsVetoToCreator.selector;

        if (callData.length < 36) {
            return false;
        }

        bytes4 selector = bytes4(callData);
        if (selector != setIsVetoToCreatorSelector) {
            return false;
        }

        bytes memory data = new bytes(callData.length - 4);
        for (uint256 i = 4; i < callData.length; i++) {
            data[i - 4] = callData[i];
        }

        (bool value) = abi.decode(data, (bool));
        return value;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == dao.admin(), NotAdmin());
    }

    function _onlyDAO() internal view {
        require(msg.sender == address(dao), NotDAO());
    }

    function _proposalExists(uint256 proposalId) internal view {
        require(proposalId < nextProposalId, ProposalDoesNotExist());
    }

    function _onlyAdminOrCreatorOrParticipant() internal view {
        bool isAdminUser = msg.sender == dao.admin();
        bool isCreator = msg.sender == dao.creator();
        uint256 vaultId = dao.addressToVaultId(msg.sender);
        bool isParticipant = vaultId > 0;

        if (isParticipant) {
            DataTypes.Vault memory vault = dao.vaults(vaultId);
            isParticipant = vault.shares > 0;
        }

        require(isAdminUser || isCreator || isParticipant, OnlyAdminOrCreatorCanExecute());
    }
}

