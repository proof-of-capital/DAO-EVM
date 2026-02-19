// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import "../src/PriceOracle.sol";
import "../src/libraries/NetworkConfig.sol";
import "../src/libraries/DataTypes.sol";

/// @title DeployPriceOracleScript
/// @notice Script for deploying PriceOracle contract
contract DeployPriceOracleScript is Script {
    string constant DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
    string constant ENV_FILE = "./.deployment_addresses.env";

    function run() external {
        address dao = vm.envAddress("DAO");
        address creator = vm.envAddress("MULTISIG");
        address whitelist;
        try vm.envAddress("WHITELIST_ORACLES") returns (address w) {
            whitelist = w;
        } catch {
            whitelist = address(0);
        }

        uint256 chainId = block.chainid;
        DataTypes.SourceConfig[] memory configs = NetworkConfig.getNetworkConfig(chainId);

        require(configs.length > 0, "No assets configured for this chain");

        vm.startBroadcast();

        PriceOracle priceOracle = new PriceOracle(dao, creator, whitelist, configs);

        console.log("PriceOracle deployed at:", address(priceOracle));
        console.log("Initialized sources count:", configs.length);

        vm.sleep(5000);
        vm.stopBroadcast();

        writeDeploymentAddresses(address(priceOracle));
        console.log("Deployment addresses successfully saved");
    }

    function writeDeploymentAddresses(address priceOracle) internal {
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

        addressesJson = string(abi.encodePacked(addressesJson, '"priceOracle":"', vm.toString(priceOracle), '"}'));
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent =
            string(abi.encodePacked(existingContent, "PRICE_ORACLE=", vm.toString(priceOracle), "\n"));

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
