// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../../src/PrivateSale.sol";
import "../../src/interfaces/IPrivateSale.sol";
import "../../src/interfaces/IDAO.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/mocks/MockDAO.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockProofOfCapital.sol";

abstract contract PrivateSaleTestBase is Test {
    PrivateSale public privateSale;
    MockDAO public dao;
    MockERC20 public mainCollateral;
    MockERC20 public launchToken;
    MockProofOfCapital public poc;

    address public admin;
    address public user1;
    address public user2;

    uint256 public constant VAULT_ID_1 = 1;
    uint256 public constant VAULT_ID_2 = 2;
    uint256 public constant DEPOSIT_LIMIT_1 = 100_000e18;
    uint256 public constant DEPOSIT_LIMIT_2 = 60_000e18;

    uint256 public constant CLIFF_DURATION = 30 days;
    uint256 public constant VESTING_PERIODS = 4;
    uint256 public constant VESTING_PERIOD_DURATION = 90 days;

    uint256 public constant POC_LAUNCH_SUPPLY = 10_000_000e18;

    function setUp() public virtual {
        admin = address(this);
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");

        _deployTokens();
        _deployPOC();
        _deployDAO();
        _deployPrivateSale();
        _mintBalances();
    }

    function _deployTokens() internal {
        mainCollateral = new MockERC20("USDC", "USDC", 18);
        launchToken = new MockERC20("Launch", "LAUNCH", 18);
    }

    function _deployPOC() internal {
        poc = new MockProofOfCapital(address(mainCollateral), address(launchToken));
        poc.setActive(true);
    }

    function _deployDAO() internal {
        dao = new MockDAO();

        DataTypes.CoreConfig memory config = DataTypes.CoreConfig({
            admin: admin,
            votingContract: address(0),
            launchToken: address(launchToken),
            mainCollateral: address(mainCollateral),
            priceOracle: address(0),
            creator: address(0),
            creatorInfraPercent: 0,
            primaryLPTokenType: DataTypes.LPTokenType.V2,
            pendingUpgradeFromVoting: address(0),
            pendingUpgradeFromVotingTimestamp: 0,
            pendingUpgradeFromCreator: address(0),
            isVetoToCreator: false
        });
        dao.setCoreConfig(config);

        dao.setPocCount(1);
        dao.setPOCContract(
            0,
            DataTypes.POCInfo({
                pocContract: address(poc),
                collateralToken: address(mainCollateral),
                sharePercent: 10000,
                active: true,
                exchanged: false,
                exchangedAmount: 0
            })
        );

        dao.setAddressToVaultId(user1, VAULT_ID_1);
        dao.setAddressToVaultId(user2, VAULT_ID_2);

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
                mainCollateralDeposit: DEPOSIT_LIMIT_1,
                depositedUSD: 0,
                depositLimit: 0
            })
        );
        dao.setVault(
            VAULT_ID_2,
            DataTypes.Vault({
                primary: user2,
                backup: address(0),
                emergency: address(0),
                shares: 0,
                votingPausedUntil: 0,
                delegateId: 0,
                delegateSetAt: 0,
                votingShares: 0,
                mainCollateralDeposit: DEPOSIT_LIMIT_2,
                depositedUSD: 0,
                depositLimit: 0
            })
        );
    }

    function _deployPrivateSale() internal {
        address[] memory pocContracts = new address[](1);
        pocContracts[0] = address(poc);

        privateSale = new PrivateSale(
            address(dao),
            address(mainCollateral),
            pocContracts,
            CLIFF_DURATION,
            VESTING_PERIODS,
            VESTING_PERIOD_DURATION
        );
    }

    function _mintBalances() internal {
        mainCollateral.mint(user1, 500_000e18);
        mainCollateral.mint(user2, 500_000e18);
        launchToken.mint(address(poc), POC_LAUNCH_SUPPLY);
        poc.setLaunchBalance(POC_LAUNCH_SUPPLY);
    }

    function _deposit(address user, uint256 amount) internal {
        vm.startPrank(user);
        mainCollateral.approve(address(privateSale), amount);
        privateSale.depositForVesting(amount);
        vm.stopPrank();
    }

    function _purchaseTokens(uint256 pocIdx, uint256 collateralAmount) internal {
        vm.prank(admin);
        privateSale.purchaseTokens(pocIdx, collateralAmount, address(0), DataTypes.SwapType.None, "");
    }

    function _warpToAfterCliff() internal {
        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION + 1);
    }

    function _warpToFullVesting() internal {
        vm.warp(privateSale.vestingStartTime() + CLIFF_DURATION + VESTING_PERIODS * VESTING_PERIOD_DURATION);
    }

    function _dissolve() internal {
        vm.prank(address(dao));
        privateSale.dissolve();
    }
}
