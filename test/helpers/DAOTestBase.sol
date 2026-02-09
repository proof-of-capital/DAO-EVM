// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../../src/DAO.sol";
import "../../src/Voting.sol";
import "../../src/libraries/DataTypes.sol";
import "../../src/libraries/Constants.sol";
import "../../src/mocks/MockERC20.sol";
import "../../src/mocks/MockPriceOracle.sol";
import "../../src/mocks/MockProofOfCapital.sol";
import "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

abstract contract DAOTestBase is Test {
    DAO public dao;
    Voting public voting;

    MockERC20 public launchToken;
    MockERC20 public mainCollateral;
    MockERC20 public lpToken;

    MockPriceOracle public priceOracle;
    MockProofOfCapital public poc;

    address public admin;
    address public creator;
    address public user1;
    address public user2;
    address public user3;
    address public royaltyRecipient;

    uint256 public constant TARGET_AMOUNT = 200_000e18;
    uint256 public constant SHARE_PRICE = 1000e18;
    uint256 public constant LAUNCH_PRICE = 0.1e18;
    uint256 public constant MIN_DEPOSIT = 1000e18;
    uint256 public constant MIN_LAUNCH_DEPOSIT = 10_000e18;

    function setUp() public virtual {
        admin = address(this);
        creator = makeAddr("creator");
        user1 = makeAddr("user1");
        user2 = makeAddr("user2");
        user3 = makeAddr("user3");
        royaltyRecipient = makeAddr("royalty");

        _deployTokens();
        _deployOracle();
        _deployPOC();
        _deployDAO();
    }

    function _deployTokens() internal {
        launchToken = new MockERC20("Launch", "LAUNCH", 18);
        mainCollateral = new MockERC20("USDC", "USDC", 18);
        lpToken = new MockERC20("LP", "LP", 18);

        launchToken.mint(address(this), 10_000_000e18);
        mainCollateral.mint(user1, 500_000e18);
        mainCollateral.mint(user2, 500_000e18);
        mainCollateral.mint(user3, 500_000e18);
    }

    function _deployOracle() internal {
        priceOracle = new MockPriceOracle();
        priceOracle.setAssetPrice(address(mainCollateral), 1e18);
        priceOracle.setAssetPrice(address(launchToken), LAUNCH_PRICE);
    }

    function _deployPOC() internal {
        poc = new MockProofOfCapital(address(mainCollateral), address(launchToken));
        launchToken.mint(address(poc), 5_000_000e18);
        poc.setLaunchBalance(5_000_000e18);
        poc.setCurrentPrice(LAUNCH_PRICE);
    }

    function _deployDAO() internal {
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
            routers: new address[](0),
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

    function _setCreator(address _creator) internal {
        vm.prank(admin);
        dao.setCreator(_creator);
    }

    function _vaultRecoveryAddresses(address user) internal pure returns (address backup, address emergency) {
        backup = address(uint160(uint256(keccak256(abi.encodePacked("backup", user)))));
        emergency = address(uint160(uint256(keccak256(abi.encodePacked("emergency", user)))));
        if (emergency == backup) {
            emergency = address(uint160(uint256(keccak256(abi.encodePacked("emergency2", user)))));
        }
    }

    function _createVaultAndDeposit(address user, uint256 amount) internal {
        (address backup, address emergency) = _vaultRecoveryAddresses(user);

        vm.startPrank(user);
        dao.createVault(backup, emergency, address(0));
        uint256 vaultId = dao.addressToVaultId(user);
        vm.stopPrank();

        uint256 sharesEstimate = (amount * 1e18) / SHARE_PRICE;
        vm.prank(admin);
        dao.setVaultDepositLimit(vaultId, sharesEstimate + 1000e18);

        vm.startPrank(user);
        mainCollateral.approve(address(dao), amount);
        dao.depositFundraising(amount, 0);
        vm.stopPrank();
    }

    function _finalizeFundraising() internal {
        vm.prank(admin);
        dao.finalizeFundraisingCollection();
    }

    function _exchangeAllPOCs() internal {
        uint256 count = dao.getPOCContractsCount();
        for (uint256 i = 0; i < count; i++) {
            vm.prank(admin);
            dao.exchangeForPOC(i, 0, address(0), DataTypes.SwapType.None, "");
        }
    }

    function _finalizeExchange() internal {
        vm.prank(admin);
        dao.finalizeExchange();
    }

    function _provideLPTokens() internal {
        uint256 lpAmount = 1000e18;
        lpToken.mint(creator, lpAmount);

        address[] memory v2Addrs = new address[](1);
        v2Addrs[0] = address(lpToken);
        uint256[] memory v2Amounts = new uint256[](1);
        v2Amounts[0] = lpAmount;

        vm.startPrank(creator);
        lpToken.approve(address(dao), lpAmount);
        dao.provideLPTokens(
            v2Addrs,
            v2Amounts,
            new uint256[](0),
            new DataTypes.PricePathV2Params[](0),
            new DataTypes.PricePathV3Params[](0)
        );
        vm.stopPrank();
    }

    function _reachActiveStage() internal {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 100_000e18);
        _createVaultAndDeposit(user2, 60_000e18);
        _createVaultAndDeposit(user3, 50_000e18);
        _finalizeFundraising();
        _exchangeAllPOCs();
        _finalizeExchange();
        _provideLPTokens();
    }

    function _createUpgradeProposalAndVote(address newImplementation)
        internal
        returns (uint256 proposalId, bytes memory callData)
    {
        callData = abi.encodeWithSelector(DAO.setPendingUpgradeFromVoting.selector, newImplementation);
        vm.warp(block.timestamp + 1 days);

        vm.prank(admin);
        proposalId = voting.createProposal(address(dao), callData);

        vm.prank(user1);
        voting.vote(proposalId, true);
        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);
    }

    function _executeUpgradeProposal(uint256 proposalId, bytes memory callData) internal {
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
    }

    function _approveUpgradeByCreatorAndUpgrade(address newImplementation) internal {
        vm.prank(creator);
        dao.setPendingUpgradeFromCreator(newImplementation);
        vm.warp(block.timestamp + Constants.UPGRADE_DELAY);
        vm.prank(admin);
        dao.upgradeToAndCall(newImplementation, "");
    }
}
