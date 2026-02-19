// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.33;

import "./interfaces/IDAO.sol";
import "./interfaces/IAggregatorV3.sol";

/// @title LaunchPriceAggregator
/// @notice Wraps DAO launch price as Chainlink-compatible aggregator (IAggregatorV3)
contract LaunchPriceAggregator is IAggregatorV3 {
    error PriceOverflow();

    IDAO public immutable dao;

    /// @param _dao DAO contract exposing getLaunchPriceFromDAO()
    constructor(address _dao) {
        dao = IDAO(_dao);
    }

    /// @inheritdoc IAggregatorV3
    function decimals() external pure returns (uint8) {
        return 18;
    }

    /// @inheritdoc IAggregatorV3
    function latestRoundData()
        external
        view
        returns (uint80 roundId, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound)
    {
        uint256 price = dao.getLaunchPriceFromDAO();
        if (price > uint256(type(int256).max)) revert PriceOverflow();
        return (0, int256(price), block.timestamp, block.timestamp, 0);
    }
}
