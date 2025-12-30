// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM
pragma solidity ^0.8.33;

import {IMultiAdminSingleHolderAccessControl} from "./interfaces/IMultiAdminSingleHolderAccessControl.sol";
import {IPausable} from "./interfaces/IPausable.sol";
import {IMultisig} from "./interfaces/IMultisig.sol";
import {IDAO} from "./interfaces/IDAO.sol";
import {INonfungiblePositionManager} from "./interfaces/INonfungiblePositionManager.sol";
import {IProofOfCapital} from "./interfaces/IProofOfCapital.sol";
import {Constants} from "./utils/Constants.sol";
import {DataTypes} from "./utils/DataTypes.sol";
import {ISwapRouter} from "./interfaces/ISwapRouter.sol";
import {IAggregatorV3} from "./interfaces/IAggregatorV3.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import {IERC721} from "@openzeppelin/contracts/token/ERC721/IERC721.sol";

contract Multisig is IMultisig {
    using SafeERC20 for IERC20;
    Owner[] private owners;
    mapping(address => bool) public isPrimaryOwner;
    mapping(address => bool) public isBackupOwner;
    mapping(address => bool) public isEmergencyOwner;
    mapping(address => uint256) public ownerIndex;
    mapping(uint256 => mapping(address => VoteOption)) private votes;
    mapping(uint256 => mapping(address => bool)) private hasVoted;
    mapping(uint256 => mapping(address => uint256)) public ownerSubmissionsPerPeriod;
    Transaction[] private transactions;

    address public admin;
    address public commonBackupAdmin;
    address public commonEmergencyAdmin;
    address public commonEmergencyInvestor;
    IDAO public dao;
    uint256 public maxCountVotePerPeriod;
    mapping(address => bool) public isVetoListContract;
    address public newMarketMaker;

    MultisigStage public multisigStage = MultisigStage.Inactive;
    uint256 public targetCollateralAmount;
    uint256 public currentCollateralAmount;
    address public uniswapV3Router;
    address public uniswapV3PositionManager;
    LPPoolParams public lpPoolParams;
    mapping(address => CollateralInfo) public collaterals;

    modifier onlyPrimaryOwner() {
        require(isPrimaryOwner[msg.sender], NotAPrimaryOwner());
        _;
    }

    modifier onlyBackupOwner() {
        require(isBackupOwner[msg.sender], NotABackupOwner());
        _;
    }

    modifier onlyEmergencyOwner() {
        require(isEmergencyOwner[msg.sender], NotAnEmergencyOwner());
        _;
    }

    modifier onlyOwnerOrAdmin() {
        require(isPrimaryOwner[msg.sender] || msg.sender == admin, NotAPrimaryOwnerOrAdmin());
        _;
    }

    modifier onlyDAO() {
        require(msg.sender == address(dao), NotDAO());
        _;
    }

    modifier onlyOwnerOrAdminOrDAO() {
        require(
            isPrimaryOwner[msg.sender] || msg.sender == admin || msg.sender == address(dao), NotAPrimaryOwnerOrAdmin()
        );
        _;
    }

    modifier onlyActiveStage() {
        require(multisigStage == MultisigStage.Active, MultisigStageNotActive());
        _;
    }

    modifier onlyInactiveStage() {
        require(multisigStage == MultisigStage.Inactive, InvalidMultisigStage());
        _;
    }

    modifier onlyNonWorkingStage() {
        require(multisigStage == MultisigStage.NonWorking, InvalidMultisigStage());
        _;
    }

    modifier onlyPrimaryOwnerOrAdmin() {
        require(isPrimaryOwner[msg.sender] || msg.sender == admin, NotAPrimaryOwnerOrAdmin());
        _;
    }

    constructor(
        address[] memory _primaryAddrs,
        address[] memory _backupAddrs,
        address[] memory _emergencyAddrs,
        address _admin,
        address _dao,
        uint256 _targetCollateralAmount,
        address _uniswapV3Router,
        address _uniswapV3PositionManager,
        LPPoolParams memory _lpPoolParams,
        CollateralConstructorParams[] memory _collateralParams,
        address _newMarketMaker
    ) {
        require(_primaryAddrs.length == 8, InvalidPrimaryOwnersLength());
        require(_backupAddrs.length == 8, InvalidBackupOwnersLength());
        require(_emergencyAddrs.length == 8, InvalidEmergencyOwnersLength());
        require(_admin != address(0), InvalidAdminAddress());
        require(_dao != address(0), InvalidAddress());

        uint8[8] memory shares = [20, 20, 15, 15, 15, 5, 5, 5];

        for (uint256 i = 0; i < _primaryAddrs.length; ++i) {
            require(_primaryAddrs[i] != address(0), InvalidPrimaryAddress());
            require(_backupAddrs[i] != address(0), InvalidBackupAddress());
            require(_emergencyAddrs[i] != address(0), InvalidEmergencyAddress());

            require(
                _primaryAddrs[i] != _backupAddrs[i] && _primaryAddrs[i] != _emergencyAddrs[i]
                    && _backupAddrs[i] != _emergencyAddrs[i],
                AddressesMustBeUnique()
            );

            owners.push(
                Owner({
                    primaryAddr: _primaryAddrs[i],
                    backupAddr: _backupAddrs[i],
                    emergencyAddr: _emergencyAddrs[i],
                    share: uint256(shares[i])
                })
            );

            isPrimaryOwner[_primaryAddrs[i]] = true;
            isBackupOwner[_backupAddrs[i]] = true;
            isEmergencyOwner[_emergencyAddrs[i]] = true;
            ownerIndex[_primaryAddrs[i]] = i;
            ownerIndex[_backupAddrs[i]] = i;
            ownerIndex[_emergencyAddrs[i]] = i;
        }

        admin = _admin;
        dao = IDAO(_dao);
        maxCountVotePerPeriod = Constants.MULTISIG_DEFAULT_MAX_COUNT_VOTE_PER_PERIOD;

        require(_targetCollateralAmount > 0, InvalidAddress());
        require(_uniswapV3Router != address(0), InvalidAddress());
        require(_uniswapV3PositionManager != address(0), InvalidAddress());
        require(_lpPoolParams.fee > 0, InvalidLPPoolParams());
        require(_lpPoolParams.amount0Min > 0, InvalidLPPoolParams());
        require(_lpPoolParams.amount1Min > 0, InvalidLPPoolParams());
        require(_newMarketMaker != address(0), InvalidAddress());

        targetCollateralAmount = _targetCollateralAmount;
        uniswapV3Router = _uniswapV3Router;
        uniswapV3PositionManager = _uniswapV3PositionManager;
        lpPoolParams = _lpPoolParams;
        multisigStage = MultisigStage.Inactive;
        newMarketMaker = _newMarketMaker;

        for (uint256 i = 0; i < _collateralParams.length; ++i) {
            require(_collateralParams[i].token != address(0), InvalidCollateralAddress());
            require(_collateralParams[i].router != address(0), InvalidRouterAddress());
            require(_collateralParams[i].router == _uniswapV3Router, InvalidRouterAddress());
            require(_collateralParams[i].swapPath.length > 0, InvalidAddress());

            address collateralToken = _collateralParams[i].token;
            collaterals[collateralToken] = CollateralInfo({
                token: collateralToken,
                priceFeed: _collateralParams[i].priceFeed,
                router: _collateralParams[i].router,
                swapPath: _collateralParams[i].swapPath,
                active: true
            });
        }
    }

    receive() external payable {}

    /// @inheritdoc IMultisig
    function submitTransaction(ProposalCall[] calldata calls)
        external
        onlyOwnerOrAdmin
        onlyActiveStage
        returns (uint256)
    {
        require(calls.length > 0, InvalidAddress());
        _checkDAOStageForVetoContracts(calls);
        uint256 currentPeriod = block.timestamp / Constants.MULTISIG_MAX_COUNT_VOTE_PERIOD;
        require(ownerSubmissionsPerPeriod[currentPeriod][msg.sender] < maxCountVotePerPeriod, VotingLimitExceeded());
        ownerSubmissionsPerPeriod[currentPeriod][msg.sender] += 1;

        VotingType votingType = _determineVotingType(calls);

        if (votingType == VotingType.TRANSFER_OWNERSHIP) {
            DataTypes.DAOState memory daoState = dao.daoState();
            bool isDissolvedOrCancelled = daoState.currentStage == DataTypes.Stage.Dissolved
                || daoState.currentStage == DataTypes.Stage.FundraisingCancelled;

            if (!isDissolvedOrCancelled) {
                for (uint256 i = 0; i < calls.length; ++i) {
                    require(!isVetoListContract[calls[i].targetContract], TransferOwnershipNotAllowedForVetoContract());
                }
            }
        }

        uint256 txId = transactions.length;
        bytes32 callDataHash = _computeCallDataHash(calls, txId);

        transactions.push(
            Transaction({
                callDataHash: callDataHash,
                id: txId,
                status: TransactionStatus.PENDING,
                confirmationsFor: 0,
                confirmationsAgainst: 0,
                createdAt: block.timestamp,
                votingType: votingType
            })
        );

        emit TransactionSubmitted(txId, callDataHash, txId, calls, votingType);
        return txId;
    }

    /// @inheritdoc IMultisig
    function voteTransaction(uint256 txId, VoteOption voteOption) external onlyPrimaryOwner onlyActiveStage {
        require(txId < transactions.length, TransactionDoesNotExist());
        require(transactions[txId].status == TransactionStatus.PENDING, TransactionNotPending());
        require(!hasVoted[txId][msg.sender], AlreadyVoted());
        require(
            block.timestamp <= transactions[txId].createdAt + Constants.MULTISIG_VOTING_PERIOD, VotingPeriodExpired()
        );

        hasVoted[txId][msg.sender] = true;
        votes[txId][msg.sender] = voteOption;

        uint256 ownerIdx = ownerIndex[msg.sender];
        uint256 share = owners[ownerIdx].share;

        if (transactions[txId].votingType == VotingType.GENERAL) {
            if (voteOption == VoteOption.FOR) {
                transactions[txId].confirmationsFor += share;
            } else {
                transactions[txId].confirmationsAgainst += share;

                if (transactions[txId].confirmationsAgainst > 20) {
                    transactions[txId].status = TransactionStatus.CANCELLED;
                    emit TransactionCancelled(txId, "More than 20% voted against");
                    return;
                }
            }
        } else if (transactions[txId].votingType == VotingType.TRANSFER_OWNERSHIP) {
            if (voteOption == VoteOption.FOR) {
                transactions[txId].confirmationsFor += 1;
            } else {
                transactions[txId].confirmationsAgainst += 1;

                if (transactions[txId].confirmationsAgainst >= 2) {
                    transactions[txId].status = TransactionStatus.CANCELLED;
                    emit TransactionCancelled(txId, "2 or more owners voted against");
                    return;
                }
            }
        }

        emit VoteCast(txId, msg.sender, voteOption, share);
    }

    /// @inheritdoc IMultisig
    function executeTransaction(uint256 txId, ProposalCall[] calldata calls)
        external
        onlyOwnerOrAdminOrDAO
        onlyActiveStage
    {
        require(txId < transactions.length, TransactionDoesNotExist());
        require(transactions[txId].status == TransactionStatus.PENDING, TransactionNotPending());
        require(
            block.timestamp > transactions[txId].createdAt + Constants.MULTISIG_VOTING_PERIOD, VotingPeriodNotEnded()
        );
        require(
            block.timestamp
                <= transactions[txId].createdAt + Constants.MULTISIG_VOTING_PERIOD
                    + Constants.MULTISIG_TRANSACTION_EXPIRY_PERIOD,
            TransactionExpired()
        );

        _checkDAOStageForVetoContracts(calls);

        Transaction storage txn = transactions[txId];

        if (txn.votingType == VotingType.TRANSFER_OWNERSHIP) {
            DataTypes.DAOState memory daoState = dao.daoState();
            bool isDissolvedOrCancelled = daoState.currentStage == DataTypes.Stage.Dissolved
                || daoState.currentStage == DataTypes.Stage.FundraisingCancelled;

            if (!isDissolvedOrCancelled) {
                for (uint256 i = 0; i < calls.length; ++i) {
                    require(!isVetoListContract[calls[i].targetContract], TransferOwnershipNotAllowedForVetoContract());
                }
            }
        }

        bytes32 computedHash = _computeCallDataHash(calls, txId);
        require(txn.callDataHash == computedHash, CallDataHashMismatch());

        bool canExecute = false;

        if (txn.votingType == VotingType.GENERAL) {
            uint256 totalParticipation = txn.confirmationsFor + txn.confirmationsAgainst;

            if (totalParticipation < Constants.MULTISIG_GENERAL_PARTICIPATION_THRESHOLD) {
                txn.status = TransactionStatus.CANCELLED;
                emit TransactionFailed(txId, "Less than 60% participation");
                return;
            }

            uint256 approvalPercentage = (txn.confirmationsFor * Constants.PERCENTAGE_MULTIPLIER) / totalParticipation;
            canExecute = approvalPercentage >= Constants.MULTISIG_GENERAL_APPROVAL_THRESHOLD;

            if (!canExecute) {
                txn.status = TransactionStatus.CANCELLED;
                emit TransactionFailed(txId, "Less than 80% approval among participants");
                return;
            }
        } else if (txn.votingType == VotingType.TRANSFER_OWNERSHIP) {
            canExecute = txn.confirmationsFor >= Constants.MULTISIG_TRANSFER_THRESHOLD_COUNT;

            if (!canExecute) {
                txn.status = TransactionStatus.CANCELLED;
                emit TransactionFailed(txId, "Less than 7 out of 8 owners confirmed");
                return;
            }
        }

        txn.status = TransactionStatus.EXECUTED;

        for (uint256 i = 0; i < calls.length; ++i) {
            (bool success,) = calls[i].targetContract.call{value: calls[i].value}(calls[i].callData);
            if (!success) {
                txn.status = TransactionStatus.FAILED;
                emit TransactionFailed(txId, "Transaction execution failed");
                return;
            }
        }

        emit TransactionExecuted(txId);
    }

    /// @inheritdoc IMultisig
    function revokeVote(uint256 txId) external onlyPrimaryOwner onlyActiveStage {
        require(txId < transactions.length, TransactionDoesNotExist());
        require(hasVoted[txId][msg.sender], NotVotedYet());
        require(transactions[txId].status == TransactionStatus.PENDING, TransactionNotPending());
        require(
            block.timestamp <= transactions[txId].createdAt + Constants.MULTISIG_VOTING_PERIOD, VotingPeriodExpired()
        );

        VoteOption previousVote = votes[txId][msg.sender];
        uint256 ownerIdx = ownerIndex[msg.sender];
        uint256 share = owners[ownerIdx].share;

        if (transactions[txId].votingType == VotingType.GENERAL) {
            if (previousVote == VoteOption.FOR) {
                transactions[txId].confirmationsFor -= share;
            } else {
                transactions[txId].confirmationsAgainst -= share;
            }
        } else if (transactions[txId].votingType == VotingType.TRANSFER_OWNERSHIP) {
            if (previousVote == VoteOption.FOR) {
                transactions[txId].confirmationsFor -= 1;
            } else {
                transactions[txId].confirmationsAgainst -= 1;
            }
        }

        hasVoted[txId][msg.sender] = false;
        delete votes[txId][msg.sender];
    }

    /// @inheritdoc IMultisig
    function changeCommonBackupAdminInUserVault(address vault) external onlyOwnerOrAdmin {
        require(vault != address(0), InvalidVaultAddress());
        require(commonBackupAdmin != address(0), CommonBackupAdminNotSet());

        IMultiAdminSingleHolderAccessControl(vault).grantRole(Constants.MULTISIG_BACKUP_ADMIN_ROLE, commonBackupAdmin);
    }

    /// @inheritdoc IMultisig
    function changeCommonEmergencyAdminInUserVault(address vault) external onlyOwnerOrAdmin {
        require(vault != address(0), InvalidVaultAddress());
        require(commonEmergencyAdmin != address(0), CommonEmergencyAdminNotSet());

        IMultiAdminSingleHolderAccessControl(vault)
            .grantRole(Constants.MULTISIG_EMERGENCY_ADMIN_ROLE, commonEmergencyAdmin);
    }

    /// @inheritdoc IMultisig
    function setCommonEmergencyInvestor(address newCommonEmergencyInvestor) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(newCommonEmergencyInvestor != address(0), InvalidCommonEmergencyInvestorAddress());
        address oldCommonEmergencyInvestor = commonEmergencyInvestor;
        commonEmergencyInvestor = newCommonEmergencyInvestor;
        emit CommonEmergencyInvestorChanged(oldCommonEmergencyInvestor, newCommonEmergencyInvestor);
    }

    /// @inheritdoc IMultisig
    function changeCommonEmergencyInvestorInUserVault(address vault) external onlyOwnerOrAdmin {
        require(vault != address(0), InvalidVaultAddress());
        require(commonEmergencyInvestor != address(0), CommonEmergencyInvestorNotSet());
        IMultiAdminSingleHolderAccessControl(vault)
            .grantRole(Constants.MULTISIG_EMERGENCY_INVESTOR_ROLE, commonEmergencyInvestor);
    }

    /// @inheritdoc IMultisig
    function changePrimaryAddressByPrimary(address newPrimaryAddr) external onlyPrimaryOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changePrimaryAddress(idx, newPrimaryAddr);
    }

    /// @inheritdoc IMultisig
    function changePrimaryAddressByBackup(address newPrimaryAddr) external onlyBackupOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changePrimaryAddress(idx, newPrimaryAddr);
    }

    /// @inheritdoc IMultisig
    function changeBackupAddressByBackup(address newBackupAddr) external onlyBackupOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changeBackupAddress(idx, newBackupAddr);
    }

    /// @inheritdoc IMultisig
    function changeEmergencyPrimaryAddressByEmergency(address newPrimaryAddr) external onlyEmergencyOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changePrimaryAddress(idx, newPrimaryAddr);
    }

    /// @inheritdoc IMultisig
    function changeEmergencyBackupAddressByEmergency(address newBackupAddr) external onlyEmergencyOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changeBackupAddress(idx, newBackupAddr);
    }

    /// @inheritdoc IMultisig
    function changeEmergencyAddressByEmergency(address newEmergencyAddr) external onlyEmergencyOwner {
        uint256 idx = ownerIndex[msg.sender];
        _changeEmergencyAddress(idx, newEmergencyAddr);
    }

    /// @inheritdoc IMultisig
    function changeOwnerEmergencyAddress(uint256 ownerIdx, address newEmergencyAddr) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(ownerIdx < owners.length, OwnerIndexOutOfBounds());
        _changeEmergencyAddress(ownerIdx, newEmergencyAddr);
    }

    /// @inheritdoc IMultisig
    function emergencyPause(address target) external onlyPrimaryOwner {
        require(target != address(0), InvalidTargetAddress());

        IPausable(target).pause();

        emit EmergencyPause(target, msg.sender);
    }

    /// @inheritdoc IMultisig
    function emergencyUnpause(address target) external onlyPrimaryOwner {
        require(target != address(0), InvalidTargetAddress());

        IPausable(target).unpause();

        emit EmergencyUnpause(target, msg.sender);
    }

    /// @inheritdoc IMultisig
    function setAdmin(address newAdmin) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(newAdmin != address(0), InvalidAdminAddress());

        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminChanged(oldAdmin, newAdmin);
    }

    /// @inheritdoc IMultisig
    function setCommonBackupAdmin(address newCommonBackupAdmin) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(newCommonBackupAdmin != address(0), InvalidCommonBackupAdminAddress());
        address oldCommonBackupAdmin = commonBackupAdmin;
        commonBackupAdmin = newCommonBackupAdmin;
        emit CommonBackupAdminChanged(oldCommonBackupAdmin, newCommonBackupAdmin);
    }

    /// @inheritdoc IMultisig
    function setCommonEmergencyAdmin(address newCommonEmergencyAdmin) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(newCommonEmergencyAdmin != address(0), InvalidCommonEmergencyAdminAddress());
        address oldCommonEmergencyAdmin = commonEmergencyAdmin;
        commonEmergencyAdmin = newCommonEmergencyAdmin;
        emit CommonEmergencyAdminChanged(oldCommonEmergencyAdmin, newCommonEmergencyAdmin);
    }

    /// @inheritdoc IMultisig
    function setMaxCountVotePerPeriod(uint256 newMaxCountVotePerPeriod) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(newMaxCountVotePerPeriod > 0, InvalidMaxCountVotePerPeriod());
        uint256 oldMaxCountVotePerPeriod = maxCountVotePerPeriod;
        maxCountVotePerPeriod = newMaxCountVotePerPeriod;
        emit MaxCountVotePerPeriodChanged(oldMaxCountVotePerPeriod, newMaxCountVotePerPeriod);
    }

    /// @inheritdoc IMultisig
    function addVetoListContract(address contractAddress) external {
        require(msg.sender == address(this), CanOnlyBeCalledThroughMultisig());
        require(contractAddress != address(0), InvalidAddress());
        isVetoListContract[contractAddress] = true;
        emit VetoListContractAdded(contractAddress);
    }

    /// @inheritdoc IMultisig
    function getOwners() external view returns (Owner[] memory) {
        return owners;
    }

    /// @inheritdoc IMultisig
    function getOwnersCount() external view returns (uint256) {
        return owners.length;
    }

    /// @inheritdoc IMultisig
    function getOwnerByIndex(uint256 idx)
        external
        view
        returns (address primaryAddr, address backupAddr, address emergencyAddr, uint256 share)
    {
        require(idx < owners.length, OwnerDoesNotExist());
        Owner storage owner = owners[idx];
        return (owner.primaryAddr, owner.backupAddr, owner.emergencyAddr, owner.share);
    }

    /// @inheritdoc IMultisig
    function getTransaction(uint256 txId) external view returns (Transaction memory) {
        require(txId < transactions.length, TransactionDoesNotExist());
        return transactions[txId];
    }

    /// @inheritdoc IMultisig
    function getVotingResults(uint256 txId)
        external
        view
        returns (
            uint256 votesFor,
            uint256 votesAgainst,
            uint256 totalParticipation,
            uint256 participationPercentage,
            uint256 approvalPercentage
        )
    {
        require(txId < transactions.length, TransactionDoesNotExist());
        Transaction storage txn = transactions[txId];

        if (txn.votingType == VotingType.GENERAL) {
            votesFor = txn.confirmationsFor;
            votesAgainst = txn.confirmationsAgainst;
            totalParticipation = votesFor + votesAgainst;

            if (totalParticipation > 0) {
                participationPercentage = totalParticipation;
                approvalPercentage = (votesFor * Constants.PERCENTAGE_MULTIPLIER) / totalParticipation;
            }
        } else if (txn.votingType == VotingType.TRANSFER_OWNERSHIP) {
            votesFor = txn.confirmationsFor;
            votesAgainst = 0;
            totalParticipation = votesFor;
            participationPercentage = (votesFor * Constants.PERCENTAGE_MULTIPLIER) / owners.length;
            approvalPercentage = Constants.PERCENTAGE_MULTIPLIER;
        }
    }

    /// @inheritdoc IMultisig
    function getTransactionCount() external view returns (uint256) {
        return transactions.length;
    }

    /// @inheritdoc IMultisig
    function isVotingActive(uint256 txId) external view returns (bool) {
        require(txId < transactions.length, TransactionDoesNotExist());
        return block.timestamp <= transactions[txId].createdAt + Constants.MULTISIG_VOTING_PERIOD;
    }

    /// @inheritdoc IMultisig
    function getOwnerShare(address owner) external view returns (uint256) {
        require(isAnyOwner(owner), NotAnOwner());
        return owners[ownerIndex[owner]].share;
    }

    /// @inheritdoc IMultisig
    function getOwnerSubmissionCountInCurrentPeriod(address owner) external view returns (uint256) {
        require(isAnyOwner(owner) || owner == admin, NotAnOwner());
        uint256 currentPeriod = block.timestamp / Constants.MULTISIG_MAX_COUNT_VOTE_PERIOD;
        return ownerSubmissionsPerPeriod[currentPeriod][owner];
    }

    /// @inheritdoc IMultisig
    function hasOwnerVoted(uint256 txId, address owner) external view returns (bool) {
        require(txId < transactions.length, TransactionDoesNotExist());
        return hasVoted[txId][owner];
    }

    /// @inheritdoc IMultisig
    function getOwnerVote(uint256 txId, address owner) external view returns (VoteOption) {
        require(txId < transactions.length, TransactionDoesNotExist());
        require(hasVoted[txId][owner], OwnerHasNotVoted());
        return votes[txId][owner];
    }

    /// @inheritdoc IMultisig
    function isAnyOwner(address addr) public view returns (bool) {
        return isPrimaryOwner[addr] || isBackupOwner[addr] || isEmergencyOwner[addr];
    }

    function _changePrimaryAddress(uint256 idx, address newPrimaryAddr) internal {
        require(newPrimaryAddr != address(0), InvalidAddress());
        require(!isAnyOwner(newPrimaryAddr), AddressInUse());

        address oldPrimaryAddr = owners[idx].primaryAddr;

        isPrimaryOwner[oldPrimaryAddr] = false;
        isPrimaryOwner[newPrimaryAddr] = true;
        ownerIndex[newPrimaryAddr] = idx;
        delete ownerIndex[oldPrimaryAddr];

        owners[idx].primaryAddr = newPrimaryAddr;

        emit OwnerAddressChanged(idx, "primary", oldPrimaryAddr, newPrimaryAddr);
    }

    function _changeBackupAddress(uint256 idx, address newBackupAddr) internal {
        require(newBackupAddr != address(0), InvalidAddress());
        require(!isAnyOwner(newBackupAddr), AddressInUse());

        address oldBackupAddr = owners[idx].backupAddr;

        isBackupOwner[oldBackupAddr] = false;
        isBackupOwner[newBackupAddr] = true;
        ownerIndex[newBackupAddr] = idx;
        delete ownerIndex[oldBackupAddr];

        owners[idx].backupAddr = newBackupAddr;

        emit OwnerAddressChanged(idx, "backup", oldBackupAddr, newBackupAddr);
    }

    function _changeEmergencyAddress(uint256 idx, address newEmergencyAddr) internal {
        require(newEmergencyAddr != address(0), InvalidAddress());
        require(!isAnyOwner(newEmergencyAddr), AddressInUse());

        address oldEmergencyAddr = owners[idx].emergencyAddr;

        isEmergencyOwner[oldEmergencyAddr] = false;
        isEmergencyOwner[newEmergencyAddr] = true;
        ownerIndex[newEmergencyAddr] = idx;
        delete ownerIndex[oldEmergencyAddr];

        owners[idx].emergencyAddr = newEmergencyAddr;

        emit OwnerAddressChanged(idx, "emergency", oldEmergencyAddr, newEmergencyAddr);
    }

    function _isOwnershipSelector(bytes4 selector) internal pure returns (bool) {
        return selector == Constants.TRANSFER_OWNERSHIP_SELECTOR || selector == Constants.RENOUNCE_OWNERSHIP_SELECTOR
            || selector == Constants.GRANT_ROLE_SELECTOR || selector == Constants.REVOKE_ROLE_SELECTOR
            || selector == Constants.CHANGE_EMERGENCY_ADDRESS_SELECTOR
            || selector == Constants.SET_COMMON_BACKUP_ADMIN_SELECTOR
            || selector == Constants.SET_COMMON_EMERGENCY_ADMIN_SELECTOR
            || selector == Constants.SET_COMMON_EMERGENCY_INVESTOR_SELECTOR
            || selector == Constants.SET_MAX_COUNT_VOTE_PER_PERIOD_SELECTOR;
    }

    function _determineVotingType(ProposalCall[] calldata calls) internal pure returns (VotingType) {
        for (uint256 i = 0; i < calls.length; ++i) {
            if (calls[i].callData.length < 4) {
                continue;
            }

            bytes memory callData = calls[i].callData;
            bytes4 selector;
            assembly {
                selector := mload(add(callData, 0x20))
            }

            if (_isOwnershipSelector(selector)) {
                return VotingType.TRANSFER_OWNERSHIP;
            }
        }

        return VotingType.GENERAL;
    }

    function _computeCallDataHash(ProposalCall[] calldata calls, uint256 id) internal pure returns (bytes32 result) {
        bytes memory data = abi.encode(id, calls);
        assembly {
            result := keccak256(add(data, 0x20), mload(data))
        }
    }

    function _checkDAOStageForVetoContracts(ProposalCall[] calldata calls) internal view {
        bool hasVetoContract = false;
        for (uint256 i = 0; i < calls.length; ++i) {
            if (isVetoListContract[calls[i].targetContract]) {
                hasVetoContract = true;
                break;
            }
        }

        if (hasVetoContract) {
            require(!dao.isVetoToCreator(), InvalidDAOStage());
            DataTypes.DAOState memory daoState = dao.daoState();
            require(
                daoState.currentStage == DataTypes.Stage.Active || daoState.currentStage == DataTypes.Stage.Dissolved,
                InvalidDAOStage()
            );
        }
    }

    /// @inheritdoc IMultisig
    function swapCollateralToMain(address collateral, uint256 collateralBalance)
        external
        onlyPrimaryOwnerOrAdmin
        onlyInactiveStage
    {
        require(collateral != address(0), InvalidCollateralAddress());
        require(collateralBalance > 0, InvalidAddress());

        CollateralInfo storage collateralInfo = collaterals[collateral];
        require(collateralInfo.active, InvalidCollateralAddress());
        require(collateralInfo.router != address(0), InvalidRouterAddress());
        require(collateralInfo.swapPath.length > 0, InvalidAddress());

        IERC20 collateralToken = IERC20(collateral);
        require(collateralToken.balanceOf(address(this)) >= collateralBalance, InsufficientBalance());

        address mainCollateral = dao.mainCollateral();

        uint256 collateralPrice = _getChainlinkPrice(collateralInfo.priceFeed);

        CollateralInfo storage mainCollateralInfo = collaterals[mainCollateral];
        require(mainCollateralInfo.active, InvalidCollateralAddress());
        uint256 mainCollateralPrice = _getChainlinkPrice(mainCollateralInfo.priceFeed);

        uint256 expectedMainCollateral = (collateralBalance * collateralPrice) / mainCollateralPrice;

        uint256 mainCollateralBalanceBefore = IERC20(mainCollateral).balanceOf(address(this));

        collateralToken.safeIncreaseAllowance(collateralInfo.router, collateralBalance);

        ISwapRouter.ExactInputParams memory params = ISwapRouter.ExactInputParams({
            path: collateralInfo.swapPath,
            recipient: address(this),
            deadline: block.timestamp + 1 hours,
            amountIn: collateralBalance,
            amountOutMinimum: 0
        });

        ISwapRouter(collateralInfo.router).exactInput(params);

        uint256 mainCollateralBalanceAfter = IERC20(mainCollateral).balanceOf(address(this));
        uint256 actualMainCollateral = mainCollateralBalanceAfter - mainCollateralBalanceBefore;

        uint256 deviation = _calculateDeviation(expectedMainCollateral, actualMainCollateral);
        require(deviation <= Constants.PRICE_DEVIATION_MAX, PriceDeviationTooHigh());

        emit CollateralChanged(collateral, collateralInfo.router);

        uint256 mainCollateralBalance = IERC20(mainCollateral).balanceOf(address(this));

        if (mainCollateralBalance >= targetCollateralAmount) {
            address launchToken = address(dao.launchToken());
            uint256 launchBalance = IERC20(launchToken).balanceOf(address(this));
            _createUniswapV3LPInternal(launchBalance, targetCollateralAmount);
        }
    }

    function _createUniswapV3LPInternal(uint256 amount0Desired, uint256 amount1Desired) internal {
        address token0 = address(dao.launchToken());
        address token1 = dao.mainCollateral();

        IERC20(token0).approve(uniswapV3PositionManager, amount0Desired);
        IERC20(token1).approve(uniswapV3PositionManager, amount1Desired);

        INonfungiblePositionManager.MintParams memory params = INonfungiblePositionManager.MintParams({
            token0: token0,
            token1: token1,
            fee: lpPoolParams.fee,
            tickLower: lpPoolParams.tickLower,
            tickUpper: lpPoolParams.tickUpper,
            amount0Desired: amount0Desired,
            amount1Desired: amount1Desired,
            amount0Min: lpPoolParams.amount0Min,
            amount1Min: lpPoolParams.amount1Min,
            recipient: address(this),
            deadline: block.timestamp + 1 hours
        });

        (uint256 tokenId,, uint256 amount0, uint256 amount1) =
            INonfungiblePositionManager(uniswapV3PositionManager).mint(params);

        emit LPCreated(tokenId, amount0, amount1);

        IERC721(uniswapV3PositionManager).safeTransferFrom(address(this), address(dao), tokenId);

        address[] memory emptyV2Addresses = new address[](0);
        uint256[] memory emptyV2Amounts = new uint256[](0);
        uint256[] memory v3TokenIds = new uint256[](1);
        v3TokenIds[0] = tokenId;

        DataTypes.PricePathV2Params[] memory emptyV2Paths = new DataTypes.PricePathV2Params[](0);
        DataTypes.PricePathV3Params[] memory emptyV3Paths = new DataTypes.PricePathV3Params[](0);

        dao.provideLPTokens(emptyV2Addresses, emptyV2Amounts, v3TokenIds, emptyV2Paths, emptyV3Paths);

        uint256 pocContractsCount = dao.getPOCContractsCount();
        uint256 newLockTimestamp = block.timestamp + Constants.LP_EXTEND_LOCK_PERIOD;

        for (uint256 i = 0; i < pocContractsCount; ++i) {
            DataTypes.POCInfo memory pocInfo = dao.getPOCContract(i);
            if (pocInfo.active) {
                IProofOfCapital pocContract = IProofOfCapital(pocInfo.pocContract);
                pocContract.extendLock(newLockTimestamp);
                pocContract.setMarketMaker(address(dao), false);
                pocContract.setMarketMaker(newMarketMaker, true);
            }
        }
    }

    /// @inheritdoc IMultisig
    function enterNonWorkingStage() external onlyPrimaryOwnerOrAdmin {
        uint256 waitingForLPStartedAt = dao.waitingForLPStartedAt();
        require(waitingForLPStartedAt > 0, CannotEnterNonWorkingStage());
        require(
            block.timestamp >= waitingForLPStartedAt + Constants.MULTISIG_WAITING_FOR_LP_TIMEOUT,
            CannotEnterNonWorkingStage()
        );

        DataTypes.DAOState memory daoState = dao.daoState();
        require(daoState.currentStage != DataTypes.Stage.Active, CannotEnterNonWorkingStage());

        MultisigStage oldStage = multisigStage;
        multisigStage = MultisigStage.NonWorking;
        emit MultisigStageChanged(oldStage, MultisigStage.NonWorking);
    }

    /// @inheritdoc IMultisig
    function withdrawTokensToDAO(address token, uint256 amount) external onlyNonWorkingStage {
        require(token != address(0), InvalidTokenAddress());
        require(amount > 0, InvalidAddress());
        require(msg.sender == admin || dao.addressToVaultId(msg.sender) > 0, NotAPrimaryOwnerOrAdmin());

        IERC20 tokenContract = IERC20(token);
        require(tokenContract.balanceOf(address(this)) >= amount, InsufficientBalance());

        tokenContract.safeTransfer(address(dao), amount);
        emit TokensWithdrawnToDAO(token, amount);
    }

    /// @notice Get price from Chainlink aggregator and normalize to 18 decimals
    /// @param priceFeed Address of Chainlink price feed aggregator
    /// @return Price in USD (18 decimals)
    function _getChainlinkPrice(address priceFeed) internal view returns (uint256) {
        IAggregatorV3 aggregator = IAggregatorV3(priceFeed);
        (, int256 price,,,) = aggregator.latestRoundData();
        require(price > 0, InvalidPrice());

        uint8 decimals = aggregator.decimals();

        if (decimals < 18) {
            return uint256(price) * (10 ** (18 - decimals));
        } else if (decimals > 18) {
            return uint256(price) / (10 ** (decimals - 18));
        }
        return uint256(price);
    }

    /// @notice Calculate price deviation in basis points
    /// @dev Only checks deviation when actual < expected (unfavorable rate)
    /// @param expected Expected amount
    /// @param actual Actual amount
    /// @return Deviation in basis points (0 if actual >= expected)
    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) {
            return 0;
        } else {
            return ((expected - actual) * Constants.BASIS_POINTS) / expected;
        }
    }
}

