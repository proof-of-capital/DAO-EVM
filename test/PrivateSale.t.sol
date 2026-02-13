// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/PrivateSaleTestBase.sol";
import "../src/PrivateSale.sol";
import "../src/interfaces/IPrivateSale.sol";
import "../src/libraries/DataTypes.sol";
import "../src/mocks/MockSellRouter.sol";

contract PrivateSaleTest is PrivateSaleTestBase {
    function test_constructor_success() public view {
        assertEq(address(privateSale.dao()), address(dao));
        assertEq(privateSale.mainCollateral(), address(mainCollateral));
        assertEq(privateSale.launchToken(), address(launchToken));
        assertEq(privateSale.cliffDuration(), CLIFF_DURATION);
        assertEq(privateSale.vestingPeriods(), VESTING_PERIODS);
        assertEq(privateSale.vestingPeriodDuration(), VESTING_PERIOD_DURATION);
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.Deposit));
        assertEq(privateSale.pocContracts(0), address(poc));
    }

    function test_constructor_revert_daoZero() public {
        address[] memory pocs = new address[](1);
        pocs[0] = address(poc);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        new PrivateSale(
            address(0), address(mainCollateral), pocs, CLIFF_DURATION, VESTING_PERIODS, VESTING_PERIOD_DURATION
        );
    }

    function test_constructor_revert_mainCollateralZero() public {
        address[] memory pocs = new address[](1);
        pocs[0] = address(poc);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        new PrivateSale(address(dao), address(0), pocs, CLIFF_DURATION, VESTING_PERIODS, VESTING_PERIOD_DURATION);
    }

    function test_constructor_revert_emptyPocContracts() public {
        address[] memory pocs = new address[](0);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        new PrivateSale(
            address(dao), address(mainCollateral), pocs, CLIFF_DURATION, VESTING_PERIODS, VESTING_PERIOD_DURATION
        );
    }

    function test_constructor_revert_zeroAddressInPocContracts() public {
        address[] memory pocs = new address[](1);
        pocs[0] = address(0);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        new PrivateSale(
            address(dao), address(mainCollateral), pocs, CLIFF_DURATION, VESTING_PERIODS, VESTING_PERIOD_DURATION
        );
    }

    function test_constructor_revert_vestingPeriodsZero() public {
        address[] memory pocs = new address[](1);
        pocs[0] = address(poc);
        vm.expectRevert(IPrivateSale.InvalidAmount.selector);
        new PrivateSale(address(dao), address(mainCollateral), pocs, CLIFF_DURATION, 0, VESTING_PERIOD_DURATION);
    }

    function test_constructor_revert_vestingPeriodDurationZero() public {
        address[] memory pocs = new address[](1);
        pocs[0] = address(poc);
        vm.expectRevert(IPrivateSale.InvalidAmount.selector);
        new PrivateSale(address(dao), address(mainCollateral), pocs, CLIFF_DURATION, VESTING_PERIODS, 0);
    }

    function test_depositForVesting_success() public {
        uint256 amount = 50_000e18;
        vm.recordLogs();
        _deposit(user1, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(logs.length, 1);
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrivateSaleDeposit(uint256,address,uint256)")) {
                found = true;
                break;
            }
        }
        assertTrue(found);

        assertEq(privateSale.totalDeposited(), amount);
        (uint256 dep,,) = privateSale.participants(VAULT_ID_1);
        assertEq(dep, amount);
        assertEq(mainCollateral.balanceOf(address(privateSale)), amount);
    }

    function test_depositForVesting_success_multipleDeposits() public {
        _deposit(user1, 30_000e18);
        _deposit(user1, 20_000e18);
        (uint256 dep,,) = privateSale.participants(VAULT_ID_1);
        assertEq(dep, 50_000e18);
        assertEq(privateSale.totalDeposited(), 50_000e18);
    }

    function test_depositForVesting_revert_invalidAmount() public {
        vm.prank(user1);
        mainCollateral.approve(address(privateSale), 1);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.InvalidAmount.selector);
        privateSale.depositForVesting(0);
    }

    function test_depositForVesting_revert_invalidVault() public {
        address noVault = makeAddr("noVault");
        mainCollateral.mint(noVault, 1000e18);
        vm.startPrank(noVault);
        mainCollateral.approve(address(privateSale), 1000e18);
        vm.expectRevert(IPrivateSale.InvalidVault.selector);
        privateSale.depositForVesting(1000e18);
        vm.stopPrank();
    }

    function test_depositForVesting_revert_unauthorized() public {
        dao.setVault(
            VAULT_ID_1,
            DataTypes.Vault({
                primary: user2,
                backup: address(0),
                emergency: address(0),
                shares: 0,
                votingPausedUntil: 0,
                delegateId: 0,
                delegateSetAt: 0,
                votingShares: 0,
                mainCollateralDeposit: DEPOSIT_LIMIT_1,
                depositedUSD: 0,
                depositLimit: 0
            })
        );
        vm.prank(user1);
        mainCollateral.approve(address(privateSale), 1000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.Unauthorized.selector);
        privateSale.depositForVesting(1000e18);
    }

    function test_depositForVesting_revert_noFundraisingDeposit() public {
        dao.setVault(
            VAULT_ID_1,
            DataTypes.Vault({
                primary: user1,
                backup: address(0),
                emergency: address(0),
                shares: 0,
                votingPausedUntil: 0,
                delegateId: 0,
                delegateSetAt: 0,
                votingShares: 0,
                mainCollateralDeposit: 0,
                depositedUSD: 0,
                depositLimit: 0
            })
        );
        vm.prank(user1);
        mainCollateral.approve(address(privateSale), 1000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.NoFundraisingDeposit.selector);
        privateSale.depositForVesting(1000e18);
    }

    function test_depositForVesting_revert_exceedsFundraisingDeposit() public {
        vm.prank(user1);
        mainCollateral.approve(address(privateSale), DEPOSIT_LIMIT_1 + 1);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.ExceedsFundraisingDeposit.selector);
        privateSale.depositForVesting(DEPOSIT_LIMIT_1 + 1);
    }

    function test_purchaseTokens_success_transitionsToPurchaseCompleted() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        assertEq(privateSale.totalDeposited(), 80_000e18);

        vm.recordLogs();
        _purchaseTokens(0, 80_000e18);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        assertGe(logs.length, 2);
        assertEq(privateSale.totalCollateralSpent(), 80_000e18);
        assertEq(privateSale.totalTokensPurchased(), 80_000e18);
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.PurchaseCompleted));
        assertEq(privateSale.vestingStartTime(), block.timestamp);
    }

    function test_purchaseTokens_success_partialThenFull() public {
        _deposit(user1, 100_000e18);
        _purchaseTokens(0, 40_000e18);
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.Deposit));
        assertEq(privateSale.totalCollateralSpent(), 40_000e18);

        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.VestingStarted(block.timestamp);
        _purchaseTokens(0, 60_000e18);
        assertEq(privateSale.totalCollateralSpent(), 100_000e18);
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.PurchaseCompleted));
    }

    function test_purchaseTokens_revert_noDeposits() public {
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.NoDeposits.selector);
        privateSale.purchaseTokens(0, 1000e18, address(0), DataTypes.SwapType.None, "");
    }

    function test_purchaseTokens_revert_invalidPocIdx() public {
        _deposit(user1, 50_000e18);
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        privateSale.purchaseTokens(1, 50_000e18, address(0), DataTypes.SwapType.None, "");
    }

    function test_purchaseTokens_revert_collateralAmountZero() public {
        _deposit(user1, 50_000e18);
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.InvalidAmount.selector);
        privateSale.purchaseTokens(0, 0, address(0), DataTypes.SwapType.None, "");
    }

    function test_purchaseTokens_revert_pocNotActive() public {
        _deposit(user1, 50_000e18);
        dao.setPOCContract(
            0,
            DataTypes.POCInfo({
                pocContract: address(poc),
                collateralToken: address(mainCollateral),
                sharePercent: 10000,
                active: false,
                exchanged: false,
                exchangedAmount: 0
            })
        );
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.purchaseTokens(0, 50_000e18, address(0), DataTypes.SwapType.None, "");
    }

    function test_purchaseTokens_revert_exceedsRemainingCollateral() public {
        _deposit(user1, 50_000e18);
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.InvalidAmount.selector);
        privateSale.purchaseTokens(0, 50_001e18, address(0), DataTypes.SwapType.None, "");
    }

    function test_purchaseTokens_revert_unauthorized() public {
        _deposit(user1, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.Unauthorized.selector);
        privateSale.purchaseTokens(0, 50_000e18, address(0), DataTypes.SwapType.None, "");
    }

    function test_getVestedAmount_inDepositState_returnsZero() public {
        _deposit(user1, 50_000e18);
        assertEq(privateSale.getVestedAmount(VAULT_ID_1), 0);
        assertEq(privateSale.getClaimableAmount(VAULT_ID_1), 0);
    }

    function test_getVestedAmount_beforeCliff_returnsZero() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION - 1);
        assertEq(privateSale.getVestedAmount(VAULT_ID_1), 0);
        assertEq(privateSale.getClaimableAmount(VAULT_ID_1), 0);
    }

    function test_getVestedAmount_afterCliff_partialVesting() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        uint256 allocated1 = (50_000e18 * 80_000e18) / 80_000e18;
        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION + VESTING_PERIOD_DURATION);
        uint256 expectedVested = (allocated1 * 1) / VESTING_PERIODS;
        assertEq(privateSale.getVestedAmount(VAULT_ID_1), expectedVested);
        assertEq(privateSale.getClaimableAmount(VAULT_ID_1), expectedVested);
    }

    function test_getVestedAmount_fullVesting() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _warpToFullVesting();
        uint256 allocated1 = (50_000e18 * 80_000e18) / 80_000e18;
        assertEq(privateSale.getVestedAmount(VAULT_ID_1), allocated1);
        assertEq(privateSale.getClaimableAmount(VAULT_ID_1), allocated1);
    }

    function test_claimVested_success() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _warpToFullVesting();

        uint256 claimable = privateSale.getClaimableAmount(VAULT_ID_1);
        uint256 balanceBefore = launchToken.balanceOf(user1);
        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.TokensClaimed(VAULT_ID_1, user1, claimable);
        vm.prank(user1);
        privateSale.claimVested();

        assertEq(launchToken.balanceOf(user1), balanceBefore + claimable);
        (, uint256 claimed,) = privateSale.participants(VAULT_ID_1);
        assertEq(claimed, claimable);
    }

    function test_claimVested_multipleClaims() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _warpToAfterCliff();
        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION + VESTING_PERIOD_DURATION);

        vm.prank(user1);
        privateSale.claimVested();
        (, uint256 firstClaim,) = privateSale.participants(VAULT_ID_1);

        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION + 2 * VESTING_PERIOD_DURATION);
        vm.prank(user1);
        privateSale.claimVested();
        (, uint256 claimedAfter,) = privateSale.participants(VAULT_ID_1);
        uint256 secondClaim = claimedAfter - firstClaim;
        assertTrue(secondClaim > 0);
    }

    function test_claimVested_revert_invalidVault() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        _warpToFullVesting();
        address noVault = makeAddr("noVault");
        vm.prank(noVault);
        vm.expectRevert(IPrivateSale.InvalidVault.selector);
        privateSale.claimVested();
    }

    function test_claimVested_revert_unauthorized() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        _warpToFullVesting();
        address notPrimary = makeAddr("notPrimary");
        dao.setAddressToVaultId(notPrimary, VAULT_ID_1);
        vm.prank(notPrimary);
        vm.expectRevert(IPrivateSale.Unauthorized.selector);
        privateSale.claimVested();
    }

    function test_claimVested_revert_nothingToClaim() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.NothingToClaim.selector);
        privateSale.claimVested();
    }

    function test_claimVested_revert_invalidState() public {
        _deposit(user1, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.claimVested();
    }

    function test_dissolve_success() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        uint256 launchBalance = launchToken.balanceOf(address(privateSale));
        uint256 collateralBalance = mainCollateral.balanceOf(address(privateSale));

        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.PrivateSaleDissolved(launchBalance, collateralBalance);
        _dissolve();

        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.Dissolved));
        assertEq(launchToken.balanceOf(address(dao)), launchBalance);
    }

    function test_dissolve_fromDepositState() public {
        _deposit(user1, 50_000e18);
        _dissolve();
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.Dissolved));
    }

    function test_dissolve_revert_unauthorized() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.Unauthorized.selector);
        privateSale.dissolve();
    }

    function test_dissolve_revert_alreadyDissolved() public {
        _deposit(user1, 50_000e18);
        _dissolve();
        vm.prank(address(dao));
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.dissolve();
    }

    function test_claimAfterDissolution_success() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _dissolve();

        uint256 collateralBalance = mainCollateral.balanceOf(address(privateSale));
        uint256 share1 = (50_000e18 * collateralBalance) / 80_000e18;
        uint256 balanceBefore = mainCollateral.balanceOf(user1);

        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.DissolutionClaimed(VAULT_ID_1, user1, share1);
        vm.prank(user1);
        privateSale.claimAfterDissolution();

        assertEq(mainCollateral.balanceOf(user1), balanceBefore + share1);
        (,, bool dissolutionClaimed) = privateSale.participants(VAULT_ID_1);
        assertTrue(dissolutionClaimed);
    }

    function test_claimAfterDissolution_revert_invalidState() public {
        _deposit(user1, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.claimAfterDissolution();
    }

    function test_claimAfterDissolution_revert_alreadyClaimed() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _dissolve();
        vm.prank(user1);
        privateSale.claimAfterDissolution();
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.AlreadyClaimed.selector);
        privateSale.claimAfterDissolution();
    }

    function test_onlyAdmin_purchaseTokens_fromDaoAdmin() public {
        _deposit(user1, 50_000e18);
        vm.prank(admin);
        privateSale.purchaseTokens(0, 50_000e18, address(0), DataTypes.SwapType.None, "");
        assertEq(uint256(privateSale.state()), uint256(IPrivateSale.VestingState.PurchaseCompleted));
    }

    function test_atState_claimVested_wrongState() public {
        _deposit(user1, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.claimVested();
    }

    function test_atState_claimAfterDissolution_wrongState() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        vm.prank(user1);
        vm.expectRevert(IPrivateSale.InvalidState.selector);
        privateSale.claimAfterDissolution();
    }

    function test_event_PrivateSaleDeposit() public {
        uint256 amount = 10_000e18;
        vm.recordLogs();
        _deposit(user1, amount);
        Vm.Log[] memory logs = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < logs.length; i++) {
            if (logs[i].topics[0] == keccak256("PrivateSaleDeposit(uint256,address,uint256)")) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_event_TokensPurchased() public {
        _deposit(user1, 50_000e18);
        vm.recordLogs();
        _purchaseTokens(0, 50_000e18);
        Vm.Log[] memory entries = vm.getRecordedLogs();
        bool found;
        for (uint256 i = 0; i < entries.length; i++) {
            if (entries[i].topics[0] == keccak256("TokensPurchased(uint256,uint256)")) {
                found = true;
                break;
            }
        }
        assertTrue(found);
    }

    function test_event_TokensClaimed() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        _warpToFullVesting();
        uint256 amt = privateSale.getClaimableAmount(VAULT_ID_1);
        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.TokensClaimed(VAULT_ID_1, user1, amt);
        vm.prank(user1);
        privateSale.claimVested();
    }

    function test_event_PrivateSaleDissolved() public {
        _deposit(user1, 50_000e18);
        _purchaseTokens(0, 50_000e18);
        uint256 launchBal = launchToken.balanceOf(address(privateSale));
        uint256 collBal = mainCollateral.balanceOf(address(privateSale));
        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.PrivateSaleDissolved(launchBal, collBal);
        _dissolve();
    }

    function test_event_DissolutionClaimed() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _dissolve();
        uint256 collBalance = mainCollateral.balanceOf(address(privateSale));
        uint256 share1 = (50_000e18 * collBalance) / 80_000e18;
        vm.expectEmit(true, true, true, true);
        emit IPrivateSale.DissolutionClaimed(VAULT_ID_1, user1, share1);
        vm.prank(user1);
        privateSale.claimAfterDissolution();
    }

    function test_getClaimableAmount_afterPartialClaim() public {
        _deposit(user1, 50_000e18);
        _deposit(user2, 30_000e18);
        _purchaseTokens(0, 80_000e18);
        _warpToFullVesting();

        vm.prank(user1);
        privateSale.claimVested();
        assertEq(privateSale.getClaimableAmount(VAULT_ID_1), 0);
        (, uint256 claimed,) = privateSale.participants(VAULT_ID_1);
        assertGt(claimed, 0);
    }

    function test_purchaseTokens_sharePercentLimit() public {
        dao.setPOCContract(
            0,
            DataTypes.POCInfo({
                pocContract: address(poc),
                collateralToken: address(mainCollateral),
                sharePercent: 5000,
                active: true,
                exchanged: false,
                exchangedAmount: 0
            })
        );
        _deposit(user1, 100_000e18);
        _purchaseTokens(0, 50_000e18);
        assertEq(privateSale.pocPurchasedAmount(address(poc)), 50_000e18);
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.NoTokensAvailable.selector);
        privateSale.purchaseTokens(0, 1, address(0), DataTypes.SwapType.None, "");
    }
}

