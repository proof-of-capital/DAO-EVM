// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IProofOfCapital.sol";
import "@openzeppelin/contracts/token/ERC20/IERC20.sol";

/// @title MockProofOfCapital
/// @notice Minimal IProofOfCapital for testing; buyLaunchTokens, collateralToken, launchToken, extendLock, isActive
contract MockProofOfCapital is IProofOfCapital {
    IERC20 private _collateralToken;
    IERC20 private _launchToken;
    bool private _active;
    uint256 private _launchBalance;

    constructor(address collateralToken_, address launchToken_) {
        _collateralToken = IERC20(collateralToken_);
        _launchToken = IERC20(launchToken_);
        _active = true;
    }

    function setActive(bool a) external {
        _active = a;
    }

    function setLaunchBalance(uint256 amount) external {
        _launchBalance = amount;
    }

    function extendLock(uint256) external override {}

    function buyLaunchTokens(uint256 amount) external override {
        if (address(_launchToken) != address(0) && _launchBalance >= amount) {
            _launchToken.transfer(msg.sender, amount);
        }
    }

    function collateralToken() external view override returns (IERC20) {
        return _collateralToken;
    }

    function launchToken() external view override returns (IERC20) {
        return _launchToken;
    }

    function isActive() external view override returns (bool) {
        return _active;
    }

    function remainingSeconds() external pure override returns (uint256) {
        return 0;
    }

    function tradingOpportunity() external pure override returns (bool) {
        return false;
    }

    function launchAvailable() external view override returns (uint256) {
        return _launchBalance;
    }

    function oldContractAddress(address) external pure override returns (bool) {
        return false;
    }

    function reserveOwner() external pure override returns (address) {
        return address(0);
    }

    function returnWalletAddresses(address) external pure override returns (bool) {
        return false;
    }

    function royaltyWalletAddress() external pure override returns (address) {
        return address(0);
    }

    function daoAddress() external pure override returns (address) {
        return address(0);
    }

    function lockEndTime() external pure override returns (uint256) {
        return 0;
    }

    function controlDay() external pure override returns (uint256) {
        return 0;
    }

    function controlPeriod() external pure override returns (uint256) {
        return 0;
    }

    function initialPricePerLaunchToken() external pure override returns (uint256) {
        return 0;
    }

    function firstLevelLaunchTokenQuantity() external pure override returns (uint256) {
        return 0;
    }

    function currentPrice() external pure override returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevel() external pure override returns (uint256) {
        return 0;
    }

    function remainderOfStep() external pure override returns (uint256) {
        return 0;
    }

    function currentStep() external pure override returns (uint256) {
        return 0;
    }

    function priceIncrementMultiplier() external pure override returns (uint256) {
        return 0;
    }

    function levelIncreaseMultiplier() external pure override returns (int256) {
        return 0;
    }

    function trendChangeStep() external pure override returns (uint256) {
        return 0;
    }

    function levelDecreaseMultiplierAfterTrend() external pure override returns (int256) {
        return 0;
    }

    function profitPercentage() external pure override returns (uint256) {
        return 0;
    }

    function royaltyProfitPercent() external pure override returns (uint256) {
        return 0;
    }

    function profitBeforeTrendChange() external pure override returns (uint256) {
        return 0;
    }

    function totalLaunchSold() external pure override returns (uint256) {
        return 0;
    }

    function contractCollateralBalance() external pure override returns (uint256) {
        return 0;
    }

    function launchBalance() external view override returns (uint256) {
        return _launchBalance;
    }

    function launchTokensEarned() external pure override returns (uint256) {
        return 0;
    }

    function ownerEarnedLaunchTokens() external pure override returns (uint256) {
        return 0;
    }

    function currentStepEarned() external pure override returns (uint256) {
        return 0;
    }

    function remainderOfStepEarned() external pure override returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevelEarned() external pure override returns (uint256) {
        return 0;
    }

    function currentPriceEarned() external pure override returns (uint256) {
        return 0;
    }

    function offsetLaunch() external pure override returns (uint256) {
        return 0;
    }

    function offsetStep() external pure override returns (uint256) {
        return 0;
    }

    function offsetPrice() external pure override returns (uint256) {
        return 0;
    }

    function remainderOfStepOffset() external pure override returns (uint256) {
        return 0;
    }

    function quantityLaunchPerLevelOffset() external pure override returns (uint256) {
        return 0;
    }

    function marketMakerAddresses(address) external pure override returns (bool) {
        return false;
    }

    function ownerCollateralBalance() external pure override returns (uint256) {
        return 0;
    }

    function royaltyCollateralBalance() external pure override returns (uint256) {
        return 0;
    }

    function profitInTime() external pure override returns (bool) {
        return false;
    }

    function canWithdrawal() external pure override returns (bool) {
        return false;
    }

    function launchDeferredWithdrawalDate() external pure override returns (uint256) {
        return 0;
    }

    function launchDeferredWithdrawalAmount() external pure override returns (uint256) {
        return 0;
    }

    function recipientDeferredWithdrawalLaunch() external pure override returns (address) {
        return address(0);
    }

    function collateralTokenDeferredWithdrawalDate() external pure override returns (uint256) {
        return 0;
    }

    function recipientDeferredWithdrawalCollateralToken() external pure override returns (address) {
        return address(0);
    }

    function unaccountedCollateralBalance() external pure override returns (uint256) {
        return 0;
    }

    function unaccountedOffset() external pure override returns (uint256) {
        return 0;
    }

    function unaccountedOffsetLaunchBalance() external pure override returns (uint256) {
        return 0;
    }

    function unaccountedReturnBuybackBalance() external pure override returns (uint256) {
        return 0;
    }

    function isInitialized() external pure override returns (bool) {
        return true;
    }

    function isFirstLaunchDeposit() external pure override returns (bool) {
        return false;
    }

    function collateralTokenOracle() external pure override returns (address) {
        return address(0);
    }

    function collateralTokenMinOracleValue() external pure override returns (int256) {
        return 0;
    }

    function toggleDeferredWithdrawal() external pure override {}

    function assignNewReserveOwner(address) external pure override {}

    function switchProfitMode(bool) external pure override {}

    function setReturnWallet(address, bool) external pure override {}

    function changeRoyaltyWallet(address) external pure override {}

    function changeProfitPercentage(uint256) external pure override {}

    function setMarketMaker(address, bool) external pure override {}

    function registerOldContract(address) external pure override {}

    function depositCollateral(uint256) external pure override {}

    function depositLaunch(uint256) external pure override {}

    function sellLaunchTokens(uint256) external pure override {}

    function sellLaunchTokensReturnWallet(uint256) external pure override {}

    function sellLaunchTokensDao(uint256) external pure override {}

    function upgradeOwnerShare() external pure override {}

    function launchDeferredWithdrawal(address, uint256) external pure override {}

    function stopLaunchDeferredWithdrawal() external pure override {}

    function confirmLaunchDeferredWithdrawal() external pure override {}

    function collateralDeferredWithdrawal(address) external pure override {}

    function stopCollateralDeferredWithdrawal() external pure override {}

    function confirmCollateralDeferredWithdrawal() external pure override {}

    function withdrawAllLaunchTokens() external pure override {}

    function withdrawAllCollateralTokens() external pure override {}

    function withdrawToken(address, uint256) external pure override {}

    function claimProfitOnRequest() external pure override {}

    function setDao(address) external pure override {}

    function calculateUnaccountedCollateralBalance(uint256) external pure override {}

    function calculateUnaccountedOffsetBalance(uint256) external pure override {}

    function calculateUnaccountedOffsetLaunchBalance(uint256) external pure override {}
}
