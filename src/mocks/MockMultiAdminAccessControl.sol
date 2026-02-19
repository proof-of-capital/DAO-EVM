// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "../interfaces/IMultiAdminSingleHolderAccessControl.sol";

/// @title MockMultiAdminAccessControl
/// @notice IMultiAdminSingleHolderAccessControl mock for testing; grantRole stores role->account
contract MockMultiAdminAccessControl is IMultiAdminSingleHolderAccessControl {
    mapping(bytes32 => address) public roleAccount;

    event RoleGranted(bytes32 indexed role, address indexed account);

    function grantRole(bytes32 role, address account) external override {
        roleAccount[role] = account;
        emit RoleGranted(role, account);
    }
}
