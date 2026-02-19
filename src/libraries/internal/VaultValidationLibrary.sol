// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "../DataTypes.sol";

/// @title VaultValidationLibrary
/// @notice Internal library for vault validation functions
/// @dev This library contains only internal functions to avoid dependencies between external libraries
library VaultValidationLibrary {
    error NoVaultFound();
    error VaultDoesNotExist();

    /// @notice Validate that vault exists (vaultId > 0 && vaultId < nextVaultId)
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to validate
    function validateVaultExists(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId) internal view {
        require(vaultId > 0 && vaultId < vaultStorage.nextVaultId, NoVaultFound());
    }

    /// @notice Validate that vault exists and has shares (vaultId > 0 && vaultId < nextVaultId && shares > 0)
    /// @param vaultStorage Vault storage structure
    /// @param vaultId Vault ID to validate
    function validateVaultWithShares(DataTypes.VaultStorage storage vaultStorage, uint256 vaultId) internal view {
        require(
            vaultId > 0 && vaultId < vaultStorage.nextVaultId && vaultStorage.vaults[vaultId].shares > 0,
            VaultDoesNotExist()
        );
    }
}
