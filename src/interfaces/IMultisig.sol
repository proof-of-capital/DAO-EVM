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

pragma solidity ^0.8.29;

/// @title IMultisig Interface
/// @notice Interface for multisig contract to execute proposals
interface IMultisig {
    /// @notice Proposal execution call data
    struct ProposalCall {
        address targetContract;
        bytes callData;
        uint256 value;
    }

    /// @notice Owner structure
    struct Owner {
        address primaryAddr;
        address backupAddr;
        address emergencyAddr;
        uint256 share;
    }

    /// @notice Transaction structure
    struct Transaction {
        bytes32 callDataHash;
        uint256 id;
        TransactionStatus status;
        uint256 confirmationsFor;
        uint256 confirmationsAgainst;
        uint256 createdAt;
        VotingType votingType;
    }

    /// @notice Vote option
    enum VoteOption {
        FOR,
        AGAINST
    }

    /// @notice Voting type
    enum VotingType {
        GENERAL,
        TRANSFER_OWNERSHIP,
        EXTEND_LOCK
    }

    /// @notice Transaction status
    enum TransactionStatus {
        PENDING,
        EXECUTED,
        CANCELLED,
        FAILED
    }

    /// @notice Multisig stage
    enum MultisigStage {
        Inactive,
        Active,
        NonWorking
    }

    /// @notice LP pool parameters for Uniswap V3
    struct LPPoolParams {
        uint24 fee;
        int24 tickLower;
        int24 tickUpper;
        uint256 amount0Min;
        uint256 amount1Min;
    }

    /// @notice LP pool config: params and share in basis points (10000 = 100%)
    struct LPPoolConfig {
        LPPoolParams params;
        uint256 shareBps;
    }

    /// @notice Collateral information
    struct CollateralInfo {
        address token;
        address priceFeed;
        address router;
        bytes swapPath;
        bool active;
    }

    /// @notice Collateral constructor parameters
    struct CollateralConstructorParams {
        address token;
        address priceFeed;
        address router;
        bytes swapPath;
    }

    /// @notice Custom errors
    error NotAPrimaryOwner();
    error NotABackupOwner();
    error NotAnEmergencyOwner();
    error NotAPrimaryOwnerOrAdmin();
    error InvalidPrimaryOwnersLength();
    error InvalidBackupOwnersLength();
    error InvalidEmergencyOwnersLength();
    error InvalidAdminAddress();
    error InvalidPrimaryAddress();
    error InvalidBackupAddress();
    error InvalidEmergencyAddress();
    error AddressesMustBeUnique();
    error VotingLimitExceeded();
    error TransactionDoesNotExist();
    error TransactionNotPending();
    error AlreadyVoted();
    error VotingPeriodExpired();
    error VotingPeriodNotEnded();
    error TransactionExpired();
    error NotVotedYet();
    error InvalidVaultAddress();
    error CommonBackupAdminNotSet();
    error CommonEmergencyAdminNotSet();
    error CanOnlyBeCalledThroughMultisig();
    error InvalidCommonEmergencyInvestorAddress();
    error CommonEmergencyInvestorNotSet();
    error InvalidAddress();
    error AddressInUse();
    error OwnerIndexOutOfBounds();
    error InvalidTargetAddress();
    error InvalidCommonBackupAdminAddress();
    error InvalidCommonEmergencyAdminAddress();
    error InvalidMaxCountVotePerPeriod();
    error OwnerDoesNotExist();
    error OwnerHasNotVoted();
    error NotAnOwner();
    error NotDAO();
    error CallDataHashMismatch();
    error InvalidDAOStage();
    error InvalidMultisigStage();
    error MultisigStageNotActive();
    error InvalidLPPoolParams();
    error InvalidLPPoolConfigs();
    error InvalidCollateralAddress();
    error InvalidRouterAddress();
    error InsufficientCollateralAmount();
    error LPAlreadyCreated();
    error CannotEnterNonWorkingStage();
    error InvalidTokenAddress();
    error InsufficientBalance();
    error TransferOwnershipNotAllowedForVetoContract();
    error ExtendLockNotAllowedWhenVeto();
    error PriceDeviationTooHigh();
    error InvalidPrice();
    error StalePrice();
    error CannotReplaceContractOwner();

