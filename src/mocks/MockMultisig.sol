// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IMultisig.sol";
import "../interfaces/IDAO.sol";

/// @title MockMultisig
/// @notice Minimal IMultisig for testing; single owner, executeTransaction performs calls
contract MockMultisig is IMultisig {
    IDAO public dao;
    address public admin;
    address private _owner;
    MultisigStage public multisigStage;
    IMultisig.Owner[] private _owners;
    IMultisig.Transaction[] private _transactions;
    mapping(uint256 => mapping(address => bool)) private _hasVoted;
    mapping(address => bool) private _isPrimaryOwner;
    mapping(address => uint256) private _ownerIndex;

    constructor(address _dao, address owner_) {
        require(_dao != address(0), "invalid dao");
        require(owner_ != address(0), "invalid owner");
        dao = IDAO(_dao);
        admin = msg.sender;
        _owner = owner_;
        _owners.push(IMultisig.Owner({primaryAddr: owner_, backupAddr: owner_, emergencyAddr: owner_, share: 100}));
        _isPrimaryOwner[owner_] = true;
        _ownerIndex[owner_] = 0;
        multisigStage = MultisigStage.Inactive;
    }

    function setMultisigStage(MultisigStage stage) external {
        multisigStage = stage;
    }

    function submitTransaction(ProposalCall[] calldata calls) external override returns (uint256) {
        uint256 txId = _transactions.length;
        bytes32 callDataHash = keccak256(abi.encode(txId, calls));
        _transactions.push(
            Transaction({
                callDataHash: callDataHash,
                id: txId,
                status: TransactionStatus.PENDING,
                confirmationsFor: 0,
                confirmationsAgainst: 0,
                createdAt: block.timestamp,
                votingType: VotingType.GENERAL
            })
        );
        return txId;
    }

    function voteTransaction(uint256, VoteOption) external pure override {}

    function executeTransaction(uint256 txId, ProposalCall[] calldata calls) external override {
        require(txId < _transactions.length, "tx does not exist");
        Transaction storage t = _transactions[txId];
        require(t.status == TransactionStatus.PENDING, "not pending");
        t.status = TransactionStatus.EXECUTED;
        for (uint256 i = 0; i < calls.length; i++) {
            (bool success,) = calls[i].targetContract.call{value: calls[i].value}(calls[i].callData);
            require(success, "MockMultisig: call failed");
        }
    }

    function revokeVote(uint256) external pure override {}

    function changeCommonBackupAdminInUserVault(address) external pure override {}

    function changeCommonEmergencyAdminInUserVault(address) external pure override {}

    function setCommonEmergencyInvestor(address) external pure override {}

    function changeCommonEmergencyInvestorInUserVault(address) external pure override {}

    function getCommonAdminAddresses()
        external
        pure
        override
        returns (address backupAdmin, address emergencyAdmin, address emergencyInvestor)
    {
        return (address(0), address(0), address(0));
    }

    function uniswapV3() external pure override returns (UniswapV3Addresses memory) {
        return UniswapV3Addresses({router: address(0), positionManager: address(0)});
    }

    function changePrimaryAddressByPrimary(address) external pure override {}

    function changePrimaryAddressByBackup(address) external pure override {}

    function changeBackupAddressByBackup(address) external pure override {}

    function changeEmergencyPrimaryAddressByEmergency(address) external pure override {}

    function changeEmergencyBackupAddressByEmergency(address) external pure override {}

    function changeEmergencyAddressByEmergency(address) external pure override {}

    function changeAllAddresses(address, address, address) external pure override {}

    function changeOwnerEmergencyAddress(uint256, address) external pure override {}

    function emergencyPause(address) external pure override {}

    function emergencyUnpause(address) external pure override {}

    function setAdmin(address) external pure override {}

    function setCommonBackupAdmin(address) external pure override {}

    function setCommonEmergencyAdmin(address) external pure override {}

    function setMaxCountVotePerPeriod(uint256) external pure override {}

    function addVetoListContract(address) external pure override {}

    function getOwners() external view override returns (Owner[] memory) {
        return _owners;
    }

    function getOwnersCount() external view override returns (uint256) {
        return _owners.length;
    }

    function getOwnerByIndex(uint256 idx)
        external
        view
        override
        returns (address primaryAddr, address backupAddr, address emergencyAddr, uint256 share)
    {
        Owner storage o = _owners[idx];
        return (o.primaryAddr, o.backupAddr, o.emergencyAddr, o.share);
    }

    function getTransaction(uint256 txId) external view override returns (Transaction memory) {
        require(txId < _transactions.length, "tx does not exist");
        return _transactions[txId];
    }

    function getVotingResults(uint256 txId)
        external
        view
        override
        returns (
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalParticipation,
            uint256 participationPercentage,
            uint256 approvalPercentage
        )
    {
        require(txId < _transactions.length, "tx does not exist");
        Transaction storage t = _transactions[txId];
        votesFor = t.confirmationsFor;
        votesAgainst = t.confirmationsAgainst;
        totalParticipation = votesFor + votesAgainst;
        participationPercentage = totalParticipation;
        approvalPercentage = totalParticipation > 0 ? (votesFor * 100) / totalParticipation : 0;
    }

    function getTransactionCount() external view override returns (uint256) {
        return _transactions.length;
    }

    function isVotingActive(uint256) external pure override returns (bool) {
        return false;
    }

    function getOwnerShare(address owner) external view override returns (uint256) {
        require(_isPrimaryOwner[owner], "not owner");
        return _owners[_ownerIndex[owner]].share;
    }

    function getOwnerSubmissionCountInCurrentPeriod(address) external pure override returns (uint256) {
        return 0;
    }

    function hasOwnerVoted(uint256, address) external pure override returns (bool) {
        return false;
    }

    function getOwnerVote(uint256, address) external pure override returns (VoteOption) {
        revert("not voted");
    }

    function isAnyOwner(address addr) external view override returns (bool) {
        return _isPrimaryOwner[addr];
    }

    function swapCollateralToMain(address, uint256) external pure override {
        revert("MockMultisig: not implemented");
    }

    function enterNonWorkingStage() external pure override {}

    function withdrawTokensToDAO(address, uint256) external pure override {}
}
