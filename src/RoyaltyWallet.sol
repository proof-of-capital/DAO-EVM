// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IPriceOracle.sol";
import "./libraries/Constants.sol";

/// @title RoyaltyWallet
/// @notice Holds tokens and launch; admin (set by external adminDAO) can swap via arbitrary target with oracle price-deviation check; approves ReturnWallet for launch pull
contract RoyaltyWallet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable adminDAO;
    IDAO public immutable launchPriceDAO;
    address public immutable priceOracle;
    IERC20 public immutable launchToken;

    address public returnWallet;
    address public admin;

    error Unauthorized();
    error InvalidAddress();
    error PriceDeviationTooHigh();
    error InsufficientOutput();
    error ExcessiveInput();

    event AdminSet(address indexed oldAdmin, address indexed newAdmin);
    event ReturnWalletSet(address indexed oldReturnWallet, address indexed newReturnWallet);
    event ExecutedWithPriceCheck(
        address indexed tokenIn, address indexed tokenOut, uint256 amountIn, uint256 amountOut, address indexed target
    );
    event ApprovalSet(address indexed token, address indexed spender, uint256 amount);

    modifier onlyAdminDAO() {
        require(msg.sender == adminDAO, Unauthorized());
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, Unauthorized());
        _;
    }

    constructor(
        address _adminDAO,
        address _admin,
        address _launchPriceDAO,
        address _priceOracle,
        address _launchToken
    ) {
        require(_adminDAO != address(0), InvalidAddress());
        require(_launchPriceDAO != address(0), InvalidAddress());
        require(_launchToken != address(0), InvalidAddress());
        adminDAO = _adminDAO;
        admin = _admin;
        launchPriceDAO = IDAO(_launchPriceDAO);
        priceOracle = _priceOracle;
        launchToken = IERC20(_launchToken);
    }

    /// @notice Set admin; only the DAO (adminDAO) can change the admin
    /// @param newAdmin New admin address
    function setAdmin(address newAdmin) external onlyAdminDAO {
        require(newAdmin != address(0), InvalidAddress());
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminSet(oldAdmin, newAdmin);
    }

    /// @notice Set ReturnWallet address (only callable by admin)
    /// @param newReturnWallet New ReturnWallet address
    function setReturnWallet(address newReturnWallet) external onlyAdmin {
        address oldReturnWallet = returnWallet;
        returnWallet = newReturnWallet;
        emit ReturnWalletSet(oldReturnWallet, newReturnWallet);
    }

    /// @notice Approve ReturnWallet to spend launch tokens
    /// @param amount Amount to approve
    function approveReturnWalletLaunch(uint256 amount) external onlyAdmin {
        require(returnWallet != address(0), InvalidAddress());
        launchToken.safeIncreaseAllowance(returnWallet, amount);
        emit ApprovalSet(address(launchToken), returnWallet, amount);
    }

    /// @notice Approve a spender for a token (for arbitrary target calls)
    /// @param token Token address
    /// @param spender Spender address
    /// @param amount Amount to approve
    function approveToken(address token, address spender, uint256 amount) external onlyAdmin {
        require(token != address(0), InvalidAddress());
        require(spender != address(0), InvalidAddress());
        IERC20(token).safeIncreaseAllowance(spender, amount);
        emit ApprovalSet(token, spender, amount);
    }

    /// @notice Execute arbitrary call then verify output vs oracle price (deviation <= PRICE_DEVIATION_MAX)
    /// @param tokenIn Input token
    /// @param tokenOut Output token
    /// @param amountInMax Max input to spend
    /// @param minOut Minimum output to receive
    /// @param target Target contract
    /// @param callData Calldata for target
    function executeWithPriceCheck(
        address tokenIn,
        address tokenOut,
        uint256 amountInMax,
        uint256 minOut,
        address target,
        bytes calldata callData
    ) external onlyAdmin nonReentrant returns (uint256 amountIn, uint256 amountOut) {
        require(tokenIn != address(0), InvalidAddress());
        require(tokenOut != address(0), InvalidAddress());
        require(target != address(0), InvalidAddress());
        require(amountInMax > 0, InvalidAddress());

        uint256 balanceInBefore = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOutBefore = IERC20(tokenOut).balanceOf(address(this));

        Address.functionCall(target, callData);

        uint256 balanceInAfter = IERC20(tokenIn).balanceOf(address(this));
        uint256 balanceOutAfter = IERC20(tokenOut).balanceOf(address(this));

        amountIn = balanceInBefore - balanceInAfter;
        amountOut = balanceOutAfter - balanceOutBefore;

        require(amountIn <= amountInMax, ExcessiveInput());
        require(amountOut >= minOut, InsufficientOutput());

        if (priceOracle != address(0)) {
            uint256 priceIn = _getPrice(tokenIn);
            uint256 priceOut = _getPrice(tokenOut);
            require(priceIn > 0 && priceOut > 0, InvalidAddress());
            uint256 expectedOut = (amountIn * priceIn) / priceOut;
            uint256 deviation = _calculateDeviation(expectedOut, amountOut);
            require(deviation <= Constants.PRICE_DEVIATION_MAX, PriceDeviationTooHigh());
        }

        emit ExecutedWithPriceCheck(tokenIn, tokenOut, amountIn, amountOut, target);
    }

    function _getPrice(address token) internal view returns (uint256) {
        if (token == address(launchToken)) {
            return launchPriceDAO.getLaunchPriceFromDAO();
        }
        if (priceOracle == address(0)) {
            return 0;
        }
        try IPriceOracle(priceOracle).getAssetPrice(token) returns (uint256 p) {
            return p;
        } catch {
            return 0;
        }
    }

    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) return 0;
        return ((expected - actual) * Constants.BASIS_POINTS) / expected;
    }
}
