// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IAggregatorV3.sol";

/// @title MockLaunchPriceAggregator
/// @notice IAggregatorV3 with configurable price for testing (no DAO dependency)
contract MockLaunchPriceAggregator is IAggregatorV3 {
    uint8 private _decimals;
    int256 private _price;

    constructor(uint8 decimals_, int256 initialPrice) {
        _decimals = decimals_;
        _price = initialPrice;
    }

    function setPrice(int256 newPrice) external {
        _price = newPrice;
    }

    function decimals() external view override returns (uint8) {
        return _decimals;
    }

    function latestRoundData()
        external
        view
        override
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        return (1, _price, block.timestamp, block.timestamp, 1);
    }
}
