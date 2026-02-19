// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "./interfaces/IPrivateSale.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IProofOfCapital.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwapRouter.sol";
import "./libraries/DataTypes.sol";
import "./libraries/Constants.sol";
import "./libraries/internal/SwapLibrary.sol";

contract PrivateSale is IPrivateSale, ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable dao;
    address public immutable mainCollateral;
    address public immutable launchToken;
    address public immutable admin;

    address[] public pocContracts;
    mapping(address => uint256) public pocIndex;

    uint256 public immutable cliffDuration;
    uint256 public immutable vestingPeriods;
    uint256 public immutable vestingPeriodDuration;

    uint256 public totalDeposited;
    uint256 public totalTokensPurchased;
    uint256 public totalCollateralSpent;
    uint256 public vestingStartTime;

    VestingState public state;

    mapping(uint256 => DataTypes.PrivateSaleParticipant) public participants;
    mapping(address => uint256) public pocPurchasedAmount;

    modifier onlyAdmin() {
        require(msg.sender == admin || msg.sender == IDAO(dao).coreConfig().admin, Unauthorized());
        _;
    }

    modifier onlyDAO() {
        require(msg.sender == dao, Unauthorized());
        _;
    }

    modifier atState(VestingState _state) {
        require(state == _state, InvalidState());
        _;
    }

    constructor(
        address _dao,
        address _mainCollateral,
        address[] memory _pocContracts,
        uint256 _cliffDuration,
        uint256 _vestingPeriods,
        uint256 _vestingPeriodDuration
    ) {
        require(_dao != address(0), InvalidAddress());
        require(_mainCollateral != address(0), InvalidAddress());
        require(_pocContracts.length > 0, InvalidAddress());
        require(_vestingPeriods > 0, InvalidAmount());
        require(_vestingPeriodDuration > 0, InvalidAmount());

        dao = _dao;
        mainCollateral = _mainCollateral;
        launchToken = IDAO(_dao).coreConfig().launchToken;
        admin = IDAO(_dao).coreConfig().admin;

        for (uint256 i = 0; i < _pocContracts.length; ++i) {
            require(_pocContracts[i] != address(0), InvalidAddress());
            pocContracts.push(_pocContracts[i]);
            pocIndex[_pocContracts[i]] = i + 1;
        }

        cliffDuration = _cliffDuration;
        vestingPeriods = _vestingPeriods;
        vestingPeriodDuration = _vestingPeriodDuration;

        state = VestingState.Deposit;
    }

    function depositForVesting(uint256 amount) external nonReentrant atState(VestingState.Deposit) {
        require(amount > 0, InvalidAmount());

        uint256 vaultId = IDAO(dao).addressToVaultId(msg.sender);
        require(vaultId > 0, InvalidVault());

        DataTypes.Vault memory vault = IDAO(dao).vaults(vaultId);
        require(vault.primary == msg.sender, Unauthorized());
        require(vault.mainCollateralDeposit > 0, NoFundraisingDeposit());

        DataTypes.PrivateSaleParticipant storage participant = participants[vaultId];

        uint256 totalDeposit = participant.depositedCollateral + amount;
        require(totalDeposit <= vault.mainCollateralDeposit, ExceedsFundraisingDeposit());

        IERC20(mainCollateral).safeTransferFrom(msg.sender, address(this), amount);

        participant.depositedCollateral = totalDeposit;
        totalDeposited += amount;

        emit PrivateSaleDeposit(vaultId, msg.sender, amount);
    }

    function purchaseTokens(
        uint256 pocIdx,
        uint256 collateralAmount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external nonReentrant onlyAdmin atState(VestingState.Deposit) {
        require(totalDeposited > 0, NoDeposits());
        require(pocIdx < pocContracts.length, InvalidAddress());
        require(collateralAmount > 0, InvalidAmount());

        address pocContract = pocContracts[pocIdx];
        DataTypes.POCInfo memory pocInfo = IDAO(dao).getPOCContract(pocIdx);

        require(pocInfo.active, InvalidState());

        uint256 maxCollateralForPOC = (totalDeposited * pocInfo.sharePercent) / 10000;
        uint256 alreadyPurchased = pocPurchasedAmount[pocContract];
        uint256 remainingCollateral =
            maxCollateralForPOC > alreadyPurchased ? maxCollateralForPOC - alreadyPurchased : 0;

        require(remainingCollateral > 0, NoTokensAvailable());
        require(collateralAmount <= remainingCollateral, InvalidAmount());

        IERC20 collateralToken = IProofOfCapital(pocContract).collateralToken();
        address collateralAddr = address(collateralToken);

        uint256 actualCollateralAmount = collateralAmount;
        if (collateralAddr != mainCollateral) {
            actualCollateralAmount =
                _swapToCollateral(mainCollateral, collateralAddr, collateralAmount, router, swapType, swapData);
        }

        uint256 launchBalanceBefore = IERC20(launchToken).balanceOf(address(this));

        IERC20(collateralAddr).safeIncreaseAllowance(pocContract, actualCollateralAmount);

        IProofOfCapital(pocContract).buyLaunchTokens(actualCollateralAmount);

        uint256 launchBalanceAfter = IERC20(launchToken).balanceOf(address(this));
        uint256 tokensReceived = launchBalanceAfter - launchBalanceBefore;

        pocPurchasedAmount[pocContract] += actualCollateralAmount;
        totalCollateralSpent += collateralAmount;
        totalTokensPurchased += tokensReceived;

        if (totalCollateralSpent >= totalDeposited && totalTokensPurchased > 0) {
            vestingStartTime = block.timestamp;
            state = VestingState.PurchaseCompleted;
            emit VestingStarted(vestingStartTime);
        }

        emit TokensPurchased(tokensReceived, collateralAmount);
    }

    function claimVested() external nonReentrant atState(VestingState.PurchaseCompleted) {
        uint256 vaultId = IDAO(dao).addressToVaultId(msg.sender);
        require(vaultId > 0, InvalidVault());

        DataTypes.Vault memory vault = IDAO(dao).vaults(vaultId);
        require(vault.primary == msg.sender, Unauthorized());

        DataTypes.PrivateSaleParticipant storage participant = participants[vaultId];
        require(participant.depositedCollateral > 0, NoTokensAvailable());

        uint256 allocatedTokens = (participant.depositedCollateral * totalTokensPurchased) / totalDeposited;
        require(allocatedTokens > 0, NoTokensAvailable());

        uint256 claimableAmount = getClaimableAmount(vaultId);
        require(claimableAmount > 0, NothingToClaim());

        participant.claimedTokens += claimableAmount;

        IERC20(launchToken).safeTransfer(msg.sender, claimableAmount);

        emit TokensClaimed(vaultId, msg.sender, claimableAmount);
    }

    function dissolve() external nonReentrant onlyDAO {
        require(state != VestingState.Dissolved, InvalidState());
        require(state == VestingState.Deposit || state == VestingState.PurchaseCompleted, InvalidState());

        uint256 launchBalance = IERC20(launchToken).balanceOf(address(this));
        if (launchBalance > 0) {
            IERC20(launchToken).safeTransfer(dao, launchBalance);
        }

        uint256 mainCollateralBalance = IERC20(mainCollateral).balanceOf(address(this));

        state = VestingState.Dissolved;

        emit PrivateSaleDissolved(launchBalance, mainCollateralBalance);
    }

    function claimAfterDissolution() external nonReentrant atState(VestingState.Dissolved) {
        uint256 vaultId = IDAO(dao).addressToVaultId(msg.sender);
        require(vaultId > 0, InvalidVault());

        DataTypes.Vault memory vault = IDAO(dao).vaults(vaultId);
        require(vault.primary == msg.sender, Unauthorized());

        DataTypes.PrivateSaleParticipant storage participant = participants[vaultId];
        require(participant.depositedCollateral > 0, NoTokensAvailable());
        require(!participant.dissolutionClaimed, AlreadyClaimed());

        uint256 collateralBalance = IERC20(mainCollateral).balanceOf(address(this));
        uint256 participantShare = (participant.depositedCollateral * collateralBalance) / totalDeposited;

        require(participantShare > 0, NothingToClaim());

        participant.dissolutionClaimed = true;

        IERC20(mainCollateral).safeTransfer(msg.sender, participantShare);

        emit DissolutionClaimed(vaultId, msg.sender, participantShare);
    }

    function getVestedAmount(uint256 vaultId) public view returns (uint256) {
        DataTypes.PrivateSaleParticipant storage participant = participants[vaultId];
        if (participant.depositedCollateral == 0) return 0;
        if (state != VestingState.PurchaseCompleted) return 0;

        uint256 allocatedTokens = (participant.depositedCollateral * totalTokensPurchased) / totalDeposited;

        uint256 timeElapsed = block.timestamp - vestingStartTime;

        if (timeElapsed < cliffDuration) {
            return 0;
        }

        uint256 timeAfterCliff = timeElapsed - cliffDuration;
        uint256 periodsElapsed = timeAfterCliff / vestingPeriodDuration;

        if (periodsElapsed >= vestingPeriods) {
            return allocatedTokens;
        }

        return (allocatedTokens * periodsElapsed) / vestingPeriods;
    }

    function getClaimableAmount(uint256 vaultId) public view returns (uint256) {
        DataTypes.PrivateSaleParticipant storage participant = participants[vaultId];
        if (participant.depositedCollateral == 0) return 0;

        uint256 vestedAmount = getVestedAmount(vaultId);
        if (vestedAmount <= participant.claimedTokens) {
            return 0;
        }

        return vestedAmount - participant.claimedTokens;
    }

    function _swapToCollateral(
        address from,
        address to,
        uint256 amount,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) internal returns (uint256) {
        require(router != address(0), InvalidAddress());
        require(IDAO(dao).availableRouterByAdmin(router), RouterNotAvailable());

        uint256 mainCollateralPrice = IDAO(dao).getCollateralPrice(from);
        uint256 collateralPrice = IDAO(dao).getCollateralPrice(to);

        uint256 expectedCollateral = (amount * mainCollateralPrice) / collateralPrice;

        uint256 balanceBefore = IERC20(to).balanceOf(address(this));

        _executeSwap(router, swapType, swapData, from, to, amount, 0);

        uint256 balanceAfter = IERC20(to).balanceOf(address(this));
        uint256 collateralAmount = balanceAfter - balanceBefore;

        uint256 deviation = _calculateDeviation(expectedCollateral, collateralAmount);
        require(deviation <= Constants.PRICE_DEVIATION_MAX, PriceDeviationTooHigh());

        return collateralAmount;
    }

    function _executeSwap(
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        return SwapLibrary.executeSwap(router, swapType, swapData, tokenIn, tokenOut, amountIn, amountOutMin);
    }

    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) {
            return 0;
        } else {
            return ((expected - actual) * Constants.BASIS_POINTS) / expected;
        }
    }
}
