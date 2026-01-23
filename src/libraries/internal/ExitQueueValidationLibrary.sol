// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity ^0.8.33;

import "../DataTypes.sol";

/// @title ExitQueueValidationLibrary
/// @notice Internal library for exit queue validation functions
/// @dev This library contains only internal functions to avoid dependencies between external libraries
library ExitQueueValidationLibrary {
    /// @notice Check if exit queue is empty (all processed)
    /// @param exitQueueStorage Exit queue storage structure
    /// @return True if no pending exits
    function isExitQueueEmpty(DataTypes.ExitQueueStorage storage exitQueueStorage) internal view returns (bool) {
        return exitQueueStorage.nextExitQueueIndex >= exitQueueStorage.exitQueue.length;
    }
}
