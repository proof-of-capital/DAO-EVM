// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IAggregatorV3.sol";

/// @title MockChainlinkAggregator
/// @notice Mock Chainlink price feed for testing
contract MockChainlinkAggregator is IAggregatorV3 {
    uint8 private _decimals;
    int256 private _price;
    uint256 private _updatedAt;

    constructor(uint8 decimals_, int256 initialPrice) {
        _decimals = decimals_;
        _price = initialPrice;
        _updatedAt = block.timestamp;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, _updatedAt, _updatedAt, 1);
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function setUpdatedAt(uint256 updatedAt_) external {
        _updatedAt = updatedAt_;
    }
}

