// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// (c) 2025 https://proofofcapital.org/
// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

/// @title IWhitelistOracles
/// @notice Central registry of price feed addresses per asset; only DAO and Creator can update via 2-of-2
interface IWhitelistOracles {
    error Unauthorized();
    error InvalidAddress();
    error UpdateNotFound();
    error UpdateAlreadyApproved();
    error UpdateNotReady();

    event FeedUpdateProposed(
        bytes32 indexed updateId, address indexed asset, address source, uint8 decimals, address proposer
    );
    event FeedUpdateApproved(bytes32 indexed updateId, address indexed approver);
    event FeedUpdateCancelled(bytes32 indexed updateId, address indexed cancelledBy);
    event FeedSet(address indexed asset, address indexed source, uint8 decimals);

    /// @notice Get price feed address for an asset
    /// @param asset Asset token address
    /// @return source Aggregator (IAggregatorV3) address
    function getFeed(address asset) external view returns (address source);

    /// @notice Get price feed address and decimals for an asset (primary feed)
    /// @param asset Asset token address
    /// @return source Aggregator address
    /// @return decimals Decimals for price normalization
    function getFeedInfo(address asset) external view returns (address source, uint8 decimals);

    /// @notice Check if aggregator is allowed for the asset
    /// @param asset Asset token address
    /// @param aggregator Aggregator address to check
    /// @return allowed True if this aggregator is in the allowed set for the asset
    function isAllowedFeed(address asset, address aggregator) external view returns (bool allowed);

    /// @notice Propose adding a feed to the allowed set for an asset
    /// @param asset Asset address
    /// @param source Source address (IAggregatorV3)
    /// @param decimals Decimals for normalization
    function proposeFeedUpdate(address asset, address source, uint8 decimals) external;

    /// @notice Approve pending feed update
    /// @param updateId Update ID
    function approveFeedUpdate(bytes32 updateId) external;

    /// @notice Cancel pending feed update
    /// @param updateId Update ID
    function cancelFeedUpdate(bytes32 updateId) external;
}
