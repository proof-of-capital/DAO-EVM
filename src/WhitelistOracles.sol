// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "./interfaces/IWhitelistOracles.sol";
import "./libraries/DataTypes.sol";

/// @title WhitelistOracles
/// @notice Central registry of price feed addresses per asset; one contract for all projects
/// @dev Only DAO and Creator can add or replace feeds via 2-of-2 (propose + approve)
contract WhitelistOracles is IWhitelistOracles {
    address public immutable dao;
    address public immutable creator;

    mapping(address => address) private _primaryFeed;
    mapping(address => mapping(address => bool)) private _allowedFeeds;
    mapping(address => mapping(address => uint8)) private _feedDecimals;
    mapping(bytes32 => DataTypes.PendingFeedUpdate) private _pendingUpdates;

    modifier onlyDAOOrCreator() {
        require(msg.sender == address(dao) || msg.sender == dao || msg.sender == creator, Unauthorized());
        _;
    }

    /// @param _dao DAO contract or admin address
    /// @param _creator Creator (e.g. multisig) address
    constructor(address _dao, address _creator) {
        require(_dao != address(0), InvalidAddress());
        require(_creator != address(0), InvalidAddress());
        dao = _dao;
        creator = _creator;
    }

    /// @inheritdoc IWhitelistOracles
    function getFeed(address asset) external view returns (address) {
        return _primaryFeed[asset];
    }

    /// @inheritdoc IWhitelistOracles
    function getFeedInfo(address asset) external view returns (address source, uint8 decimals) {
        source = _primaryFeed[asset];
        decimals = _feedDecimals[asset][source];
    }

    /// @inheritdoc IWhitelistOracles
    function isAllowedFeed(address asset, address aggregator) external view returns (bool) {
        return _allowedFeeds[asset][aggregator];
    }

    /// @inheritdoc IWhitelistOracles
    function proposeFeedUpdate(address asset, address source, uint8 decimals) external onlyDAOOrCreator {
        require(asset != address(0), InvalidAddress());
        require(source != address(0), InvalidAddress());

        bytes32 updateId = keccak256(abi.encodePacked(asset, source, decimals, block.timestamp));

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        _pendingUpdates[updateId] = DataTypes.PendingFeedUpdate({
            daoApproved: isDAO,
            creatorApproved: isCreator,
            asset: asset,
            source: source,
            decimals: decimals,
            timestamp: block.timestamp
        });

        emit FeedUpdateProposed(updateId, asset, source, decimals, msg.sender);

        if (isDAO && isCreator) {
            _executeFeedUpdate(updateId);
        } else if (isDAO) {
            emit FeedUpdateApproved(updateId, msg.sender);
        } else if (isCreator) {
            emit FeedUpdateApproved(updateId, msg.sender);
        }
    }

    /// @inheritdoc IWhitelistOracles
    function approveFeedUpdate(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingFeedUpdate storage update = _pendingUpdates[updateId];
        require(update.asset != address(0), UpdateNotFound());

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        if (isDAO) {
            require(!update.daoApproved, UpdateAlreadyApproved());
            update.daoApproved = true;
        }

        if (isCreator) {
            require(!update.creatorApproved, UpdateAlreadyApproved());
            update.creatorApproved = true;
        }

        emit FeedUpdateApproved(updateId, msg.sender);

        if (update.daoApproved && update.creatorApproved) {
            _executeFeedUpdate(updateId);
        }
    }

    /// @inheritdoc IWhitelistOracles
    function cancelFeedUpdate(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingFeedUpdate storage update = _pendingUpdates[updateId];
        require(update.asset != address(0), UpdateNotFound());
        require(!(update.daoApproved && update.creatorApproved), UpdateNotReady());

        delete _pendingUpdates[updateId];

        emit FeedUpdateCancelled(updateId, msg.sender);
    }

    function _executeFeedUpdate(bytes32 updateId) internal {
        DataTypes.PendingFeedUpdate memory update = _pendingUpdates[updateId];
        require(update.daoApproved && update.creatorApproved, UpdateNotReady());

        _allowedFeeds[update.asset][update.source] = true;
        _feedDecimals[update.asset][update.source] = update.decimals;
        if (_primaryFeed[update.asset] == address(0)) {
            _primaryFeed[update.asset] = update.source;
        }

        delete _pendingUpdates[updateId];

        emit FeedSet(update.asset, update.source, update.decimals);
    }
}
