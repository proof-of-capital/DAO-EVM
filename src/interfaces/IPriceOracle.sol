// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

/// @title IPriceOracle
/// @notice Interface for Price Oracle contract
interface IPriceOracle {
    error TokenAlreadyAdded(address asset);

    event SourceUpdateProposed(bytes32 indexed updateId, address indexed asset, address source, uint8 decimals, address proposer);
    event SourceUpdateApproved(bytes32 indexed updateId, address indexed approver);
    event SourceUpdateCancelled(bytes32 indexed updateId, address indexed cancelledBy);
    event SourceAdded(address indexed asset, address indexed source, uint8 decimals);

    /// @notice Get asset price from source
    /// @param asset Asset address
    /// @return Price in USD (18 decimals)
    function getAssetPrice(address asset) external view returns (uint256);

    /// @notice Propose source update for an asset
    /// @param asset Asset address
    /// @param source Source address (IAggregatorV3)
    /// @param decimals Decimals for normalization
    function proposeSourceUpdate(address asset, address source, uint8 decimals) external;

    /// @notice Approve pending source update
    /// @param updateId Update ID
    function approveSourceUpdate(bytes32 updateId) external;

    /// @notice Cancel pending source update
    /// @param updateId Update ID
    function cancelSourceUpdate(bytes32 updateId) external;

    /// @notice Get source address for an asset
    /// @param asset Asset address
    /// @return Source address (IAggregatorV3)
    function getSourceOfAsset(address asset) external view returns (address);
}
