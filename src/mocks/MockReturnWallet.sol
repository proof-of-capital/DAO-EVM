// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IReturnWallet.sol";
import "../interfaces/IDAO.sol";
import "../libraries/DataTypes.sol";

/// @title MockReturnWallet
/// @notice IReturnWallet stub for testing; actions no-op, getExpectedLaunchAmount configurable
contract MockReturnWallet is IReturnWallet {
    IDAO public immutable dao;
    address public admin;
    mapping(address => bool) public trustedRouters;
    mapping(address => bool) public blacklistedRoyalty;
    uint256 private _expectedLaunchAmount;

    constructor(address _dao, address _admin) {
        dao = IDAO(_dao);
        admin = _admin;
    }

    function setExpectedLaunchAmount(uint256 amount) external {
        _expectedLaunchAmount = amount;
    }

    function setTrustedRouter(address router, bool trusted) external {
        trustedRouters[router] = trusted;
    }

    function returnLaunches(uint256) external override {}

    function exchangeCollateralForLaunch(uint256, address, uint256, uint256) external override {}

    function exchange(address, uint256, uint256, address, DataTypes.SwapType, bytes calldata) external override {}

    function getExpectedLaunchAmount(address, uint256, address, DataTypes.SwapType, bytes calldata)
        external
        view
        override
        returns (uint256)
    {
        return _expectedLaunchAmount;
    }

    function setRoyaltyBlacklisted(address royalty, bool value) external override {
        blacklistedRoyalty[royalty] = value;
    }

    function pullLaunchFromRoyaltyAndReturn(address, uint256) external override {}

    function burnBlacklistedRoyaltyLaunch(address, uint256) external override {}
}
