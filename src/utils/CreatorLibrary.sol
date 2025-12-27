// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.20;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./DataTypes.sol";
import "./Constants.sol";

/// @title CreatorLibrary
/// @notice Library for managing creator allocations
library CreatorLibrary {
    using SafeERC20 for IERC20;

    error AmountMustBeGreaterThanZero();
    error AllocationTooSoon();
    error ExceedsMaxAllocation();
    error InvalidSharePrice();
    error NoShares();
    error CreatorShareTooLow();

    event CreatorLaunchesAllocated(
        uint256 launchAmount, uint256 profitPercentEquivalent, uint256 newCreatorProfitPercent
    );

    /// @notice Allocate launch tokens to creator, reducing their profit share proportionally
    /// @param daoState DAO state storage
    /// @param accountedBalance Accounted balance mapping
    /// @param launchToken Launch token address
    /// @param creator Creator address
    /// @param totalSharesSupply Total shares supply
    /// @param launchAmount Amount of launch tokens to allocate
    function executeAllocateLaunchesToCreator(
        DataTypes.DAOState storage daoState,
        mapping(address => uint256) storage accountedBalance,
        address launchToken,
        address creator,
        uint256 totalSharesSupply,
        uint256 launchAmount
    ) external {
        require(block.timestamp >= daoState.lastCreatorAllocation + Constants.ALLOCATION_PERIOD, AllocationTooSoon());
        require(launchAmount > 0, AmountMustBeGreaterThanZero());

        uint256 maxAllocation =
            (daoState.totalLaunchBalance * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        require(launchAmount <= maxAllocation, ExceedsMaxAllocation());

        require(daoState.sharePriceInLaunches > 0, InvalidSharePrice());
        uint256 sharesEquivalent = (launchAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / daoState.sharePriceInLaunches;

        require(totalSharesSupply > 0, NoShares());
        uint256 profitPercentEquivalent = (sharesEquivalent * Constants.BASIS_POINTS) / totalSharesSupply;

        require(daoState.creatorProfitPercent >= profitPercentEquivalent, CreatorShareTooLow());

        uint256 minCreatorProfitPercent =
            Constants.BASIS_POINTS - Constants.MIN_DAO_PROFIT_SHARE - daoState.royaltyPercent;
        uint256 newCreatorProfitPercent = daoState.creatorProfitPercent - profitPercentEquivalent;
        if (newCreatorProfitPercent < minCreatorProfitPercent) {
            newCreatorProfitPercent = minCreatorProfitPercent;
            profitPercentEquivalent = daoState.creatorProfitPercent - minCreatorProfitPercent;
        }
        daoState.creatorProfitPercent = newCreatorProfitPercent;

        IERC20(launchToken).safeTransfer(creator, launchAmount);
        daoState.totalLaunchBalance -= launchAmount;
        accountedBalance[launchToken] -= launchAmount;
        daoState.lastCreatorAllocation = block.timestamp;

        emit CreatorLaunchesAllocated(launchAmount, profitPercentEquivalent, daoState.creatorProfitPercent);
    }
}

