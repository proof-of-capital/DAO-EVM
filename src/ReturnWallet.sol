// SPDX-License-Identifier: UNLICENSED
// All rights reserved.

// This source code is provided for reference purposes only.
// You may not copy, reproduce, distribute, modify, deploy, or otherwise use this code in whole or in part without explicit written permission from the author.

// (c) 2025 https://proofofcapital.org/

// https://github.com/proof-of-capital/DAO-EVM

pragma solidity 0.8.34;

import "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import "@openzeppelin/contracts/token/ERC20/utils/SafeERC20.sol";
import "./interfaces/IReturnWallet.sol";
import "./interfaces/IERC20Burnable.sol";
import "./interfaces/IPriceOracle.sol";
import "./interfaces/IDAO.sol";
import "./interfaces/IProofOfCapital.sol";
import "./interfaces/IUniswapV2Router02.sol";
import "./interfaces/ISwapRouter.sol";
import "./libraries/DataTypes.sol";
import "./libraries/Constants.sol";
import "./libraries/internal/SwapLibrary.sol";

/// @title ReturnWallet
/// @notice Unified contract for returning launch tokens, exchanging collateral for launch, and exchanging tokens for launch
contract ReturnWallet is IReturnWallet {
    using SafeERC20 for IERC20;

    IDAO public immutable dao;
    address public admin;
    IERC20 public immutable launchToken;
    address public priceOracle;

    mapping(address => bool) public trustedRouters;
    mapping(address => bool) public blacklistedRoyalty;

    modifier onlyDAO() {
        require(msg.sender == address(dao), Unauthorized());
        _;
    }

    modifier onlyAdmin() {
        require(msg.sender == admin, Unauthorized());
        _;
    }

    constructor(address _dao, address _launchToken, address _admin, address _priceOracle) {
        require(_dao != address(0), InvalidAddress());
        require(_launchToken != address(0), InvalidAddress());
        require(_admin != address(0), InvalidAddress());
        dao = IDAO(_dao);
        launchToken = IERC20(_launchToken);
        admin = _admin;
        priceOracle = _priceOracle;
    }

    /// @inheritdoc IReturnWallet
    function returnLaunches(uint256 amount) external {
        require(amount > 0, InvalidAddress());
        (uint256 distributed, uint256 activePocCount) = _returnLaunches(amount);
        emit LaunchesReturned(distributed, activePocCount);
    }

    function setRoyaltyBlacklisted(address royalty, bool value) external onlyDAO {
        require(royalty != address(0), InvalidAddress());
        blacklistedRoyalty[royalty] = value;
        emit RoyaltyBlacklistSet(royalty, value);
    }

    /// @notice Pull launch tokens from a royalty contract and return them to POC in shares
    /// @param royalty Royalty contract address (must have approved this contract; must not be blacklisted)
    /// @param amount Amount of launch tokens to pull and return
    function pullLaunchFromRoyaltyAndReturn(address royalty, uint256 amount) external onlyAdmin {
        require(royalty != address(0), InvalidAddress());
        require(amount > 0, InvalidAddress());
        require(!blacklistedRoyalty[royalty], RoyaltyBlacklisted());
        launchToken.safeTransferFrom(royalty, address(this), amount);
        (uint256 distributed, uint256 activePocCount) = _returnLaunches(amount);
        emit LaunchesReturned(distributed, activePocCount);
        emit LaunchPulledFromRoyalty(royalty, amount);
    }

    /// @notice Burn launch tokens held by a blacklisted royalty contract (anyone may call)
    /// @param royalty Blacklisted royalty contract address
    /// @param amount Amount of launch tokens to pull and burn
    function burnBlacklistedRoyaltyLaunch(address royalty, uint256 amount) external {
        require(royalty != address(0), InvalidAddress());
        require(amount > 0, InvalidAddress());
        require(blacklistedRoyalty[royalty], RoyaltyNotBlacklisted());
        launchToken.safeTransferFrom(royalty, address(this), amount);
        IERC20Burnable(address(launchToken)).burn(amount);
        emit RoyaltyLaunchBurned(royalty, amount, msg.sender);
    }

    function _returnLaunches(uint256 amount) internal returns (uint256 distributed, uint256 activePocCount) {
        uint256 pocCount = dao.getPOCContractsCount();
        require(pocCount > 0, InvalidAddress());

        uint256 totalActiveSharePercent = 0;
        activePocCount = 0;

        for (uint256 i = 0; i < pocCount; ++i) {
            DataTypes.POCInfo memory poc = dao.getPOCContract(i);
            if (poc.active) {
                totalActiveSharePercent += poc.sharePercent;
                ++activePocCount;
            }
        }

        require(activePocCount > 0, InvalidAddress());

        distributed = 0;

        for (uint256 i = 0; i < pocCount; ++i) {
            DataTypes.POCInfo memory poc = dao.getPOCContract(i);

            if (!poc.active) {
                continue;
            }

            uint256 pocAmount;
            bool isLastActive = true;
            for (uint256 j = i + 1; j < pocCount; ++j) {
                DataTypes.POCInfo memory nextPoc = dao.getPOCContract(j);
                if (nextPoc.active) {
                    isLastActive = false;
                    break;
                }
            }

            if (isLastActive) {
                pocAmount = amount - distributed;
            } else {
                pocAmount = (amount * poc.sharePercent) / totalActiveSharePercent;
            }

            if (pocAmount == 0) {
                continue;
            }

            launchToken.safeIncreaseAllowance(poc.pocContract, pocAmount);
            IProofOfCapital(poc.pocContract).sellLaunchTokensReturnWallet(pocAmount);

            distributed += pocAmount;
        }
    }

    /// @inheritdoc IReturnWallet
    function exchangeCollateralForLaunch(
        uint256 pocIndex,
        address collateral,
        uint256 collateralAmount,
        uint256 minLaunchAmount
    ) external {
        require(collateral != address(0), InvalidAddress());
        require(collateralAmount > 0, InvalidAddress());

        uint256 pocCount = dao.getPOCContractsCount();
        require(pocIndex < pocCount, InvalidPOCIndex());

        DataTypes.POCInfo memory poc = dao.getPOCContract(pocIndex);
        require(poc.active, POCNotActive());
        require(poc.collateralToken == collateral, CollateralMismatch());

        IERC20(collateral).safeIncreaseAllowance(poc.pocContract, collateralAmount);

        uint256 launchBalanceBefore = launchToken.balanceOf(address(this));
        IProofOfCapital(poc.pocContract).buyLaunchTokens(collateralAmount);
        uint256 launchBalanceAfter = launchToken.balanceOf(address(this));

        uint256 launchReceived = launchBalanceAfter - launchBalanceBefore;
        require(launchReceived >= minLaunchAmount, InsufficientLaunchAmount());

        emit CollateralExchangedForLaunch(pocIndex, collateral, collateralAmount, launchReceived);
    }

    /// @inheritdoc IReturnWallet
    function exchange(
        address tokenIn,
        uint256 amountIn,
        uint256 minLaunchOut,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external onlyAdmin {
        require(tokenIn != address(0), InvalidAddress());
        require(amountIn > 0, InvalidAddress());
        require(router != address(0), InvalidAddress());
        require(trustedRouters[router], RouterNotTrusted());

        (, bool active,,) = dao.sellableCollaterals(tokenIn);
        require(!active, TokenIsCollateral());

        uint256 launchOut = _executeSwapWithPriceCheck(tokenIn, amountIn, minLaunchOut, router, swapType, swapData);

        emit TokenExchangedForLaunch(tokenIn, amountIn, launchOut, router);
    }

    /// @inheritdoc IReturnWallet
    function getExpectedLaunchAmount(
        address tokenIn,
        uint256 amountIn,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) external view returns (uint256) {
        if (swapType == DataTypes.SwapType.UniswapV2ExactTokensForTokens) {
            (address[] memory path,) = abi.decode(swapData, (address[], uint256));
            require(path.length >= 2, InvalidPath());
            require(path[0] == tokenIn && path[path.length - 1] == address(launchToken), InvalidPath());
            return IUniswapV2Router02(router).getAmountsOut(amountIn, path)[path.length - 1];
        }
        return 0;
    }

    function setAdmin(address newAdmin) external onlyDAO {
        require(newAdmin != address(0), InvalidAddress());
        address oldAdmin = admin;
        admin = newAdmin;
        emit AdminSet(oldAdmin, newAdmin);
    }

    function addTrustedRouter(address router) external onlyDAO {
        require(router != address(0), InvalidAddress());
        require(!trustedRouters[router], InvalidAddress());
        trustedRouters[router] = true;
        emit RouterAdded(router);
    }

    function removeTrustedRouter(address router) external onlyDAO {
        require(trustedRouters[router], InvalidAddress());
        trustedRouters[router] = false;
        emit RouterRemoved(router);
    }

    function _executeSwap(
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData,
        address tokenIn,
        address tokenOut,
        uint256 amountIn,
        uint256 amountOutMin
    ) internal returns (uint256 amountOut) {
        return SwapLibrary.executeSwap(router, swapType, swapData, tokenIn, tokenOut, amountIn, amountOutMin);
    }

    function _getLaunchPriceFromDAO() internal view returns (uint256) {
        uint256 pocCount = dao.getPOCContractsCount();
        require(pocCount > 0, InvalidAddress());

        uint256 totalWeightedPrice = 0;
        uint256 totalSharePercent = 0;

        for (uint256 i = 0; i < pocCount; ++i) {
            DataTypes.POCInfo memory poc = dao.getPOCContract(i);

            if (!poc.active) {
                continue;
            }

            uint256 launchPriceInCollateral = IProofOfCapital(poc.pocContract).currentPrice();

            if (launchPriceInCollateral == 0) {
                continue;
            }

            uint256 collateralPriceUSD = 0;
            if (priceOracle != address(0)) {
                try IPriceOracle(priceOracle).getAssetPrice(poc.collateralToken) returns (uint256 price) {
                    collateralPriceUSD = price;
                } catch {}
            }

            if (collateralPriceUSD == 0) {
                continue;
            }

            uint256 launchPriceUSD =
                (launchPriceInCollateral * collateralPriceUSD) / Constants.PRICE_DECIMALS_MULTIPLIER;

            if (launchPriceUSD == 0) {
                continue;
            }

            totalWeightedPrice += (launchPriceUSD * poc.sharePercent);
            totalSharePercent += poc.sharePercent;
        }

        require(totalSharePercent > 0, InvalidAddress());
        return totalWeightedPrice / totalSharePercent;
    }

    function _calculateDeviation(uint256 expected, uint256 actual) internal pure returns (uint256) {
        if (expected == 0) return Constants.BASIS_POINTS;
        if (actual >= expected) {
            return 0;
        } else {
            return ((expected - actual) * Constants.BASIS_POINTS) / expected;
        }
    }

    function _executeSwapWithPriceCheck(
        address tokenIn,
        uint256 amountIn,
        uint256 minLaunchOut,
        address router,
        DataTypes.SwapType swapType,
        bytes calldata swapData
    ) internal returns (uint256) {
        if (priceOracle == address(0)) {
            return _executeSwap(router, swapType, swapData, tokenIn, address(launchToken), amountIn, minLaunchOut);
        }

        uint256 tokenInPrice = IPriceOracle(priceOracle).getAssetPrice(tokenIn);
        uint256 launchPrice = _getLaunchPriceFromDAO();

        uint256 expectedLaunchOut = (amountIn * tokenInPrice) / launchPrice;

        uint256 balanceBefore = launchToken.balanceOf(address(this));
        SwapLibrary.executeSwap(router, swapType, swapData, tokenIn, address(launchToken), amountIn, minLaunchOut);
        uint256 balanceAfter = launchToken.balanceOf(address(this));
        uint256 actualLaunchOut = balanceAfter - balanceBefore;

        uint256 deviation = _calculateDeviation(expectedLaunchOut, actualLaunchOut);
        require(deviation <= Constants.PRICE_DEVIATION_MAX, InvalidPath());

        return actualLaunchOut;
    }
}
