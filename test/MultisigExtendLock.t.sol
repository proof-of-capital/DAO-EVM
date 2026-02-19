// SPDX-License-Identifier: UNLICENSED
// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "forge-std/Test.sol";
import "../src/Multisig.sol";
import "../src/interfaces/IMultisig.sol";
import "../src/interfaces/IDAO.sol";
import "../src/interfaces/IProofOfCapital.sol";
import "../src/libraries/DataTypes.sol";
import "../src/libraries/Constants.sol";
import "../src/mocks/MockDAO.sol";
import "../src/mocks/MockProofOfCapital.sol";

contract MultisigExtendLockTest is Test {
    Multisig public multisig;
    MockDAO public mockDao;
    MockProofOfCapital public poc;

    address public admin;
    address[] public primaryAddrs;
    address[] public backupAddrs;
    address[] public emergencyAddrs;
    address public marketMaker;

    function setUp() public {
        admin = makeAddr("admin");
        marketMaker = makeAddr("marketMaker");
        mockDao = new MockDAO();

        primaryAddrs = new address[](8);
        backupAddrs = new address[](8);
        emergencyAddrs = new address[](8);
        for (uint256 i = 0; i < 8; ++i) {
            primaryAddrs[i] = makeAddr(string(abi.encodePacked("primary", i)));
            backupAddrs[i] = makeAddr(string(abi.encodePacked("backup", i)));
            emergencyAddrs[i] = makeAddr(string(abi.encodePacked("emergency", i)));
        }

        address mockCollateral = makeAddr("collateral");
        address mockLaunch = makeAddr("launch");
        poc = new MockProofOfCapital(mockCollateral, mockLaunch);

        IMultisig.LPPoolConfig[] memory lpPoolConfigs = new IMultisig.LPPoolConfig[](1);
        lpPoolConfigs[0] = IMultisig.LPPoolConfig({
            params: IMultisig.LPPoolParams({
                fee: 3000, tickLower: -887220, tickUpper: 887220, amount0Min: 1, amount1Min: 1
            }),
            shareBps: 10_000
        });

        IMultisig.CollateralConstructorParams[] memory collateralParams = new IMultisig.CollateralConstructorParams[](0);

        multisig = new Multisig(
            primaryAddrs,
            backupAddrs,
            emergencyAddrs,
            admin,
            address(mockDao),
            1e18,
            makeAddr("router"),
            makeAddr("positionManager"),
            lpPoolConfigs,
            collateralParams,
            marketMaker
        );

        vm.store(address(multisig), bytes32(uint256(16)), bytes32((uint256(1) << 160) | uint256(uint160(marketMaker))));
    }

    function test_submitTransaction_extendLock_hasVotingTypeExtendLock() public {
        IMultisig.ProposalCall[] memory calls = new IMultisig.ProposalCall[](1);
        calls[0] = IMultisig.ProposalCall({
            targetContract: address(poc),
            callData: abi.encodeWithSelector(IProofOfCapital.extendLock.selector, block.timestamp + 180 days),
            value: 0
        });

        vm.prank(primaryAddrs[0]);
        uint256 txId = multisig.submitTransaction(calls);

        IMultisig.Transaction memory txn = multisig.getTransaction(txId);
        assertEq(uint256(txn.votingType), uint256(IMultisig.VotingType.EXTEND_LOCK));
    }

    function test_executeTransaction_extendLock_whenVeto_reverts() public {
        DataTypes.CoreConfig memory config;
        config.isVetoToCreator = true;
        mockDao.setCoreConfig(config);

        IMultisig.ProposalCall[] memory calls = new IMultisig.ProposalCall[](1);
        calls[0] = IMultisig.ProposalCall({
            targetContract: address(poc),
            callData: abi.encodeWithSelector(IProofOfCapital.extendLock.selector, block.timestamp + 180 days),
            value: 0
        });

        vm.prank(primaryAddrs[0]);
        uint256 txId = multisig.submitTransaction(calls);

        _voteAllFor(primaryAddrs, txId);
        vm.warp(block.timestamp + Constants.MULTISIG_VOTING_PERIOD + 1);

        vm.prank(primaryAddrs[0]);
        vm.expectRevert(IMultisig.ExtendLockNotAllowedWhenVeto.selector);
        multisig.executeTransaction(txId, calls);
    }

    function test_executeTransaction_extendLock_whenNoVeto_succeeds() public {
        DataTypes.CoreConfig memory config;
        config.isVetoToCreator = false;
        vm.prank(admin);
        mockDao.setCoreConfig(config);

        IMultisig.ProposalCall[] memory calls = new IMultisig.ProposalCall[](1);
        calls[0] = IMultisig.ProposalCall({
            targetContract: address(poc),
            callData: abi.encodeWithSelector(IProofOfCapital.extendLock.selector, block.timestamp + 180 days),
            value: 0
        });

        vm.prank(primaryAddrs[0]);
        uint256 txId = multisig.submitTransaction(calls);

        _voteAllFor(primaryAddrs, txId);
        vm.warp(block.timestamp + Constants.MULTISIG_VOTING_PERIOD + 1);

        vm.prank(primaryAddrs[0]);
        multisig.executeTransaction(txId, calls);

        IMultisig.Transaction memory txn = multisig.getTransaction(txId);
        assertEq(uint256(txn.status), uint256(IMultisig.TransactionStatus.EXECUTED));
    }

    function _voteAllFor(address[] memory owners, uint256 txId) internal {
        for (uint256 i = 0; i < owners.length; ++i) {
            vm.prank(owners[i]);
            multisig.voteTransaction(txId, IMultisig.VoteOption.FOR);
        }
    }
}
