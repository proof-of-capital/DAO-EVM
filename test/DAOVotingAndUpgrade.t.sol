// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/libraries/DataTypes.sol";

contract DAOVotingAndUpgradeTest is DAOTestBase {
    bytes32 private constant ERC1967_IMPLEMENTATION_SLOT =
        0x360894a13ba1a3210667c828492db98dca3e2076cc3735a920a3ca505d382bbc;

    function test_votingAndDAOUpgrade() external {
        _reachActiveStage();

        address implBefore = address(uint160(uint256(vm.load(address(dao), ERC1967_IMPLEMENTATION_SLOT))));
        DAO newImpl = new DAO();

        (uint256 proposalId, bytes memory callData) = _createUpgradeProposalAndVote(address(newImpl));
        _executeUpgradeProposal(proposalId, callData);
        _approveUpgradeByCreatorAndUpgrade(address(newImpl));

        address implAfter = address(uint160(uint256(vm.load(address(dao), ERC1967_IMPLEMENTATION_SLOT))));
        assertEq(implAfter, address(newImpl));
        assertTrue(implAfter != implBefore);
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));
    }
}
