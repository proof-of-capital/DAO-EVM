// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import "../src/WhitelistOracles.sol";

/// @title DeployWhitelistOraclesScript
/// @notice Script for deploying WhitelistOracles (central feed registry; one per all projects)
contract DeployWhitelistOraclesScript is Script {
    string constant DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
    string constant ENV_FILE = "./.deployment_addresses.env";

    function run() external {
        address dao = vm.envAddress("DAO");
        address creator = vm.envAddress("MULTISIG");

        vm.startBroadcast();

        WhitelistOracles whitelistOracles = new WhitelistOracles(dao, creator);

        console.log("WhitelistOracles deployed at:", address(whitelistOracles));

        vm.sleep(5000);
        vm.stopBroadcast();

        writeDeploymentAddresses(address(whitelistOracles));
        console.log("Deployment addresses successfully saved");
    }

    function writeDeploymentAddresses(address whitelistOracles) internal {
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

        addressesJson =
            string(abi.encodePacked(addressesJson, '"whitelistOracles":"', vm.toString(whitelistOracles), '"}'));
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent =
            string(abi.encodePacked(existingContent, "WHITELIST_ORACLES=", vm.toString(whitelistOracles), "\n"));
        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
