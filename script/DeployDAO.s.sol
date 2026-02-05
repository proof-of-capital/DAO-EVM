// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

// Proof of Capital is a technology for managing the issue of tokens that are backed by capital.
// The contract allows you to block the desired part of the issue for a selected period with a
// guaranteed buyback under pre-set conditions.

// During the lock-up period, only the market maker appointed by the contract creator has the
// right to buyback the tokens. Starting two months before the lock-up ends, any token holders
// can interact with the contract. They have the right to return their purchased tokens to the
// contract in exchange for the collateral.

// The goal of our technology is to create a market for assets backed by capital and
// transparent issuance management conditions.

// You can integrate the provided contract and Proof of Capital technology into your token if
// you specify the royalty wallet address of our project, listed on our website:
// https://proofofcapital.org

// All royalties collected are automatically used to repurchase the project's core token, as
// specified on the website, and are returned to the contract.

pragma solidity ^0.8.20;

import "forge-std/Script.sol";
import "../src/DAO.sol";
import "../src/Voting.sol";
import "../src/libraries/DataTypes.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

/// @title Deploy script for DAO system
/// @notice Deploys DAO and Voting contracts with initial configuration
contract DeployDAO is Script {
    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");

        // Required parameters
        address launchTokenAddress = vm.envAddress("LAUNCH_TOKEN_ADDRESS");
        address mainCollateralAddress = vm.envAddress("MAIN_COLLATERAL_ADDRESS"); // USDT
        address creatorAddress = address(0); // Will be set later via setCreator

        // Fundraising parameters (with defaults)
        uint256 creatorProfitPercent = vm.envOr("CREATOR_PROFIT_PERCENT", uint256(4000)); // 40%
        uint256 creatorInfraPercent = vm.envOr("CREATOR_INFRA_PERCENT", uint256(1000)); // 10%
        address royaltyRecipient = vm.envOr("ROYALTY_RECIPIENT", address(0)); // Royalty recipient (e.g., POC1)
        uint256 royaltyPercent = vm.envOr("ROYALTY_PERCENT", uint256(1000)); // 10% royalty
        uint256 minDeposit = vm.envOr("MIN_DEPOSIT_USD", uint256(1000e18)); // $1000
        uint256 minLaunchDeposit = vm.envOr("MIN_LAUNCH_DEPOSIT", uint256(10000e18)); // 10k launches minimum
        uint256 sharePrice = vm.envOr("SHARE_PRICE_USD", uint256(1000e18)); // $1000
        uint256 launchPrice = vm.envOr("LAUNCH_PRICE_USD", uint256(0.1e18)); // $0.1
        uint256 targetAmountMainCollateral = vm.envOr("TARGET_AMOUNT_USD", uint256(200000e18)); // $200k
        uint256 fundraisingDuration = vm.envOr("FUNDRAISING_DURATION", uint256(30 days)); // 30 days
        uint256 extensionPeriod = vm.envOr("EXTENSION_PERIOD", uint256(14 days)); // 14 days

        vm.startBroadcast(deployerPrivateKey);

        address[] memory collateralTokens = new address[](0);

        // Prepare routers and reward tokens for constructor
        address[] memory routers;
        address[] memory tokens; // Deprecated: kept for backward compatibility
        DataTypes.RewardTokenConstructorParams[] memory rewardTokenParams;

        // Optional: Load routers if configured
        if (vm.envOr("ADD_ROUTERS", false)) {
            routers = vm.envAddress("ROUTER_ADDRESSES", ",");
        }

        // Optional: Load additional reward tokens if configured
        if (vm.envOr("ADD_REWARD_TOKENS", false)) {
            address[] memory rewardTokens = vm.envAddress("REWARD_TOKEN_ADDRESSES", ",");
            rewardTokenParams = new DataTypes.RewardTokenConstructorParams[](rewardTokens.length);
            for (uint256 i = 0; i < rewardTokens.length; i++) {
                rewardTokenParams[i] = DataTypes.RewardTokenConstructorParams({token: rewardTokens[i]});
            }
        }

        // Prepare POC contracts for constructor
        DataTypes.POCConstructorParams[] memory pocParams;

        // Optional: Load POC contracts if configured
        // Note: POC params should be loaded from environment if needed
        // For now, using empty array - POC contracts can be added later via addPOCContract

        // Orderbook parameters (required)
        DataTypes.OrderbookConstructorParams memory orderbookParams = DataTypes.OrderbookConstructorParams({
            initialPrice: vm.envOr("ORDERBOOK_INITIAL_PRICE", uint256(0.1e18)), // $0.1
            initialVolume: vm.envOr("ORDERBOOK_INITIAL_VOLUME", uint256(1000e18)), // 1000 tokens
            priceStepPercent: vm.envOr("ORDERBOOK_PRICE_STEP_PERCENT", uint256(500)), // 5% = 500 basis points
            volumeStepPercent: vm.envOr("ORDERBOOK_VOLUME_STEP_PERCENT", int256(-100)), // -1% = -100 basis points
            proportionalityCoefficient: vm.envOr("ORDERBOOK_PROPORTIONALITY_COEFFICIENT", uint256(7500)), // 0.75 = 7500 basis points
            totalSupply: vm.envOr("ORDERBOOK_TOTAL_SUPPLY", uint256(1e27)) // 1 billion = 1e27 (1e9 * 1e18)
        });

        // Deploy Voting contract first (before DAO)
        Voting voting = new Voting();
        console.log("Voting deployed at:", address(voting));

        address priceOracleAddress = vm.envAddress("PRICE_ORACLE_ADDRESS");

        // Build constructor params
        DataTypes.ConstructorParams memory params = DataTypes.ConstructorParams({
            launchToken: launchTokenAddress,
            mainCollateral: mainCollateralAddress,
            creator: creatorAddress,
            creatorProfitPercent: creatorProfitPercent,
            creatorInfraPercent: creatorInfraPercent,
            royaltyRecipient: royaltyRecipient,
            royaltyPercent: royaltyPercent,
            minDeposit: minDeposit,
            minLaunchDeposit: minLaunchDeposit,
            sharePrice: sharePrice,
            launchPrice: launchPrice,
            targetAmountMainCollateral: targetAmountMainCollateral,
            fundraisingDuration: fundraisingDuration,
            extensionPeriod: extensionPeriod,
            collateralTokens: collateralTokens,
            routers: routers,
            tokens: tokens, // Deprecated: kept for backward compatibility
            pocParams: pocParams,
            rewardTokenParams: rewardTokenParams,
            orderbookParams: orderbookParams,
            primaryLPTokenType: DataTypes.LPTokenType.V2, // Default to V2, can be changed
            v3LPPositions: new DataTypes.V3LPPositionParams[](0), // Empty array by default
            allowedExitTokens: new address[](0), // Empty array by default, can be populated
            launchTokenPricePaths: DataTypes.TokenPricePathsParams({
                v2Paths: new DataTypes.PricePathV2Params[](0),
                v3Paths: new DataTypes.PricePathV3Params[](0),
                minLiquidity: 1000e18
            }),
            priceOracle: priceOracleAddress,
            votingContract: address(voting), // Set Voting address
            marketMaker: vm.envOr("MARKET_MAKER", address(0)) // Market maker address
        });

        // Deploy DAO implementation contract (upgradeable pattern)
        DAO daoImplementation = new DAO();
        console.log("DAO implementation deployed at:", address(daoImplementation));

        // Encode initialize function call
        bytes memory initData = abi.encodeWithSelector(DAO.initialize.selector, params);

        // Deploy ERC1967Proxy with implementation and initialize call
        ERC1967Proxy proxy = new ERC1967Proxy(address(daoImplementation), initData);
        DAO dao = DAO(payable(address(proxy)));
        console.log("DAO proxy deployed at:", address(dao));

        // Set DAO in Voting contract (only deployer, only once)
        voting.setDAO(address(dao));
        console.log("DAO set in Voting contract");

        // Log configuration
        if (collateralTokens.length > 0) {
            console.log("Sellable collaterals added in constructor:", collateralTokens.length);
        }
        if (routers.length > 0) {
            console.log("Routers added in constructor:", routers.length);
        }
        if (rewardTokenParams.length > 0) {
            console.log("Additional reward tokens added in constructor:", rewardTokenParams.length);
        }

        vm.stopBroadcast();

        writeDeploymentAddresses(
            address(daoImplementation),
            address(dao),
            address(voting),
            launchTokenAddress,
            mainCollateralAddress,
            dao.admin()
        );

        console.log("\n=== Deployment Summary ===");
        console.log("DAO Implementation:", address(daoImplementation));
        console.log("DAO Proxy:", address(dao));
        console.log("Voting:", address(voting));
        console.log("Launch Token:", launchTokenAddress);
        console.log("Main Collateral (USDT):", mainCollateralAddress);
        console.log("Creator:", creatorAddress);
        console.log("Admin:", dao.admin());
        console.log("\n=== Fundraising Config ===");
        console.log("Min Deposit:", minDeposit);
        console.log("Share Price:", sharePrice);
        console.log("Target Amount:", targetAmountMainCollateral);
        console.log("Creator Profit %:", creatorProfitPercent);
        console.log("Creator Infra %:", creatorInfraPercent);
        console.log("Royalty Recipient:", royaltyRecipient);
        console.log("Royalty %:", royaltyPercent);
    }

    function writeDeploymentAddresses(
        address daoImplementation,
        address dao,
        address voting,
        address launchToken,
        address mainCollateral,
        address admin
    ) internal {
        string memory DEPLOYMENT_ADDRESSES_FILE = "./.deployment_addresses";
        string memory ENV_FILE = "./.deployment_addresses.env";

        string memory addressesJson = string(
            abi.encodePacked(
                '{"daoImplementation":"',
                vm.toString(daoImplementation),
                '",',
                '"dao":"',
                vm.toString(dao),
                '",',
                '"voting":"',
                vm.toString(voting),
                '",',
                '"launchToken":"',
                vm.toString(launchToken),
                '",',
                '"mainCollateral":"',
                vm.toString(mainCollateral),
                '",',
                '"admin":"',
                vm.toString(admin),
                '"}'
            )
        );
        vm.writeFile(DEPLOYMENT_ADDRESSES_FILE, addressesJson);
        console.log("Deployment addresses saved to", DEPLOYMENT_ADDRESSES_FILE);

        string memory envContent = string(
            abi.encodePacked(
                "DAO_IMPLEMENTATION=",
                vm.toString(daoImplementation),
                "\n",
                "DAO=",
                vm.toString(dao),
                "\n",
                "VOTING=",
                vm.toString(voting),
                "\n",
                "LAUNCH_TOKEN=",
                vm.toString(launchToken),
                "\n",
                "MAIN_COLLATERAL=",
                vm.toString(mainCollateral),
                "\n",
                "ADMIN=",
                vm.toString(admin),
                "\n"
            )
        );

        vm.writeFile(ENV_FILE, envContent);
        console.log("Environment variables saved to", ENV_FILE);
    }
}
