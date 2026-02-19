// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";
import "../src/PrivateSale.sol";
import "../src/DAO.sol";

/// @title DeployPrivateSaleScript
/// @notice Script for deploying PrivateSale contract
contract DeployPrivateSaleScript is Script {
    string constant DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
    string constant ENV_FILE = "./.deployment_addresses.env";

    function run() external {
        address dao = vm.envAddress("DAO");
        address mainCollateral = vm.envAddress("MAIN_COLLATERAL");
        address[] memory pocContracts = vm.envAddress("POC_CONTRACTS", ",");

        require(pocContracts.length > 0, "POC contracts array is empty");

        uint256 cliffDuration = vm.envUint("PRIVATE_SALE_CLIFF_DURATION");
        uint256 vestingPeriods = vm.envUint("PRIVATE_SALE_VESTING_PERIODS");
        uint256 vestingPeriodDuration = vm.envUint("PRIVATE_SALE_VESTING_PERIOD_DURATION");

        vm.startBroadcast();

        PrivateSale privateSale =
            new PrivateSale(dao, mainCollateral, pocContracts, cliffDuration, vestingPeriods, vestingPeriodDuration);

        console.log("PrivateSale deployed at:", address(privateSale));

        DAO(payable(dao)).registerPrivateSale(address(privateSale));
        console.log("PrivateSale registered in DAO");

        vm.sleep(5000);
        vm.stopBroadcast();

        writeDeploymentAddresses(address(privateSale));
        console.log("Deployment addresses successfully saved");
    }

    function writeDeploymentAddresses(address privateSale) internal {
        string memory existingContent = "";
        try vm.readFile(ENV_FILE) returns (string memory content) {
            existingContent = string(abi.encodePacked(content));
        } catch {}

        string memory addressesJson = "";
        try vm.readFile(DEPLOYMENT_ADDRESSES_FILE) returns (string memory content) {
            addressesJson = content;
            if (bytes(addressesJson).length > 0 && bytes(addressesJson)[bytes(addressesJson).length - 1] != "}") {
                addressesJson = string(abi.encodePacked(addressesJson, ","));
            } else {
                addressesJson = "{";
            }
        } catch {
            addressesJson = "{";
        }

        addressesJson = string(abi.encodePacked(addressesJson, '"privateSale":"', vm.toString(privateSale), '"}'));
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent =
            string(abi.encodePacked(existingContent, "PRIVATE_SALE=", vm.toString(privateSale), "\n"));

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
