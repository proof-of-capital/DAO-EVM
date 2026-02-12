// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/LaunchPriceAggregator.sol";
import "../src/mocks/MockDAO.sol";

contract LaunchPriceAggregatorTest is Test {
    LaunchPriceAggregator public aggregator;
    MockDAO public mockDao;

    function setUp() public {
        mockDao = new MockDAO();
        aggregator = new LaunchPriceAggregator(address(mockDao));
    }

    function test_constructor_setsDao() public view {
        assertEq(address(aggregator.dao()), address(mockDao));
    }

    function test_decimals_returns18() public view {
        assertEq(aggregator.decimals(), 18);
    }

    function test_latestRoundData_returnsPriceAndTimestamps() public {
        uint256 price = 1e18;
        mockDao.setLaunchPrice(price);

        (, int256 answer, uint256 startedAt, uint256 updatedAt, uint80 answeredInRound) = aggregator.latestRoundData();

        assertEq(answer, int256(price));
        assertEq(startedAt, block.timestamp);
        assertEq(updatedAt, block.timestamp);
        assertEq(answeredInRound, 0);

        (uint80 roundId,,,,) = aggregator.latestRoundData();
        assertEq(roundId, 0);
    }

    function test_latestRoundData_revertsPriceOverflow_whenPriceExceedsInt256Max() public {
        mockDao.setLaunchPrice(uint256(type(int256).max) + 1);

        vm.expectRevert(LaunchPriceAggregator.PriceOverflow.selector);
        aggregator.latestRoundData();
    }

    function test_latestRoundData_succeeds_whenPriceEqualsInt256Max() public {
        mockDao.setLaunchPrice(uint256(type(int256).max));

        (, int256 answer,,,) = aggregator.latestRoundData();
        assertEq(answer, type(int256).max);
    }
}
