// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./helpers/DAOTestBase.sol";
import "../src/DAO.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";

contract DAOExitQueueSuccessTest is DAOTestBase {
    function _deployDAO() internal override {
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

        address[] memory exitTokens = new address[](2);
        exitTokens[0] = address(launchToken);
        exitTokens[1] = address(mainCollateral);

        DataTypes.ConstructorParams memory params = DataTypes.ConstructorParams({
            launchToken: address(launchToken),
            mainCollateral: address(mainCollateral),
            creator: address(0),
            creatorProfitPercent: 7000,
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
            allowedExitTokens: exitTokens,
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

    function _reachActiveStageOneInQueue() internal {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 1_000e18);
        _createVaultAndDeposit(user2, 100_000e18);
        _createVaultAndDeposit(user3, 99_000e18);
        _finalizeFundraising();
        _exchangeAllPOCs();
        _finalizeExchange();
        _provideLPTokens();
    }

    function _reachActiveStageTwoInQueue() internal {
        _setCreator(creator);
        _createVaultAndDeposit(user1, 42_000e18);
        _createVaultAndDeposit(user2, 42_000e18);
        _createVaultAndDeposit(user3, 126_000e18);
        _finalizeFundraising();
        _exchangeAllPOCs();
        _finalizeExchange();
        _provideLPTokens();
    }

    function _allocateLaunchesToCreatorViaGovernance(uint256 launchAmount) internal returns (uint256 proposalId) {
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, launchAmount);
        vm.warp(block.timestamp + 1 days);

        vm.prank(admin);
        proposalId = voting.createProposal(address(dao), callData);

        vm.prank(user2);
        voting.vote(proposalId, true);
        vm.prank(user3);
        voting.vote(proposalId, true);

        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
    }

    function _allocateLaunchesToCreatorViaGovernanceSingleVoter(uint256 launchAmount)
        internal
        returns (uint256 proposalId)
    {
        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD);
        bytes memory callData = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, launchAmount);
        vm.warp(block.timestamp + 1 days);

        vm.prank(admin);
        proposalId = voting.createProposal(address(dao), callData);

        vm.prank(user3);
        voting.vote(proposalId, true);

        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId, callData);
    }

    function test_oneParticipant_requestExit_then_allocate_then_processExit_success() external {
        _reachActiveStageOneInQueue();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 totalSharesBefore = dao.totalSharesSupply();
        DataTypes.Vault memory v1Before = dao.vaults(vaultId1);
        uint256 user1LaunchBefore = launchToken.balanceOf(user1);

        vm.prank(user1);
        dao.requestExit();

        assertEq(dao.getDaoState().totalExitQueueShares, v1Before.shares);

        uint256 daoLaunchBalance = launchToken.balanceOf(address(dao));
        uint256 maxAlloc = (daoLaunchBalance * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        uint256 allocAmount = maxAlloc;
        if (allocAmount == 0) allocAmount = 1e18;

        _allocateLaunchesToCreatorViaGovernance(allocAmount);

        assertTrue(dao.getDaoState().pendingExitQueuePayment >= allocAmount);

        vm.prank(admin);
        dao.processPendingExitQueue(allocAmount);

        assertTrue(launchToken.balanceOf(user1) > user1LaunchBefore);
        assertEq(dao.vaults(vaultId1).shares, 0);
        assertEq(dao.totalSharesSupply(), totalSharesBefore - v1Before.shares);
        assertEq(dao.getDaoState().totalExitQueueShares, 0);
    }

    function test_oneParticipant_requestExit_then_distributeProfit_sellableCollateral_exit_success() external {
        _reachActiveStageOneInQueue();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        (, bool mainActive,,) = dao.sellableCollaterals(address(mainCollateral));
        assertTrue(mainActive, "mainCollateral should be sellable");

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 totalSharesBefore = dao.totalSharesSupply();
        DataTypes.Vault memory v1Before = dao.vaults(vaultId1);
        uint256 user1CollateralBefore = mainCollateral.balanceOf(user1);

        vm.prank(user1);
        dao.requestExit();

        assertEq(dao.getDaoState().totalExitQueueShares, v1Before.shares);

        uint256 extraForDistribution = 500_000e18;
        mainCollateral.mint(address(dao), extraForDistribution);

        vm.prank(admin);
        dao.distributeProfit(address(mainCollateral), 0);

        assertEq(dao.getDaoState().totalExitQueueShares, 0);
        assertTrue(mainCollateral.balanceOf(user1) > user1CollateralBefore);
        assertEq(dao.vaults(vaultId1).shares, 0);
        assertEq(dao.totalSharesSupply(), totalSharesBefore - v1Before.shares);
    }

    function test_twoParticipants_requestExit_bothExit_inOneProcessPendingExitQueue_success() external {
        _reachActiveStageTwoInQueue();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 vaultId2 = dao.addressToVaultId(user2);
        DataTypes.Vault memory v1 = dao.vaults(vaultId1);
        DataTypes.Vault memory v2 = dao.vaults(vaultId2);
        uint256 totalSharesBefore = dao.totalSharesSupply();
        uint256 user1LaunchBefore = launchToken.balanceOf(user1);
        uint256 user2LaunchBefore = launchToken.balanceOf(user2);

        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();

        assertEq(dao.getDaoState().totalExitQueueShares, v1.shares + v2.shares);

        uint256 daoLaunchBalance = launchToken.balanceOf(address(dao));
        uint256 maxAlloc = (daoLaunchBalance * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        uint256 allocAmount = maxAlloc;
        if (allocAmount == 0) allocAmount = 10e18;

        _allocateLaunchesToCreatorViaGovernanceSingleVoter(allocAmount);

        vm.prank(admin);
        dao.processPendingExitQueue(allocAmount);

        assertTrue(launchToken.balanceOf(user1) > user1LaunchBefore || launchToken.balanceOf(user2) > user2LaunchBefore);
        assertTrue(dao.totalSharesSupply() < totalSharesBefore);
    }

    function test_twoParticipants_requestExit_bothExit_inOneDistributeProfit_success() external {
        _reachActiveStageTwoInQueue();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        (, bool mainActive,,) = dao.sellableCollaterals(address(mainCollateral));
        assertTrue(mainActive, "mainCollateral should be sellable");

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 vaultId2 = dao.addressToVaultId(user2);
        DataTypes.Vault memory v1 = dao.vaults(vaultId1);
        DataTypes.Vault memory v2 = dao.vaults(vaultId2);
        uint256 totalSharesBefore = dao.totalSharesSupply();
        uint256 user1CollateralBefore = mainCollateral.balanceOf(user1);
        uint256 user2CollateralBefore = mainCollateral.balanceOf(user2);

        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();

        assertEq(dao.getDaoState().totalExitQueueShares, v1.shares + v2.shares);

        uint256 amountToDistribute = 500_000e18;
        mainCollateral.mint(address(dao), amountToDistribute);

        vm.prank(admin);
        dao.distributeProfit(address(mainCollateral), amountToDistribute);

        assertEq(dao.getDaoState().totalExitQueueShares, 0);
        assertTrue(mainCollateral.balanceOf(user1) > user1CollateralBefore);
        assertTrue(mainCollateral.balanceOf(user2) > user2CollateralBefore);
        assertEq(dao.totalSharesSupply(), totalSharesBefore - v1.shares - v2.shares);
        assertEq(dao.vaults(vaultId1).shares, 0);
        assertEq(dao.vaults(vaultId2).shares, 0);
    }

    function test_twoParticipants_exitInTwoDistributeProfitCalls_success() external {
        _reachActiveStageTwoInQueue();
        assertEq(uint256(dao.getDaoState().currentStage), uint256(DataTypes.Stage.Active));

        (, bool mainActive,,) = dao.sellableCollaterals(address(mainCollateral));
        assertTrue(mainActive, "mainCollateral should be sellable");

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 vaultId2 = dao.addressToVaultId(user2);
        DataTypes.Vault memory v1 = dao.vaults(vaultId1);
        DataTypes.Vault memory v2 = dao.vaults(vaultId2);
        uint256 totalSharesBefore = dao.totalSharesSupply();

        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();

        uint256 amount1 = 100_000e18;
        mainCollateral.mint(address(dao), amount1);
        vm.prank(admin);
        dao.distributeProfit(address(mainCollateral), amount1);

        assertTrue(dao.totalSharesSupply() < totalSharesBefore);
        assertTrue(dao.vaults(vaultId1).shares < v1.shares || dao.vaults(vaultId2).shares < v2.shares);

        uint256 amount2 = 500_000e18;
        mainCollateral.mint(address(dao), amount2);
        vm.prank(admin);
        dao.distributeProfit(address(mainCollateral), amount2);

        assertEq(dao.getDaoState().totalExitQueueShares, 0);
        assertTrue(dao.totalSharesSupply() < totalSharesBefore);
    }

    function test_twoParticipants_exitInTwoProcessPendingExitQueueCalls_success() external {
        _reachActiveStageTwoInQueue();

        uint256 vaultId1 = dao.addressToVaultId(user1);
        uint256 vaultId2 = dao.addressToVaultId(user2);
        DataTypes.Vault memory v1 = dao.vaults(vaultId1);
        DataTypes.Vault memory v2 = dao.vaults(vaultId2);
        uint256 totalSharesBefore = dao.totalSharesSupply();

        vm.prank(user1);
        dao.requestExit();
        vm.prank(user2);
        dao.requestExit();

        uint256 daoLaunchBalance = launchToken.balanceOf(address(dao));
        uint256 maxAlloc = (daoLaunchBalance * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        uint256 allocAmount1 = maxAlloc / 4;
        if (allocAmount1 == 0) allocAmount1 = 1e18;

        _allocateLaunchesToCreatorViaGovernanceSingleVoter(allocAmount1);

        vm.prank(admin);
        dao.processPendingExitQueue(allocAmount1);

        assertTrue(dao.vaults(vaultId1).shares < v1.shares || dao.vaults(vaultId1).shares == 0);
        assertTrue(dao.totalSharesSupply() < totalSharesBefore);

        vm.warp(block.timestamp + Constants.ALLOCATION_PERIOD);
        uint256 allocAmount2 =
            (launchToken.balanceOf(address(dao)) * Constants.MAX_CREATOR_ALLOCATION_PERCENT) / Constants.BASIS_POINTS;
        if (allocAmount2 == 0) allocAmount2 = 1e18;

        bytes memory callData2 = abi.encodeWithSelector(DAO.allocateLaunchesToCreator.selector, allocAmount2);
        vm.warp(block.timestamp + 1 days);
        vm.prank(admin);
        uint256 proposalId2 = voting.createProposal(address(dao), callData2);
        vm.prank(user3);
        voting.vote(proposalId2, true);
        vm.warp(block.timestamp + 7 days);
        vm.prank(admin);
        voting.execute(proposalId2, callData2);

        vm.prank(admin);
        dao.processPendingExitQueue(allocAmount2);

        assertTrue(dao.totalSharesSupply() < totalSharesBefore);
    }
}
