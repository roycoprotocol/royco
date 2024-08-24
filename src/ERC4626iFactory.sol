// SPDX-License-Identifier: MIT
pragma solidity ^0.8.0;

import {Owned} from "lib/solmate/src/auth/Owned.sol";

import {ERC20} from "lib/solmate/src/tokens/ERC20.sol";
import {ERC4626} from "lib/solmate/src/tokens/ERC4626.sol";

import {ERC4626i} from "src/ERC4626i.sol";

/// @title ERC4626iFactory
/// @author CopyPaste, corddry
/// @dev A factory for deploying incentivized vaults, and managing protocol or other fees
contract ERC4626iFactory is Owned(msg.sender) {

    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(uint256 startingProtocolFee, uint256 startingReferralFee) {
      defaultProtocolFee = startingProtocolFee;
      defaultReferralFee = startingReferralFee;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    /// @dev MakerDAO Constant for a 1e18 Scalar
    uint256 constant WAD = 1e18;

    /// @dev The default protocolFee to initialize incentivized vaults with
    uint256 public defaultProtocolFee;
    /// @dev The default referralFee to initialize incentivized vaults with
    uint256 public defaultReferralFee;

    /// @dev A mapping to track newly created incentivized vaults, for any given token 
    mapping(ERC4626 vault => ERC4626i incentivizedVault) public incentivizedVaults;

     /*//////////////////////////////////////////////////////////////
                               INTERFACE
    //////////////////////////////////////////////////////////////*/
    error ProtocolFeeTooHigh();
    error ReferralFeeTooHigh();
    error VaultAlreadyDeployed();
    error VaultNotDeployed();

    event VaultCreated(ERC4626 indexed baseTokenAddress, ERC4626i indexed incentivzedVaultAddress);
    
    /*//////////////////////////////////////////////////////////////
                             OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @param vault The ERC4626 Vault to deploy an incentivized vault for
    /// @param newProtocolFee The new protocol fee to set for a given vault
    function updateProtocolFee(ERC4626 vault, uint256 newProtocolFee) external onlyOwner {
        ERC4626i incentivizedVault = incentivizedVaults[vault];
        
        if (address(incentivizedVault) == address(0)) {
          revert VaultNotDeployed();
        }

        incentivizedVault.setProtocolFee(newProtocolFee);
    }

    function updateReferralFee(ERC4626 vault, uint256 newFee) external onlyOwner {
        ERC4626i incentivizedVault = incentivizedVaults[vault];
        
        if (address(incentivizedVault) == address(0)) {
          revert VaultNotDeployed();
        }
        
        incentivizedVault.setReferralFee(newFee);
    }

    /*//////////////////////////////////////////////////////////////
                             VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /// @param vault The ERC4626 Vault to deploy an incentivized vault for
    /// @param newProtocolFee The protocol fee for the incentives within the vault
    /// @param newReferralFee The fee to taken for referalls from incentivies on the vault
    function createIncentivizedVault(ERC4626 vault, uint256 newProtocolFee, uint256 newReferralFee) public {
        if (address(incentivizedVaults[vault]) != address(0)) {
          revert VaultAlreadyDeployed();
        }

        ERC4626i incentivizedVault = new ERC4626i(vault, newProtocolFee, newReferralFee);
        incentivizedVaults[vault] = incentivizedVault;
    }
}
