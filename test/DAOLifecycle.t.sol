// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "./helpers/DAOTestBase.sol";
import "../src/interfaces/IDAO.sol";
import "../src/libraries/DataTypes.sol";

contract DAOLifecycleTest is DAOTestBase {
    function test_fullLifecycleToActive() external {
        _setCreator(creator);

        _createVaultAndDeposit(user1, 100_000e18);
        _createVaultAndDeposit(user2, 60_000e18);
        _createVaultAndDeposit(user3, 50_000e18);

        _finalizeFundraising();
        _exchangeAllPOCs();
        _finalizeExchange();
        _provideLPTokens();

        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));
    }

    function test_transitionToClosingAndBackToActive() external {
        _reachActiveStage();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();

        vm.prank(admin);
        dao.enterClosingStage();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Closing));

        vm.prank(user2);
        dao.cancelExit();

        vm.prank(admin);
        dao.returnToActiveStage();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));
    }

    function test_enterClosingStage_revertsWhenNotActive() external {
        _reachActiveStage();
        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();
        vm.prank(admin);
        dao.enterClosingStage();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Closing));

        vm.expectRevert(IDAO.InvalidStage.selector);
        vm.prank(admin);
        dao.enterClosingStage();
    }

    function test_returnToActiveStage_revertsWhenNotClosing() external {
        _reachActiveStage();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        vm.expectRevert(IDAO.InvalidStage.selector);
        vm.prank(admin);
        dao.returnToActiveStage();
    }
}
