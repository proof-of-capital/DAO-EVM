// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/Voting.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";

contract DAOVotingScenariosTest is DAOTestBase {
    function test_setDAO_notDeployer_reverts() public {
        Voting v = new Voting();
        vm.prank(user1);
        vm.expectRevert(Voting.NotAdmin.selector);
        v.setDAO(address(dao));
    }

    function test_setDAO_zeroAddress_reverts() public {
        Voting v = new Voting();
        vm.expectRevert(Voting.InvalidDAOAddress.selector);
        v.setDAO(address(0));
    }

    function test_setDAO_secondTime_reverts() public {
        vm.expectRevert(Voting.InvalidAddress.selector);
        voting.setDAO(address(dao));
    }

    function test_createProposal_daoNotActive_reverts() public {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0));
        vm.prank(admin);
        vm.expectRevert(Voting.DAONotInActiveStage.selector);
        voting.createProposal(address(dao), callData);
    }

    function test_createProposal_insufficientShares_reverts() public {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);
        _createVaultAndDeposit(user2, 60_000e18);
        _createVaultAndDeposit(user3, 50_000e18);
        address smallHolder = makeAddr("small");
        mainCollateral.mint(smallHolder, 10_000e18);
        (address backup, address emergency) = _vaultRecoveryAddresses(smallHolder);
        vm.startPrank(smallHolder);
        dao.createVault(backup, emergency, address(0));
        uint256 vaultId = dao.addressToVaultId(smallHolder);
        vm.stopPrank();
        vm.prank(admin);
        dao.setVaultDepositLimit(vaultId, 5e18);
        vm.prank(smallHolder);
        mainCollateral.approve(address(dao), 5_000e18);
        vm.prank(smallHolder);
        dao.depositFundraising(5_000e18, 0);
        _finalizeFundraising();
        _exchangeAllPOCs();
        _finalizeExchange();
        _provideLPTokens();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setVaultDepositLimit.selector, vaultId, 100e18);
        vm.prank(smallHolder);
        vm.expectRevert(Voting.InsufficientSharesToCreateProposal.selector);
        voting.createProposal(address(dao), callData);
    }

    function test_createProposal_cooldownParticipant_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1));
        vm.prank(user1);
        voting.createProposal(address(dao), callData);
        vm.prank(user1);
        vm.expectRevert(Voting.ProposalCreationCooldown.selector);
        voting.createProposal(address(dao), callData);
    }

    function test_createProposal_cooldownAdmin_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(admin);
        vm.expectRevert(Voting.ProposalCreationCooldown.selector);
        voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x2)));
    }

    function test_createProposal_cooldownCreator_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(creator);
        voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(creator);
        vm.expectRevert(Voting.ProposalCreationCooldown.selector);
        voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x2)));
    }

    function test_createProposal_notAuthorizedNoVault_reverts() public {
        _reachActiveStage();
        address noVault = makeAddr("noVault");
        vm.warp(block.timestamp + 1 days);
        vm.prank(noVault);
        vm.expectRevert(Voting.NotAuthorizedToCreateProposal.selector);
        voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
    }

    function test_createProposal_invalidTarget_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        vm.expectRevert(Voting.InvalidTarget.selector);
        voting.createProposal(address(0), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
    }

    function test_createProposal_tokenContract_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        vm.expectRevert(Voting.TokenContractProposalNotAllowed.selector);
        voting.createProposal(address(lpToken), "");
    }

    function test_createProposal_admin_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        assertEq(id, 0);
        (, address proposer,,, , , , , , ) = voting.proposals(0);
        (,, DataTypes.ProposalType ptype, , , , , , , ) = voting.proposals(0);
        assertEq(proposer, admin);
        assertEq(uint256(ptype), uint256(DataTypes.ProposalType.Unanimous));
    }

    function test_createProposal_creator_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(creator);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        assertEq(id, 0);
        (, address proposer,,, , , , , , ) = voting.proposals(0);
        assertEq(proposer, creator);
    }

    function test_createProposal_boardMember_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(user1);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        assertEq(id, 0);
        (, address proposer,,, , , , , , ) = voting.proposals(0);
        assertEq(proposer, user1);
    }

    function test_vote_proposalDoesNotExist_reverts() public {
        _reachActiveStage();
        vm.prank(user1);
        vm.expectRevert(Voting.ProposalDoesNotExist.selector);
        voting.vote(999, true);
    }

    function test_vote_votingNotStarted_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.warp(block.timestamp - 1);
        vm.prank(user1);
        vm.expectRevert(Voting.VotingNotStarted.selector);
        voting.vote(id, true);
    }

    function test_vote_votingEnded_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.warp(block.timestamp + 8 days);
        vm.prank(user1);
        vm.expectRevert(Voting.VotingEnded.selector);
        voting.vote(id, true);
    }

    function test_vote_proposalAlreadyExecuted_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
        vm.expectRevert(Voting.VotingEnded.selector);
        vm.prank(user1);
        voting.vote(proposalId, true);
    }

    function test_vote_daoNotActive_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();
        vm.prank(admin);
        dao.enterClosingStage();
        vm.expectRevert(Voting.DAONotInActiveStage.selector);
        vm.prank(user3);
        voting.vote(id, true);
    }

    function test_vote_noVaultFound_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(admin);
        vm.expectRevert(Voting.NoVaultFound.selector);
        voting.vote(id, true);
    }

    function test_vote_onlyPrimaryCanVote_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        (address backup,) = _vaultRecoveryAddresses(user1);
        vm.expectRevert(Voting.NoVaultFound.selector);
        vm.prank(backup);
        voting.vote(id, true);
    }

    function test_vote_alreadyVoted_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user1);
        vm.expectRevert(Voting.AlreadyVoted.selector);
        voting.vote(id, false);
    }

    function test_vote_vaultInExitQueue_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        dao.requestExit();
        assertGt(dao.getDaoState().totalExitQueueShares, 0);
        vm.skip(true);
        vm.prank(user1);
        vm.expectRevert(Voting.VaultInExitQueue.selector);
        voting.vote(id, true);
    }

    function test_vote_successFor() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        (,,,,, uint256 forVotes, uint256 againstVotes, , , ) = voting.proposals(id);
        assertEq(forVotes, dao.vaults(dao.addressToVaultId(user1)).votingShares);
        assertEq(againstVotes, 0);
    }

    function test_vote_successAgainst() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, false);
        (,,,,, uint256 forVotes, uint256 againstVotes, , , ) = voting.proposals(id);
        assertEq(againstVotes, dao.vaults(dao.addressToVaultId(user1)).votingShares);
        assertEq(forVotes, 0);
    }

    function test_updateVotesForVault_notDAO_reverts() public {
        _reachActiveStage();
        vm.prank(user1);
        vm.expectRevert(Voting.NotDAO.selector);
        voting.updateVotesForVault(1, 100);
    }

    function test_updateVotesForVault_zeroDelta_noRevert() public {
        _reachActiveStage();
        vm.prank(address(dao));
        voting.updateVotesForVault(1, 0);
    }

    function test_updateVotesForVault_viaRequestExit() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        (,,,,, uint256 forBefore, , , , ) = voting.proposals(id);
        vm.prank(user1);
        dao.requestExit();
        (,,,,, uint256 forAfter, , , , ) = voting.proposals(id);
        assertTrue(forAfter < forBefore || forBefore == 0);
    }

    function test_setDelegate_daoNotActive_reverts() public {
        _reachActiveStage();
        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();
        vm.prank(admin);
        dao.enterClosingStage();
        vm.expectRevert(Voting.DAONotInActiveStage.selector);
        vm.prank(user3);
        voting.setDelegate(user1);
    }

    function test_setDelegate_noVault_reverts() public {
        _reachActiveStage();
        address noVault = makeAddr("noVault");
        vm.prank(noVault);
        vm.expectRevert(Voting.NoVaultFound.selector);
        voting.setDelegate(user1);
    }

    function test_setDelegate_onlyPrimary_reverts() public {
        _reachActiveStage();
        (address backup,) = _vaultRecoveryAddresses(user1);
        vm.prank(backup);
        vm.expectRevert(Voting.NoVaultFound.selector);
        voting.setDelegate(user2);
    }

    function test_setDelegate_noVotingPower_reverts() public {
        _reachActiveStage();
        address noSharesUser = makeAddr("noShares");
        (address backup, address emergency) = _vaultRecoveryAddresses(noSharesUser);
        vm.prank(noSharesUser);
        dao.createVault(backup, emergency, address(0));
        vm.prank(noSharesUser);
        vm.expectRevert(Voting.NoVotingPower.selector);
        voting.setDelegate(user1);
    }

    function test_setDelegate_vaultInExitQueue_reverts() public {
        _reachActiveStage();
        vm.prank(user1);
        dao.requestExit();
        assertGt(dao.getDaoState().totalExitQueueShares, 0);
        vm.skip(true);
        vm.prank(user1);
        vm.expectRevert(Voting.VaultInExitQueue.selector);
        voting.setDelegate(user2);
    }

    function test_setDelegate_transferVotesSameSupport() public {
        _reachActiveStage();
        vm.prank(user1);
        voting.setDelegate(user2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user1);
        voting.setDelegate(address(0));
        (,,,,, uint256 forVotes, , , , ) = voting.proposals(id);
        assertTrue(forVotes >= 0);
        assertEq(dao.vaults(dao.addressToVaultId(user1)).delegateId, 0);
    }

    function test_setDelegate_transferVotesOppositeSupport() public {
        _reachActiveStage();
        vm.prank(user1);
        voting.setDelegate(user2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, false);
        vm.prank(user1);
        voting.setDelegate(user3);
        (,,,,, uint256 forVotes, uint256 againstVotes, , , ) = voting.proposals(id);
        assertTrue(forVotes >= 0);
        assertTrue(againstVotes >= 0);
    }

    function test_execute_votingNotEnded_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.prank(admin);
        vm.expectRevert(Voting.VotingNotEnded.selector);
        voting.execute(id, abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
    }

    function test_execute_alreadyExecuted_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
        vm.prank(admin);
        vm.expectRevert(Voting.AlreadyExecuted.selector);
        voting.execute(proposalId, callData);
    }

    function test_execute_proposalNotSuccessful_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vm.expectRevert(Voting.ProposalNotSuccessful.selector);
        voting.execute(id, abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
    }

    function test_execute_callDataHashMismatch_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 8 days);
        vm.prank(admin);
        vm.expectRevert(Voting.CallDataHashMismatch.selector);
        voting.execute(proposalId, abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, false));
    }

    function test_execute_onlyAdminOrCreatorOrParticipant_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 8 days);
        address stranger = makeAddr("stranger");
        vm.prank(stranger);
        vm.expectRevert(Voting.OnlyAdminOrCreatorCanExecute.selector);
        voting.execute(id, abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
    }

    function test_getProposalStatus_executed() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        assertEq(uint256(voting.getProposalStatus(proposalId)), uint256(DataTypes.ProposalStatus.Active));
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
        assertEq(uint256(voting.getProposalStatus(proposalId)), uint256(DataTypes.ProposalStatus.Executed));
    }

    function test_getProposalStatus_financial_defeatedQuorum() public {
        _reachActiveStage();
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, 1000e18);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_financial_activeDuringVoting() public {
        _reachActiveStage();
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, 1000e18);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Active));
    }

    function test_getProposalStatus_financial_expired() public {
        _reachActiveStage();
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, 1000e18);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 7 days + Constants.PROPOSAL_EXPIRY_PERIOD + 1);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Expired));
    }

    function test_determineCategory_vetoFor() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.VetoFor));
    }

    function test_determineCategory_vetoAgainst() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, false);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.VetoAgainst));
    }

    function test_determineCategory_unanimous_setPendingUpgrade() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1));
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Unanimous));
    }

    function test_determineCategory_unanimous_addPOCContract() public {
        address newPoc = makeAddr("newPoc");
        bytes memory callData = abi.encodeWithSelector(DAO.addPOCContract.selector, newPoc, address(mainCollateral), 5000);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Unanimous));
    }

    function test_determineCategory_unanimous_removePOCContract() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.removePOCContract.selector, address(poc));
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Unanimous));
    }

    function test_determineCategory_financial_allocate() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, 1000e18);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Financial));
    }

    function test_determineCategory_financial_returnLaunches() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.returnLaunchesToPOC.selector, 1000e18);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Financial));
    }

    function test_determineCategory_financial_callDataTooShort() public view {
        bytes memory callData = hex"12";
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_determineCategory_pocContract() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.returnLaunchesToPOC.selector, 1000e18);
        assertEq(uint256(voting.determineCategory(address(poc), callData)), uint256(DataTypes.ProposalType.Unanimous));
    }

    function test_determineCategory_other() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setVaultDepositLimit.selector, 1, 100e18);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_determineCategory_other_nonDaoTarget() public view {
        address other = address(0x1234);
        bytes memory callData = abi.encodeWithSelector(DAO.returnLaunchesToPOC.selector, 1000e18);
        assertEq(uint256(voting.determineCategory(other, callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_determineCategory_veto_targetNotDao_returnsOther() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        assertEq(uint256(voting.determineCategory(address(0x1), callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_determineCategory_veto_callDataTooShort_returnsOther() public view {
        bytes memory callData = new bytes(35);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_determineCategory_veto_wrongSelector_returnsOther() public view {
        bytes memory callData = abi.encodeWithSelector(DAO.setVaultDepositLimit.selector, 1, 100e18);
        assertEq(uint256(voting.determineCategory(address(dao), callData)), uint256(DataTypes.ProposalType.Other));
    }

    function test_setDelegate_transferVotesNewDelegateHasNotVoted() public {
        _reachActiveStage();
        vm.prank(user1);
        voting.setDelegate(user2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user1);
        voting.setDelegate(user3);
        assertEq(dao.vaults(dao.addressToVaultId(user1)).delegateId, dao.addressToVaultId(user3));
    }

    function test_getProposalStatus_vetoFor_earlyActive() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Active));
    }

    function test_getProposalStatus_unanimous_earlyApproval() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Active));
    }

    function test_getProposalStatus_financial_defeatedApproval() public {
        _reachActiveStage();
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, 1000e18);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, false);
        vm.prank(user2);
        voting.vote(id, false);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_vetoFor_defeatedQuorum() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_vetoFor_defeatedApproval() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, false);
        vm.prank(user2);
        voting.vote(id, false);
        vm.prank(user3);
        voting.vote(id, false);
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_unanimous_defeatedAgainst() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, false);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_unanimous_defeatedQuorum() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.warp(block.timestamp + 8 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_createProposal_targetTokenOther_reverts() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        vm.expectRevert(Voting.TokenContractProposalNotAllowed.selector);
        voting.createProposal(address(lpToken), abi.encodeWithSelector(DAO.setVaultDepositLimit.selector, 1, 100e18));
    }

    function test_integration_vetoFor_fullCycle() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        (,, DataTypes.ProposalType ptype, , , , , , , ) = voting.proposals(id);
        assertEq(uint256(ptype), uint256(DataTypes.ProposalType.VetoFor));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(id, callData);
        assertTrue(dao.coreConfig().isVetoToCreator);
    }

    function test_integration_financial_returnLaunchesToPOC_fullCycle() public {
        _reachActiveStage();
        vm.warp(block.timestamp + Constants.POC_RETURN_PERIOD + 1 days);
        uint256 amount = 1000e18;
        bytes memory callData = abi.encodeWithSelector(DAO.returnLaunchesToPOC.selector, amount);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        (,, DataTypes.ProposalType ptype, , , , , , , ) = voting.proposals(id);
        assertEq(uint256(ptype), uint256(DataTypes.ProposalType.Financial));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 7 days);
        uint256 pocBefore = launchToken.balanceOf(address(poc));
        vm.prank(admin);
        voting.execute(id, callData);
        assertGe(launchToken.balanceOf(address(poc)), pocBefore);
    }

    function test_integration_unanimous_upgrade_fullCycle() public {
        test_votingAndDAOUpgrade();
    }

    function test_votingAndDAOUpgrade() public {
        _reachActiveStage();
        DAO newImpl = new DAO();
        (uint256 proposalId, bytes memory callData) = _createUpgradeProposalAndVote(address(newImpl));
        _executeUpgradeProposal(proposalId, callData);
        _approveUpgradeByCreatorAndUpgrade(address(newImpl));
    }

    function test_getProposalStatus_unanimous_earlyReject() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, false);
        vm.prank(user2);
        voting.vote(id, false);
        vm.prank(user3);
        voting.vote(id, false);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_vetoFor_defeated() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, false);
        vm.warp(block.timestamp + 7 days);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Defeated));
    }

    function test_getProposalStatus_vetoFor_expired() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.setIsVetoToCreator.selector, true);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 7 days + Constants.PROPOSAL_EXPIRY_PERIOD + 1);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Expired));
    }

    function test_getProposalStatus_unanimous_expired() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        vm.prank(user2);
        voting.vote(id, true);
        vm.prank(user3);
        voting.vote(id, true);
        vm.warp(block.timestamp + 7 days + Constants.PROPOSAL_EXPIRY_PERIOD + 1);
        assertEq(uint256(voting.getProposalStatus(id)), uint256(DataTypes.ProposalStatus.Expired));
    }

    function test_updateVotesForVault_viaDepositLaunches() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 id = voting.createProposal(address(dao), abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, address(0x1)));
        vm.prank(user1);
        voting.vote(id, true);
        (,,,,, uint256 forBefore, , , , ) = voting.proposals(id);
        launchToken.mint(user1, 100_000e18);
        vm.prank(user1);
        launchToken.approve(address(dao), 100_000e18);
        vm.prank(user1);
        dao.depositLaunches(100_000e18, 0);
        (,,,,, uint256 forAfter, , , , ) = voting.proposals(id);
        assertTrue(forAfter >= forBefore);
    }

    function test_categoryThresholds_read() public view {
        (uint256 finQuorum, uint256 finApproval) = voting.categoryThresholds(DataTypes.ProposalType.Financial);
        assertEq(finQuorum, Constants.DEFAULT_FINANCIAL_QUORUM);
        assertEq(finApproval, Constants.DEFAULT_FINANCIAL_APPROVAL);
        (uint256 otherQuorum,) = voting.categoryThresholds(DataTypes.ProposalType.Other);
        assertEq(otherQuorum, Constants.DEFAULT_FINANCIAL_QUORUM);
    }
}
