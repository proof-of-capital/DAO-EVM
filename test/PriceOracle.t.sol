// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/PriceOracle.sol";
import "../src/interfaces/IPriceOracle.sol";
import "../src/interfaces/IWhitelistOracles.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";
import "../src/mocks/MockChainlinkAggregator.sol";
import "../src/mocks/MockWhitelistOracles.sol";

contract WhitelistOraclesDisallowFeed is IWhitelistOracles {
    address private _primaryFeed;
    uint8 private _decimals;
    bool private _allowFeed;

    function setFeedInfo(address source, uint8 decimals) external {
        _primaryFeed = source;
        _decimals = decimals;
        _allowFeed = true;
    }

    function setAllowFeed(bool allow) external {
        _allowFeed = allow;
    }

    function getFeed(address) external view override returns (address) {
        return _primaryFeed;
    }

    function getFeedInfo(address) external view override returns (address source, uint8 decimals) {
        return (_primaryFeed, _decimals);
    }

    function isAllowedFeed(address, address) external view override returns (bool) {
        return _allowFeed;
    }

    function proposeFeedUpdate(address, address, uint8) external pure override {
        revert();
    }

    function approveFeedUpdate(bytes32) external pure override {
        revert();
    }

    function cancelFeedUpdate(bytes32) external pure override {
        revert();
    }
}

