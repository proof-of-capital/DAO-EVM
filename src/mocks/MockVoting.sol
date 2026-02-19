// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IVoting.sol";
import "../interfaces/IDAO.sol";
import "../libraries/DataTypes.sol";

/// @title MockVoting
/// @notice Configurable IVoting for testing; execute() performs low-level call
contract MockVoting is IVoting {
    IDAO public dao;
    uint256 public nextProposalId;
    mapping(uint256 => DataTypes.ProposalStatus) private _proposalStatus;
    mapping(uint256 => DataTypes.ProposalType) private _proposalCategory;
    mapping(uint256 => address) private _targetContract;

    constructor(address _dao) {
        dao = IDAO(_dao);
    }

    function setProposalStatus(uint256 proposalId, DataTypes.ProposalStatus status) external {
        _proposalStatus[proposalId] = status;
    }

    function setProposalCategory(uint256 proposalId, DataTypes.ProposalType category) external {
        _proposalCategory[proposalId] = category;
    }

    function createProposal(address targetContract, bytes calldata) external override returns (uint256 proposalId) {
        proposalId = nextProposalId++;
        _proposalStatus[proposalId] = DataTypes.ProposalStatus.Active;
        _proposalCategory[proposalId] = DataTypes.ProposalType.Other;
        _targetContract[proposalId] = targetContract;
        return proposalId;
    }

    function vote(uint256, bool) external pure override {}

    function execute(uint256 proposalId, bytes calldata callData) external override {
        address target = _targetContract[proposalId];
        require(target != address(0), "MockVoting: unknown proposal");
        (bool success,) = target.call(callData);
        require(success, "MockVoting: execution failed");
        _proposalStatus[proposalId] = DataTypes.ProposalStatus.Executed;
    }

    function updateVotesForVault(uint256, int256) external pure override {}

    function getProposalStatus(uint256 proposalId) external view override returns (DataTypes.ProposalStatus) {
        return _proposalStatus[proposalId];
    }

    function determineCategory(address, bytes calldata) external view override returns (DataTypes.ProposalType) {
        return DataTypes.ProposalType.Other;
    }
}
