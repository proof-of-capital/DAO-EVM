// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

pragma solidity ^0.8.33;

import "../utils/DataTypes.sol";

interface IPrivateSale {
    error InvalidAddress();
    error InvalidAmount();
    error InvalidVault();
    error NoFundraisingDeposit();
    error ExceedsFundraisingDeposit();
    error AlreadyDeposited();
    error InvalidState();
    error Unauthorized();
    error NothingToClaim();
    error CliffNotEnded();
    error NoTokensAvailable();
    error PurchaseAlreadyCompleted();
    error NoDeposits();
    error TransferFailed();
    error AlreadyClaimed();
    error RouterNotAvailable();
    error PriceDeviationTooHigh();
    error ZeroAmountNotAllowed();
    error InvalidSwapType();
    error InvalidSwapData();
    error InvalidPrice();
    error StalePrice();

    enum VestingState {
        Deposit,
        PurchaseCompleted,
        Dissolved
    }

    event PrivateSaleDeposit(uint256 indexed vaultId, address indexed depositor, uint256 amount);
    event TokensPurchased(uint256 totalTokens, uint256 totalCollateral);
    event TokensClaimed(uint256 indexed vaultId, address indexed claimer, uint256 amount);
    event PrivateSaleDissolved(uint256 tokensReturned, uint256 collateralReturned);
    event VestingStarted(uint256 startTime);
    event DissolutionClaimed(uint256 indexed vaultId, address indexed claimer, uint256 amount);

    function depositForVesting(uint256 amount) external;
    function purchaseTokens(
        uint256 pocIdx,
        uint256 collateralAmount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external;
    function claimVested() external;
    function dissolve() external;
    function claimAfterDissolution() external;
    function getVestedAmount(uint256 vaultId) external view returns (uint256);
    function getClaimableAmount(uint256 vaultId) external view returns (uint256);
    function state() external view returns (VestingState);
    function dao() external view returns (address);
    function mainCollateral() external view returns (address);
    function launchToken() external view returns (address);
    function cliffDuration() external view returns (uint256);
    function vestingPeriods() external view returns (uint256);
    function vestingPeriodDuration() external view returns (uint256);
    function totalDeposited() external view returns (uint256);
    function totalTokensPurchased() external view returns (uint256);
    function vestingStartTime() external view returns (uint256);
}
