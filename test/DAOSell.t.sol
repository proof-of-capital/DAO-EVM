// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/interfaces/IDAO.sol";
import "../src/Voting.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/external/Orderbook.sol";
import "../src/libraries/internal/SwapLibrary.sol";
import "../src/mocks/MockSellRouter.sol";
import "../src/mocks/MockERC20.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

event LaunchTokenSold(
    address indexed seller, address indexed collateral, uint256 launchTokenAmount, uint256 collateralAmount
);

contract DAOSellTest is DAOTestBase {
    MockSellRouter public mockSellRouter;

    function _deployDAO() internal override {
        mockSellRouter = new MockSellRouter();
        mainCollateral.mint(address(mockSellRouter), 1_000_000e18);

        Voting _voting = new Voting();

        DataTypes.POCConstructorParams[] memory pocParams = new DataTypes.POCConstructorParams[](1);
        pocParams[0] = DataTypes.POCConstructorParams({
            pocContract: address(poc), collateralToken: address(mainCollateral), sharePercent: 10000
        });

        DataTypes.OrderbookConstructorParams memory orderbookParams = DataTypes.OrderbookConstructorParams({
            initialPrice: LAUNCH_PRICE,
            initialVolume: 1000e18,
            priceStepPercent: 500,
            volumeStepPercent: -100,
            proportionalityCoefficient: 7500,
            totalSupply: 1e27
        });

        address[] memory routers = new address[](1);
        routers[0] = address(mockSellRouter);

        DataTypes.ConstructorParams memory params = DataTypes.ConstructorParams({
            launchToken: address(launchToken),
            mainCollateral: address(mainCollateral),
            creator: address(0),
            creatorProfitPercent: 4000,
            creatorInfraPercent: 1000,
            royaltyRecipient: royaltyRecipient,
            royaltyPercent: 1000,
            minDeposit: MIN_DEPOSIT,
            minLaunchDeposit: MIN_LAUNCH_DEPOSIT,
            sharePrice: SHARE_PRICE,
            launchPrice: LAUNCH_PRICE,
            targetAmountMainCollateral: TARGET_AMOUNT,
            fundraisingDuration: 30 days,
            extensionPeriod: 14 days,
            collateralTokens: new address[](0),
            routers: routers,
            tokens: new address[](0),
            pocParams: pocParams,
            rewardTokenParams: new DataTypes.RewardTokenConstructorParams[](0),
            orderbookParams: orderbookParams,
            primaryLPTokenType: DataTypes.LPTokenType.V2,
            v3LPPositions: new DataTypes.V3LPPositionParams[](0),
            allowedExitTokens: new address[](0),
            launchTokenPricePaths: DataTypes.TokenPricePathsParams({
                v2Paths: new DataTypes.PricePathV2Params[](0),
                v3Paths: new DataTypes.PricePathV3Params[](0),
                minLiquidity: 1000e18
            }),
            priceOracle: address(priceOracle),
            votingContract: address(_voting),
            marketMaker: address(0),
            lpDepegParams: new DataTypes.LPTokenDepegParams[](0)
        });

        DAO impl = new DAO();
        bytes memory initData = abi.encodeWithSelector(DAO.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        dao = DAO(payable(address(proxy)));
        voting = _voting;
        voting.setDAO(address(dao));
    }

    function _sellSwapDataV3ExactInputSingle() internal view returns (bytes memory) {
        return abi.encode(uint24(0), block.timestamp, uint160(0));
    }

    function test_sell_success() external {
        _reachActiveStage();

        uint256 launchAmount = 1e14;
        uint256 minCollateral = 1e13;
        uint256 balanceBefore = dao.accountedBalance(address(launchToken));
        (,,,,,, uint256 totalSoldBefore,,,,,) = dao.orderbookParams();

        vm.prank(user1);
        vm.expectEmit(true, true, true, true);
        emit LaunchTokenSold(user1, address(mainCollateral), launchAmount, minCollateral);
        dao.sell(
            address(mainCollateral),
            launchAmount,
            minCollateral,
            address(mockSellRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );

        assertEq(dao.accountedBalance(address(launchToken)), balanceBefore - launchAmount);
        (,,,,,, uint256 totalSoldAfter,,,,,) = dao.orderbookParams();
        assertEq(totalSoldAfter, totalSoldBefore + launchAmount);
    }

    function test_sell_revert_CollateralNotSellable() external {
        _reachActiveStage();

        address notSellableCollateral = address(new MockERC20("Other", "OTH", 18));

        vm.prank(user1);
        vm.expectRevert(Orderbook.CollateralNotSellable.selector);
        dao.sell(
            notSellableCollateral,
            1000e18,
            100e18,
            address(mockSellRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }

    function test_sell_revert_RouterNotAvailable() external {
        _reachActiveStage();

        address unknownRouter = makeAddr("unknownRouter");

        vm.prank(user1);
        vm.expectRevert(SwapLibrary.RouterNotAvailable.selector);
        dao.sell(
            address(mainCollateral),
            1000e18,
            100e18,
            unknownRouter,
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }

    function test_sell_revert_Unauthorized() external {
        _reachActiveStage();

        address stranger = makeAddr("stranger");

        vm.prank(stranger);
        vm.expectRevert(IDAO.Unauthorized.selector);
        dao.sell(
            address(mainCollateral),
            1000e18,
            100e18,
            address(mockSellRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }

    function test_sell_revert_InvalidStage() external {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);

        vm.prank(user1);
        vm.expectRevert(IDAO.InvalidStage.selector);
        dao.sell(
            address(mainCollateral),
            1000e18,
            100e18,
            address(mockSellRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }

    function test_sell_revert_insufficient_accountedBalance() external {
        _reachActiveStage();

        uint256 excessLaunch = dao.accountedBalance(address(launchToken)) + 1e18;

        vm.prank(user1);
        vm.expectRevert();
        dao.sell(
            address(mainCollateral),
            excessLaunch,
            100e18,
            address(mockSellRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }
}

contract DAOSellInsufficientCollateralTest is DAOTestBase {
    MockSellRouterLowOutput public lowRouter;

    function _deployDAO() internal override {
        lowRouter = new MockSellRouterLowOutput();
        lowRouter.setOutputAmount(1e18);
        mainCollateral.mint(address(lowRouter), 1e18);

        Voting _voting = new Voting();
        DataTypes.POCConstructorParams[] memory pocParams = new DataTypes.POCConstructorParams[](1);
        pocParams[0] = DataTypes.POCConstructorParams({
            pocContract: address(poc), collateralToken: address(mainCollateral), sharePercent: 10000
        });
        DataTypes.OrderbookConstructorParams memory orderbookParams = DataTypes.OrderbookConstructorParams({
            initialPrice: LAUNCH_PRICE,
            initialVolume: 1000e18,
            priceStepPercent: 500,
            volumeStepPercent: -100,
            proportionalityCoefficient: 7500,
            totalSupply: 1e27
        });
        address[] memory routers = new address[](1);
        routers[0] = address(lowRouter);
        DataTypes.ConstructorParams memory params = DataTypes.ConstructorParams({
            launchToken: address(launchToken),
            mainCollateral: address(mainCollateral),
            creator: address(0),
            creatorProfitPercent: 4000,
            creatorInfraPercent: 1000,
            royaltyRecipient: royaltyRecipient,
            royaltyPercent: 1000,
            minDeposit: MIN_DEPOSIT,
            minLaunchDeposit: MIN_LAUNCH_DEPOSIT,
            sharePrice: SHARE_PRICE,
            launchPrice: LAUNCH_PRICE,
            targetAmountMainCollateral: TARGET_AMOUNT,
            fundraisingDuration: 30 days,
            extensionPeriod: 14 days,
            collateralTokens: new address[](0),
            routers: routers,
            tokens: new address[](0),
            pocParams: pocParams,
            rewardTokenParams: new DataTypes.RewardTokenConstructorParams[](0),
            orderbookParams: orderbookParams,
            primaryLPTokenType: DataTypes.LPTokenType.V2,
            v3LPPositions: new DataTypes.V3LPPositionParams[](0),
            allowedExitTokens: new address[](0),
            launchTokenPricePaths: DataTypes.TokenPricePathsParams({
                v2Paths: new DataTypes.PricePathV2Params[](0),
                v3Paths: new DataTypes.PricePathV3Params[](0),
                minLiquidity: 1000e18
            }),
            priceOracle: address(priceOracle),
            votingContract: address(_voting),
            marketMaker: address(0),
            lpDepegParams: new DataTypes.LPTokenDepegParams[](0)
        });
        DAO impl = new DAO();
        bytes memory initData = abi.encodeWithSelector(DAO.initialize.selector, params);
        ERC1967Proxy proxy = new ERC1967Proxy(address(impl), initData);
        dao = DAO(payable(address(proxy)));
        voting = _voting;
        voting.setDAO(address(dao));
    }

    function _sellSwapDataV3ExactInputSingle() internal view returns (bytes memory) {
        return abi.encode(uint24(0), block.timestamp, uint160(0));
    }

    function test_sell_revert_InsufficientCollateralReceived() external {
        _reachActiveStage();
        uint256 launchAmount = 1e14;
        uint256 minCollateral = 1e12;
        lowRouter.setOutputAmount(1e12);
        vm.prank(user1);
        vm.expectRevert(abi.encodeWithSelector(Orderbook.InsufficientCollateralReceived.selector, 1e13, 1e12));
        dao.sell(
            address(mainCollateral),
            launchAmount,
            minCollateral,
            address(lowRouter),
            DataTypes.SwapType.UniswapV3ExactInputSingle,
            _sellSwapDataV3ExactInputSingle()
        );
    }
}
