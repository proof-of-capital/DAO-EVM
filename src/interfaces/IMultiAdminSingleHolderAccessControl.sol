// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 fundmera.com

// https://github.com/merafund
pragma solidity ^0.8.29;

/// @title IMultiAdminSingleHolderAccessControl Interface
/// @notice Minimal interface for access control with grantRole function
interface IMultiAdminSingleHolderAccessControl {
    /// @notice Grant a role to an account
    /// @param role Role identifier
    /// @param account Account address to grant role to
    function grantRole(bytes32 role, address account) external;
}

