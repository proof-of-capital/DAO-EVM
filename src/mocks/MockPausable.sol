// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IPausable.sol";

/// @title MockPausable
/// @notice IPausable mock for testing; stores paused flag
contract MockPausable is IPausable {
    bool public paused;

    function pause() external override {
        paused = true;
    }

    function unpause() external override {
        paused = false;
    }
}
