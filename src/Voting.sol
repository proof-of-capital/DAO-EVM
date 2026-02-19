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

import "./interfaces/IVoting.sol";
import "./interfaces/IDAO.sol";
import "./libraries/DataTypes.sol";
import "./libraries/Constants.sol";

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
    error DAONotInActiveStage();
    error TokenContractProposalNotAllowed();
    error TargetAddressNotAllowedForInteraction();
    error VaultInExitQueue();
    error ProposalCreationCooldown();
    error CallDataHashMismatch();

    // State variables
    IDAO public dao;
    address public immutable deployer;

    uint256 public votingPeriod;
    uint256 public quorumPercentage;
    uint256 public approvalThreshold;
    mapping(DataTypes.ProposalType => DataTypes.VotingThresholds) public categoryThresholds;

    uint256 public nextProposalId;
    uint256 public lastProcessedProposalId;

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

    constructor() {
        deployer = msg.sender;

        votingPeriod = Constants.DEFAULT_VOTING_PERIOD;
        quorumPercentage = Constants.DEFAULT_QUORUM_PERCENTAGE;
        approvalThreshold = Constants.DEFAULT_APPROVAL_THRESHOLD;

        categoryThresholds[DataTypes.ProposalType.Financial] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_FINANCIAL_QUORUM,
            approvalThreshold: Constants.DEFAULT_FINANCIAL_APPROVAL
        });

        categoryThresholds[DataTypes.ProposalType.Other] = DataTypes.VotingThresholds({
            quorumPercentage: Constants.DEFAULT_FINANCIAL_QUORUM,
            approvalThreshold: Constants.DEFAULT_FINANCIAL_APPROVAL
        });
    }

    /// @notice Set DAO contract address (can only be called once by deployer)
    /// @param _dao DAO contract address
    function setDAO(address _dao) external {
        require(msg.sender == deployer, NotAdmin());
        require(_dao != address(0), InvalidDAOAddress());
        require(address(dao) == address(0), InvalidAddress());

        dao = IDAO(_dao);
    }

    /// @notice Create a new proposal
    /// @dev Only admin, creator, or board members (>= 10 shares) can create proposals
    /// @dev Proposal type is auto-detected based on target contract and call data
    /// @dev Each address can create only one proposal per day
    /// @param targetContract Target contract for the call
    /// @param callData Encoded call data
    /// @return proposalId ID of created proposal
    function createProposal(address targetContract, bytes calldata callData) external returns (uint256 proposalId) {
        DataTypes.DAOState memory daoState = dao.getDaoState();
        require(daoState.currentStage == DataTypes.Stage.Active, DAONotInActiveStage());

        bool isAdminUser = msg.sender == dao.coreConfig().admin;
        bool isCreator = msg.sender == dao.coreConfig().creator;
        uint256 vaultId = dao.addressToVaultId(msg.sender);

        if (vaultId > 0) {
            DataTypes.Vault memory vault = dao.vaults(vaultId);
            require(
                isAdminUser || isCreator || vault.votingShares >= Constants.BOARD_MEMBER_MIN_SHARES,
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

        proposalId = nextProposalId++;

        bytes32 callDataHash = _computeCallDataHash(targetContract, callData, proposalId);

        proposals[proposalId] = DataTypes.ProposalCore({
            id: proposalId,
            proposer: msg.sender,
            proposalType: proposalType,
            callDataHash: callDataHash,
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

        DataTypes.DAOState memory daoState = dao.getDaoState();
        require(daoState.currentStage == DataTypes.Stage.Active, DAONotInActiveStage());

        uint256 vaultId = dao.addressToVaultId(msg.sender);
        require(vaultId > 0, NoVaultFound());
        DataTypes.Vault memory vault = dao.vaults(vaultId);
        require(vault.shares > 0, NoVotingPower());
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

    /// @notice Update votes for a vault in a specific proposal
    /// @param proposalId Proposal ID
    /// @param vaultId Vault ID
    /// @param voteChange Change in votes (positive for increase, negative for decrease)
    /// @param support Vote direction (true for for, false for against)
    function _updateVotesInProposal(uint256 proposalId, uint256 vaultId, int256 voteChange, bool support) internal {
        if (voteChange == 0) {
            return;
        }

        DataTypes.ProposalCore storage proposal = proposals[proposalId];
        uint256 currentVotes = proposalVotesByVault[proposalId][vaultId];
        if (currentVotes == 0 && voteChange < 0) {
            return;
        }

        uint256 voteChangeAbs;
        if (voteChange > 0) {
            voteChangeAbs = uint256(voteChange);
            proposalVotesByVault[proposalId][vaultId] = currentVotes + voteChangeAbs;
        } else {
            voteChangeAbs = uint256(-voteChange);
            if (voteChangeAbs > currentVotes) {
                voteChangeAbs = currentVotes;
            }
            proposalVotesByVault[proposalId][vaultId] = currentVotes - voteChangeAbs;
        }

        if (support) {
            if (voteChange > 0) {
                proposal.forVotes += voteChangeAbs;
            } else {
                if (proposal.forVotes >= voteChangeAbs) {
                    proposal.forVotes -= voteChangeAbs;
                } else {
                    proposal.forVotes = 0;
                }
            }
        } else {
            if (voteChange > 0) {
                proposal.againstVotes += voteChangeAbs;
            } else {
                if (proposal.againstVotes >= voteChangeAbs) {
                    proposal.againstVotes -= voteChangeAbs;
                } else {
                    proposal.againstVotes = 0;
                }
            }
        }
    }

    /// @notice Update votes for a vault when its voting shares change
    /// @dev Only callable by DAO contract
    /// @param vaultId Vault ID whose voting shares changed
    /// @param votingSharesDelta Change in voting shares (positive for increase, negative for decrease)
    function updateVotesForVault(uint256 vaultId, int256 votingSharesDelta) external onlyDAO {
        if (votingSharesDelta == 0) {
            return;
        }

        for (uint256 proposalId = lastProcessedProposalId; proposalId < nextProposalId; proposalId++) {
            DataTypes.ProposalCore storage proposal = proposals[proposalId];

            if (block.timestamp >= proposal.endTime || proposal.executed) {
                lastProcessedProposalId = proposalId + 1;
                continue;
            }

            uint256 currentVotes = proposalVotesByVault[proposalId][vaultId];
            if (currentVotes == 0) {
                continue;
            }

            bool support = proposalVoteDirection[proposalId][vaultId];
            _updateVotesInProposal(proposalId, vaultId, votingSharesDelta, support);
        }
    }

    /// @notice Set delegate address for voting
    /// @dev Only callable by vault primary owner
    /// @dev Transfers votes from old delegate to new delegate in active proposals
    /// @param delegate New delegate address (if zero, self-delegation)
    function setDelegate(address delegate) external {
        DataTypes.DAOState memory daoState = dao.getDaoState();
        require(daoState.currentStage == DataTypes.Stage.Active, DAONotInActiveStage());

        uint256 vaultId = dao.addressToVaultId(msg.sender);
        require(vaultId > 0, NoVaultFound());

        DataTypes.Vault memory vault = dao.vaults(vaultId);
        require(vault.shares > 0, NoVotingPower());
        require(!dao.isVaultInExitQueue(vaultId), VaultInExitQueue());

        uint256 oldDelegateId = vault.delegateId;
        uint256 newDelegateId = delegate == address(0) ? 0 : dao.addressToVaultId(delegate);
        uint256 vaultShares = vault.shares;

        if (oldDelegateId != newDelegateId && oldDelegateId != 0 && oldDelegateId != vaultId) {
            _transferVotesFromDelegate(oldDelegateId, newDelegateId, vaultShares, vaultId);
        }

        dao.setDelegate(msg.sender, delegate);
    }

    /// @notice Transfer votes from old delegate to new delegate in active proposals
    /// @param oldDelegateId Old delegate vault ID
    /// @param newDelegateId New delegate vault ID
    /// @param vaultShares Shares amount to transfer
    /// @param delegatorVaultId Vault ID that is delegating
    function _transferVotesFromDelegate(
        uint256 oldDelegateId,
        uint256 newDelegateId,
        uint256 vaultShares,
        uint256 delegatorVaultId
    ) internal {
        for (uint256 proposalId = lastProcessedProposalId; proposalId < nextProposalId; proposalId++) {
            DataTypes.ProposalCore storage proposal = proposals[proposalId];

            if (block.timestamp >= proposal.endTime || proposal.executed) {
                lastProcessedProposalId = proposalId + 1;
                continue;
            }

            if (!hasVotedMapping[proposalId][oldDelegateId]) {
                continue;
            }

            uint256 oldDelegateVotes = proposalVotesByVault[proposalId][oldDelegateId];
            if (oldDelegateVotes == 0) {
                continue;
            }

            bool support = proposalVoteDirection[proposalId][oldDelegateId];
            uint256 votesToTransfer = vaultShares;
            if (votesToTransfer > oldDelegateVotes) {
                votesToTransfer = oldDelegateVotes;
            }

            _updateVotesInProposal(proposalId, oldDelegateId, -int256(votesToTransfer), support);

            if (newDelegateId != 0 && newDelegateId != delegatorVaultId) {
                if (hasVotedMapping[proposalId][newDelegateId]) {
                    bool newDelegateSupport = proposalVoteDirection[proposalId][newDelegateId];
                    if (newDelegateSupport == support) {
                        _updateVotesInProposal(proposalId, newDelegateId, int256(votesToTransfer), support);
                    } else {
                        uint256 newDelegateVotes = proposalVotesByVault[proposalId][newDelegateId];
                        uint256 votesToRemove = votesToTransfer;
                        if (votesToRemove > newDelegateVotes) {
                            votesToRemove = newDelegateVotes;
                        }

                        if (votesToRemove > 0) {
                            _updateVotesInProposal(
                                proposalId, newDelegateId, -int256(votesToRemove), newDelegateSupport
                            );
                        }

                        proposalVotesByVault[proposalId][newDelegateId] += votesToTransfer;
                        proposalVoteDirection[proposalId][newDelegateId] = support;
                        if (support) {
                            proposal.forVotes += votesToTransfer;
                        } else {
                            proposal.againstVotes += votesToTransfer;
                        }
                    }
                }
            }
        }
    }

    /// @notice Execute a successful proposal
    /// @dev Only admin, creator, or participant can execute proposals
    /// @param proposalId Proposal ID
    /// @param callData Encoded call data for execution
    function execute(uint256 proposalId, bytes calldata callData)
        external
        proposalExists(proposalId)
        onlyAdminOrCreatorOrParticipant
    {
        DataTypes.ProposalCore storage proposal = proposals[proposalId];

        require(block.timestamp >= proposal.endTime, VotingNotEnded());
        require(!proposal.executed, AlreadyExecuted());

        DataTypes.ProposalStatus status = getProposalStatus(proposalId);
        require(status == DataTypes.ProposalStatus.Active, ProposalNotSuccessful());

        bytes32 computedHash = _computeCallDataHash(proposal.targetContract, callData, proposalId);
        require(proposal.callDataHash == computedHash, CallDataHashMismatch());

        proposal.executed = true;

        dao.executeProposal(proposal.targetContract, callData);

        emit ProposalExecuted(proposalId);
    }

    /// @notice Get proposal status
    /// @dev Different proposal types have different voting rules
    /// @dev Exit queue shares are counted: for veto proposals (VetoFor/VetoAgainst) they go to forVotes, for others to againstVotes
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
        uint256 exitQueueShares = dao.getDaoState().totalExitQueueShares;

        uint256 adjustedForVotes = proposal.forVotes;
        uint256 adjustedAgainstVotes = proposal.againstVotes;

        if (proposal.proposalType == DataTypes.ProposalType.VetoFor) {
            adjustedForVotes += exitQueueShares;
        } else {
            adjustedAgainstVotes += exitQueueShares;
        }

        if (proposal.proposalType == DataTypes.ProposalType.VetoFor) {
            if (block.timestamp < proposal.endTime) {
                uint256 earlyTotalVotes = adjustedForVotes + adjustedAgainstVotes;
                uint256 earlyQuorumRequired = (totalShares * Constants.VETO_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

                if (earlyTotalVotes >= earlyQuorumRequired && earlyTotalVotes > 0) {
                    uint256 earlyApprovalRequired = (earlyTotalVotes * dao.getVetoThreshold()) / Constants.BASIS_POINTS;
                    if (adjustedForVotes >= earlyApprovalRequired) {
                        return DataTypes.ProposalStatus.Active;
                    }
                }
            }

            uint256 vetoTotalVotes = adjustedForVotes + adjustedAgainstVotes;
            uint256 vetoQuorumRequired = (totalShares * Constants.VETO_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

            if (vetoTotalVotes < vetoQuorumRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (vetoTotalVotes == 0) {
                return DataTypes.ProposalStatus.Defeated;
            }

            uint256 vetoApprovalRequired = (vetoTotalVotes * dao.getVetoThreshold()) / Constants.BASIS_POINTS;
            if (adjustedForVotes < vetoApprovalRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (block.timestamp > proposal.endTime + Constants.PROPOSAL_EXPIRY_PERIOD) {
                return DataTypes.ProposalStatus.Expired;
            }

            return DataTypes.ProposalStatus.Active;
        }

        if (proposal.proposalType == DataTypes.ProposalType.Unanimous) {
            if (block.timestamp < proposal.endTime) {
                uint256 earlyRejectThreshold =
                    (totalShares * Constants.UNANIMOUS_EARLY_REJECT_THRESHOLD) / Constants.PERCENTAGE_MULTIPLIER;

                if (adjustedAgainstVotes > earlyRejectThreshold) {
                    return DataTypes.ProposalStatus.Defeated;
                }

                uint256 earlyTotalVotes = adjustedForVotes + adjustedAgainstVotes;
                uint256 earlyQuorumRequired =
                    (totalShares * Constants.UNANIMOUS_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

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
                (totalShares * Constants.UNANIMOUS_QUORUM) / Constants.PERCENTAGE_MULTIPLIER;

            if (unanimousTotalVotes < unanimousQuorumRequired) {
                return DataTypes.ProposalStatus.Defeated;
            }

            if (adjustedForVotes < totalShares) {
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

        if (totalVotes * Constants.PERCENTAGE_MULTIPLIER < totalShares * thresholds.quorumPercentage) {
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
    /// @dev Types: Financial (loans to creator, returns to POC), Other, VetoFor/VetoAgainst, Unanimous (upgrades, POC changes)
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return Proposal type
    function _determineProposalType(address targetContract, bytes calldata callData)
        internal
        view
        returns (DataTypes.ProposalType)
    {
        DataTypes.ProposalType vetoType = _getVetoProposalType(targetContract, callData);
        if (vetoType == DataTypes.ProposalType.VetoFor || vetoType == DataTypes.ProposalType.VetoAgainst) {
            return vetoType;
        }

        if (_isUnanimousProposal(targetContract, callData)) {
            return DataTypes.ProposalType.Unanimous;
        }

        if (targetContract == address(dao)) {
            if (_isFinancialProposal(callData)) {
                return DataTypes.ProposalType.Financial;
            }
        }

        if (_isPOCContract(targetContract)) {
            return DataTypes.ProposalType.Unanimous;
        }

        require(!_isTokenContract(targetContract), TargetAddressNotAllowedForInteraction());

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
        if (dao.isV2LPToken(target)) {
            return true;
        }
        DataTypes.RewardTokenInfo memory rewardInfo = dao.rewardTokenInfo(target);
        if (rewardInfo.active) {
            return true;
        }

        return false;
    }

    /// @notice Get veto proposal type (calls setIsVetoToCreator)
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return ProposalType.VetoFor if setIsVetoToCreator(true), ProposalType.VetoAgainst if setIsVetoToCreator(false), or Other if not a veto proposal
    function _getVetoProposalType(address targetContract, bytes calldata callData)
        internal
        view
        returns (DataTypes.ProposalType)
    {
        if (targetContract != address(dao)) {
            return DataTypes.ProposalType.Other;
        }

        bytes4 setIsVetoToCreatorSelector = IDAO.setIsVetoToCreator.selector;

        if (callData.length < 36) {
            return DataTypes.ProposalType.Other;
        }

        bytes4 selector = bytes4(callData);
        if (selector != setIsVetoToCreatorSelector) {
            return DataTypes.ProposalType.Other;
        }

        bytes memory data = callData[4:];

        (bool value) = abi.decode(data, (bool));
        return value ? DataTypes.ProposalType.VetoFor : DataTypes.ProposalType.VetoAgainst;
    }

    /// @notice Check if proposal is an unanimous proposal (calls setPendingUpgradeFromVoting, addPOCContract, or removePOCContract)
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @return True if proposal calls setPendingUpgradeFromVoting, addPOCContract, or removePOCContract on DAO contract
    function _isUnanimousProposal(address targetContract, bytes calldata callData) internal view returns (bool) {
        if (targetContract != address(dao)) {
            return false;
        }

        bytes4 setPendingUpgradeFromVotingSelector = IDAO.setPendingUpgradeFromVoting.selector;
        bytes4 addPOCContractSelector = IDAO.addPOCContract.selector;
        bytes4 removePOCContractSelector = IDAO.removePOCContract.selector;

        if (callData.length < 4) {
            return false;
        }

        bytes4 selector = bytes4(callData);
        return selector == setPendingUpgradeFromVotingSelector || selector == addPOCContractSelector
            || selector == removePOCContractSelector;
    }

    /// @notice Check if proposal is a financial proposal (calls takeLoanInLaunches or returnLaunchesToPOC)
    /// @param callData Encoded call data
    /// @return True if proposal calls financial functions on DAO contract
    function _isFinancialProposal(bytes calldata callData) internal pure returns (bool) {
        if (callData.length < 4) {
            return false;
        }

        bytes4 selector = bytes4(callData);
        bytes4 takeLoanInLaunchesSelector = IDAO.takeLoanInLaunches.selector;
        bytes4 returnLaunchesToPOCSelector = IDAO.returnLaunchesToPOC.selector;

        return selector == takeLoanInLaunchesSelector || selector == returnLaunchesToPOCSelector;
    }

    function _onlyAdmin() internal view {
        require(msg.sender == dao.coreConfig().admin, NotAdmin());
    }

    function _onlyDAO() internal view {
        require(msg.sender == address(dao), NotDAO());
    }

    function _proposalExists(uint256 proposalId) internal view {
        require(proposalId < nextProposalId, ProposalDoesNotExist());
    }

    function _onlyAdminOrCreatorOrParticipant() internal view {
        bool isAdminUser = msg.sender == dao.coreConfig().admin;
        bool isCreator = msg.sender == dao.coreConfig().creator;
        uint256 vaultId = dao.addressToVaultId(msg.sender);
        bool isParticipant = vaultId > 0;

        if (isParticipant) {
            DataTypes.Vault memory vault = dao.vaults(vaultId);
            isParticipant = vault.shares > 0;
        }

        require(isAdminUser || isCreator || isParticipant, OnlyAdminOrCreatorCanExecute());
    }

    /// @notice Compute hash of call data for proposal
    /// @param targetContract Target contract address
    /// @param callData Encoded call data
    /// @param proposalId Proposal ID
    /// @return result Hash of the call data
    function _computeCallDataHash(address targetContract, bytes calldata callData, uint256 proposalId)
        internal
        pure
        returns (bytes32 result)
    {
        bytes memory data = abi.encode(proposalId, targetContract, callData);
        assembly {
            result := keccak256(add(data, 0x20), mload(data))
        }
    }
}