contract PrivateSaleSwapTest is PrivateSaleTestBase {
    MockERC20 public altCollateral;
    MockProofOfCapital public poc1;
    MockSellRouterLowOutput public mockRouter;

    function setUp() public override {
        super.setUp();
        altCollateral = new MockERC20("DAI", "DAI", 18);
        poc1 = new MockProofOfCapital(address(altCollateral), address(launchToken));
        poc1.setActive(true);
        launchToken.mint(address(poc1), POC_LAUNCH_SUPPLY);
        poc1.setLaunchBalance(POC_LAUNCH_SUPPLY);

        dao.setPocCount(2);
        dao.setPOCContract(
            1,
            DataTypes.POCInfo({
                pocContract: address(poc1),
                collateralToken: address(altCollateral),
                sharePercent: 5000,
                active: true,
                exchanged: false,
                exchangedAmount: 0
            })
        );
        dao.setCollateralPrice(address(mainCollateral), 1e18);
        dao.setCollateralPrice(address(altCollateral), 1e18);

        mockRouter = new MockSellRouterLowOutput();
        altCollateral.mint(address(mockRouter), 500_000e18);
        dao.setAvailableRouterByAdmin(address(mockRouter), true);

        address[] memory pocContracts = new address[](2);
        pocContracts[0] = address(poc);
        pocContracts[1] = address(poc1);
        privateSale = new PrivateSale(
            address(dao),
            address(mainCollateral),
            pocContracts,
            CLIFF_DURATION,
            VESTING_PERIODS,
            VESTING_PERIOD_DURATION
        );
    }

    function _purchaseTokensWithSwap(
        uint256 pocIdx,
        uint256 collateralAmount,
        address router,
        DataTypes.SwapType swapType,
        bytes memory swapData
    ) internal {
        vm.prank(admin);
        privateSale.purchaseTokens(pocIdx, collateralAmount, router, swapType, swapData);
    }

    function test_swapToCollateral_success() public {
        _deposit(user1, 80_000e18);
        uint256 amount = 40_000e18;
        mockRouter.setOutputAmount(amount);
        bytes memory swapData = abi.encode(uint24(3000), block.timestamp + 3600, uint160(0));
        _purchaseTokensWithSwap(1, amount, address(mockRouter), DataTypes.SwapType.UniswapV3ExactInputSingle, swapData);
        assertEq(privateSale.totalCollateralSpent(), amount);
        assertGt(privateSale.totalTokensPurchased(), 0);
    }

    function test_swapToCollateral_revert_routerZero() public {
        _deposit(user1, 80_000e18);
        uint256 amount = 40_000e18;
        bytes memory swapData = abi.encode(uint24(3000), block.timestamp + 3600, uint160(0));
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.InvalidAddress.selector);
        privateSale.purchaseTokens(1, amount, address(0), DataTypes.SwapType.UniswapV3ExactInputSingle, swapData);
    }

    function test_swapToCollateral_revert_routerNotAvailable() public {
        _deposit(user1, 80_000e18);
        dao.setAvailableRouterByAdmin(address(mockRouter), false);
        uint256 amount = 40_000e18;
        mockRouter.setOutputAmount(amount);
        bytes memory swapData = abi.encode(uint24(3000), block.timestamp + 3600, uint160(0));
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.RouterNotAvailable.selector);
        privateSale.purchaseTokens(
            1, amount, address(mockRouter), DataTypes.SwapType.UniswapV3ExactInputSingle, swapData
        );
    }

    function test_swapToCollateral_revert_priceDeviationTooHigh() public {
        _deposit(user1, 80_000e18);
        uint256 amount = 40_000e18;
        uint256 expectedCollateral = amount;
        uint256 lowOutput = (expectedCollateral * 96) / 100;
        mockRouter.setOutputAmount(lowOutput);
        bytes memory swapData = abi.encode(uint24(3000), block.timestamp + 3600, uint160(0));
        vm.prank(admin);
        vm.expectRevert(IPrivateSale.PriceDeviationTooHigh.selector);
        privateSale.purchaseTokens(
            1, amount, address(mockRouter), DataTypes.SwapType.UniswapV3ExactInputSingle, swapData
        );
    }
}