    /// @notice Events
    event TransactionSubmitted(
        uint256 indexed txId, bytes32 callDataHash, uint256 id, ProposalCall[] calls, VotingType votingType
    );
    event VoteCast(uint256 indexed txId, address indexed voter, VoteOption voteOption, uint256 share);
    event TransactionExecuted(uint256 indexed txId);
    event TransactionCancelled(uint256 indexed txId, string reason);
    event TransactionFailed(uint256 indexed txId, string reason);
    event OwnerAddressChanged(uint256 indexed ownerIdx, string addressType, address oldAddress, address newAddress);
    event EmergencyPause(address indexed target, address indexed caller);
    event EmergencyUnpause(address indexed target, address indexed caller);
    event AdminChanged(address indexed oldAdmin, address indexed newAdmin);
    event CommonBackupAdminChanged(address indexed oldCommonBackupAdmin, address indexed newCommonBackupAdmin);
    event CommonEmergencyAdminChanged(address indexed oldCommonEmergencyAdmin, address indexed newCommonEmergencyAdmin);
    event CommonEmergencyInvestorChanged(
        address indexed oldCommonEmergencyInvestor, address indexed newCommonEmergencyInvestor
    );
    event MaxCountVotePerPeriodChanged(uint256 oldMaxCountVotePerPeriod, uint256 newMaxCountVotePerPeriod);
    event VetoListContractAdded(address indexed contractAddress);
    event MultisigStageChanged(MultisigStage oldStage, MultisigStage newStage);
    event SharePriceRequested(uint256 sharePrice);
    event CollateralChanged(address indexed collateral, address router);
    event LPCreated(uint256 indexed tokenId, uint256 amount0, uint256 amount1);
    event TokensWithdrawnToDAO(address indexed token, uint256 amount);

    /// @notice Submit a new transaction for voting
    /// @param calls Array of calls to execute
    /// @return Transaction ID
    function submitTransaction(ProposalCall[] calldata calls) external returns (uint256);

    /// @notice Vote on a transaction
    /// @param txId Transaction ID
    /// @param voteOption Vote option (FOR or AGAINST)
    function voteTransaction(uint256 txId, VoteOption voteOption) external;

    /// @notice Execute a transaction that has been approved
    /// @param txId Transaction ID
    /// @param calls Array of calls to execute
    function executeTransaction(uint256 txId, ProposalCall[] calldata calls) external;

    /// @notice Revoke a vote on a transaction
    /// @param txId Transaction ID
    function revokeVote(uint256 txId) external;

    /// @notice Change common backup admin in user vault
    /// @param vault Vault address
    function changeCommonBackupAdminInUserVault(address vault) external;

    /// @notice Change common emergency admin in user vault
    /// @param vault Vault address
    function changeCommonEmergencyAdminInUserVault(address vault) external;

    /// @notice Set common emergency investor
    function setCommonEmergencyInvestor(address newCommonEmergencyInvestor) external;

    /// @notice Change common emergency investor in user vault
    /// @param vault Vault address
    function changeCommonEmergencyInvestorInUserVault(address vault) external;

    /// @notice Change primary address by primary owner
    /// @param newPrimaryAddr New primary address
    function changePrimaryAddressByPrimary(address newPrimaryAddr) external;

    /// @notice Change primary address by backup owner
    /// @param newPrimaryAddr New primary address
    function changePrimaryAddressByBackup(address newPrimaryAddr) external;

    /// @notice Change backup address by backup owner
    /// @param newBackupAddr New backup address
    function changeBackupAddressByBackup(address newBackupAddr) external;

    /// @notice Change emergency primary address by emergency owner
    /// @param newPrimaryAddr New primary address
    function changeEmergencyPrimaryAddressByEmergency(address newPrimaryAddr) external;

    /// @notice Change emergency backup address by emergency owner
    /// @param newBackupAddr New backup address
    function changeEmergencyBackupAddressByEmergency(address newBackupAddr) external;

    /// @notice Change emergency address by emergency owner
    /// @param newEmergencyAddr New emergency address
    function changeEmergencyAddressByEmergency(address newEmergencyAddr) external;

    /// @notice Change all three addresses (primary, backup, emergency) in one transaction
    /// @param newPrimaryAddr New primary address
    /// @param newBackupAddr New backup address
    /// @param newEmergencyAddr New emergency address
    function changeAllAddresses(address newPrimaryAddr, address newBackupAddr, address newEmergencyAddr) external;

