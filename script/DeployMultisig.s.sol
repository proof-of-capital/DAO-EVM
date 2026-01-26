// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import {Script, console} from "forge-std/Script.sol";
import "../src/Multisig.sol";
import "../src/interfaces/IMultisig.sol";

/// @title DeployMultisigScript
/// @notice Script for deploying Multisig contract
contract DeployMultisigScript is Script {
    string constant DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
    string constant ENV_FILE = "./.deployment_addresses.env";

    function run() external {
        address dao = vm.envAddress("DAO");
        address admin = vm.envOr("MULTISIG_ADMIN", vm.envAddress("ADMIN"));

        address[] memory primaryAddrs = vm.envAddress("MULTISIG_PRIMARY_ADDRESSES", ",");
        address[] memory backupAddrs = vm.envAddress("MULTISIG_BACKUP_ADDRESSES", ",");
        address[] memory emergencyAddrs = vm.envAddress("MULTISIG_EMERGENCY_ADDRESSES", ",");

        require(primaryAddrs.length == 8, "Invalid primary addresses length");
        require(backupAddrs.length == 8, "Invalid backup addresses length");
        require(emergencyAddrs.length == 8, "Invalid emergency addresses length");

        uint256 targetCollateralAmount = vm.envUint("MULTISIG_TARGET_COLLATERAL_AMOUNT");
        address uniswapV3Router = vm.envAddress("UNISWAP_V3_ROUTER");
        address uniswapV3PositionManager = vm.envAddress("UNISWAP_V3_POSITION_MANAGER");

        IMultisig.LPPoolParams memory lpPoolParams = IMultisig.LPPoolParams({
            fee: uint24(vm.envUint("LP_POOL_FEE")),
            tickLower: int24(vm.envInt("LP_POOL_TICK_LOWER")),
            tickUpper: int24(vm.envInt("LP_POOL_TICK_UPPER")),
            amount0Min: vm.envUint("LP_POOL_AMOUNT0_MIN"),
            amount1Min: vm.envUint("LP_POOL_AMOUNT1_MIN")
        });

        address newMarketMaker = vm.envAddress("NEW_MARKET_MAKER");

        IMultisig.CollateralConstructorParams[] memory collateralParams = new IMultisig.CollateralConstructorParams[](0);
        if (vm.envOr("ADD_COLLATERALS", false)) {
            address[] memory collateralTokens = vm.envAddress("COLLATERAL_ADDRESSES", ",");
            address[] memory priceFeeds = vm.envAddress("PRICE_FEED_ADDRESSES", ",");
            address[] memory routers = vm.envAddress("COLLATERAL_ROUTERS", ",");
            bytes[] memory swapPaths = vm.envBytes("COLLATERAL_SWAP_PATHS", ",");

            require(
                collateralTokens.length == priceFeeds.length
                    && priceFeeds.length == routers.length && routers.length == swapPaths.length,
                "Collateral params length mismatch"
            );

            collateralParams = new IMultisig.CollateralConstructorParams[](collateralTokens.length);
            for (uint256 i = 0; i < collateralTokens.length; i++) {
                collateralParams[i] = IMultisig.CollateralConstructorParams({
                    token: collateralTokens[i],
                    priceFeed: priceFeeds[i],
                    router: routers[i],
                    swapPath: swapPaths[i]
                });
            }
        }

        vm.startBroadcast();

        Multisig multisig = new Multisig(
            primaryAddrs,
            backupAddrs,
            emergencyAddrs,
            admin,
            dao,
            targetCollateralAmount,
            uniswapV3Router,
            uniswapV3PositionManager,
            lpPoolParams,
            collateralParams,
            newMarketMaker
        );

        console.log("Multisig deployed at:", address(multisig));

        vm.sleep(5000);
        vm.stopBroadcast();

        writeDeploymentAddresses(address(multisig));
        console.log("Deployment addresses successfully saved");
    }

    function writeDeploymentAddresses(address multisig) internal {
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

        addressesJson = string(
            abi.encodePacked(addressesJson, '"multisig":"', vm.toString(multisig), '"}')
        );
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent = string(
            abi.encodePacked(existingContent, "MULTISIG=", vm.toString(multisig), "\n")
        );

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
