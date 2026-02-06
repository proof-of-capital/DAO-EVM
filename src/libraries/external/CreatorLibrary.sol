// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "../internal/ExitQueueValidationLibrary.sol";

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
    /// @param exitQueueStorage Exit queue storage structure
    /// @param fundraisingConfig Fundraising configuration
    /// @param accountedBalance Accounted balance mapping
    /// @param coreConfig DAO core config (launchToken, creator)
    /// @param totalSharesSupply Total shares supply
    /// @param launchAmount Amount of launch tokens to allocate
    function executeAllocateLaunchesToCreator(
        DataTypes.DAOState storage daoState,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        uint256 totalSharesSupply,
        uint256 launchAmount
    ) external {
        require(block.timestamp >= daoState.lastCreatorAllocation + Constants.ALLOCATION_PERIOD, AllocationTooSoon());
        require(launchAmount > 0, AmountMustBeGreaterThanZero());

        uint256 maxAllocation = (accountedBalance[coreConfig.launchToken] * Constants.MAX_CREATOR_ALLOCATION_PERCENT)
            / Constants.BASIS_POINTS;
        require(launchAmount <= maxAllocation, ExceedsMaxAllocation());

        require(fundraisingConfig.sharePrice > 0, InvalidSharePrice());
        address launchToken = coreConfig.launchToken;
        address creator = coreConfig.creator;
        uint256 sharesEquivalent = (launchAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;

        require(totalSharesSupply > 0, NoShares());

        uint256 daoProfitPercent = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;

        uint256 profitPercentEquivalent = (sharesEquivalent * daoProfitPercent) / totalSharesSupply;

        uint256 newDaoProfitPercent =
            (daoProfitPercent * (Constants.BASIS_POINTS + profitPercentEquivalent)) / Constants.BASIS_POINTS;

        if (newDaoProfitPercent > Constants.BASIS_POINTS - daoState.royaltyPercent) {
            newDaoProfitPercent = Constants.BASIS_POINTS - daoState.royaltyPercent;
        }

        uint256 newCreatorProfitPercent = Constants.BASIS_POINTS - newDaoProfitPercent - daoState.royaltyPercent;

        uint256 minCreatorProfitPercent =
            Constants.BASIS_POINTS - Constants.MIN_DAO_PROFIT_SHARE - daoState.royaltyPercent;
        if (newCreatorProfitPercent < minCreatorProfitPercent) {
            newCreatorProfitPercent = minCreatorProfitPercent;
            newDaoProfitPercent = Constants.MIN_DAO_PROFIT_SHARE;
            profitPercentEquivalent = newDaoProfitPercent - daoProfitPercent;
        }

        require(daoState.creatorProfitPercent >= newCreatorProfitPercent, CreatorShareTooLow());
        daoState.creatorProfitPercent = newCreatorProfitPercent;

        bool isQueueEmpty = ExitQueueValidationLibrary.isExitQueueEmpty(exitQueueStorage);

        if (isQueueEmpty) {
            IERC20(coreConfig.launchToken).safeTransfer(coreConfig.creator, launchAmount);
            accountedBalance[coreConfig.launchToken] -= launchAmount;
        } else {
            daoState.pendingExitQueuePayment += launchAmount;
        }

        daoState.lastCreatorAllocation = block.timestamp;

        emit CreatorLaunchesAllocated(launchAmount, profitPercentEquivalent, daoState.creatorProfitPercent);
    }
}

