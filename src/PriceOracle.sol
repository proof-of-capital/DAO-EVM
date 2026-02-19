// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "./interfaces/IPriceOracle.sol";
import "./interfaces/IWhitelistOracles.sol";
import "./interfaces/IAggregatorV3.sol";
import "./libraries/Constants.sol";
import "./libraries/DataTypes.sol";

/// @title PriceOracle
/// @notice Contract to get asset prices; sources are set at deploy or added from WhitelistOracles by DAO + Creator (2-of-2)
contract PriceOracle is IPriceOracle {
    address public immutable dao;
    address public immutable creator;
    IWhitelistOracles public whitelist;

    mapping(address => IAggregatorV3) private assetSources;
    mapping(address => uint8) private assetDecimals;
    mapping(bytes32 => DataTypes.PendingWhitelistAdd) private pendingWhitelistAdds;
    mapping(bytes32 => DataTypes.PendingWhitelistUpdate) private pendingWhitelistUpdates;

    error Unauthorized();
    error InvalidAddress();
    error InvalidSource();
    error UpdateNotFound();
    error UpdateAlreadyApproved();
    error UpdateNotReady();
    error WhitelistNotSet();
    error AssetNotInWhitelist(address asset);
    error EmptyAssets();

    modifier onlyDAOOrCreator() {
        require(msg.sender == address(dao) || msg.sender == dao || msg.sender == creator, Unauthorized());
        _;
    }

    /// @param _dao DAO contract or admin address
    /// @param _creator Creator (e.g. multisig) address
    /// @param _whitelist WhitelistOracles address (can be address(0), set later via 2-of-2 if needed)
    /// @param sourceConfigs Initial sources for bootstrap
    constructor(address _dao, address _creator, address _whitelist, DataTypes.SourceConfig[] memory sourceConfigs) {
        require(_dao != address(0), InvalidAddress());
        require(_creator != address(0), InvalidAddress());

        dao = _dao;
        creator = _creator;
        whitelist = IWhitelistOracles(_whitelist);

        _initializeSources(sourceConfigs);
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

    /// @notice Propose adding price sources from whitelist for one or more assets (DAO or Creator)
    /// @param assets Array of asset addresses to add from whitelist
    function proposeAddSourcesFromWhitelist(address[] calldata assets) external onlyDAOOrCreator {
        require(address(whitelist) != address(0), WhitelistNotSet());
        require(assets.length > 0, EmptyAssets());

        for (uint256 i = 0; i < assets.length; i++) {
            require(assets[i] != address(0), InvalidAddress());
            require(address(assetSources[assets[i]]) == address(0), TokenAlreadyAdded(assets[i]));
            (address feed,) = whitelist.getFeedInfo(assets[i]);
            require(feed != address(0), AssetNotInWhitelist(assets[i]));
        }

        bytes32 updateId = keccak256(abi.encode(assets, block.timestamp));

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        DataTypes.PendingWhitelistAdd storage pending = pendingWhitelistAdds[updateId];
        pending.assets = new address[](assets.length);
        for (uint256 i = 0; i < assets.length; i++) {
            pending.assets[i] = assets[i];
        }
        pending.daoApproved = isDAO;
        pending.creatorApproved = isCreator;

        emit SourcesFromWhitelistProposed(updateId, assets, msg.sender);

        if (isDAO && isCreator) {
            _executeAddSourcesFromWhitelist(updateId);
        } else {
            emit SourcesFromWhitelistApproved(updateId, msg.sender);
        }
    }

    /// @notice Approve pending add-sources-from-whitelist (second of DAO/Creator)
    /// @param updateId Update ID from proposeAddSourcesFromWhitelist
    function approveAddSourcesFromWhitelist(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingWhitelistAdd storage pending = pendingWhitelistAdds[updateId];
        require(pending.assets.length > 0, UpdateNotFound());

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        if (isDAO) {
            require(!pending.daoApproved, UpdateAlreadyApproved());
            pending.daoApproved = true;
        }

        if (isCreator) {
            require(!pending.creatorApproved, UpdateAlreadyApproved());
            pending.creatorApproved = true;
        }

        emit SourcesFromWhitelistApproved(updateId, msg.sender);

        if (pending.daoApproved && pending.creatorApproved) {
            _executeAddSourcesFromWhitelist(updateId);
        }
    }

    /// @notice Cancel pending add-sources-from-whitelist
    /// @param updateId Update ID
    function cancelAddSourcesFromWhitelist(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingWhitelistAdd storage pending = pendingWhitelistAdds[updateId];
        require(pending.assets.length > 0, UpdateNotFound());
        require(!(pending.daoApproved && pending.creatorApproved), UpdateNotReady());

        delete pendingWhitelistAdds[updateId];

        emit SourcesFromWhitelistCancelled(updateId, msg.sender);
    }

    /// @notice Propose setting or changing whitelist address (DAO or Creator)
    /// @param _whitelist New WhitelistOracles address (use address(0) to clear)
    function proposeWhitelistUpdate(address _whitelist) external onlyDAOOrCreator {
        bytes32 updateId = keccak256(abi.encodePacked(_whitelist, block.timestamp, msg.sender));

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        DataTypes.PendingWhitelistUpdate storage pending = pendingWhitelistUpdates[updateId];
        pending.newWhitelist = _whitelist;
        pending.daoApproved = isDAO;
        pending.creatorApproved = isCreator;
        pending.timestamp = block.timestamp;

        emit WhitelistUpdateProposed(updateId, _whitelist, msg.sender);

        if (isDAO && isCreator) {
            _executeWhitelistUpdate(updateId);
        } else {
            emit WhitelistUpdateApproved(updateId, msg.sender);
        }
    }

    /// @notice Approve pending whitelist update
    /// @param updateId Update ID from proposeWhitelistUpdate
    function approveWhitelistUpdate(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingWhitelistUpdate storage pending = pendingWhitelistUpdates[updateId];
        require(pending.timestamp != 0, UpdateNotFound());

        bool isDAO = msg.sender == address(dao) || msg.sender == dao;
        bool isCreator = msg.sender == creator;

        if (isDAO) {
            require(!pending.daoApproved, UpdateAlreadyApproved());
            pending.daoApproved = true;
        }

        if (isCreator) {
            require(!pending.creatorApproved, UpdateAlreadyApproved());
            pending.creatorApproved = true;
        }

        emit WhitelistUpdateApproved(updateId, msg.sender);

        if (pending.daoApproved && pending.creatorApproved) {
            _executeWhitelistUpdate(updateId);
        }
    }

    /// @notice Cancel pending whitelist update
    function cancelWhitelistUpdate(bytes32 updateId) external onlyDAOOrCreator {
        DataTypes.PendingWhitelistUpdate storage pending = pendingWhitelistUpdates[updateId];
        require(pending.timestamp != 0, UpdateNotFound());
        require(!(pending.daoApproved && pending.creatorApproved), UpdateNotReady());

        delete pendingWhitelistUpdates[updateId];

        emit WhitelistUpdateCancelled(updateId, msg.sender);
    }

    /// @inheritdoc IPriceOracle
    function getSourceOfAsset(address asset) external view returns (address) {
        return address(assetSources[asset]);
    }

    function _initializeSources(DataTypes.SourceConfig[] memory sourceConfigs) internal {
        for (uint256 i = 0; i < sourceConfigs.length; i++) {
            require(sourceConfigs[i].asset != address(0), InvalidAddress());
            require(sourceConfigs[i].source != address(0), InvalidAddress());
            require(
                address(assetSources[sourceConfigs[i].asset]) == address(0), TokenAlreadyAdded(sourceConfigs[i].asset)
            );

            assetSources[sourceConfigs[i].asset] = IAggregatorV3(sourceConfigs[i].source);
            assetDecimals[sourceConfigs[i].asset] = sourceConfigs[i].decimals;

            emit SourceAdded(sourceConfigs[i].asset, sourceConfigs[i].source, sourceConfigs[i].decimals);
        }
    }

    function _executeAddSourcesFromWhitelist(bytes32 updateId) internal {
        DataTypes.PendingWhitelistAdd storage pending = pendingWhitelistAdds[updateId];
        require(pending.daoApproved && pending.creatorApproved, UpdateNotReady());

        address[] memory assets = pending.assets;
        for (uint256 i = 0; i < assets.length; i++) {
            (address source, uint8 decimals) = whitelist.getFeedInfo(assets[i]);
            require(source != address(0), AssetNotInWhitelist(assets[i]));
            require(whitelist.isAllowedFeed(assets[i], source), AssetNotInWhitelist(assets[i]));
            require(address(assetSources[assets[i]]) == address(0), TokenAlreadyAdded(assets[i]));

            assetSources[assets[i]] = IAggregatorV3(source);
            assetDecimals[assets[i]] = decimals;

            emit SourceAdded(assets[i], source, decimals);
        }

        delete pendingWhitelistAdds[updateId];
    }

    function _executeWhitelistUpdate(bytes32 updateId) internal {
        DataTypes.PendingWhitelistUpdate memory pending = pendingWhitelistUpdates[updateId];
        require(pending.timestamp != 0, UpdateNotFound());
        require(pending.daoApproved && pending.creatorApproved, UpdateNotReady());

        whitelist = IWhitelistOracles(pending.newWhitelist);

        delete pendingWhitelistUpdates[updateId];
    }
}