contract PriceOracleTest is Test {
    PriceOracle public oracle;
    address public dao;
    address public creator;
    MockWhitelistOracles public whitelist;
    address public user;

    MockChainlinkAggregator public aggregator18;
    MockChainlinkAggregator public aggregator8;
    MockChainlinkAggregator public aggregator6;
    address public asset1;
    address public asset2;

    function setUp() public {
        dao = makeAddr("dao");
        creator = makeAddr("creator");
        user = makeAddr("user");
        asset1 = makeAddr("asset1");
        asset2 = makeAddr("asset2");
        whitelist = new MockWhitelistOracles();
        aggregator18 = new MockChainlinkAggregator(18, 1e18);
        aggregator8 = new MockChainlinkAggregator(8, 1e8);
        aggregator6 = new MockChainlinkAggregator(6, 1e6);
    }

    function test_Constructor_RevertWhen_DaoZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        vm.expectRevert(PriceOracle.InvalidAddress.selector);
        new PriceOracle(address(0), creator, address(whitelist), configs);
    }

    function test_Constructor_RevertWhen_CreatorZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        vm.expectRevert(PriceOracle.InvalidAddress.selector);
        new PriceOracle(dao, address(0), address(whitelist), configs);
    }

    function test_Constructor_RevertWhen_AssetZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: address(0), source: address(aggregator18), decimals: 18});
        vm.expectRevert(PriceOracle.InvalidAddress.selector);
        new PriceOracle(dao, creator, address(whitelist), configs);
    }

    function test_Constructor_RevertWhen_SourceZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(0), decimals: 18});
        vm.expectRevert(PriceOracle.InvalidAddress.selector);
        new PriceOracle(dao, creator, address(whitelist), configs);
    }

    function test_Constructor_RevertWhen_DuplicateAsset() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](2);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        configs[1] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator8), decimals: 18});
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.TokenAlreadyAdded.selector, asset1));
        new PriceOracle(dao, creator, address(whitelist), configs);
    }

    function test_Constructor_Success_EmptySourceConfigs() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        assertEq(oracle.dao(), dao);
        assertEq(oracle.creator(), creator);
        assertEq(address(oracle.whitelist()), address(0));
    }

    function test_Constructor_Success_WithSourceConfigs() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](2);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        configs[1] = DataTypes.SourceConfig({asset: asset2, source: address(aggregator8), decimals: 18});
        vm.expectEmit(true, true, true, true);
        emit IPriceOracle.SourceAdded(asset1, address(aggregator18), 18);
        vm.expectEmit(true, true, true, true);
        emit IPriceOracle.SourceAdded(asset2, address(aggregator8), 18);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        assertEq(oracle.getSourceOfAsset(asset1), address(aggregator18));
        assertEq(oracle.getSourceOfAsset(asset2), address(aggregator8));
    }

    function test_GetAssetPrice_RevertWhen_NoSource() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.InvalidSource.selector);
        oracle.getAssetPrice(asset1);
    }

    function test_GetAssetPrice_RevertWhen_PriceZero() public {
        MockChainlinkAggregator aggZero = new MockChainlinkAggregator(18, 0);
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggZero), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.InvalidSource.selector);
        oracle.getAssetPrice(asset1);
    }

    function test_GetAssetPrice_RevertWhen_StalePrice() public {
        vm.warp(Constants.ORACLE_MAX_AGE + 2);
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        aggregator18.setUpdatedAt(block.timestamp - Constants.ORACLE_MAX_AGE - 1);
        vm.expectRevert(PriceOracle.InvalidSource.selector);
        oracle.getAssetPrice(asset1);
    }

    function test_GetAssetPrice_Success_SameDecimals() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        aggregator18.setPrice(1234e18);
        assertEq(oracle.getAssetPrice(asset1), 1234e18);
    }

    function test_GetAssetPrice_Success_SourceDecimalsLessThanTarget() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator8), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        aggregator8.setPrice(1e8);
        assertEq(oracle.getAssetPrice(asset1), 1e18);
    }

    function test_GetAssetPrice_Success_SourceDecimalsGreaterThanTarget() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 8});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        aggregator18.setPrice(1e18);
        assertEq(oracle.getAssetPrice(asset1), 1e8);
    }

    function test_GetSourceOfAsset_UnknownAsset() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        assertEq(oracle.getSourceOfAsset(asset1), address(0));
    }

    function test_GetSourceOfAsset_KnownAsset() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        assertEq(oracle.getSourceOfAsset(asset1), address(aggregator18));
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_WhitelistNotSet() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.expectRevert(PriceOracle.WhitelistNotSet.selector);
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_EmptyAssets() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        address[] memory assets = new address[](0);
        vm.expectRevert(PriceOracle.EmptyAssets.selector);
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_AssetZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        address[] memory assets = new address[](1);
        assets[0] = address(0);
        vm.expectRevert(PriceOracle.InvalidAddress.selector);
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_TokenAlreadyAdded() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](1);
        configs[0] = DataTypes.SourceConfig({asset: asset1, source: address(aggregator18), decimals: 18});
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.expectRevert(abi.encodeWithSelector(IPriceOracle.TokenAlreadyAdded.selector, asset1));
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_RevertWhen_AssetNotInWhitelist() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.AssetNotInWhitelist.selector, asset1));
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
    }

    function test_ProposeAddSourcesFromWhitelist_DAOThenCreatorApproves() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;

        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.prank(dao);
        vm.expectEmit(true, true, true, true);
        emit IPriceOracle.SourcesFromWhitelistProposed(updateId, assets, dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit IPriceOracle.SourcesFromWhitelistApproved(updateId, creator);
        vm.expectEmit(true, true, true, true);
        emit IPriceOracle.SourceAdded(asset1, address(aggregator18), 18);
        oracle.approveAddSourcesFromWhitelist(updateId);

        assertEq(oracle.getSourceOfAsset(asset1), address(aggregator18));
        assertEq(oracle.getAssetPrice(asset1), 1e18);
    }

    function test_ProposeAddSourcesFromWhitelist_CreatorThenDAOApproves() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;

        vm.prank(creator);
        oracle.proposeAddSourcesFromWhitelist(assets);

        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.prank(dao);
        oracle.approveAddSourcesFromWhitelist(updateId);

        assertEq(oracle.getSourceOfAsset(asset1), address(aggregator18));
    }

    function test_ProposeAddSourcesFromWhitelist_SameSenderIsBoth_ExecutesImmediately() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;

        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);

        assertEq(oracle.getSourceOfAsset(asset1), address(0));

        address both = makeAddr("both");
        oracle = new PriceOracle(both, both, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        vm.prank(both);
        oracle.proposeAddSourcesFromWhitelist(assets);

        assertEq(oracle.getSourceOfAsset(asset1), address(aggregator18));
    }

    function test_ApproveAddSourcesFromWhitelist_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.approveAddSourcesFromWhitelist(updateId);
    }

    function test_ApproveAddSourcesFromWhitelist_RevertWhen_UpdateNotFound() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.approveAddSourcesFromWhitelist(keccak256("none"));
    }

    function test_ApproveAddSourcesFromWhitelist_RevertWhen_UpdateAlreadyApproved() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectRevert(PriceOracle.UpdateAlreadyApproved.selector);
        vm.prank(dao);
        oracle.approveAddSourcesFromWhitelist(updateId);
    }

    function test_CancelAddSourcesFromWhitelist_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.cancelAddSourcesFromWhitelist(updateId);
    }

    function test_CancelAddSourcesFromWhitelist_RevertWhen_UpdateNotFound() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.cancelAddSourcesFromWhitelist(keccak256("none"));
    }

    function test_CancelAddSourcesFromWhitelist_RevertWhen_UpdateNotReady() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.prank(creator);
        oracle.approveAddSourcesFromWhitelist(updateId);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.cancelAddSourcesFromWhitelist(updateId);
    }

    function test_CancelAddSourcesFromWhitelist_Success() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        whitelist.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectEmit(true, true, false, false);
        emit IPriceOracle.SourcesFromWhitelistCancelled(updateId, dao);
        vm.prank(dao);
        oracle.cancelAddSourcesFromWhitelist(updateId);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(creator);
        oracle.approveAddSourcesFromWhitelist(updateId);
    }

    function test_ProposeWhitelistUpdate_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.proposeWhitelistUpdate(address(0x123));
    }

    function test_ProposeWhitelistUpdate_DAOThenCreatorApproves() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        address newWL = address(whitelist);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(newWL);
        bytes32 updateId = keccak256(abi.encodePacked(newWL, block.timestamp, dao));
        vm.prank(creator);
        oracle.approveWhitelistUpdate(updateId);
        assertEq(address(oracle.whitelist()), newWL);
    }

    function test_ProposeWhitelistUpdate_SameSenderBoth_ExecutesImmediately() public {
        address both = makeAddr("both");
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(both, both, address(0), configs);
        vm.prank(both);
        oracle.proposeWhitelistUpdate(address(whitelist));
        assertEq(address(oracle.whitelist()), address(whitelist));
    }

    function test_ProposeWhitelistUpdate_SetToZero() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(0));
        bytes32 updateId = keccak256(abi.encodePacked(address(0), block.timestamp, dao));
        vm.prank(creator);
        oracle.approveWhitelistUpdate(updateId);
        assertEq(address(oracle.whitelist()), address(0));
    }

    function test_ApproveWhitelistUpdate_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(whitelist));
        bytes32 updateId = keccak256(abi.encodePacked(address(whitelist), block.timestamp, dao));
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.approveWhitelistUpdate(updateId);
    }

    function test_ApproveWhitelistUpdate_RevertWhen_UpdateNotFound() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.approveWhitelistUpdate(keccak256("none"));
    }

    function test_ApproveWhitelistUpdate_RevertWhen_UpdateAlreadyApproved() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(whitelist));
        bytes32 updateId = keccak256(abi.encodePacked(address(whitelist), block.timestamp, dao));
        vm.expectRevert(PriceOracle.UpdateAlreadyApproved.selector);
        vm.prank(dao);
        oracle.approveWhitelistUpdate(updateId);
    }

    function test_CancelWhitelistUpdate_RevertWhen_Unauthorized() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(whitelist));
        bytes32 updateId = keccak256(abi.encodePacked(address(whitelist), block.timestamp, dao));
        vm.expectRevert(PriceOracle.Unauthorized.selector);
        vm.prank(user);
        oracle.cancelWhitelistUpdate(updateId);
    }

    function test_CancelWhitelistUpdate_RevertWhen_UpdateNotFound() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(whitelist), configs);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.cancelWhitelistUpdate(keccak256("none"));
    }

    function test_CancelWhitelistUpdate_RevertWhen_UpdateNotReady() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(whitelist));
        bytes32 updateId = keccak256(abi.encodePacked(address(whitelist), block.timestamp, dao));
        vm.prank(creator);
        oracle.approveWhitelistUpdate(updateId);
        vm.expectRevert(PriceOracle.UpdateNotFound.selector);
        vm.prank(dao);
        oracle.cancelWhitelistUpdate(updateId);
    }

    function test_CancelWhitelistUpdate_Success() public {
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(0), configs);
        vm.prank(dao);
        oracle.proposeWhitelistUpdate(address(whitelist));
        bytes32 updateId = keccak256(abi.encodePacked(address(whitelist), block.timestamp, dao));
        vm.expectEmit(true, true, false, false);
        emit IPriceOracle.WhitelistUpdateCancelled(updateId, dao);
        vm.prank(dao);
        oracle.cancelWhitelistUpdate(updateId);
        assertEq(address(oracle.whitelist()), address(0));
    }

    function test_ExecuteAddSourcesFromWhitelist_RevertWhen_AssetNotInWhitelistAtExecute() public {
        MockWhitelistOracles wl2 = new MockWhitelistOracles();
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(wl2), configs);
        wl2.setFeed(asset1, address(aggregator18), 18);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        wl2.setFeed(asset1, address(0), 0);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.AssetNotInWhitelist.selector, asset1));
        vm.prank(creator);
        oracle.approveAddSourcesFromWhitelist(updateId);
    }

    function test_ExecuteAddSourcesFromWhitelist_RevertWhen_FeedNotAllowedAtExecute() public {
        WhitelistOraclesDisallowFeed wlDisallow = new WhitelistOraclesDisallowFeed();
        wlDisallow.setFeedInfo(address(aggregator18), 18);
        DataTypes.SourceConfig[] memory configs = new DataTypes.SourceConfig[](0);
        oracle = new PriceOracle(dao, creator, address(wlDisallow), configs);
        address[] memory assets = new address[](1);
        assets[0] = asset1;
        vm.prank(dao);
        oracle.proposeAddSourcesFromWhitelist(assets);
        wlDisallow.setAllowFeed(false);
        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));
        vm.expectRevert(abi.encodeWithSelector(PriceOracle.AssetNotInWhitelist.selector, asset1));
        vm.prank(creator);
        oracle.approveAddSourcesFromWhitelist(updateId);
    }
}
