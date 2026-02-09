// SPDX-License-Identifier: MIT
pragma solidity ^0.8.33;

import "../interfaces/IDAO.sol";
import "../interfaces/IMultisig.sol";
import "../libraries/DataTypes.sol";

/// @title MockDAO
/// @notice Configurable IDAO stub for testing
contract MockDAO is IDAO {
    DataTypes.CoreConfig private _coreConfig;
    DataTypes.DAOState private _daoState;
    uint256 private _launchPrice;
    uint256 private _pocCount;
    uint256 private _waitingForLPStartedAt;
    uint256 private _nextVaultId;
    uint256 private _totalSharesSupply;
    uint256 private _totalCollectedMainCollateral;

    mapping(uint256 => DataTypes.POCInfo) private _pocContracts;
    mapping(address => uint256) private _addressToVaultId;
    mapping(uint256 => DataTypes.Vault) private _vaults;
    mapping(address => bool) private _availableRouterByAdmin;
    mapping(address => uint256) private _collateralPrice;
    mapping(address => DataTypes.CollateralInfo) private _sellableCollaterals;
    mapping(address => uint256) private _pocIndex;

    constructor() {
        _daoState.currentStage = DataTypes.Stage.Active;
        _launchPrice = 1e18;
    }

    function setCoreConfig(DataTypes.CoreConfig memory c) external {
        _coreConfig = c;
    }

    function setDaoState(DataTypes.DAOState memory s) external {
        _daoState = s;
    }

    function setLaunchPrice(uint256 p) external {
        _launchPrice = p;
    }

    function setPocCount(uint256 n) external {
        _pocCount = n;
    }

    function setPOCContract(uint256 index, DataTypes.POCInfo memory info) external {
        _pocContracts[index] = info;
    }

    function setAddressToVaultId(address account, uint256 vaultId) external {
        _addressToVaultId[account] = vaultId;
    }

    function setVault(uint256 vaultId, DataTypes.Vault memory v) external {
        _vaults[vaultId] = v;
    }

    function setAvailableRouterByAdmin(address router, bool allowed) external {
        _availableRouterByAdmin[router] = allowed;
    }

    function setCollateralPrice(address collateral, uint256 price) external {
        _collateralPrice[collateral] = price;
    }

    function setWaitingForLPStartedAt(uint256 t) external {
        _waitingForLPStartedAt = t;
    }

    function setSellableCollateral(
        address token,
        address tokenAddr,
        bool active,
        uint256 ratioBps,
        uint256 depegThresholdMinPrice
    ) external {
        _sellableCollaterals[token] = DataTypes.CollateralInfo({
            token: tokenAddr, active: active, ratioBps: ratioBps, depegThresholdMinPrice: depegThresholdMinPrice
        });
    }

    function setPocIndex(address poc, uint256 index) external {
        _pocIndex[poc] = index;
    }

    function coreConfig() external view override returns (DataTypes.CoreConfig memory) {
        return _coreConfig;
    }

    function getDaoState() external view override returns (DataTypes.DAOState memory) {
        return _daoState;
    }

    function getLaunchPriceFromDAO() external view override returns (uint256) {
        return _launchPrice;
    }

    function waitingForLPStartedAt() external view override returns (uint256) {
        return _waitingForLPStartedAt;
    }

    function totalSharesSupply() external view override returns (uint256) {
        return _totalSharesSupply;
    }

    function nextVaultId() external view override returns (uint256) {
        return _nextVaultId;
    }

    function totalCollectedMainCollateral() external view override returns (uint256) {
        return _totalCollectedMainCollateral;
    }

    function getPOCContractsCount() external view override returns (uint256) {
        return _pocCount;
    }

    function getPOCContract(uint256 index) external view override returns (DataTypes.POCInfo memory) {
        return _pocContracts[index];
    }

    function vaults(uint256 vaultId) external view override returns (DataTypes.Vault memory) {
        return _vaults[vaultId];
    }

    function addressToVaultId(address account) external view override returns (uint256) {
        return _addressToVaultId[account];
    }

    function vaultMainCollateralDeposit(uint256) external pure override returns (uint256) {
        return 0;
    }

    function availableRouterByAdmin(address router) external view override returns (bool) {
        return _availableRouterByAdmin[router];
    }

    function getCollateralPrice(address collateral) external view override returns (uint256) {
        uint256 p = _collateralPrice[collateral];
        return p == 0 ? 1e18 : p;
    }

    function sellableCollaterals(address token) external view override returns (address, bool, uint256, uint256) {
        DataTypes.CollateralInfo storage c = _sellableCollaterals[token];
        return (c.token, c.active, c.ratioBps, c.depegThresholdMinPrice);
    }

    function pocIndex(address poc) external view override returns (uint256) {
        return _pocIndex[poc];
    }

    function rewardTokens(uint256) external pure override returns (address) {
        return address(0);
    }

    function rewardTokenInfo(address) external pure override returns (DataTypes.RewardTokenInfo memory) {
        return DataTypes.RewardTokenInfo({token: address(0), active: false});
    }

    function accountedBalance(address) external pure override returns (uint256) {
        return 0;
    }

    function rewardPerShareStored(address) external pure override returns (uint256) {
        return 0;
    }

    function vaultRewardIndex(uint256, address) external pure override returns (uint256) {
        return 0;
    }

    function earnedRewards(uint256, address) external pure override returns (uint256) {
        return 0;
    }

    function v2LPTokens(uint256) external pure override returns (address) {
        return address(0);
    }

    function isV2LPToken(address) external pure override returns (bool) {
        return false;
    }

    function lastLPDistribution(address) external pure override returns (uint256) {
        return 0;
    }

    function lpTokenAddedAt(address) external pure override returns (uint256) {
        return 0;
    }

    function depegInfoV2(address) external pure override returns (DataTypes.DepegInfo memory) {
        return DataTypes.DepegInfo({
            timestamp: 0,
            amountToken0: 0,
            amountToken1: 0,
            token0: address(0),
            token1: address(0),
            returnedToken0: 0,
            returnedToken1: 0,
            lpUnused: false
        });
    }

    function depegInfoV3(uint256) external pure override returns (DataTypes.DepegInfo memory) {
        return DataTypes.DepegInfo({
            timestamp: 0,
            amountToken0: 0,
            amountToken1: 0,
            token0: address(0),
            token1: address(0),
            returnedToken0: 0,
            returnedToken1: 0,
            lpUnused: false
        });
    }

    function v3LPPositions(uint256) external pure override returns (DataTypes.V3LPPositionInfo memory) {
        return
            DataTypes.V3LPPositionInfo({
                positionManager: address(0), tokenId: 0, token0: address(0), token1: address(0)
            });
    }

    function v3TokenIdToIndex(uint256) external pure override returns (uint256) {
        return 0;
    }

    function v3PositionManager() external pure override returns (address) {
        return address(0);
    }

    function v3LastLPDistribution(uint256) external pure override returns (uint256) {
        return 0;
    }

    function v3LPTokenAddedAt(uint256) external pure override returns (uint256) {
        return 0;
    }

    function isBoardMember(address) external pure override returns (bool) {
        return false;
    }

    function isVaultInExitQueue(uint256) external pure override returns (bool) {
        return false;
    }

    function getDAOProfitShare() external pure override returns (uint256) {
        return 0;
    }

    function getVetoThreshold() external pure override returns (uint256) {
        return 0;
    }

    function getClosingThreshold() external pure override returns (uint256) {
        return 0;
    }

    function createVault(address, address, address) external pure override returns (uint256) {
        revert("MockDAO: not implemented");
    }

    function depositFundraising(uint256, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function depositLaunches(uint256, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function updatePrimaryAddress(uint256, address) external pure override {
        revert("MockDAO: not implemented");
    }

    function updateBackupAddress(uint256, address) external pure override {
        revert("MockDAO: not implemented");
    }

    function updateEmergencyAddress(uint256, address) external pure override {
        revert("MockDAO: not implemented");
    }

    function setDelegate(address, address) external pure override {
        revert("MockDAO: not implemented");
    }

    function claimReward(address[] calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function requestExit() external pure override {
        revert("MockDAO: not implemented");
    }

    function cancelExit() external pure override {
        revert("MockDAO: not implemented");
    }

    function allocateLaunchesToCreator(uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function upgradeOwnerShare(uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function returnLaunchesToPOC(uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function sell(address, uint256, uint256, address, DataTypes.SwapType, bytes calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function addPOCContract(address, address, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function removePOCContract(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function withdrawFundraising() external pure override {
        revert("MockDAO: not implemented");
    }

    function extendFundraising() external pure override {
        revert("MockDAO: not implemented");
    }

    function cancelFundraising() external pure override {
        revert("MockDAO: not implemented");
    }

    function finalizeFundraisingCollection() external pure override {
        revert("MockDAO: not implemented");
    }

    function exchangeForPOC(uint256, uint256, address, DataTypes.SwapType, bytes calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function finalizeExchange() external pure override {
        revert("MockDAO: not implemented");
    }

    function dissolveIfLocksEnded() external pure override {
        revert("MockDAO: not implemented");
    }

    function claimDissolution(address[] calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function claimCreatorDissolution() external pure override {
        revert("MockDAO: not implemented");
    }

    function declareDepeg(address, uint256, DataTypes.LPTokenType) external pure override {
        revert("MockDAO: not implemented");
    }

    function addLiquidityBackV2(address, address, uint256, uint256, uint256, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function addLiquidityBackV3(uint256, uint256, uint256, uint256, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function rebalance(
        address,
        address,
        DataTypes.SwapType,
        bytes calldata,
        DataTypes.RebalanceDirection,
        uint256,
        uint256
    ) external pure override {
        revert("MockDAO: not implemented");
    }

    function finalizeDepegAfterGracePeriod(address, uint256, DataTypes.LPTokenType) external pure override {
        revert("MockDAO: not implemented");
    }

    function executeProposal(address, bytes calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function provideLPTokens(
        address[] calldata,
        uint256[] calldata,
        uint256[] calldata,
        DataTypes.PricePathV2Params[] calldata,
        DataTypes.PricePathV3Params[] calldata
    ) external pure override {
        revert("MockDAO: not implemented");
    }

    function setVotingContract(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function setAdmin(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function setIsVetoToCreator(bool) external pure override {
        revert("MockDAO: not implemented");
    }

    function setRoyaltyRecipient(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function setPriceOracle(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function setPendingUpgradeFromVoting(address) external pure override {
        revert("MockDAO: not implemented");
    }

    function pushMultisigExecution(uint256, IMultisig.ProposalCall[] calldata) external pure override {
        revert("MockDAO: not implemented");
    }

    function distributeProfit(address, uint256) external pure override {
        revert("MockDAO: not implemented");
    }

    function distributeLPProfit(address, DataTypes.LPTokenType) external pure override {
        revert("MockDAO: not implemented");
    }
}
