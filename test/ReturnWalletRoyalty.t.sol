// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/ReturnWallet.sol";
import "../src/RoyaltyWallet.sol";
import "../src/interfaces/IReturnWallet.sol";
import "../src/libraries/Constants.sol";
import "../src/mocks/MockERC20.sol";
import "../src/mocks/MockDAO.sol";
import "../src/mocks/MockPriceOracle.sol";

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
    MockDAO public dao;
    MockPriceOracle public oracle;
    MockERC20 public launchToken;
    RoyaltyHolder public royaltyHolder;

    address public daoAddress;
    address public admin;
    address public priceOracle;

    function setUp() public {
        admin = makeAddr("admin");
        dao = new MockDAO();
        daoAddress = address(dao);
        dao.setLaunchPrice(1e18);
        dao.setPocCount(0);

        launchToken = new MockERC20("Launch", "LAUNCH", 18);
        launchToken.mint(address(this), 1000e18);

        oracle = new MockPriceOracle();
        oracle.setAssetPrice(address(launchToken), 1e18);
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
    MockDAO public dao;
    MockPriceOracle public oracle;
    MockERC20 public launchToken;
    MockERC20 public tokenIn;
    TargetThatSendsToken public target;

    address public adminDAO;
    address public admin;
    address public priceOracleAddr;

    function setUp() public {
        adminDAO = makeAddr("adminDAO");
        admin = makeAddr("admin");
        dao = new MockDAO();
        dao.setLaunchPrice(1e18);
        oracle = new MockPriceOracle();
        priceOracleAddr = address(oracle);
        launchToken = new MockERC20("Launch", "LAUNCH", 18);
        tokenIn = new MockERC20("TokenIn", "TIN", 18);
        tokenIn.mint(address(this), 1000e18);
        launchToken.mint(address(this), 1000e18);
        oracle.setAssetPrice(address(tokenIn), 2e18);
        oracle.setAssetPrice(address(launchToken), 1e18);

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
