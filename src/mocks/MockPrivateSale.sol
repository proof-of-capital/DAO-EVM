// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IPrivateSale.sol";
import "../interfaces/IDAO.sol";
import "../libraries/DataTypes.sol";

/// @title MockPrivateSale
/// @notice Configurable IPrivateSale for testing; state and view methods configurable, actions no-op
contract MockPrivateSale is IPrivateSale {
    address public immutable dao;
    address public immutable mainCollateral;
    address public immutable launchToken;
    address[] public pocContracts;

    uint256 public immutable cliffDuration;
    uint256 public immutable vestingPeriods;
    uint256 public immutable vestingPeriodDuration;

    VestingState public state;
    uint256 public totalDeposited;
    uint256 public totalTokensPurchased;
    uint256 public vestingStartTime;

    mapping(uint256 => uint256) public vestedAmountByVault;
    mapping(uint256 => uint256) public claimableAmountByVault;

    constructor(
        address _dao,
        address _mainCollateral,
        address[] memory _pocContracts,
        uint256 _cliffDuration,
        uint256 _vestingPeriods,
        uint256 _vestingPeriodDuration
    ) {
        dao = _dao;
        mainCollateral = _mainCollateral;
        launchToken = IDAO(_dao).coreConfig().launchToken;
        pocContracts = _pocContracts;
        cliffDuration = _cliffDuration;
        vestingPeriods = _vestingPeriods;
        vestingPeriodDuration = _vestingPeriodDuration;
        state = VestingState.Deposit;
    }

    function setState(VestingState s) external {
        state = s;
    }

    function setTotalDeposited(uint256 amount) external {
        totalDeposited = amount;
    }

    function setTotalTokensPurchased(uint256 amount) external {
        totalTokensPurchased = amount;
    }

    function setVestingStartTime(uint256 t) external {
        vestingStartTime = t;
    }

    function setVestedAmount(uint256 vaultId, uint256 amount) external {
        vestedAmountByVault[vaultId] = amount;
    }

    function setClaimableAmount(uint256 vaultId, uint256 amount) external {
        claimableAmountByVault[vaultId] = amount;
    }

    function depositForVesting(uint256) external override {}

    function purchaseTokens(uint256, uint256, address, DataTypes.SwapType, bytes calldata) external override {}

    function claimVested() external override {}

    function dissolve() external override {}

    function claimAfterDissolution() external override {}

    function getVestedAmount(uint256 vaultId) external view override returns (uint256) {
        return vestedAmountByVault[vaultId];
    }

    function getClaimableAmount(uint256 vaultId) external view override returns (uint256) {
        return claimableAmountByVault[vaultId];
    }
}
