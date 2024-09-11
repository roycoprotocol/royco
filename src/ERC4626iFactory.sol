// SPDX-License-Identifier: MIT
pragma solidity ^0.8.12;

import { Owned } from "lib/solmate/src/auth/Owned.sol";

import { ERC20 } from "lib/solmate/src/tokens/ERC20.sol";
import { ERC4626 } from "lib/solmate/src/tokens/ERC4626.sol";
import { LibString } from "lib/solmate/src/utils/LibString.sol";

import { ERC4626i } from "src/ERC4626i.sol";
import { PointsFactory } from "src/PointsFactory.sol";

/// @title ERC4626iFactory
/// @author CopyPaste, corddry
/// @dev A factory for deploying incentivized vaults, and managing protocol or other fees
contract ERC4626iFactory is Owned(msg.sender) {
    /*//////////////////////////////////////////////////////////////
                              CONSTRUCTOR
    //////////////////////////////////////////////////////////////*/
    constructor(address _protocolFeeRecipient, uint256 _protocolFee, uint256 _minimumFrontendFee, address _pointsFactory) {
        protocolFeeRecipient = _protocolFeeRecipient;
        protocolFee = _protocolFee;
        minimumFrontendFee = _minimumFrontendFee;
        pointsFactory = _pointsFactory;
    }

    /*//////////////////////////////////////////////////////////////
                                STORAGE
    //////////////////////////////////////////////////////////////*/

    uint256 public constant MAX_PROTOCOL_FEE = 30e18;
    uint256 public constant MAX_MIN_REFERRAL_FEE = 30e18;

    address public pointsFactory;

    address public protocolFeeRecipient;

    /// @dev MakerDAO Constant for a 1e18 Scalar
    uint256 constant WAD = 1e18;

    /// @dev The protocolFee for all incentivized vaults
    uint256 public protocolFee;
    /// @dev The default minimumFrontendFee to initialize incentivized vaults with
    uint256 public minimumFrontendFee;

    /// @dev All incentivized vaults deployed by this factory
    address[] public incentivizedVaults;
    mapping(address => bool) public isVault;

    /*//////////////////////////////////////////////////////////////
                               INTERFACE
    //////////////////////////////////////////////////////////////*/
    error ProtocolFeeTooHigh();
    error ReferralFeeTooHigh();
    error VaultNotDeployed();

    event ProtocolFeeUpdated(uint256 newProtocolFee);
    event ReferralFeeUpdated(uint256 newReferralFee);
    event VaultCreated(ERC4626 indexed baseTokenAddress, ERC4626i indexed incentivzedVaultAddress);
    /*//////////////////////////////////////////////////////////////
                             OWNER CONTROLS
    //////////////////////////////////////////////////////////////*/

    /// @param newProtocolFee The new protocol fee to set for a given vault
    function updateProtocolFee(uint256 newProtocolFee) external onlyOwner {
        if (newProtocolFee > MAX_PROTOCOL_FEE) revert ProtocolFeeTooHigh();
        protocolFee = newProtocolFee;
        emit ProtocolFeeUpdated(newProtocolFee);
    }

    /// @param newMinimumReferralFee The new minimum referral fee to set for all incentivized vaults
    function updateMinimumReferralFee(uint256 newMinimumReferralFee) external onlyOwner {
        if (newMinimumReferralFee > MAX_MIN_REFERRAL_FEE) revert ReferralFeeTooHigh();
        minimumFrontendFee = newMinimumReferralFee;
        emit ReferralFeeUpdated(newMinimumReferralFee);
    }

    /*//////////////////////////////////////////////////////////////
                             VAULT CREATION
    //////////////////////////////////////////////////////////////*/

    /// @param vault The ERC4626 Vault to deploy an incentivized vault for
    function createIncentivizedVault(ERC4626 vault, address owner, string memory name, uint256 initialFrontendFee) public returns (ERC4626i incentivizedVault) {
        incentivizedVault = new ERC4626i(owner, name, getNextSymbol(), vault.decimals(), address(vault), initialFrontendFee, pointsFactory);

        incentivizedVaults.push(address(incentivizedVault));
        isVault[address(incentivizedVault)] = true;

        emit VaultCreated(vault, incentivizedVault);
    }

    /// @dev Helper function to get the symbol for a new incentivized vault, ROY-0, ROY-1, etc.
    function getNextSymbol() private view returns (string memory) {
        return string.concat("ROY-", LibString.toString(incentivizedVaults.length));
    }
}
