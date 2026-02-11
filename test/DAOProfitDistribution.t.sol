// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/interfaces/IDAO.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/external/ProfitDistributionLibrary.sol";
import "../src/mocks/MockERC20.sol";

/// distributeProfit uses only nonReentrant and atActiveOrClosingStage; no onlyParticipantOrAdmin, so no Unauthorized test.
contract DAOProfitDistributionTest is DAOTestBase {
    function test_distributeProfit_noRevertWhenNoProfit_launchToken() external {
        _reachActiveStage();

        uint256 accountedBefore = dao.accountedBalance(address(launchToken));
        uint256 totalSupplyBefore = dao.totalSharesSupply();

        vm.prank(admin);
        dao.distributeProfit(address(launchToken), 0);

        assertEq(dao.accountedBalance(address(launchToken)), accountedBefore);
        assertEq(dao.totalSharesSupply(), totalSupplyBefore);
    }

    function test_distributeProfit_noRevertWhenNoProfit_lpToken() external {
        _reachActiveStage();

        uint256 accountedBefore = dao.accountedBalance(address(lpToken));
        uint256 totalSupplyBefore = dao.totalSharesSupply();
        uint256 royaltyBefore = lpToken.balanceOf(royaltyRecipient);
        uint256 creatorBefore = lpToken.balanceOf(creator);

        vm.prank(user1);
        dao.distributeProfit(address(lpToken), 0);

        assertEq(dao.accountedBalance(address(lpToken)), accountedBefore);
        assertEq(dao.totalSharesSupply(), totalSupplyBefore);
        assertEq(lpToken.balanceOf(royaltyRecipient), royaltyBefore);
        assertEq(lpToken.balanceOf(creator), creatorBefore);
    }

    function test_distributeProfit_noRevertWhenNoProfit_amountGreaterThanZero() external {
        _reachActiveStage();

        uint256 accountedBefore = dao.accountedBalance(address(lpToken));
        uint256 totalSupplyBefore = dao.totalSharesSupply();

        vm.prank(admin);
        dao.distributeProfit(address(lpToken), 1e18);

        assertEq(dao.accountedBalance(address(lpToken)), accountedBefore);
        assertEq(dao.totalSharesSupply(), totalSupplyBefore);
    }

    function test_distributeProfit_sellableCollateral() external {
        _reachActiveStage();

        (, bool active,,) = dao.sellableCollaterals(address(mainCollateral));
        assertTrue(active, "mainCollateral should be sellable");

        uint256 accountedBefore = dao.accountedBalance(address(mainCollateral));
        uint256 totalSupplyBefore = dao.totalSharesSupply();

        vm.prank(admin);
        dao.distributeProfit(address(mainCollateral), 0);

        assertTrue(dao.accountedBalance(address(mainCollateral)) >= accountedBefore, "accounted should not decrease");
        assertEq(dao.totalSharesSupply(), totalSupplyBefore);
    }

    function test_distributeProfit_revert_TokenNotAdded() external {
        _reachActiveStage();

        MockERC20 randomToken = new MockERC20("Random", "RND", 18);
        randomToken.mint(address(dao), 100e18);

        vm.prank(admin);
        vm.expectRevert(ProfitDistributionLibrary.TokenNotAdded.selector);
        dao.distributeProfit(address(randomToken), 0);
    }

    function test_distributeProfit_revert_InvalidStage() external {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);
        _createVaultAndDeposit(user2, 60_000e18);
        _createVaultAndDeposit(user3, 50_000e18);
        _finalizeFundraising();

        vm.prank(admin);
        vm.expectRevert(IDAO.InvalidStage.selector);
        dao.distributeProfit(address(mainCollateral), 0);
    }
}
