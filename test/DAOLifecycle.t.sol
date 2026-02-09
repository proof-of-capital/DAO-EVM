// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/DAOTestBase.sol";
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
}
