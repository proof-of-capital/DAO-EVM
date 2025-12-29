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
    error VotingNotAllowedInClosing();
    error TokenContractProposalNotAllowed();
    error VaultInExitQueue();
    error ProposalCreationCooldown();

    // State variables
    IDAO public immutable dao;

    uint256 public votingPeriod;
    uint256 public quorumPercentage;
    uint256 public approvalThreshold;
    mapping(DataTypes.ProposalType => DataTypes.VotingThresholds) public categoryThresholds;

    uint256 public nextProposalId;

    mapping(uint256 => DataTypes.ProposalCore) public proposals;
    mapping(uint256 => mapping(uint256 => bool)) public hasVotedMapping;
    mapping(uint256 => mapping(uint256 => uint256)) public proposalVotesByVault;
    mapping(uint256 => mapping(uint256 => bool)) public proposalVoteDirection;
    mapping(uint256 => uint256) public lastProposalCreationTimeByVault;
    uint256 public lastAdminProposalCreationTime;
    uint256 public lastCreatorProposalCreationTime;

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

        categoryThresholds[DataTypes.ProposalType.Governance] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_GOVERNANCE_QUORUM,
            approvalThreshold: Constants.DEFAULT_GOVERNANCE_APPROVAL
        });

        categoryThresholds[DataTypes.ProposalType.POC] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_POC_QUORUM, approvalThreshold: Constants.DEFAULT_POC_APPROVAL
        });

        categoryThresholds[DataTypes.ProposalType.Financial] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_FINANCIAL_QUORUM,
            approvalThreshold: Constants.DEFAULT_FINANCIAL_APPROVAL
        });

        categoryThresholds[DataTypes.ProposalType.Other] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_OTHER_QUORUM, approvalThreshold: Constants.DEFAULT_OTHER_APPROVAL
        });
    }

    /// @notice Create a new proposal
    /// @dev Only admin, creator, or board members (>= 10 shares) can create proposals
    /// @dev Proposal type is auto-detected based on target contract and call data
    /// @dev Each address can create only one proposal per day
    /// @param targetContract Target contract for the call
    /// @param callData Encoded call data
    /// @return proposalId ID of created proposal
    function createProposal(address targetContract, bytes calldata callData) external returns (uint256 proposalId) {
        bool isAdminUser = msg.sender == dao.admin();
        bool isCreator = msg.sender == dao.creator();
        uint256 vaultId = dao.addressToVaultId(msg.sender);

        if (vaultId > 0) {
            DataTypes.Vault memory vault = dao.vaults(vaultId);
            require(
                isAdminUser || isCreator || vault.shares >= Constants.BOARD_MEMBER_MIN_SHARES,
                InsufficientSharesToCreateProposal()
            );
            require(
                block.timestamp >= lastProposalCreationTimeByVault[vaultId] + Constants.PROPOSAL_CREATION_COOLDOWN,
                ProposalCreationCooldown()
            );
        } else {
            require(isAdminUser || isCreator, NotAuthorizedToCreateProposal());
            if (isAdminUser) {
                require(
                    block.timestamp >= lastAdminProposalCreationTime + Constants.PROPOSAL_CREATION_COOLDOWN,
                    ProposalCreationCooldown()
                );
            } else {
                require(
                    block.timestamp >= lastCreatorProposalCreationTime + Constants.PROPOSAL_CREATION_COOLDOWN,
                    ProposalCreationCooldown()
                );
            }
        }

        require(targetContract != address(0), InvalidTarget());

        require(!_isTokenContract(targetContract), TokenContractProposalNotAllowed());

        DataTypes.ProposalType proposalType = _determineProposalType(targetContract, callData);
        require(proposalType != DataTypes.ProposalType.Financial, TokenContractProposalNotAllowed());

        proposalId = nextProposalId++;

        proposals[proposalId] = DataTypes.ProposalCore({
            id: proposalId,
            proposer: msg.sender,
            proposalType: proposalType,
            callData: callData,
            targetContract: targetContract,
            forVotes: 0,
            againstVotes: 0,
            startTime: block.timestamp,
            endTime: block.timestamp + votingPeriod,
            executed: false
        });

        if (vaultId > 0) {
            lastProposalCreationTimeByVault[vaultId] = block.timestamp;
        } else {
            if (isAdminUser) {
                lastAdminProposalCreationTime = block.timestamp;
            } else {
                lastCreatorProposalCreationTime = block.timestamp;
            }
        }

        emit ProposalCreated(proposalId, msg.sender, proposalType, targetContract, callData);
        emit ProposalCategoryDetected(proposalId, proposalType);
    }

    /// @notice Vote on a proposal
    /// @param proposalId Proposal ID
    /// @param support True for yes, false for no
    function vote(uint256 proposalId, bool support) external proposalExists(proposalId) {
        DataTypes.ProposalCore storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.startTime, VotingNotStarted());
        require(block.timestamp < proposal.endTime, VotingEnded());
        require(!proposal.executed, ProposalAlreadyExecuted());

        DataTypes.DAOState memory daoState = dao.daoState();
        require(daoState.currentStage != DataTypes.Stage.Closing, VotingNotAllowedInClosing());

        uint256 vaultId = dao.addressToVaultId(msg.sender);
        require(vaultId > 0, NoVaultFound());
        DataTypes.Vault memory vault = dao.vaults(vaultId);
        require(vault.shares > 0, NoVotingPower());
        require(vault.primary == msg.sender, OnlyPrimaryCanVote());
        require(block.timestamp >= vault.votingPausedUntil, VotingIsPaused());
        require(!hasVotedMapping[proposalId][vaultId], AlreadyVoted());

        require(!dao.isVaultInExitQueue(vaultId), VaultInExitQueue());

        uint256 votingPower = vault.votingShares;
        require(votingPower > 0, NoVotingPower());

        hasVotedMapping[proposalId][vaultId] = true;
        proposalVotesByVault[proposalId][vaultId] = votingPower;
        proposalVoteDirection[proposalId][vaultId] = support;

        if (support) {
            proposal.forVotes += votingPower;
        } else {
            proposal.againstVotes += votingPower;
        }

        emit VoteCast(proposalId, vaultId, support, votingPower);
    }

    /// @notice Update votes for a vault when its voting shares change
    /// @dev Only callable by DAO contract
    /// @param vaultId Vault ID whose voting shares changed
    /// @param votingSharesDelta Change in voting shares (positive for increase, negative for decrease)
    function updateVotesForVault(uint256 vaultId, int256 votingSharesDelta) external onlyDAO {
        if (votingSharesDelta == 0) {
            return;
        }

        for (uint256 proposalId = 0; proposalId < nextProposalId; proposalId++) {
            DataTypes.ProposalCore storage proposal = proposals[proposalId];

            if (block.timestamp >= proposal.endTime || proposal.executed) {
                continue;
            }

            uint256 currentVotes = proposalVotesByVault[proposalId][vaultId];
            if (currentVotes == 0) {
                continue;
            }

            bool support = proposalVoteDirection[proposalId][vaultId];
            uint256 voteChange;

            if (votingSharesDelta > 0) {
                voteChange = uint256(votingSharesDelta);
                proposalVotesByVault[proposalId][vaultId] = currentVotes + voteChange;
            } else {
                voteChange = uint256(-votingSharesDelta);
                if (voteChange > currentVotes) {
                    voteChange = currentVotes;
                }
                proposalVotesByVault[proposalId][vaultId] = currentVotes - voteChange;
            }

            if (support) {
                if (votingSharesDelta > 0) {
                    proposal.forVotes += voteChange;
                } else {
                    if (proposal.forVotes >= voteChange) {
                        proposal.forVotes -= voteChange;
                    } else {
                        proposal.forVotes = 0;
                    }
                }
            } else {
                if (votingSharesDelta > 0) {
                    proposal.againstVotes += voteChange;
                } else {
                    if (proposal.againstVotes >= voteChange) {
                        proposal.againstVotes -= voteChange;
                    } else {
                        proposal.againstVotes = 0;
                    }
                }
            }
        }
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
    /// @dev Different proposal types have different voting rules
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

        uint256 adjustedForVotes = proposal.forVotes;
        uint256 adjustedAgainstVotes = proposal.againstVotes;
        uint256 adjustedTotalShares = totalShares + exitQueueShares;

        if (proposal.proposalType == DataTypes.ProposalType.Veto) {
            adjustedForVotes += exitQueueShares;
        } else {
            adjustedAgainstVotes += exitQueueShares;
        }

        if (proposal.proposalType == DataTypes.ProposalType.Veto) {
            if (block.timestamp < proposal.endTime) {
                uint256 earlyTotalVotes = adjustedForVotes + adjustedAgainstVotes;
                uint256 earlyQuorumRequired =
                    (adjustedTotalShares * Constants.VETO_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

                if (earlyTotalVotes >= earlyQuorumRequired && earlyTotalVotes > 0) {
                    uint256 earlyApprovalRequired =
                        (earlyTotalVotes * Constants.VETO_APPROVAL) / Constants.PERCENTAGE_MULTIPLIER;
                    if (adjustedForVotes >= earlyApprovalRequired) {
                        return DataTypes.ProposalStatus.Active;
                    }
                }
                return DataTypes.ProposalStatus.Active;
            }

            uint256 vetoTotalVotes = adjustedForVotes + adjustedAgainstVotes;
            uint256 vetoQuorumRequired = (adjustedTotalShares * Constants.VETO_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

            if (vetoTotalVotes < vetoQuorumRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (vetoTotalVotes == 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            uint256 vetoApprovalRequired = (vetoTotalVotes * Constants.VETO_APPROVAL) / Constants.PERCENTAGE_MULTIPLIER;
            if (adjustedForVotes < vetoApprovalRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (block.timestamp > proposal.endTime + Constants.PROPOSAL_EXPIRY_PERIOD) {
                return DataTypes.ProposalStatus.Expired;
            }

            return DataTypes.ProposalStatus.Active;
        }

        if (proposal.proposalType == DataTypes.ProposalType.Arbitrary) {
            if (block.timestamp < proposal.endTime) {
                uint256 earlyTotalVotes = adjustedForVotes + adjustedAgainstVotes;
                uint256 earlyRejectThreshold = (adjustedTotalShares * Constants.ARBITRARY_EARLY_REJECT_THRESHOLD)
                    / Constants.PERCENTAGE_MULTIPLIER;

                if (adjustedAgainstVotes > earlyRejectThreshold) {
                    return DataTypes.ProposalStatus.Defeated;
                }

                uint256 earlyQuorumRequired =
                    (adjustedTotalShares * Constants.ARBITRARY_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;
                if (earlyTotalVotes >= earlyQuorumRequired && earlyTotalVotes > 0) {
                    uint256 earlyApprovalRequired =
                        (earlyTotalVotes * Constants.ARBITRARY_APPROVAL) / Constants.PERCENTAGE_MULTIPLIER;
                    if (adjustedForVotes >= earlyApprovalRequired) {
                        return DataTypes.ProposalStatus.Active;
                    }
                }
                return DataTypes.ProposalStatus.Active;
            }

            uint256 arbitraryTotalVotes = adjustedForVotes + adjustedAgainstVotes;
            uint256 arbitraryQuorumRequired =
                (adjustedTotalShares * Constants.ARBITRARY_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

            if (arbitraryTotalVotes < arbitraryQuorumRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (arbitraryTotalVotes == 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            uint256 arbitraryApprovalRequired =
                (arbitraryTotalVotes * Constants.ARBITRARY_APPROVAL) / Constants.PERCENTAGE_MULTIPLIER;
            if (adjustedForVotes < arbitraryApprovalRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (block.timestamp > proposal.endTime + Constants.PROPOSAL_EXPIRY_PERIOD) {
                return DataTypes.ProposalStatus.Expired;
            }

            return DataTypes.ProposalStatus.Active;
        }

        if (proposal.proposalType == DataTypes.ProposalType.Unanimous) {
            if (block.timestamp < proposal.endTime) {
                uint256 earlyRejectThreshold = (adjustedTotalShares * Constants.UNANIMOUS_EARLY_REJECT_THRESHOLD)
                    / Constants.PERCENTAGE_MULTIPLIER;

                if (adjustedAgainstVotes > earlyRejectThreshold) {
                    return DataTypes.ProposalStatus.Defeated;
                }

                uint256 earlyTotalVotes = adjustedForVotes + adjustedAgainstVotes;
                uint256 earlyQuorumRequired =
                    (adjustedTotalShares * Constants.UNANIMOUS_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

                if (earlyTotalVotes >= earlyQuorumRequired && earlyTotalVotes > 0) {
                    uint256 earlyApprovalRequired =
                        (earlyTotalVotes * Constants.UNANIMOUS_APPROVAL) / Constants.PERCENTAGE_MULTIPLIER;
                    if (adjustedForVotes >= earlyApprovalRequired) {
                        return DataTypes.ProposalStatus.Active;
                    }
                }
                return DataTypes.ProposalStatus.Active;
            }

            if (adjustedAgainstVotes > 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            uint256 unanimousTotalVotes = adjustedForVotes + adjustedAgainstVotes;
            uint256 unanimousQuorumRequired =
                (adjustedTotalShares * Constants.UNANIMOUS_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

            if (unanimousTotalVotes < unanimousQuorumRequired) {
                return DataTypes.ProposalStatus.Defeated;
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

        DataTypes.VotingThresholds memory thresholds = categoryThresholds[proposal.proposalType];

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

    /// @notice Get voting thresholds for a specific proposal type
    /// @param proposalType Proposal type
    /// @return quorumPct Quorum percentage (participation rate)
    /// @return approvalPct Approval threshold (approval rate)
    function getCategoryThresholds(DataTypes.ProposalType proposalType)
        external
        view
        returns (uint256 quorumPct, uint256 approvalPct)
    {
        DataTypes.VotingThresholds memory thresholds = categoryThresholds[proposalType];
        return (thresholds.quorumPercentage, thresholds.approvalThreshold);
    }

    /// @notice Get proposal's type
    /// @param proposalId Proposal ID
    /// @return Proposal type
    function getProposalCategory(uint256 proposalId)
        external
        view
        proposalExists(proposalId)
        returns (DataTypes.ProposalType)
    {
        return proposals[proposalId].proposalType;
    }

    /// @notice Determine what proposal type a target contract and call data would result in
    /// @param targetContract Target contract address to check
    /// @param callData Encoded call data
    /// @return Proposal type for the target
    function determineCategory(address targetContract, bytes calldata callData)
        external
        view
        returns (DataTypes.ProposalType)
    {
        return _determineProposalType(targetContract, callData);
    }

    /// @notice Determine proposal type based on target contract and call data
    /// @dev Types: Governance (DAO itself), POC (POC contracts), Financial (tokens - forbidden), Other, Veto, Arbitrary, Unanimous (upgrades)
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return Proposal type
    function _determineProposalType(address targetContract, bytes memory callData)
        internal
        view
        returns (DataTypes.ProposalType)
    {
        if (_isVetoProposal(targetContract, callData)) {
            return DataTypes.ProposalType.Veto;
        }

        if (_isUnanimousProposal(targetContract, callData)) {
            return DataTypes.ProposalType.Unanimous;
        }

        if (targetContract == address(dao)) {
            return DataTypes.ProposalType.Governance;
        }

        if (_isPOCContract(targetContract)) {
            return DataTypes.ProposalType.POC;
        }

        if (_isTokenContract(targetContract)) {
            return DataTypes.ProposalType.Financial;
        }

        return DataTypes.ProposalType.Other;
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
        for (uint256 i = 4; i < callData.length; ++i) {
            data[i - 4] = callData[i];
        }

        (bool value) = abi.decode(data, (bool));
        return value;
    }

    /// @notice Check if proposal is an unanimous proposal (calls setPendingUpgradeFromVoting)
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return True if proposal calls setPendingUpgradeFromVoting on DAO contract
    function _isUnanimousProposal(address targetContract, bytes memory callData) internal view returns (bool) {
        if (targetContract != address(dao)) {
            return false;
        }

        bytes4 setPendingUpgradeFromVotingSelector = IDAO.setPendingUpgradeFromVoting.selector;

        if (callData.length < 4) {
            return false;
        }

        bytes4 selector = bytes4(callData);
        return selector == setPendingUpgradeFromVotingSelector;
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

