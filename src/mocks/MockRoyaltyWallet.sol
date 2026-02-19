// SPDX-License-Identifier: MIT
pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "@openzeppelin/contracts/utils/ReentrancyGuard.sol";
import "@openzeppelin/contracts/utils/Address.sol";
import "../interfaces/IDAO.sol";

/// @title MockRoyaltyWallet
/// @notice Same external surface as RoyaltyWallet for testing; no oracle/price deviation check in executeWithPriceCheck
contract MockRoyaltyWallet is ReentrancyGuard {
    using SafeERC20 for IERC20;

    address public immutable adminDAO;
    IDAO public immutable launchPriceDAO;
    address public immutable priceOracle;
    IERC20 public immutable launchToken;

    address public returnWallet;
    address public admin;

    error Unauthorized();
    error InvalidAddress();

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

    function setAdmin(address newAdmin) external onlyAdminDAO {
        require(newAdmin != address(0), InvalidAddress());
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminSet(oldAdmin, newAdmin);
    }

    function setReturnWallet(address newReturnWallet) external onlyAdmin {
        address oldReturnWallet = returnWallet;
        returnWallet = newReturnWallet;
        emit ReturnWalletSet(oldReturnWallet, newReturnWallet);
    }

    function approveReturnWalletLaunch(uint256 amount) external onlyAdmin {
        require(returnWallet != address(0), InvalidAddress());
        launchToken.safeIncreaseAllowance(returnWallet, amount);
        emit ApprovalSet(address(launchToken), returnWallet, amount);
    }

    function approveToken(address token, address spender, uint256 amount) external onlyAdmin {
        require(token != address(0), InvalidAddress());
        require(spender != address(0), InvalidAddress());
        IERC20(token).safeIncreaseAllowance(spender, amount);
        emit ApprovalSet(token, spender, amount);
    }

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

        require(amountIn <= amountInMax, "ExcessiveInput");
        require(amountOut >= minOut, "InsufficientOutput");

        emit ExecutedWithPriceCheck(tokenIn, tokenOut, amountIn, amountOut, target);
    }
}
