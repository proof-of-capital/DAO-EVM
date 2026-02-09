// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "@openzeppelin/contracts/token/ERC721/extensions/ERC721Enumerable.sol";
import "../interfaces/INonfungiblePositionManager.sol";

/// @title MockNonfungiblePositionManager
/// @notice Minimal mock: ERC721 + mint(MintParams) for testing Multisig LP flow
contract MockNonfungiblePositionManager is ERC721Enumerable, INonfungiblePositionManager {
    uint256 private _nextTokenId;

    constructor() ERC721("MockNFT", "MNFT") {}

    function PERMIT_TYPEHASH() external pure override returns (bytes32) {
        return keccak256("Permit(address spender,uint256 tokenId,uint256 nonce,uint256 deadline)");
    }

    function DOMAIN_SEPARATOR() external view override returns (bytes32) {
        return bytes32(0);
    }

    function permit(address, uint256, uint256, uint8, bytes32, bytes32) external payable override {}

    function mint(INonfungiblePositionManager.MintParams calldata params)
        external
        payable
        override
        returns (uint256 tokenId, uint128 liquidity, uint256 amount0, uint256 amount1)
    {
        tokenId = _nextTokenId++;
        _mint(params.recipient, tokenId);
        liquidity = 1;
        amount0 = params.amount0Desired;
        amount1 = params.amount1Desired;
    }

    function positions(uint256)
        external
        pure
        override
        returns (
            uint96,
            address,
            address,
            address,
            uint24,
            int24,
            int24,
            uint128,
            uint256,
            uint256,
            uint128,
            uint128
        )
    {
        revert("MockNFT: not implemented");
    }

    function increaseLiquidity(IncreaseLiquidityParams calldata) external payable override returns (uint128, uint256, uint256) {
        revert("MockNFT: not implemented");
    }

    function decreaseLiquidity(DecreaseLiquidityParams calldata) external payable override returns (uint256, uint256) {
        revert("MockNFT: not implemented");
    }

    function collect(CollectParams calldata) external payable override returns (uint256, uint256) {
        revert("MockNFT: not implemented");
    }

    function burn(uint256) external payable override {
        revert("MockNFT: not implemented");
    }

    function createAndInitializePoolIfNecessary(
        address,
        address,
        uint24,
        uint160
    ) external payable override returns (address) {
        revert("MockNFT: not implemented");
    }

    function unwrapWETH9(uint256, address) external payable override {}

    function refundETH() external payable override {}

    function sweepToken(address, uint256, address) external payable override {}

    function factory() external pure override returns (address) {
        return address(0);
    }

    function WETH9() external pure override returns (address) {
        return address(0);
    }
}
