// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/ReturnWallet.sol";
import "../src/RoyaltyWallet.sol";
import "../src/interfaces/IReturnWallet.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";
import "../src/mocks/MockERC20.sol";

contract MockDAOForReturnWallet {
    address public caller;
    uint256 public launchPrice = 1e18;
    uint256 public pocCount;
    mapping(uint256 => DataTypes.POCInfo) public pocContracts;

    function setLaunchPrice(uint256 p) external {
        launchPrice = p;
    }

    function setPocCount(uint256 n) external {
        pocCount = n;
    }

    function getLaunchPriceFromDAO() external view returns (uint256) {
        return launchPrice;
    }

    function getPOCContractsCount() external view returns (uint256) {
        return pocCount;
    }

    function getPOCContract(uint256 i) external view returns (DataTypes.POCInfo memory) {
        return pocContracts[i];
    }

    function coreConfig() external pure returns (DataTypes.CoreConfig memory) {
        return DataTypes.CoreConfig({
            admin: address(0),
            votingContract: address(0),
            launchToken: address(0),
            mainCollateral: address(0),
            priceOracle: address(0),
            creator: address(0),
            creatorInfraPercent: 0,
            primaryLPTokenType: DataTypes.LPTokenType.V2,
            pendingUpgradeFromVoting: address(0),
            pendingUpgradeFromVotingTimestamp: 0,
            pendingUpgradeFromCreator: address(0),
            isVetoToCreator: false
        });
    }

    function getDaoState() external pure returns (DataTypes.DAOState memory) {
        return DataTypes.DAOState({
            currentStage: DataTypes.Stage.Active,
            royaltyRecipient: address(0),
            royaltyPercent: 0,
            creator: address(0),
            creatorProfitPercent: 0,
            totalCollectedMainCollateral: 0,
            lastCreatorAllocation: 0,
            totalExitQueueShares: 0,
            totalDepositedUSD: 0,
            lastPOCReturn: 0,
            pendingExitQueuePayment: 0,
            marketMaker: address(0),
            privateSaleContract: address(0)
        });
    }

    function sellableCollaterals(address) external pure returns (address, bool, uint256, uint256) {
        return (address(0), false, 0, 0);
    }

    function pocIndex(address) external pure returns (uint256) {
        return 0;
    }
}

contract MockOracle {
    mapping(address => uint256) public prices;

    function setPrice(address asset, uint256 price) external {
        prices[asset] = price;
    }

    function getAssetPrice(address asset) external view returns (uint256) {
        return prices[asset];
    }
}

contract RoyaltyHolder {
    IERC20 public token;

    constructor(address _token) {
        token = IERC20(_token);
    }

    function approve(address spender, uint256 amount) external {
        token.approve(spender, amount);
    }

    function receiveTokens(address from, uint256 amount) external {
        token.transferFrom(from, address(this), amount);
    }
}