    /// @notice Change owner emergency address (only through multisig)
    /// @param ownerIdx Owner index
    /// @param newEmergencyAddr New emergency address
    function changeOwnerEmergencyAddress(uint256 ownerIdx, address newEmergencyAddr) external;

    /// @notice Emergency pause a target contract
    /// @param target Target contract address
    function emergencyPause(address target) external;

    /// @notice Emergency unpause a target contract
    /// @param target Target contract address
    function emergencyUnpause(address target) external;

    /// @notice Set admin (only through multisig)
    /// @param newAdmin New admin address
    function setAdmin(address newAdmin) external;

    /// @notice Set common backup admin (only through multisig)
    /// @param newCommonBackupAdmin New common backup admin address
    function setCommonBackupAdmin(address newCommonBackupAdmin) external;

    /// @notice Set common emergency admin (only through multisig)
    /// @param newCommonEmergencyAdmin New common emergency admin address
    function setCommonEmergencyAdmin(address newCommonEmergencyAdmin) external;

    /// @notice Set max count vote per period (only through multisig)
    /// @param newMaxCountVotePerPeriod New max count vote per period
    function setMaxCountVotePerPeriod(uint256 newMaxCountVotePerPeriod) external;

    /// @notice Add contract address to veto list (only through multisig)
    /// @param contractAddress Contract address to add to veto list
    function addVetoListContract(address contractAddress) external;

    /// @notice Get all owners
    /// @return Array of owners
    function getOwners() external view returns (Owner[] memory);

    /// @notice Get owners count
    /// @return Owners count
    function getOwnersCount() external view returns (uint256);

    /// @notice Get owner by index
    /// @param idx Owner index
    /// @return primaryAddr Primary address
    /// @return backupAddr Backup address
    /// @return emergencyAddr Emergency address
    /// @return share Owner share
    function getOwnerByIndex(uint256 idx)
        external
        view
        returns (address primaryAddr, address backupAddr, address emergencyAddr, uint256 share);

    /// @notice Get transaction by ID
    /// @param txId Transaction ID
    /// @return Transaction data
    function getTransaction(uint256 txId) external view returns (Transaction memory);

    /// @notice Get voting results for a transaction
    /// @param txId Transaction ID
    /// @return votesFor Votes for
    /// @return votesAgainst Votes against
    /// @return totalParticipation Total participation
    /// @return participationPercentage Participation percentage
    /// @return approvalPercentage Approval percentage
    function getVotingResults(uint256 txId)
        external
        view
        returns (
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalParticipation,
            uint256 participationPercentage,
            uint256 approvalPercentage
        );

    /// @notice Get transaction count
    /// @return Transaction count
    function getTransactionCount() external view returns (uint256);

    /// @notice Check if voting is active for a transaction
    /// @param txId Transaction ID
    /// @return True if voting is active
    function isVotingActive(uint256 txId) external view returns (bool);

    /// @notice Get owner share
    /// @param owner Owner address
    /// @return Owner share
    function getOwnerShare(address owner) external view returns (uint256);

    /// @notice Get owner submission count in current period
    /// @param owner Owner address
    /// @return Submission count
    function getOwnerSubmissionCountInCurrentPeriod(address owner) external view returns (uint256);

    /// @notice Check if owner has voted
    /// @param txId Transaction ID
    /// @param owner Owner address
    /// @return True if owner has voted
    function hasOwnerVoted(uint256 txId, address owner) external view returns (bool);

    /// @notice Get owner vote
    /// @param txId Transaction ID
    /// @param owner Owner address
    /// @return Vote option
    function getOwnerVote(uint256 txId, address owner) external view returns (VoteOption);

    /// @notice Check if address is any owner type
    /// @param addr Address to check
    /// @return True if address is any owner type
    function isAnyOwner(address addr) external view returns (bool);

    /// @notice Swap collateral to main collateral
    /// @param collateral Collateral token address
    /// @param collateralBalance Amount of collateral to swap
    function swapCollateralToMain(address collateral, uint256 collateralBalance) external;

    /// @notice Enter non-working stage
    function enterNonWorkingStage() external;

    /// @notice Withdraw tokens to DAO
    /// @param token Token address
    /// @param amount Amount to withdraw
    function withdrawTokensToDAO(address token, uint256 amount) external;
}
