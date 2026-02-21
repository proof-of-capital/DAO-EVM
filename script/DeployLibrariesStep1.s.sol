// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import {Script, console} from "forge-std/Script.sol";

/// @title DeployLibrariesStep1Script
/// @notice Script for deploying external libraries without dependencies
contract DeployLibrariesStep1Script is Script {
    string constant LIBRARY_ADDRESSES_FILE = "./.library_addresses";
    string constant ENV_FILE = "./.library_addresses.env";

    function run() public {
        vm.startBroadcast();

        address vaultLibrary = deployCode("src/libraries/external/VaultLibrary.sol:VaultLibrary");
        address orderbook = deployCode("src/libraries/external/Orderbook.sol:Orderbook");
        address oracleLibrary = deployCode("src/libraries/external/OracleLibrary.sol:OracleLibrary");
        address multisigSwapLibrary = deployCode("src/libraries/external/MultisigSwapLibrary.sol:MultisigSwapLibrary");
        address multisigLPLibrary = deployCode("src/libraries/external/MultisigLPLibrary.sol:MultisigLPLibrary");

        require(vaultLibrary != address(0), "Failed to deploy VaultLibrary");
        require(orderbook != address(0), "Failed to deploy Orderbook");
        require(oracleLibrary != address(0), "Failed to deploy OracleLibrary");
        require(multisigSwapLibrary != address(0), "Failed to deploy MultisigSwapLibrary");
        require(multisigLPLibrary != address(0), "Failed to deploy MultisigLPLibrary");

        console.log("VaultLibrary deployed at:", vaultLibrary);
        console.log("Orderbook deployed at:", orderbook);
        console.log("OracleLibrary deployed at:", oracleLibrary);
        console.log("MultisigSwapLibrary deployed at:", multisigSwapLibrary);
        console.log("MultisigLPLibrary deployed at:", multisigLPLibrary);

        vm.sleep(5000);
        vm.stopBroadcast();

        writeLibraryAddresses(vaultLibrary, orderbook, oracleLibrary, multisigSwapLibrary, multisigLPLibrary);
        console.log("Library addresses successfully saved");
    }

    function writeLibraryAddresses(
        address vaultLibrary,
        address orderbook,
        address oracleLibrary,
        address multisigSwapLibrary,
        address multisigLPLibrary
    ) internal {
        string memory addressesJson = string(
            abi.encodePacked(
                '{"vaultLibrary":"',
                vm.toString(vaultLibrary),
                '",',
                '"orderbook":"',
                vm.toString(orderbook),
                '",',
                '"oracleLibrary":"',
                vm.toString(oracleLibrary),
                '",',
                '"multisigSwapLibrary":"',
                vm.toString(multisigSwapLibrary),
                '",',
                '"multisigLPLibrary":"',
                vm.toString(multisigLPLibrary),
                '"}'
            )
        );
        vm.writeFile(LIBRARY_ADDRESSES_FILE, addressesJson);
        console.log("Library addresses saved to", LIBRARY_ADDRESSES_FILE);

        string memory envContent = string(
            abi.encodePacked(
                "vaultLibrary=",
                vm.toString(vaultLibrary),
                "\n",
                "orderbook=",
                vm.toString(orderbook),
                "\n",
                "oracleLibrary=",
                vm.toString(oracleLibrary),
                "\n",
                "multisigSwapLibrary=",
                vm.toString(multisigSwapLibrary),
                "\n",
                "multisigLPLibrary=",
                vm.toString(multisigLPLibrary),
                "\n"
            )
        );

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
