// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";

contract DAOLoanAndDropTest is DAOTestBase {
    function test_getLoanState_initialZero() public {
        _reachActiveStage();
        (,, uint256 principal, uint256 interestAccrued,,) = dao.creatorLoanDrop();
        assertEq(principal, 0);
        assertEq(interestAccrued, 0);
    }

    function test_creatorVaultId_hasSharesAfterFinalizeExchange() public {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);
        _createVaultAndDeposit(user2, 60_000e18);
        _createVaultAndDeposit(user3, 50_000e18);
        _finalizeFundraising();
        _exchangeAllPOCs();
        uint256 supplyBefore = dao.totalSharesSupply();
        _finalizeExchange();
        uint256 supplyAfter = dao.totalSharesSupply();
        assertTrue(supplyAfter > supplyBefore, "totalSharesSupply should increase after infra shares mint");
        (uint256 cvId,,,,,) = dao.creatorLoanDrop();
        assertTrue(cvId != 0, "creatorVaultId should be set");
        DataTypes.Vault memory v = dao.vaults(cvId);
        assertTrue(v.shares > 0, "creator vault should have infra shares");
        assertEq(v.primary, creator);
    }

    function test_takeLoanInLaunches_viaGovernance_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1);

        uint256 balanceBefore = launchToken.balanceOf(creator);
        uint256 creatorPercentBefore = dao.getDaoState().creatorProfitPercent;

        bytes memory callData = abi.encodeWithSelector(DAO.takeLoanInLaunches.selector, 10_000e18, false);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.prank(creator);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);

        (,, uint256 principal, uint256 interestAccrued,,) = dao.creatorLoanDrop();
        assertEq(principal, 10_000e18);
        assertEq(interestAccrued, 0);
        assertTrue(launchToken.balanceOf(creator) == balanceBefore + 10_000e18, "creator should receive launches");
        assertTrue(dao.getDaoState().creatorProfitPercent < creatorPercentBefore, "creator share should decrease");
    }

    function test_takeLoanInLaunches_revert_allocationTooSoon() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        bytes memory callData = abi.encodeWithSelector(DAO.takeLoanInLaunches.selector, 10_000e18, false);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.prank(creator);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        vm.expectRevert(IDAO.AllocationTooSoon.selector);
        voting.execute(proposalId, callData);
    }

    function test_repayLoanInLaunches_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1);

        bytes memory takeCallData = abi.encodeWithSelector(DAO.takeLoanInLaunches.selector, 5_000e18, false);
        vm.prank(admin);
        uint256 takeProposalId = voting.createProposal(address(dao), takeCallData);
        vm.prank(user1);
        voting.vote(takeProposalId, true);
        vm.prank(user2);
        voting.vote(takeProposalId, true);
        vm.prank(user3);
        voting.vote(takeProposalId, true);
        vm.prank(creator);
        voting.vote(takeProposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(takeProposalId, takeCallData);

        uint256 creatorPercentAfterLoan = dao.getDaoState().creatorProfitPercent;
        (,, uint256 principal,,,) = dao.creatorLoanDrop();
        assertEq(principal, 5_000e18);

        vm.warp(block.timestamp + 365 days);
        (,, uint256 principalBeforeRepay,,,) = dao.creatorLoanDrop();
        uint256 interestAccrued = (principalBeforeRepay * Constants.LOAN_APR_BPS * (365 days))
            / (Constants.BASIS_POINTS * Constants.SECONDS_PER_YEAR);
        uint256 totalOwed = principalBeforeRepay + interestAccrued;
        launchToken.mint(creator, totalOwed);
        vm.startPrank(creator);
        launchToken.approve(address(dao), totalOwed);
        dao.repayLoanInLaunches(totalOwed);
        vm.stopPrank();

        (,, uint256 principalAfter, uint256 interestAfter,,) = dao.creatorLoanDrop();
        assertEq(principalAfter, 0);
        assertEq(interestAfter, 0);
        assertTrue(dao.getDaoState().creatorProfitPercent > creatorPercentAfterLoan, "creator share should restore");
    }

    function test_dropLaunchesAsProfit_success() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        uint256 dropAmount =
            (dao.accountedBalance(address(launchToken)) * Constants.DROP_MAX_PERCENT) / Constants.BASIS_POINTS;
        if (dropAmount == 0) return;
        launchToken.mint(creator, dropAmount);
        vm.prank(creator);
        launchToken.approve(address(dao), dropAmount);

        bytes memory callData = abi.encodeWithSelector(DAO.dropLaunchesAsProfit.selector, dropAmount);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.prank(creator);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);

        (,,,,, uint256 dropUsed) = dao.creatorLoanDrop();
        assertTrue(dropUsed == dropAmount);
    }

    function test_dropLaunchesAsProfit_revert_whenLoanActive() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD + 1);
        bytes memory takeCallData = abi.encodeWithSelector(DAO.takeLoanInLaunches.selector, 1_000e18, false);
        vm.prank(admin);
        uint256 takeProposalId = voting.createProposal(address(dao), takeCallData);
        vm.prank(user1);
        voting.vote(takeProposalId, true);
        vm.prank(user2);
        voting.vote(takeProposalId, true);
        vm.prank(user3);
        voting.vote(takeProposalId, true);
        vm.prank(creator);
        voting.vote(takeProposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(takeProposalId, takeCallData);

        vm.warp(block.timestamp + Constants.PROPOSAL_CREATION_COOLDOWN + 1);
        uint256 dropAmount = 100e18;
        launchToken.mint(creator, dropAmount);
        vm.prank(creator);
        launchToken.approve(address(dao), dropAmount);
        bytes memory dropCallData = abi.encodeWithSelector(DAO.dropLaunchesAsProfit.selector, dropAmount);
        vm.prank(admin);
        uint256 dropProposalId = voting.createProposal(address(dao), dropCallData);
        vm.prank(user1);
        voting.vote(dropProposalId, true);
        vm.prank(user2);
        voting.vote(dropProposalId, true);
        vm.prank(user3);
        voting.vote(dropProposalId, true);
        vm.prank(creator);
        voting.vote(dropProposalId, true);
        vm.warp(block.timestamp + Constants.DEFAULT_VOTING_PERIOD + 1);
        vm.prank(admin);
        vm.expectRevert(IDAO.LoanActive.selector);
        voting.execute(dropProposalId, dropCallData);
    }

    function test_dropLaunchesAsProfit_revert_exceedsDropLimit() public {
        _reachActiveStage();
        vm.warp(block.timestamp + 1 days);
        uint256 maxDrop =
            (dao.accountedBalance(address(launchToken)) * Constants.DROP_MAX_PERCENT) / Constants.BASIS_POINTS;
        if (maxDrop < 2) return;
        uint256 overAmount = maxDrop + 1;
        launchToken.mint(creator, overAmount);
        vm.prank(creator);
        launchToken.approve(address(dao), overAmount);
        bytes memory callData = abi.encodeWithSelector(DAO.dropLaunchesAsProfit.selector, overAmount);
        vm.prank(admin);
        uint256 proposalId = voting.createProposal(address(dao), callData);
        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
        vm.prank(creator);
        voting.vote(proposalId, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        vm.expectRevert(IDAO.ExceedsDropLimit.selector);
        voting.execute(proposalId, callData);
    }
}
