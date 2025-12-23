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

    // Constants
    uint256 public constant DEFAULT_VOTING_PERIOD = 7 days;
    uint256 public constant DEFAULT_QUORUM_PERCENTAGE = 30; // 30%
    uint256 public constant DEFAULT_APPROVAL_THRESHOLD = 51; // 51%

    // Default thresholds per category (quorum%, approval%)
    // Governance: DAO settings changes - higher thresholds
    uint256 public constant DEFAULT_GOVERNANCE_QUORUM = 40; // 40% participation
    uint256 public constant DEFAULT_GOVERNANCE_APPROVAL = 66; // 66% approval

    // POC: External management of POC contracts - medium thresholds
    uint256 public constant DEFAULT_POC_QUORUM = 35; // 35% participation
    uint256 public constant DEFAULT_POC_APPROVAL = 60; // 60% approval

    // Financial: Token operations - medium-high thresholds
    uint256 public constant DEFAULT_FINANCIAL_QUORUM = 35; // 35% participation
    uint256 public constant DEFAULT_FINANCIAL_APPROVAL = 60; // 60% approval

    // Other: External calls - standard thresholds
    uint256 public constant DEFAULT_OTHER_QUORUM = 30; // 30% participation
    uint256 public constant DEFAULT_OTHER_APPROVAL = 51; // 51% approval

    // State variables
    IDAO public immutable dao;
    address public admin;

    uint256 public votingPeriod;
    uint256 public quorumPercentage; // Legacy: kept for backwards compatibility
    uint256 public approvalThreshold; // Legacy: kept for backwards compatibility

    // Category-specific voting thresholds
    mapping(DataTypes.VotingCategory => DataTypes.VotingThresholds) public categoryThresholds;

    uint256 public nextProposalId;

    mapping(uint256 => DataTypes.ProposalCore) public proposals;
    mapping(uint256 => mapping(uint256 => bool)) public hasVotedMapping; // proposalId => vaultId => hasVoted

    // Modifiers
    modifier onlyAdmin() {
        _onlyAdmin();
        _;
    }

    modifier onlyDAO() {
        _onlyDAO();
        _;
    }

    modifier proposalExists(uint256 proposalId) {
        _proposalExists(proposalId);
        _;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == admin, NotAdmin());
    }

    function _onlyDAO() internal view {
        require(msg.sender == address(dao), NotDAO());
    }

    function _proposalExists(uint256 proposalId) internal view {
        require(proposalId < nextProposalId, ProposalDoesNotExist());
    }

    // Constructor
    constructor(address _dao) {
        require(_dao != address(0), InvalidDAOAddress());
        dao = IDAO(_dao);
        admin = msg.sender;

        votingPeriod = DEFAULT_VOTING_PERIOD;
        quorumPercentage = DEFAULT_QUORUM_PERCENTAGE;
        approvalThreshold = DEFAULT_APPROVAL_THRESHOLD;

        // Initialize category-specific thresholds
        categoryThresholds[DataTypes.VotingCategory.Governance] = DataTypes.VotingThresholds({
            quorumPercentage: DEFAULT_GOVERNANCE_QUORUM, approvalThreshold: DEFAULT_GOVERNANCE_APPROVAL
        });

        categoryThresholds[DataTypes.VotingCategory.POC] =
            DataTypes.VotingThresholds({quorumPercentage: DEFAULT_POC_QUORUM, approvalThreshold: DEFAULT_POC_APPROVAL});

        categoryThresholds[DataTypes.VotingCategory.Financial] = DataTypes.VotingThresholds({
            quorumPercentage: DEFAULT_FINANCIAL_QUORUM, approvalThreshold: DEFAULT_FINANCIAL_APPROVAL
        });

        categoryThresholds[DataTypes.VotingCategory.Other] = DataTypes.VotingThresholds({
            quorumPercentage: DEFAULT_OTHER_QUORUM, approvalThreshold: DEFAULT_OTHER_APPROVAL
        });
    }

    // ============================================
    // PROPOSAL MANAGEMENT
    // ============================================

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
        // Check if sender is admin, creator, or board member (>= 10 shares)
        bool isAdminUser = msg.sender == admin;
        bool isCreator = msg.sender == dao.creator();
        uint256 vaultId = dao.addressToVaultId(msg.sender);

        if (vaultId > 0) {
            (,,, uint256 shares,) = dao.vaults(vaultId);
            // Board members need >= 10 shares to create proposals
            uint256 minShares = dao.BOARD_MEMBER_MIN_SHARES();
            require(isAdminUser || isCreator || shares >= minShares, InsufficientSharesToCreateProposal());
        } else {
            require(isAdminUser || isCreator, NotAuthorizedToCreateProposal());
        }

        // Validate target
        require(targetContract != address(0), InvalidTarget());

        // Auto-detect voting category based on target contract
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

        // Get voter's vault
        uint256 vaultId = dao.addressToVaultId(msg.sender);
        require(vaultId > 0, NoVaultFound());
        (address primary,,, uint256 shares, uint256 votingPausedUntil) = dao.vaults(vaultId);
        require(shares > 0, NoVotingPower());
        require(primary == msg.sender, OnlyPrimaryCanVote());
        require(block.timestamp >= votingPausedUntil, VotingIsPaused());
        require(!hasVotedMapping[proposalId][vaultId], AlreadyVoted());

        uint256 votingPower = shares;
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
    /// @dev Only admin or creator can execute proposals
    /// @param proposalId Proposal ID
    function execute(uint256 proposalId) external proposalExists(proposalId) {
        // Only admin or creator can execute proposals
        require(msg.sender == admin || msg.sender == dao.creator(), OnlyAdminOrCreatorCanExecute());

        DataTypes.ProposalCore storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.endTime, VotingNotEnded());
        require(!proposal.executed, AlreadyExecuted());

        DataTypes.ProposalStatus status = getProposalStatus(proposalId);
        require(status == DataTypes.ProposalStatus.Active, ProposalNotSuccessful());

        proposal.executed = true;

        // Execute the call through DAO
        dao.executeProposal(proposal.targetContract, proposal.callData);

        emit ProposalExecuted(proposalId);
    }

    // ============================================
    // ADMIN FUNCTIONS
    // ============================================

    /// @notice Update voting parameters
    /// @param _votingPeriod New voting period
    /// @param _quorumPercentage New quorum percentage
    /// @param _approvalThreshold New approval threshold
    function setVotingParameters(uint256 _votingPeriod, uint256 _quorumPercentage, uint256 _approvalThreshold)
        external
        onlyAdmin
    {
        require(_votingPeriod > 0, InvalidVotingPeriod());
        require(_quorumPercentage > 0 && _quorumPercentage <= 100, InvalidQuorum());
        require(_approvalThreshold > 0 && _approvalThreshold <= 100, InvalidThreshold());

        votingPeriod = _votingPeriod;
        quorumPercentage = _quorumPercentage;
        approvalThreshold = _approvalThreshold;

        emit VotingParametersUpdated(_votingPeriod, _quorumPercentage, _approvalThreshold);
    }

    /// @notice Transfer admin role
    /// @param newAdmin New admin address
    function transferAdmin(address newAdmin) external onlyAdmin {
        require(newAdmin != address(0), InvalidAddress());
        admin = newAdmin;
    }

    // ============================================
    // VIEW FUNCTIONS
    // ============================================

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

        // Handle Unanimous proposals specially
        if (proposal.proposalType == DataTypes.ProposalType.Unanimous) {
            // Any vote against defeats it immediately
            if (proposal.againstVotes > 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            // If voting period hasn't ended yet, check if we have unanimous agreement
            if (block.timestamp < proposal.endTime) {
                // If all shares have voted "for", it can be executed early
                if (proposal.forVotes >= totalShares) {
                    return DataTypes.ProposalStatus.Active; // Passed, ready to execute
                }
                return DataTypes.ProposalStatus.Active; // Still voting
            }

            // Voting ended - need 100% of all shares to vote "for"
            if (proposal.forVotes < totalShares) {
                return DataTypes.ProposalStatus.Defeated; // Not everyone voted for
            }

            // Check if expired (30 days after voting ended)
            if (block.timestamp > proposal.endTime + 30 days) {
                return DataTypes.ProposalStatus.Expired;
            }

            return DataTypes.ProposalStatus.Active; // Unanimously passed, ready to execute
        }

        // Regular proposals
        if (block.timestamp < proposal.endTime) {
            return DataTypes.ProposalStatus.Active;
        }

        // Voting ended, check if passed using category-specific thresholds
        uint256 totalVotes = proposal.forVotes + proposal.againstVotes;

        // Get thresholds for this proposal's category
        DataTypes.VotingThresholds memory thresholds = categoryThresholds[proposal.votingCategory];

        // Check quorum (minimum participation rate)
        if (totalVotes * 100 < totalShares * thresholds.quorumPercentage) {
            return DataTypes.ProposalStatus.Defeated;
        }

        // Check approval threshold (minimum approval rate)
        if (proposal.forVotes * 100 < totalVotes * thresholds.approvalThreshold) {
            return DataTypes.ProposalStatus.Defeated;
        }

        // Check if expired (e.g., 30 days after voting ended)
        if (block.timestamp > proposal.endTime + 30 days) {
            return DataTypes.ProposalStatus.Expired;
        }

        return DataTypes.ProposalStatus.Active; // Passed but not executed yet
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

    // ============================================
    // INTERNAL FUNCTIONS
    // ============================================

    /// @notice Determine voting category based on target contract
    /// @dev Categories: Governance (DAO itself), POC (POC contracts), Financial (tokens), Other
    /// @param targetContract Target contract address
    /// @return Voting category for the target
    function _determineCategory(address targetContract) internal view returns (DataTypes.VotingCategory) {
        // Governance: calls to DAO contract itself (settings changes)
        if (targetContract == address(dao)) {
            return DataTypes.VotingCategory.Governance;
        }

        // POC: calls to POC contracts (external management)
        if (_isPOCContract(targetContract)) {
            return DataTypes.VotingCategory.POC;
        }

        // Financial: calls to token contracts (launch token, reward tokens, LP tokens)
        if (_isTokenContract(targetContract)) {
            return DataTypes.VotingCategory.Financial;
        }

        // Other: all other external calls
        return DataTypes.VotingCategory.Other;
    }

    /// @notice Check if address is a registered POC contract
    /// @param target Address to check
    /// @return True if target is a POC contract
    function _isPOCContract(address target) internal view returns (bool) {
        uint256 pocIdx = dao.pocIndex(target);
        return pocIdx > 0; // pocIndex stores index + 1, so 0 means not found
    }

    /// @notice Check if address is a known token contract (launch, reward, or LP token)
    /// @param target Address to check
    /// @return True if target is a token contract
    function _isTokenContract(address target) internal view returns (bool) {
        // Check if it's the launch token
        if (target == address(dao.launchToken())) {
            return true;
        }

        // Check if it's an LP token
        if (dao.isLPToken(target)) {
            return true;
        }

        // Check if it's the main collateral token
        if (target == dao.mainCollateral()) {
            return true;
        }

        // Check if it's a sellable collateral (reward tokens are now sellable collaterals)
        (,, bool isActive) = dao.sellableCollaterals(target);
        if (isActive) {
            return true;
        }

        return false;
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
}

