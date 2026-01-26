// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";

/// @title DeployLibrariesStep2Script
/// @notice Script for deploying external libraries with dependencies
/// @dev Libraries addresses from step1 should be provided via --libraries flag in forge script command
contract DeployLibrariesStep2Script is Script {
    string constant LIBRARY_ADDRESSES_FILE = "./.library_addresses";
    string constant ENV_FILE = "./.library_addresses.env";

    function run() public {
        vm.startBroadcast();

        address pocLibrary = deployCode("src/libraries/external/POCLibrary.sol:POCLibrary");
        address fundraisingLibrary = deployCode("src/libraries/external/FundraisingLibrary.sol:FundraisingLibrary");
        address exitQueueLibrary = deployCode("src/libraries/external/ExitQueueLibrary.sol:ExitQueueLibrary");
        address lpTokenLibrary = deployCode("src/libraries/external/LPTokenLibrary.sol:LPTokenLibrary");
        address profitDistributionLibrary = deployCode("src/libraries/external/ProfitDistributionLibrary.sol:ProfitDistributionLibrary");
        address rewardsLibrary = deployCode("src/libraries/external/RewardsLibrary.sol:RewardsLibrary");
        address dissolutionLibrary = deployCode("src/libraries/external/DissolutionLibrary.sol:DissolutionLibrary");
        address creatorLibrary = deployCode("src/libraries/external/CreatorLibrary.sol:CreatorLibrary");

        require(pocLibrary != address(0), "Failed to deploy POCLibrary");
        require(fundraisingLibrary != address(0), "Failed to deploy FundraisingLibrary");
        require(exitQueueLibrary != address(0), "Failed to deploy ExitQueueLibrary");
        require(lpTokenLibrary != address(0), "Failed to deploy LPTokenLibrary");
        require(profitDistributionLibrary != address(0), "Failed to deploy ProfitDistributionLibrary");
        require(rewardsLibrary != address(0), "Failed to deploy RewardsLibrary");
        require(dissolutionLibrary != address(0), "Failed to deploy DissolutionLibrary");
        require(creatorLibrary != address(0), "Failed to deploy CreatorLibrary");

        console.log("POCLibrary deployed at:", pocLibrary);
        console.log("FundraisingLibrary deployed at:", fundraisingLibrary);
        console.log("ExitQueueLibrary deployed at:", exitQueueLibrary);
        console.log("LPTokenLibrary deployed at:", lpTokenLibrary);
        console.log("ProfitDistributionLibrary deployed at:", profitDistributionLibrary);
        console.log("RewardsLibrary deployed at:", rewardsLibrary);
        console.log("DissolutionLibrary deployed at:", dissolutionLibrary);
        console.log("CreatorLibrary deployed at:", creatorLibrary);

        vm.sleep(5000);
        vm.stopBroadcast();

        writeLibraryAddresses(
            pocLibrary,
            fundraisingLibrary,
            exitQueueLibrary,
            lpTokenLibrary,
            profitDistributionLibrary,
            rewardsLibrary,
            dissolutionLibrary,
            creatorLibrary
        );
        console.log("Library addresses successfully saved");
    }

    function writeLibraryAddresses(
        address pocLibrary,
        address fundraisingLibrary,
        address exitQueueLibrary,
        address lpTokenLibrary,
        address profitDistributionLibrary,
        address rewardsLibrary,
        address dissolutionLibrary,
        address creatorLibrary
    ) internal {
        string memory existingContent = "";
        try vm.readFile(ENV_FILE) returns (string memory content) {
            existingContent = string(abi.encodePacked(content));
        } catch {}

        string memory addressesJson = "";
        try vm.readFile(LIBRARY_ADDRESSES_FILE) returns (string memory content) {
            addressesJson = content;
            if (bytes(addressesJson).length > 0 && bytes(addressesJson)[bytes(addressesJson).length - 1] != "}") {
                addressesJson = string(abi.encodePacked(addressesJson, ","));
            } else {
                addressesJson = "{";
            }
        } catch {
            addressesJson = "{";
        }

        addressesJson = string(
            abi.encodePacked(
                addressesJson,
                '"pocLibrary":"',
                vm.toString(pocLibrary),
                '",',
                '"fundraisingLibrary":"',
                vm.toString(fundraisingLibrary),
                '",',
                '"exitQueueLibrary":"',
                vm.toString(exitQueueLibrary),
                '",',
                '"lpTokenLibrary":"',
                vm.toString(lpTokenLibrary),
                '",',
                '"profitDistributionLibrary":"',
                vm.toString(profitDistributionLibrary),
                '",',
                '"rewardsLibrary":"',
                vm.toString(rewardsLibrary),
                '",',
                '"dissolutionLibrary":"',
                vm.toString(dissolutionLibrary),
                '",',
                '"creatorLibrary":"',
                vm.toString(creatorLibrary),
                '"}'
            )
        );
        vm.writeFile(LIBRARY_ADDRESSES_FILE, addressesJson);
        console.log("Library addresses saved to", LIBRARY_ADDRESSES_FILE);

        string memory envContent = string(
            abi.encodePacked(
                existingContent,
                "pocLibrary=",
                vm.toString(pocLibrary),
                "\n",
                "fundraisingLibrary=",
                vm.toString(fundraisingLibrary),
                "\n",
                "exitQueueLibrary=",
                vm.toString(exitQueueLibrary),
                "\n",
                "lpTokenLibrary=",
                vm.toString(lpTokenLibrary),
                "\n",
                "profitDistributionLibrary=",
                vm.toString(profitDistributionLibrary),
                "\n",
                "rewardsLibrary=",
                vm.toString(rewardsLibrary),
                "\n",
                "dissolutionLibrary=",
                vm.toString(dissolutionLibrary),
                "\n",
                "creatorLibrary=",
                vm.toString(creatorLibrary),
                "\n"
            )
        );

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
