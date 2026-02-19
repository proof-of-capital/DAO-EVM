// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IWhitelistOracles.sol";

/// @title MockWhitelistOracles
/// @notice Configurable IWhitelistOracles for testing; setFeed bypasses 2-of-2
contract MockWhitelistOracles is IWhitelistOracles {
    mapping(address => address) private _primaryFeed;
    mapping(address => mapping(address => uint8)) private _feedDecimals;
    mapping(address => mapping(address => bool)) private _allowedFeeds;

    function setFeed(address asset, address source, uint8 decimals) external {
        _primaryFeed[asset] = source;
        _feedDecimals[asset][source] = decimals;
        _allowedFeeds[asset][source] = true;
    }

    function getFeed(address asset) external view override returns (address) {
        return _primaryFeed[asset];
    }

    function getFeedInfo(address asset) external view override returns (address source, uint8 decimals) {
        source = _primaryFeed[asset];
        decimals = _feedDecimals[asset][source];
    }

    function isAllowedFeed(address asset, address aggregator) external view override returns (bool) {
        return _allowedFeeds[asset][aggregator];
    }

    function proposeFeedUpdate(address, address, uint8) external pure override {
        revert("MockWhitelistOracles: use setFeed for tests");
    }

    function approveFeedUpdate(bytes32) external pure override {
        revert("MockWhitelistOracles: use setFeed for tests");
    }

    function cancelFeedUpdate(bytes32) external pure override {
        revert("MockWhitelistOracles: use setFeed for tests");
    }
}
