// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./interfaces/IPriceOracle.sol";
import "./interfaces/IAggregatorV3.sol";
import "./interfaces/IDAO.sol";
import "./utils/Constants.sol";

/// @title PriceOracle
/// @notice Contract to get asset prices, manage price sources
/// - Use of Chainlink Aggregators as source of price
/// - Owned by DAO and Creator (multisig for adding new sources)
contract PriceOracle is IPriceOracle {
    struct PendingSourceUpdate {
        bool daoApproved;
        bool creatorApproved;
        address asset;
        address source;
        uint8 decimals;
        uint256 timestamp;
    }

    address public immutable dao;
    address public immutable creator;

    mapping(address => IAggregatorV3) private assetSources;
    mapping(address => uint8) private assetDecimals;
    mapping(bytes32 => PendingSourceUpdate) private pendingUpdates;

    error Unauthorized();
    error InvalidAddress();
    error InvalidSource();
    error UpdateNotFound();
    error UpdateAlreadyApproved();
    error UpdateNotReady();

    modifier onlyDAO() {
        require(msg.sender == address(dao) || msg.sender == dao, Unauthorized());
        _;
    }

    modifier onlyCreator() {
        require(msg.sender == creator, Unauthorized());
        _;
    }

    modifier onlyDAOOrCreator() {
        require(msg.sender == address(dao) || msg.sender == dao || msg.sender == creator, Unauthorized());
        _;
    }

    constructor(address _dao, address _creator) {
        require(_dao != address(0), InvalidAddress());
        require(_creator != address(0), InvalidAddress());
        dao = _dao;
        creator = _creator;
    }

    /// @inheritdoc IPriceOracle
    function getAssetPrice(address asset) external view returns (uint256) {
        IAggregatorV3 source = assetSources[asset];
        require(address(source) != address(0), InvalidSource());

        (, int256 price,, uint256 updatedAt,) = source.latestRoundData();
        require(price > 0, InvalidSource());
        require(block.timestamp - updatedAt <= Constants.ORACLE_MAX_AGE, InvalidSource());

        uint8 sourceDecimals = source.decimals();
        uint8 targetDecimals = assetDecimals[asset];

        if (sourceDecimals < targetDecimals) {
            return uint256(price) * (10 ** (targetDecimals - sourceDecimals));
        } else if (sourceDecimals > targetDecimals) {
            return uint256(price) / (10 ** (sourceDecimals - targetDecimals));
        }
        return uint256(price);
    }

    /// @inheritdoc IPriceOracle
    function proposeSourceUpdate(address asset, address source, uint8 decimals) external onlyDAOOrCreator {
        require(asset != address(0), InvalidAddress());
        require(source != address(0), InvalidAddress());
        require(assetSources[asset] == IAggregatorV3(address(0)), TokenAlreadyAdded(asset));

        bytes32 updateId = keccak256(abi.encodePacked(asset, source, decimals, block.timestamp));

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        pendingUpdates[updateId] = PendingSourceUpdate({
            daoApproved: isDAO,
            creatorApproved: isCreator,
            asset: asset,
            source: source,
            decimals: decimals,
            timestamp: block.timestamp
        });

        emit SourceUpdateProposed(updateId, asset, source, decimals, msg.sender);

        if (isDAO && isCreator) {
            _executeSourceUpdate(updateId);
        } else if (isDAO) {
            emit SourceUpdateApproved(updateId, msg.sender);
        } else if (isCreator) {
            emit SourceUpdateApproved(updateId, msg.sender);
        }
    }

    /// @inheritdoc IPriceOracle
    function approveSourceUpdate(bytes32 updateId) external onlyDAOOrCreator {
        PendingSourceUpdate storage update = pendingUpdates[updateId];
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

        emit SourceUpdateApproved(updateId, msg.sender);

        if (update.daoApproved && update.creatorApproved) {
            _executeSourceUpdate(updateId);
        }
    }

    /// @inheritdoc IPriceOracle
    function cancelSourceUpdate(bytes32 updateId) external onlyDAOOrCreator {
        PendingSourceUpdate storage update = pendingUpdates[updateId];
        require(update.asset != address(0), UpdateNotFound());
        require(!(update.daoApproved && update.creatorApproved), UpdateNotReady());

        delete pendingUpdates[updateId];

        emit SourceUpdateCancelled(updateId, msg.sender);
    }

    /// @inheritdoc IPriceOracle
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(assetSources[asset]);
    }

    function _executeSourceUpdate(bytes32 updateId) internal {
        PendingSourceUpdate memory update = pendingUpdates[updateId];
        require(update.daoApproved && update.creatorApproved, UpdateNotReady());
        require(assetSources[update.asset] == IAggregatorV3(address(0)), TokenAlreadyAdded(update.asset));

        assetSources[update.asset] = IAggregatorV3(update.source);
        assetDecimals[update.asset] = update.decimals;

        delete pendingUpdates[updateId];

        emit SourceAdded(update.asset, update.source, update.decimals);
    }
}
