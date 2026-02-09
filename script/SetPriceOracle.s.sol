// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import "../src/DAO.sol";

/// @title SetPriceOracleScript
/// @notice Script for setting price oracle in DAO (one-time, admin only)
contract SetPriceOracleScript is Script {
    function run() external {
        address dao = vm.envAddress("DAO");
        address priceOracle = vm.envAddress("PRICE_ORACLE");

        vm.startBroadcast();

        DAO(payable(dao)).setPriceOracle(priceOracle);

        console.log("Price oracle set to:", priceOracle);

        vm.sleep(5000);
        vm.stopBroadcast();
    }
}
