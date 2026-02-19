// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import "../src/ReturnWallet.sol";

/// @title DeployReturnWalletScript
/// @notice Script for deploying ReturnWallet contract
contract DeployReturnWalletScript is Script {
    string constant DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
    string constant ENV_FILE = "./.deployment_addresses.env";

    function run() external {
        address dao = vm.envAddress("DAO");
        address launchToken = vm.envAddress("LAUNCH_TOKEN");
        address admin = vm.envAddress("ADMIN");
        address priceOracle = vm.envAddress("PRICE_ORACLE");

        vm.startBroadcast();

        ReturnWallet returnWallet = new ReturnWallet(dao, launchToken, admin, priceOracle);

        console.log("ReturnWallet deployed at:", address(returnWallet));

        vm.sleep(5000);
        vm.stopBroadcast();

        writeDeploymentAddresses(address(returnWallet));
        console.log("Deployment addresses successfully saved");
    }

    function writeDeploymentAddresses(address returnWallet) internal {
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

        addressesJson = string(abi.encodePacked(addressesJson, '"returnWallet":"', vm.toString(returnWallet), '"}'));
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent =
            string(abi.encodePacked(existingContent, "RETURN_WALLET=", vm.toString(returnWallet), "\n"));

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
