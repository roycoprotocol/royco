/// SPDX-License-Identifier: MIT

pragma solidity ^0.8.19;

interface IERC4626 {
    /// @return assetTokenAddress The address of the asset token
    function asset() external view returns (address assetTokenAddress);

    /// @return totalManagedAssets The amount of eth controlled by the vault
    function totalAssets() external view returns (uint256 totalManagedAssets);

    /// @param assets The amount of assets to convert to shares
    /// @return shares The value of the given assets in shares
    function convertToShares(uint256 assets) external view returns (uint256 shares);

    /// @param shares The amount of shares to convert to assets
    /// @return assets The value of the given shares in assets
    function convertToAssets(uint256 shares) external view returns (uint256 assets);

    /// @param reciever The address in question of who would be depositing, doesn't matter in this case
    /// @return maxAssets The maximum amount of assets that can be deposited
    function maxDeposit(address reciever) external view returns (uint256 maxAssets);

    /// @param assets The amount of assets that would be deposited
    /// @return shares The amount of shares that would be minted, *under ideal conditions* only
    function previewDeposit(uint256 assets) external view returns (uint256 shares);

    /// @param assets The amount of WETH which should be deposited
    /// @param receiver The address user whom should recieve the mevEth out
    /// @return shares The amount of shares minted
    function deposit(uint256 assets, address receiver) external returns (uint256 shares);

    /// @param reciever The address in question of who would be minting, doesn't matter in this case
    /// @return maxShares The maximum amount of shares that can be minted
    function maxMint(address reciever) external view returns (uint256 maxShares);

    /// @param shares The amount of shares that would be minted
    /// @return assets The amount of assets that would be required, *under ideal conditions* only
    function previewMint(uint256 shares) external view returns (uint256 assets);

    /// @param shares The amount of shares that should be minted
    /// @param receiver The address user whom should recieve the mevEth out
    /// @return assets The amount of assets deposited
    function mint(uint256 shares, address receiver) external returns (uint256 assets);

    /// @param owner The address in question of who would be withdrawing
    /// @return maxAssets The maximum amount of assets that can be withdrawn
    function maxWithdraw(address owner) external view returns (uint256 maxAssets);

    /// @param assets The amount of assets that would be withdrawn
    /// @return shares The amount of shares that would be burned, *under ideal conditions* only
    function previewWithdraw(uint256 assets) external view returns (uint256 shares);

    /// @param assets The amount of assets that should be withdrawn
    /// @param receiver The address user whom should recieve the mevEth out
    /// @param owner The address of the owner of the mevEth
    /// @return shares The amount of shares burned
    function withdraw(uint256 assets, address receiver, address owner) external returns (uint256 shares);

    /// @param owner The address in question of who would be redeeming their shares
    /// @return maxShares The maximum amount of shares they could redeem
    function maxRedeem(address owner) external view returns (uint256 maxShares);

    /// @param shares The amount of shares that would be burned
    /// @return assets The amount of assets that would be withdrawn, *under ideal conditions* only
    function previewRedeem(uint256 shares) external view returns (uint256 assets);

    /// @param shares The amount of shares that should be burned
    /// @param receiver The address user whom should recieve the wETH out
    /// @param owner The address of the owner of the mevEth
    /// @return assets The amount of assets withdrawn
    function redeem(uint256 shares, address receiver, address owner) external returns (uint256 assets);

    /**
     * @dev Emitted when a deposit is made, either through mint or deposit
     */
    event Deposit(address indexed caller, address indexed owner, uint256 assets, uint256 shares);

    /**
     * @dev Emitted when a withdrawal is made, either through redeem or withdraw
     */
    event Withdraw(
        address indexed caller, address indexed receiver, address indexed owner, uint256 assets, uint256 shares
    );
}
