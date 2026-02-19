// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

/// @title IPriceOracle
/// @notice Interface for Price Oracle contract
interface IPriceOracle {
    error TokenAlreadyAdded(address asset);

    event SourceAdded(address indexed asset, address indexed source, uint8 decimals);
    event SourcesFromWhitelistProposed(bytes32 indexed updateId, address[] assets, address proposer);
    event SourcesFromWhitelistApproved(bytes32 indexed updateId, address approver);
    event SourcesFromWhitelistCancelled(bytes32 indexed updateId, address cancelledBy);
    event WhitelistUpdateProposed(bytes32 indexed updateId, address newWhitelist, address proposer);
    event WhitelistUpdateApproved(bytes32 indexed updateId, address approver);
    event WhitelistUpdateCancelled(bytes32 indexed updateId, address cancelledBy);

    /// @notice Get asset price from source
    /// @param asset Asset address
    /// @return Price in USD (18 decimals)
    function getAssetPrice(address asset) external view returns (uint256);

    /// @notice Get source address for an asset
    /// @param asset Asset address
    /// @return Source address (IAggregatorV3)
    function getSourceOfAsset(address asset) external view returns (address);
}