contract ReturnWalletRoyaltyTest is Test {
    ReturnWallet public returnWallet;
    RoyaltyWallet public royaltyWallet;
    MockDAOForReturnWallet public dao;
    MockOracle public oracle;
    MockERC20 public launchToken;
    RoyaltyHolder public royaltyHolder;

    address public daoAddress;
    address public admin;
    address public priceOracle;

    function setUp() public {
        admin = makeAddr("admin");
        daoAddress = address(new MockDAOForReturnWallet());
        dao = MockDAOForReturnWallet(daoAddress);
        dao.setLaunchPrice(1e18);
        dao.setPocCount(0);

        launchToken = new MockERC20("Launch", "LAUNCH", 18);
        launchToken.mint(address(this), 1000e18);

        oracle = new MockOracle();
        oracle.setPrice(address(launchToken), 1e18);
        priceOracle = address(oracle);

        returnWallet = new ReturnWallet(daoAddress, address(launchToken), admin, priceOracle);

        royaltyHolder = new RoyaltyHolder(address(launchToken));
        launchToken.transfer(address(royaltyHolder), 100e18);
        royaltyHolder.approve(address(returnWallet), type(uint256).max);
    }

    function test_setRoyaltyBlacklisted_onlyDAO() public {
        address royalty = address(royaltyHolder);
        vm.prank(makeAddr("stranger"));
        vm.expectRevert(IReturnWallet.Unauthorized.selector);
        returnWallet.setRoyaltyBlacklisted(royalty, true);

        vm.prank(daoAddress);
        returnWallet.setRoyaltyBlacklisted(royalty, true);
        assertTrue(returnWallet.blacklistedRoyalty(royalty));

        vm.prank(daoAddress);
        returnWallet.setRoyaltyBlacklisted(royalty, false);
        assertFalse(returnWallet.blacklistedRoyalty(royalty));
    }

    function test_pullLaunchFromRoyaltyAndReturn_revertsWhenBlacklisted() public {
        address royalty = address(royaltyHolder);
        vm.prank(daoAddress);
        returnWallet.setRoyaltyBlacklisted(royalty, true);

        vm.prank(admin);
        vm.expectRevert(IReturnWallet.RoyaltyBlacklisted.selector);
        returnWallet.pullLaunchFromRoyaltyAndReturn(royalty, 10e18);
    }

    function test_burnBlacklistedRoyaltyLaunch_revertsWhenNotBlacklisted() public {
        vm.prank(makeAddr("anyone"));
        vm.expectRevert(IReturnWallet.RoyaltyNotBlacklisted.selector);
        returnWallet.burnBlacklistedRoyaltyLaunch(address(royaltyHolder), 10e18);
    }

    function test_burnBlacklistedRoyaltyLaunch_anyoneCanCallWhenBlacklisted() public {
        address royalty = address(royaltyHolder);
        vm.prank(daoAddress);
        returnWallet.setRoyaltyBlacklisted(royalty, true);

        uint256 amount = 10e18;
        uint256 supplyBefore = launchToken.totalSupply();
        address caller = makeAddr("anyone");

        vm.prank(caller);
        returnWallet.burnBlacklistedRoyaltyLaunch(royalty, amount);

        assertEq(launchToken.balanceOf(royalty), 100e18 - amount);
        assertEq(launchToken.balanceOf(address(returnWallet)), 0);
        assertEq(launchToken.totalSupply(), supplyBefore - amount);
    }
}

contract TargetThatSendsToken {
    IERC20 public tokenOut;
    IERC20 public tokenIn;
    uint256 public sendAmountOut;

    constructor(address _tokenIn, address _tokenOut) {
        tokenIn = IERC20(_tokenIn);
        tokenOut = IERC20(_tokenOut);
    }

    function setSendAmountOut(uint256 amount) external {
        sendAmountOut = amount;
    }

    function swap(uint256 amountIn) external {
        tokenIn.transferFrom(msg.sender, address(this), amountIn);
        tokenOut.transfer(msg.sender, sendAmountOut);
    }
}

contract RoyaltyWalletPriceCheckTest is Test {
    RoyaltyWallet public royaltyWallet;
    MockDAOForReturnWallet public dao;
    MockOracle public oracle;
    MockERC20 public launchToken;
    MockERC20 public tokenIn;
    TargetThatSendsToken public target;

    address public adminDAO;
    address public admin;
    address public priceOracleAddr;

    function setUp() public {
        adminDAO = makeAddr("adminDAO");
        admin = makeAddr("admin");
        dao = new MockDAOForReturnWallet();
        dao.setLaunchPrice(1e18);
        oracle = new MockOracle();
        priceOracleAddr = address(oracle);
        launchToken = new MockERC20("Launch", "LAUNCH", 18);
        tokenIn = new MockERC20("TokenIn", "TIN", 18);
        tokenIn.mint(address(this), 1000e18);
        launchToken.mint(address(this), 1000e18);
        oracle.setPrice(address(tokenIn), 2e18);
        oracle.setPrice(address(launchToken), 1e18);

        royaltyWallet = new RoyaltyWallet(adminDAO, admin, address(dao), priceOracleAddr, address(launchToken));

        target = new TargetThatSendsToken(address(tokenIn), address(launchToken));
        launchToken.transfer(address(target), 500e18);
    }

    function test_executeWithPriceCheck_revertsWhenDeviationTooHigh() public {
        tokenIn.transfer(address(royaltyWallet), 100e18);
        vm.startPrank(admin);
        royaltyWallet.approveToken(address(tokenIn), address(target), 100e18);
        target.setSendAmountOut(50e18);
        bytes memory callData = abi.encodeWithSelector(TargetThatSendsToken.swap.selector, 100e18);
        vm.expectRevert(RoyaltyWallet.PriceDeviationTooHigh.selector);
        royaltyWallet.executeWithPriceCheck(
            address(tokenIn), address(launchToken), 100e18, 50e18, address(target), callData
        );
        vm.stopPrank();
    }
}
