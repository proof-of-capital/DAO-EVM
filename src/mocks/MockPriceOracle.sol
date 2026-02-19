// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IPriceOracle.sol";

/// @title MockPriceOracle
/// @notice Configurable IPriceOracle for testing
contract MockPriceOracle is IPriceOracle {
    mapping(address => uint256) private _assetPrice;
    mapping(address => address) private _assetSource;

    function setAssetPrice(address asset, uint256 price) external {
        _assetPrice[asset] = price;
    }

    function setSource(address asset, address source) external {
        _assetSource[asset] = source;
    }

    function getAssetPrice(address asset) external view override returns (uint256) {
        return _assetPrice[asset];
    }

    function getSourceOfAsset(address asset) external view override returns (address) {
        return _assetSource[asset];
    }
}
