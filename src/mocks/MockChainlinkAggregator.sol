// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

/// @title MockChainlinkAggregator
/// @notice Mock Chainlink price feed for testing
contract MockChainlinkAggregator {
    uint8 private _decimals;
    int256 private _price;

    constructor(uint8 decimals_, int256 initialPrice) {
        _decimals = decimals_;
        _price = initialPrice;
    }

    function decimals() external view returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }
}

