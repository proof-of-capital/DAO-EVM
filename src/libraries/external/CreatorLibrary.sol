// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/math/Math.sol";
import "../../interfaces/IPriceOracle.sol";
import "../DataTypes.sol";
import "../Constants.sol";
import "../internal/ExitQueueValidationLibrary.sol";
import "./ProfitDistributionLibrary.sol";
import "./VaultLibrary.sol";

/// @title CreatorLibrary
/// @notice Library for managing creator allocations, loans, drops and creator vault
library CreatorLibrary {
    using SafeERC20 for IERC20;

    error AmountMustBeGreaterThanZero();
    error AllocationTooSoon();
    error ExceedsMaxAllocation();
    error InvalidSharePrice();
    error NoShares();
    error CreatorShareTooLow();
    error LoanNotActive();
    error LoanActive();
    error RepayAmountTooHigh();
    error ExitQueueNotEmpty();
    error ExceedsDropLimit();
    error InvalidAddress();
    error InvalidPercentage();

    event CreatorLaunchesAllocated(
        uint256 launchAmount, uint256 profitPercentEquivalent, uint256 newCreatorProfitPercent
    );
    event CreatorLaunchesReturned(uint256 launchAmount, uint256 profitPercentIncrease, uint256 newCreatorProfitPercent);
    event LoanTaken(
        uint256 launchAmount,
        bool reservedForExitQueue,
        uint256 newPrincipal,
        uint256 newInterestAccrued,
        uint256 newCreatorProfitPercent
    );
    event LoanRepaid(
        uint256 paidAmount,
        uint256 principalPaid,
        uint256 interestPaid,
        uint256 remainingPrincipal,
        uint256 remainingInterestAccrued,
        uint256 newCreatorProfitPercent
    );
    event CreatorVaultSet(uint256 indexed vaultId, address indexed creator);
    event LaunchDropDistributed(uint256 amount);

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
            profitPercentEquivalent = daoProfitPercent - newDaoProfitPercent;
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

    function _accrueLoan(DataTypes.CreatorLoanDropStorage storage cls) internal {
        if (cls.loanPrincipal == 0) {
            cls.loanLastUpdate = block.timestamp;
            return;
        }
        if (cls.loanLastUpdate == 0) {
            cls.loanLastUpdate = block.timestamp;
            return;
        }
        uint256 dt = block.timestamp - cls.loanLastUpdate;
        if (dt == 0) return;
        uint256 numerator = Constants.LOAN_APR_BPS * dt;
        uint256 denominator = Constants.BASIS_POINTS * Constants.SECONDS_PER_YEAR;
        uint256 interest = Math.mulDiv(cls.loanPrincipal, numerator, denominator);
        cls.loanInterestAccrued += interest;
        cls.loanLastUpdate = block.timestamp;
    }

    /// @notice Take a loan in launch tokens by shifting profit share from creator to DAO
    function executeTakeLoanInLaunches(
        DataTypes.CreatorLoanDropStorage storage creatorLoanDrop,
        DataTypes.DAOState storage daoState,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        DataTypes.VaultStorage storage vaultStorage,
        uint256 launchAmount,
        bool reserveForExitQueue
    ) external {
        require(block.timestamp >= daoState.lastCreatorAllocation + Constants.ALLOCATION_PERIOD, AllocationTooSoon());
        require(launchAmount > 0, AmountMustBeGreaterThanZero());

        _accrueLoan(creatorLoanDrop);

        address launchToken = coreConfig.launchToken;
        uint256 maxAllocation =
            (accountedBalance[launchToken] * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        require(launchAmount <= maxAllocation, ExceedsMaxAllocation());

        uint256 sharesSupply = vaultStorage.totalSharesSupply;
        require(sharesSupply > 0, NoShares());
        require(fundraisingConfig.sharePrice > 0, InvalidSharePrice());

        uint256 oldCreatorProfitPercent = daoState.creatorProfitPercent;
        uint256 daoProfitPercent = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;
        uint256 sharesEquivalent = (launchAmount * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        uint256 profitPercentEquivalent = (sharesEquivalent * daoProfitPercent) / sharesSupply;

        uint256 newDaoProfitPercent =
            (daoProfitPercent * (Constants.BASIS_POINTS + profitPercentEquivalent)) / Constants.BASIS_POINTS;

        uint256 maxDaoProfitPercent = Constants.MAX_DAO_PROFIT_SHARE;
        uint256 absoluteMaxDaoProfitPercent = Constants.BASIS_POINTS - daoState.royaltyPercent;
        if (maxDaoProfitPercent > absoluteMaxDaoProfitPercent) {
            maxDaoProfitPercent = absoluteMaxDaoProfitPercent;
        }
        if (newDaoProfitPercent > maxDaoProfitPercent) {
            newDaoProfitPercent = maxDaoProfitPercent;
        }

        uint256 newCreatorProfitPercent = Constants.BASIS_POINTS - newDaoProfitPercent - daoState.royaltyPercent;
        require(daoState.creatorProfitPercent >= newCreatorProfitPercent, CreatorShareTooLow());
        daoState.creatorProfitPercent = newCreatorProfitPercent;

        creatorLoanDrop.loanPrincipal += launchAmount;
        creatorLoanDrop.loanLastUpdate = block.timestamp;

        bool isQueueEmpty = ExitQueueValidationLibrary.isExitQueueEmpty(exitQueueStorage);
        if (!reserveForExitQueue) {
            require(isQueueEmpty, ExitQueueNotEmpty());
            IERC20(launchToken).safeTransfer(coreConfig.creator, launchAmount);
            accountedBalance[launchToken] -= launchAmount;
        } else {
            if (isQueueEmpty) {
                IERC20(launchToken).safeTransfer(coreConfig.creator, launchAmount);
                accountedBalance[launchToken] -= launchAmount;
            } else {
                daoState.pendingExitQueuePayment += launchAmount;
            }
        }

        daoState.lastCreatorAllocation = block.timestamp;

        uint256 profitPercentReduction =
            oldCreatorProfitPercent > newCreatorProfitPercent ? oldCreatorProfitPercent - newCreatorProfitPercent : 0;

        emit LoanTaken(
            launchAmount,
            reserveForExitQueue && !isQueueEmpty,
            creatorLoanDrop.loanPrincipal,
            creatorLoanDrop.loanInterestAccrued,
            newCreatorProfitPercent
        );
        emit CreatorLaunchesAllocated(launchAmount, profitPercentReduction, newCreatorProfitPercent);
    }

    function _restoreCreatorProfitShareByPrincipal(
        DataTypes.DAOState storage daoState,
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        uint256 principalPaid
    ) internal {
        require(principalPaid > 0, AmountMustBeGreaterThanZero());

        uint256 sharesSupply = vaultStorage.totalSharesSupply;
        require(sharesSupply > 0, NoShares());
        require(fundraisingConfig.sharePrice > 0, InvalidSharePrice());

        uint256 oldCreatorProfitPercent = daoState.creatorProfitPercent;
        uint256 daoProfitPercent = Constants.BASIS_POINTS - daoState.creatorProfitPercent - daoState.royaltyPercent;
        uint256 sharesEquivalent = (principalPaid * Constants.PRICE_DECIMALS_MULTIPLIER) / fundraisingConfig.sharePrice;
        uint256 profitPercentEquivalent = (sharesEquivalent * daoProfitPercent) / sharesSupply;

        uint256 newDaoProfitPercent =
            (daoProfitPercent * Constants.BASIS_POINTS) / (Constants.BASIS_POINTS + profitPercentEquivalent);

        if (newDaoProfitPercent < Constants.MIN_DAO_PROFIT_SHARE) {
            newDaoProfitPercent = Constants.MIN_DAO_PROFIT_SHARE;
        }

        uint256 newCreatorProfitPercent = Constants.BASIS_POINTS - newDaoProfitPercent - daoState.royaltyPercent;
        daoState.creatorProfitPercent = newCreatorProfitPercent;

        uint256 profitPercentIncrease =
            newCreatorProfitPercent > oldCreatorProfitPercent ? newCreatorProfitPercent - oldCreatorProfitPercent : 0;
        emit CreatorLaunchesReturned(principalPaid, profitPercentIncrease, newCreatorProfitPercent);
    }

    function _distributeLaunchProfitWithoutCreatorShare(
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.VaultStorage storage vaultStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        uint256 amount,
        IPriceOracle oracle,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        mapping(address => bool) storage allowedExitTokens,
        mapping(uint256 => mapping(address => bool)) storage vaultAllowedExitTokens
    ) internal {
        require(amount > 0, AmountMustBeGreaterThanZero());
        uint256 oldCreatorProfitPercent = daoState.creatorProfitPercent;
        daoState.creatorProfitPercent = 0;

        ProfitDistributionLibrary.executeDistributeProfit(
            daoState,
            rewardsStorage,
            exitQueueStorage,
            lpTokenStorage,
            vaultStorage,
            participantEntries,
            fundraisingConfig,
            accountedBalance,
            ProfitDistributionLibrary.DistributeProfitParams({
                totalSharesSupply: vaultStorage.totalSharesSupply,
                token: coreConfig.launchToken,
                launchToken: coreConfig.launchToken,
                amount: amount
            }),
            oracle,
            sellableCollaterals,
            pocContracts,
            pricePathsStorage,
            allowedExitTokens,
            vaultStorage.vaultAllowedExitTokens
        );

        daoState.creatorProfitPercent = oldCreatorProfitPercent;
    }

    /// @notice Repay loan in launch tokens and restore profit share; distribute interest as profit
    function executeRepayLoanInLaunches(
        DataTypes.CreatorLoanDropStorage storage creatorLoanDrop,
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.VaultStorage storage vaultStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        mapping(address => bool) storage allowedExitTokens,
        IPriceOracle oracle,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        uint256 amount
    ) external {
        require(amount > 0, AmountMustBeGreaterThanZero());

        _accrueLoan(creatorLoanDrop);

        uint256 principal = creatorLoanDrop.loanPrincipal;
        uint256 interest = creatorLoanDrop.loanInterestAccrued;
        require(principal > 0 || interest > 0, LoanNotActive());

        uint256 totalOwed = principal + interest;
        require(amount <= totalOwed, RepayAmountTooHigh());

        address launchToken = coreConfig.launchToken;
        IERC20(launchToken).safeTransferFrom(msg.sender, address(this), amount);

        uint256 interestPaid = amount <= interest ? amount : interest;
        creatorLoanDrop.loanInterestAccrued = interest - interestPaid;

        uint256 remaining = amount - interestPaid;
        uint256 principalPaid = remaining <= principal ? remaining : principal;
        creatorLoanDrop.loanPrincipal = principal - principalPaid;

        if (principalPaid > 0) {
            accountedBalance[launchToken] += principalPaid;
            _restoreCreatorProfitShareByPrincipal(daoState, vaultStorage, fundraisingConfig, principalPaid);
        }

        if (interestPaid > 0) {
            _distributeLaunchProfitWithoutCreatorShare(
                daoState,
                rewardsStorage,
                exitQueueStorage,
                lpTokenStorage,
                vaultStorage,
                participantEntries,
                fundraisingConfig,
                accountedBalance,
                coreConfig,
                interestPaid,
                oracle,
                sellableCollaterals,
                pocContracts,
                pricePathsStorage,
                allowedExitTokens,
                vaultStorage.vaultAllowedExitTokens
            );
        }

        emit LoanRepaid(
            amount,
            principalPaid,
            interestPaid,
            creatorLoanDrop.loanPrincipal,
            creatorLoanDrop.loanInterestAccrued,
            daoState.creatorProfitPercent
        );
    }

    /// @notice Distribute creator-provided launches as profit (governance-limited drop)
    function executeDropLaunchesAsProfit(
        DataTypes.CreatorLoanDropStorage storage creatorLoanDrop,
        DataTypes.DAOState storage daoState,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.ExitQueueStorage storage exitQueueStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.VaultStorage storage vaultStorage,
        mapping(uint256 => DataTypes.ParticipantEntry) storage participantEntries,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        mapping(address => bool) storage allowedExitTokens,
        IPriceOracle oracle,
        mapping(address => DataTypes.CollateralInfo) storage sellableCollaterals,
        DataTypes.POCInfo[] storage pocContracts,
        DataTypes.PricePathsStorage storage pricePathsStorage,
        uint256 amount
    ) external {
        require(amount > 0, AmountMustBeGreaterThanZero());
        require(creatorLoanDrop.loanPrincipal == 0 && creatorLoanDrop.loanInterestAccrued == 0, LoanActive());

        if (
            creatorLoanDrop.dropPeriodStart == 0
                || block.timestamp >= creatorLoanDrop.dropPeriodStart + Constants.DROP_PERIOD
        ) {
            creatorLoanDrop.dropPeriodStart = block.timestamp;
            creatorLoanDrop.dropUsedInPeriod = 0;
        }

        uint256 maxDrop =
            (accountedBalance[coreConfig.launchToken] * Constants.DROP_MAX_PERCENT) / Constants.BASIS_POINTS;
        require(creatorLoanDrop.dropUsedInPeriod + amount <= maxDrop, ExceedsDropLimit());
        creatorLoanDrop.dropUsedInPeriod += amount;

        IERC20(coreConfig.launchToken).safeTransferFrom(coreConfig.creator, address(this), amount);
        _distributeLaunchProfitWithoutCreatorShare(
            daoState,
            rewardsStorage,
            exitQueueStorage,
            lpTokenStorage,
            vaultStorage,
            participantEntries,
            fundraisingConfig,
            accountedBalance,
            coreConfig,
            amount,
            oracle,
            sellableCollaterals,
            pocContracts,
            pricePathsStorage,
            allowedExitTokens,
            vaultStorage.vaultAllowedExitTokens
        );

        emit LaunchDropDistributed(amount);
    }

    function _ensureCreatorVaultId(
        DataTypes.CreatorLoanDropStorage storage creatorLoanDrop,
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.CoreConfig storage coreConfig
    ) internal returns (uint256 vaultId) {
        address creator = coreConfig.creator;
        require(creator != address(0), InvalidAddress());

        uint256 existingVaultId = vaultStorage.addressToVaultId[creator];
        if (existingVaultId != 0) {
            if (creatorLoanDrop.creatorVaultId != existingVaultId) {
                creatorLoanDrop.creatorVaultId = existingVaultId;
                emit CreatorVaultSet(existingVaultId, creator);
            }
            return existingVaultId;
        }

        if (creatorLoanDrop.creatorVaultId != 0) {
            return creatorLoanDrop.creatorVaultId;
        }

        vaultId = vaultStorage.nextVaultId++;

        vaultStorage.vaults[vaultId] = DataTypes.Vault({
            primary: creator,
            backup: creator,
            emergency: creator,
            shares: 0,
            votingPausedUntil: 0,
            delegateId: 0,
            delegateSetAt: block.timestamp,
            votingShares: 0,
            mainCollateralDeposit: 0,
            depositedUSD: 0,
            depositLimit: 0
        });

        vaultStorage.addressToVaultId[creator] = vaultId;

        for (uint256 i = 0; i < rewardsStorage.rewardTokens.length; ++i) {
            address rewardToken = rewardsStorage.rewardTokens[i];
            if (rewardsStorage.rewardTokenInfo[rewardToken].active) {
                rewardsStorage.vaultRewardIndex[vaultId][rewardToken] = rewardsStorage.rewardPerShareStored[rewardToken];
            }
        }

        for (uint256 i = 0; i < lpTokenStorage.v2LPTokens.length; ++i) {
            address token = lpTokenStorage.v2LPTokens[i];
            rewardsStorage.vaultRewardIndex[vaultId][token] = rewardsStorage.rewardPerShareStored[token];
        }

        creatorLoanDrop.creatorVaultId = vaultId;
        emit CreatorVaultSet(vaultId, creator);
    }

    /// @notice Mint creator infra shares based on creatorInfraPercent (call after finalize exchange)
    function executeMintCreatorInfraShares(
        DataTypes.CreatorLoanDropStorage storage creatorLoanDrop,
        DataTypes.VaultStorage storage vaultStorage,
        DataTypes.RewardsStorage storage rewardsStorage,
        DataTypes.LPTokenStorage storage lpTokenStorage,
        DataTypes.FundraisingConfig storage fundraisingConfig,
        mapping(address => uint256) storage accountedBalance,
        DataTypes.CoreConfig storage coreConfig,
        address votingContract
    ) external {
        uint256 infraPercent = coreConfig.creatorInfraPercent;
        if (infraPercent == 0) return;

        address launchToken = coreConfig.launchToken;
        uint256 launchBalance = accountedBalance[launchToken];
        if (launchBalance == 0) return;

        uint256 infraLaunches = (launchBalance * infraPercent) / Constants.BASIS_POINTS;
        if (infraLaunches == 0) return;

        require(launchBalance > infraLaunches, InvalidPercentage());

        uint256 oldSupply = vaultStorage.totalSharesSupply;
        require(oldSupply > 0, NoShares());

        uint256 sharesToMint = Math.mulDiv(oldSupply, infraLaunches, launchBalance - infraLaunches);
        if (sharesToMint == 0) return;

        uint256 vaultId =
            _ensureCreatorVaultId(creatorLoanDrop, vaultStorage, rewardsStorage, lpTokenStorage, coreConfig);

        DataTypes.Vault memory vault = vaultStorage.vaults[vaultId];
        vault.shares += sharesToMint;
        vaultStorage.vaults[vaultId] = vault;

        vaultStorage.totalSharesSupply = oldSupply + sharesToMint;
        VaultLibrary.executeUpdateDelegateVotingShares(vaultStorage, vaultId, int256(sharesToMint), votingContract);

        if (fundraisingConfig.sharePrice > 0) {
            fundraisingConfig.sharePrice =
                Math.mulDiv(fundraisingConfig.sharePrice, oldSupply, vaultStorage.totalSharesSupply);
        }
        fundraisingConfig.sharePriceStart = fundraisingConfig.sharePrice;
    }
}

