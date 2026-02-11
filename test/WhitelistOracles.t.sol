// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "forge-std/Test.sol";
import "../src/WhitelistOracles.sol";
import "../src/interfaces/IWhitelistOracles.sol";
import "../src/mocks/MockChainlinkAggregator.sol";

contract WhitelistOraclesTest is Test {
    WhitelistOracles public whitelist;
    address public dao;
    address public creator;
    address public user;
    address public asset1;
    address public asset2;
    address public source1;
    address public source2;

    function setUp() public {
        dao = makeAddr("dao");
        creator = makeAddr("creator");
        user = makeAddr("user");
        asset1 = makeAddr("asset1");
        asset2 = makeAddr("asset2");
        source1 = address(new MockChainlinkAggregator(18, 1e18));
        source2 = address(new MockChainlinkAggregator(8, 1e8));
        whitelist = new WhitelistOracles(dao, creator);
    }

    function test_Constructor_RevertWhen_DaoZero() public {
        vm.expectRevert(IWhitelistOracles.InvalidAddress.selector);
        new WhitelistOracles(address(0), creator);
    }

    function test_Constructor_RevertWhen_CreatorZero() public {
        vm.expectRevert(IWhitelistOracles.InvalidAddress.selector);
        new WhitelistOracles(dao, address(0));
    }

    function test_Constructor_Success() public {
        assertEq(whitelist.dao(), dao);
        assertEq(whitelist.creator(), creator);
    }

    function test_GetFeed_NoFeed() public view {
        assertEq(whitelist.getFeed(asset1), address(0));
    }

    function test_GetFeedInfo_NoFeed() public view {
        (address source, uint8 decimals) = whitelist.getFeedInfo(asset1);
        assertEq(source, address(0));
        assertEq(decimals, 0);
    }

    function test_IsAllowedFeed_NotAllowed() public view {
        assertFalse(whitelist.isAllowedFeed(asset1, source1));
    }

    function test_GetFeed_GetFeedInfo_IsAllowedFeed_AfterExecute() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId);

        assertEq(whitelist.getFeed(asset1), source1);
        (address source, uint8 decimals) = whitelist.getFeedInfo(asset1);
        assertEq(source, source1);
        assertEq(decimals, 18);
        assertTrue(whitelist.isAllowedFeed(asset1, source1));
    }

    function test_TwoAllowedFeeds_PrimaryStaysFirst() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId1 = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId1);

        vm.prank(creator);
        whitelist.proposeFeedUpdate(asset1, source2, 8);
        bytes32 updateId2 = keccak256(abi.encodePacked(asset1, source2, uint8(8), block.timestamp));
        vm.prank(dao);
        whitelist.approveFeedUpdate(updateId2);

        assertEq(whitelist.getFeed(asset1), source1);
        (address source, uint8 decimals) = whitelist.getFeedInfo(asset1);
        assertEq(source, source1);
        assertEq(decimals, 18);
        assertTrue(whitelist.isAllowedFeed(asset1, source1));
        assertTrue(whitelist.isAllowedFeed(asset1, source2));
    }

    function test_IsAllowedFeed_RandomAddrFalse() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId);
        assertFalse(whitelist.isAllowedFeed(asset1, makeAddr("random")));
    }

    function test_ProposeFeedUpdate_RevertWhen_Unauthorized() public {
        vm.expectRevert(IWhitelistOracles.Unauthorized.selector);
        vm.prank(user);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
    }

    function test_ProposeFeedUpdate_RevertWhen_AssetZero() public {
        vm.expectRevert(IWhitelistOracles.InvalidAddress.selector);
        vm.prank(dao);
        whitelist.proposeFeedUpdate(address(0), source1, 18);
    }

    function test_ProposeFeedUpdate_RevertWhen_SourceZero() public {
        vm.expectRevert(IWhitelistOracles.InvalidAddress.selector);
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, address(0), 18);
    }

    function test_ProposeFeedUpdate_DAOThenCreatorApproves() public {
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(dao);
        vm.expectEmit(true, true, true, true);
        emit IWhitelistOracles.FeedUpdateProposed(updateId, asset1, source1, 18, dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);

        vm.prank(creator);
        vm.expectEmit(true, true, false, false);
        emit IWhitelistOracles.FeedUpdateApproved(updateId, creator);
        vm.expectEmit(true, true, true, true);
        emit IWhitelistOracles.FeedSet(asset1, source1, 18);
        whitelist.approveFeedUpdate(updateId);

        assertEq(whitelist.getFeed(asset1), source1);
        assertTrue(whitelist.isAllowedFeed(asset1, source1));
    }

    function test_ProposeFeedUpdate_CreatorThenDAOApproves() public {
        vm.prank(creator);
        whitelist.proposeFeedUpdate(asset1, source1, 18);

        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(dao);
        whitelist.approveFeedUpdate(updateId);

        assertEq(whitelist.getFeed(asset1), source1);
    }

    function test_ProposeFeedUpdate_SameSenderBoth_ExecutesImmediately() public {
        address both = makeAddr("both");
        WhitelistOracles wl = new WhitelistOracles(both, both);
        vm.prank(both);
        wl.proposeFeedUpdate(asset1, source1, 18);
        assertEq(wl.getFeed(asset1), source1);
        assertTrue(wl.isAllowedFeed(asset1, source1));
    }

    function test_ApproveFeedUpdate_RevertWhen_Unauthorized() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.expectRevert(IWhitelistOracles.Unauthorized.selector);
        vm.prank(user);
        whitelist.approveFeedUpdate(updateId);
    }

    function test_ApproveFeedUpdate_RevertWhen_UpdateNotFound() public {
        vm.expectRevert(IWhitelistOracles.UpdateNotFound.selector);
        vm.prank(dao);
        whitelist.approveFeedUpdate(keccak256("none"));
    }

    function test_ApproveFeedUpdate_RevertWhen_UpdateAlreadyApproved() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.expectRevert(IWhitelistOracles.UpdateAlreadyApproved.selector);
        vm.prank(dao);
        whitelist.approveFeedUpdate(updateId);
    }

    function test_ApproveFeedUpdate_SecondApprovalExecutes() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId);
        assertEq(whitelist.getFeed(asset1), source1);
        vm.expectRevert(IWhitelistOracles.UpdateNotFound.selector);
        vm.prank(dao);
        whitelist.approveFeedUpdate(updateId);
    }

    function test_CancelFeedUpdate_RevertWhen_Unauthorized() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.expectRevert(IWhitelistOracles.Unauthorized.selector);
        vm.prank(user);
        whitelist.cancelFeedUpdate(updateId);
    }

    function test_CancelFeedUpdate_RevertWhen_UpdateNotFound() public {
        vm.expectRevert(IWhitelistOracles.UpdateNotFound.selector);
        vm.prank(dao);
        whitelist.cancelFeedUpdate(keccak256("none"));
    }

    function test_CancelFeedUpdate_Success() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.expectEmit(true, true, false, false);
        emit IWhitelistOracles.FeedUpdateCancelled(updateId, dao);
        vm.prank(dao);
        whitelist.cancelFeedUpdate(updateId);
        assertEq(whitelist.getFeed(asset1), address(0));
        vm.expectRevert(IWhitelistOracles.UpdateNotFound.selector);
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId);
    }

    function test_CancelFeedUpdate_AfterExecute_UpdateNotFound() public {
        vm.prank(dao);
        whitelist.proposeFeedUpdate(asset1, source1, 18);
        bytes32 updateId = keccak256(abi.encodePacked(asset1, source1, uint8(18), block.timestamp));
        vm.prank(creator);
        whitelist.approveFeedUpdate(updateId);
        vm.expectRevert(IWhitelistOracles.UpdateNotFound.selector);
        vm.prank(dao);
        whitelist.cancelFeedUpdate(updateId);
    }
}
