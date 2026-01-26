// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./DataTypes.sol";

/// @title NetworkConfig
/// @notice Configuration library containing asset addresses, price sources, and decimals for different networks
/// @dev This library centralizes all network-specific configurations for price oracle deployments
library NetworkConfig {
    /// @notice Get network configuration for a specific chain ID
    /// @param chainId The chain ID to get configuration for
    /// @return SourceConfig array containing asset, source, and decimals for each asset
    function getNetworkConfig(uint256 chainId) internal pure returns (DataTypes.SourceConfig[] memory) {
        if (chainId == 31337) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](3);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0x1111111111111111111111111111111111111111),
                source: address(0x3333333333333333333333333333333333333333),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0x2222222222222222222222222222222222222222),
                source: address(0x4444444444444444444444444444444444444444),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0x5555555555555555555555555555555555555555),
                source: address(0x6666666666666666666666666666666666666666),
                decimals: 8
            });

            return configs;
        } else if (chainId == 137) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](10);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0x2791Bca1f2de4661ED88A30C99A7a9449Aa84174),
                source: address(0xfE4A8cc5b5B2366C1B58Bea3858e81843581b2F7),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0x1BFD67037B42Cf73acF2047067bd4F2C47D9BfD6),
                source: address(0xDE31F8bFBD8c84b5360CFACCa3539B938dd78ae6),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0x7ceB23fD6bC0adD59E62ac25578270cFf1b9f619),
                source: address(0xF9680D99D6C9589e2a93a78A04A279e509205945),
                decimals: 8
            });
            configs[3] = DataTypes.SourceConfig({
                asset: address(0x0d500B1d8E8eF31E21C99d1Db9A6444d3ADf1270),
                source: address(0xAB594600376Ec9fD91F8e885dADF0CE036862dE0),
                decimals: 8
            });
            configs[4] = DataTypes.SourceConfig({
                asset: address(0xc2132D05D31c914a87C6611C10748AEb04B58e8F),
                source: address(0x0A6513e40db6EB1b165753AD52E80663aeA50545),
                decimals: 8
            });
            configs[5] = DataTypes.SourceConfig({
                asset: address(0x8f3Cf7ad23Cd3CaDbD9735AFf958023239c6A063),
                source: address(0x4746DeC9e833A82EC7C2C1356372CcF2cfcD2F3D),
                decimals: 8
            });
            configs[6] = DataTypes.SourceConfig({
                asset: address(0xD6DF932A45C0f255f85145f286eA0b292B21C90B),
                source: address(0x72484B12719E23115761D5DA1646945632979bB6),
                decimals: 8
            });
            configs[7] = DataTypes.SourceConfig({
                asset: address(0x53E0bca35eC356BD5ddDFebbD1Fc0fD03FaBad39),
                source: address(0xd9FFdb71EbE7496cC440152d43986Aae0AB76665),
                decimals: 8
            });
            configs[8] = DataTypes.SourceConfig({
                asset: address(0xd93f7E271cB87c23AaA73edC008A79646d1F9912),
                source: address(0x10C8264C0935b3B9870013e057f330Ff3e9C56dC),
                decimals: 8
            });
            configs[9] = DataTypes.SourceConfig({
                asset: address(0xb33EaAd8d922B1083446DC23f610c2567fB5180f),
                source: address(0xdf0Fb4e4F928d2dCB76f438575fDD8682386e13C),
                decimals: 8
            });

            return configs;
        } else if (chainId == 8453) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](6);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0x833589fCD6eDb6E08f4c7C32D4f71b54bdA02913),
                source: address(0x7e860098F58bBFC8648a4311b374B1D669a2bc6B),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0x4200000000000000000000000000000000000006),
                source: address(0x71041dddad3595F9CEd3DcCFBe3D1F4b0a16Bb70),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0xfde4C96c8593536E31F229EA8f37b2ADa2699bb2),
                source: address(0xf19d560eB8d2ADf07BD6D13ed03e1D11215721F9),
                decimals: 8
            });
            configs[3] = DataTypes.SourceConfig({
                asset: address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf),
                source: address(0x64c911996D3c6aC71f9b455B1E8E7266BcbD848F),
                decimals: 8
            });
            configs[4] = DataTypes.SourceConfig({
                asset: address(0x0b3e328455c4059EEb9e3f84b5543F74E24e7E1b),
                source: address(0xEaf310161c9eF7c813A14f8FEF6Fb271434019F7),
                decimals: 8
            });
            configs[5] = DataTypes.SourceConfig({
                asset: address(0x60a3E35Cc302bFA44Cb288Bc5a4F316Fdb1adb42),
                source: address(0xDAe398520e2B67cd3f27aeF9Cf14D93D927f8250),
                decimals: 8
            });

            return configs;
        } else if (chainId == 42161) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](7);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0xaf88d065e77c8cC2239327C5EDb3A432268e5831),
                source: address(0x50834F3163758fcC1Df9973b6e91f0F0F0434aD3),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0x2f2a2543B76A4166549F7aaB2e75Bef0aefC5B0f),
                source: address(0x6ce185860a4963106506C203335A2910413708e9),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0x82aF49447D8a07e3bd95BD0d56f35241523fBab1),
                source: address(0x639Fe6ab55C921f74e7fac1ee960C0B6293ba612),
                decimals: 8
            });
            configs[3] = DataTypes.SourceConfig({
                asset: address(0xFd086bC7CD5C481DCC9C85ebE478A1C0b69FCbb9),
                source: address(0x3f3f5dF88dC9F13eac63DF89EC16ef6e7E25DdE7),
                decimals: 8
            });
            configs[4] = DataTypes.SourceConfig({
                asset: address(0x912CE59144191C1204E64559FE8253a0e49E6548),
                source: address(0xb2A824043730FE05F3DA2efaFa1CBbe83fa548D6),
                decimals: 8
            });
            configs[5] = DataTypes.SourceConfig({
                asset: address(0xDA10009cBd5D07dd0CeCc66161FC93D7c9000da1),
                source: address(0xc5C8E77B397E531B8EC06BFb0048328B30E9eCfB),
                decimals: 8
            });
            configs[6] = DataTypes.SourceConfig({
                asset: address(0xba5DdD1f9d7F570dc94a51479a000E3BCE967196),
                source: address(0xaD1d5344AaDE45F43E596773Bcc4c423EAbdD034),
                decimals: 8
            });

            return configs;
        } else if (chainId == 56) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](11);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d),
                source: address(0xaD8b4e59A7f25B68945fAf0f3a3EAF027832FFB0),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0x55d398326f99059fF775485246999027B3197955),
                source: address(0xB97Ad0E74fa7d920791E90258A6E2085088b4320),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0x8AC76a51cc950d9822D68b83fE1Ad97B32Cd580d),
                source: address(0x51597f405303C4377E36123cBc172b13269EA163),
                decimals: 8
            });
            configs[3] = DataTypes.SourceConfig({
                asset: address(0x1AF3F329e8BE154074D8769D1FFa4eE058B1DBc3),
                source: address(0x132d3C0B1D2cEa0BC552588063bdBb210FDeecfA),
                decimals: 8
            });
            configs[4] = DataTypes.SourceConfig({
                asset: address(0xbb4CdB9CBd36B01bD1cBaEBF2De08d9173bc095c),
                source: address(0x0567F2323251f0Aab15c8dFb1967E4e8A7D42aeE),
                decimals: 8
            });
            configs[5] = DataTypes.SourceConfig({
                asset: address(0x2170Ed0880ac9A755fd29B2688956BD959F933F8),
                source: address(0x9ef1B8c0E4F7dc8bF5719Ea496883DC6401d5b2e),
                decimals: 8
            });
            configs[6] = DataTypes.SourceConfig({
                asset: address(0x7130d2A12B9BCbFAe4f2634d864A1Ee1Ce3Ead9c),
                source: address(0x264990fbd0A4796A3E3d8E37C4d5F87a3aCa5Ebf),
                decimals: 8
            });
            configs[7] = DataTypes.SourceConfig({
                asset: address(0x1D2F0da169ceB9fC7B3144628dB156f3F6c60dBE),
                source: address(0x93A67D414896A280bF8FFB3b389fE3686E014fda),
                decimals: 8
            });
            configs[8] = DataTypes.SourceConfig({
                asset: address(0x570A5D26f7765Ecb712C0924E4De545B89fD43dF),
                source: address(0x0E8a53DD9c13589df6382F13dA6B3Ec8F919B323),
                decimals: 8
            });
            configs[9] = DataTypes.SourceConfig({
                asset: address(0xbA2aE424d960c26247Dd6c32edC70B295c744C43),
                source: address(0x3AB0A0d137D4F946fBB19eecc6e92E64660231C8),
                decimals: 8
            });
            configs[10] = DataTypes.SourceConfig({
                asset: address(0x0E09FaBB73Bd3Ade0a17ECC321fD13a19e81cE82),
                source: address(0xB6064eD41d4f67e353768aA239cA86f4F73665a1),
                decimals: 8
            });

            return configs;
        } else if (chainId == 1) {
            DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](12);
            configs[0] = DataTypes.SourceConfig({
                asset: address(0xdAC17F958D2ee523a2206206994597C13D831ec7),
                source: address(0x3E7d1eAB13ad0104d2750B8863b489D65364e32D),
                decimals: 8
            });
            configs[1] = DataTypes.SourceConfig({
                asset: address(0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48),
                source: address(0x8fFfFfd4AfB6115b954Bd326cbe7B4BA576818f6),
                decimals: 8
            });
            configs[2] = DataTypes.SourceConfig({
                asset: address(0x4c9EDD5852cd905f086C759E8383e09bff1E68B3),
                source: address(0xa569d910839Ae8865Da8F8e70FfFb0cBA869F961),
                decimals: 8
            });
            configs[3] = DataTypes.SourceConfig({
                asset: address(0x1aBaEA1f7C830bD89Acc67eC4af516284b1bC33c),
                source: address(0x04F84020Fdf10d9ee64D1dcC2986EDF2F556DA11),
                decimals: 8
            });
            configs[4] = DataTypes.SourceConfig({
                asset: address(0x6B175474E89094C44Da98b954EedeAC495271d0F),
                source: address(0xAed0c38402a5d19df6E4c03F4E2DceD6e29c1ee9),
                decimals: 8
            });
            configs[5] = DataTypes.SourceConfig({
                asset: address(0xC02aaA39b223FE8D0A0e5C4F27eAD9083C756Cc2),
                source: address(0x5f4eC3Df9cbd43714FE2740f5E3616155c5b8419),
                decimals: 8
            });
            configs[6] = DataTypes.SourceConfig({
                asset: address(0x2260FAC5E5542a773Aa44fBCfeDf7C193bc2C599),
                source: address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c),
                decimals: 8
            });
            configs[7] = DataTypes.SourceConfig({
                asset: address(0xcbB7C0000aB88B473b1f5aFd9ef808440eed33Bf),
                source: address(0xF4030086522a5bEEa4988F8cA5B36dbC97BeE88c),
                decimals: 8
            });
            configs[8] = DataTypes.SourceConfig({
                asset: address(0x1f9840a85d5aF5bf1D1762F925BDADdC4201F984),
                source: address(0x553303d460EE0afB37EdFf9bE42922D8FF63220e),
                decimals: 8
            });
            configs[9] = DataTypes.SourceConfig({
                asset: address(0x514910771AF9Ca656af840dff83E8264EcF986CA),
                source: address(0x2c1d072e956AFFC0D435Cb7AC38EF18d24d9127c),
                decimals: 8
            });
            configs[10] = DataTypes.SourceConfig({
                asset: address(0xD31a59c85aE9D8edEFeC411D448f90841571b89c),
                source: address(0x4ffC43a60e009B551865A93d232E33Fce9f01507),
                decimals: 8
            });
            configs[11] = DataTypes.SourceConfig({
                asset: address(0x8d0D000Ee44948FC98c9B98A4FA4921476f08B0d),
                source: address(0xF0d9bb015Cd7BfAb877B7156146dc09Bf461370d),
                decimals: 8
            });

            return configs;
        } else {
            DataTypes.SourceConfig[] memory emptyConfigs = new DataTypes.SourceConfig[](0);
            return emptyConfigs;
        }
    }
}
