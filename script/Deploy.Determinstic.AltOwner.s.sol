// SPDX-License-Identifier: UNLICENSED

// Usage: source .env && forge script ./script/Deploy.Deterministic.s.sol --rpc-url=$SEPOLIA_RPC_URL --broadcast --etherscan-api-key=$ETHERSCAN_API_KEY --verify

pragma solidity ^0.8.0;

import "forge-std/Script.sol";

import { WrappedVault } from "../src/WrappedVault.sol";
import { WrappedVaultFactory } from "../src/WrappedVaultFactory.sol";
import { Points } from "../src/Points.sol";
import { PointsFactory } from "../src/PointsFactory.sol";
import { VaultMarketHub } from "../src/VaultMarketHub.sol";
import { RecipeMarketHub } from "../src/RecipeMarketHub.sol";
import { WeirollWallet } from "../src/WeirollWallet.sol";

import { MockERC20 } from "test/mocks/MockERC20.sol";
import { MockERC4626 } from "test/mocks/MockERC4626.sol";

// Deployer
address constant CREATE2_FACTORY_ADDRESS = 0x4e59b44847b379578588920cA78FbF26c0B4956C;

// Deployment Salts
string constant POINTS_FACTORY_SALT = "ROYCO_POINTS_FACTORY_458371a243a7299e99f3fbfb67799eaaf734ccaf";
string constant WRAPPED_VAULT_SALT = "ROYCO_WRAPPED_VAULT_627001f37bde0b6f93a8a618530963e24ea2b9af";
string constant WRAPPED_VAULT_FACTORY_SALT = "ROYCO_WRAPPED_VAULT_FACTORY_5414c04eeefec8db6047b9508f5c07245a5e7c81";
string constant WEIROLL_WALLET_SALT = "ROYCO_WEIROLL_WALLET_458371a243a7299e99f3fbfb67799eaaf734ccaf";
string constant VAULT_MARKET_HUB_SALT = "ROYCO_VAULT_MARKET_HUB_458371a243a7299e99f3fbfb67799eaaf734ccaf";
string constant RECIPE_MARKET_HUB_SALT = "ROYCO_RECIPE_MARKET_HUB_458371a243a7299e99f3fbfb67799eaaf734ccaf";

// Deployment Configuration
address constant ROYCO_OWNER = 0x6462540Cf29B35962eB2a0329F7C514e1DcDD78e;
address constant PROTOCOL_FEE_RECIPIENT = 0x6462540Cf29B35962eB2a0329F7C514e1DcDD78e;
uint256 constant PROTOCOL_FEE = 0;
uint256 constant MINIMUM_FRONTEND_FEE = 0.005e18;

// Expected Deployment Addresses
address constant EXPECTED_POINTS_FACTORY_ADDRESS = 0x86cBEfbA5CEF451F9Ff5Bb76e0DA6Ea845a05201;
address constant EXPECTED_WRAPPED_VAULT_ADDRESS = 0xb0a3960B115E0999F33e8AfD4a11f16e04e2bf33;
address constant EXPECTED_WRAPPED_VAULT_FACTORY_ADDRESS = 0x75E502644284eDf34421f9c355D75DB79e343Bca;
address constant EXPECTED_WEIROLL_WALLET_ADDRESS = 0x40a1c08084671E9A799B73853E82308225309Dc0;
address constant EXPECTED_VAULT_MARKET_HUB_ADDRESS = 0xa97eCc6Bfda40baf2fdd096dD33e88bd8e769280;
address constant EXPECTED_RECIPE_MARKET_HUB_ADDRESS = 0x783251f103555068c1E9D755f69458f39eD937c0;

bytes32 constant WRAPPED_VAULT_FACTORY_IMPL_SLOT = bytes32(uint256(2));

contract DeployDeterministic is Script {
    error Create2DeployerNotDeployed();

    error DeploymentFailed(bytes reason);
    error NotDeployedToExpectedAddress(address expected, address actual);
    error AddressDoesNotContainBytecode(address addr);
    error UnexpectedDeploymentAddress(address expected, address actual);

    error PointsFactoryOwnerIncorrect(address expected, address actual);

    error WrappedVaultFactoryProtocolFeeRecipientIncorrect(address expected, address actual);
    error WrappedVaultFactoryProtocolFeeIncorrect(uint256 expected, uint256 actual);
    error WrappedVaultFactoryMinimumFrontendFeeIncorrect(uint256 expected, uint256 actual);
    error WrappedVaultFactoryOwnerIncorrect(address expected, address actual);
    error WrappedVaultFactoryPointsFactoryIncorrect(address expected, address actual);
    error WrappedVaultFactoryImplementationIncorrect(address expected, address actual);

    error VaultMarketHubOwnerIncorrect(address expected, address actual);

    error RecipeMarketHubWeirollWalletImplementationIncorrect(address expected, address actual);
    error RecipeMarketHubProtocolFeeIncorrect(uint256 expected, uint256 actual);
    error RecipeMarketHubMinimumFrontendFeeIncorrect(uint256 expected, uint256 actual);
    error RecipeMarketHubOwnerIncorrect(address expected, address actual);
    error RecipeMarketHubPointsFactoryIncorrect(address expected, address actual);

    function _generateUint256SaltFromString(string memory _salt) internal pure returns (uint256) {
        return uint256(keccak256(abi.encodePacked(_salt)));
    }

    function _generateDeterminsticAddress(string memory _salt, bytes memory _creationCode) internal pure returns (address) {
        uint256 salt = _generateUint256SaltFromString(_salt);
        bytes32 hash = keccak256(abi.encodePacked(bytes1(0xff), CREATE2_FACTORY_ADDRESS, salt, keccak256(_creationCode)));
        return address(uint160(uint256(hash)));
    }

    function _checkDeployer() internal view {
        if (CREATE2_FACTORY_ADDRESS.code.length == 0) {
            revert Create2DeployerNotDeployed();
        }
    }

    function _deploy(string memory _salt, bytes memory _creationCode) internal returns (address deployedAddress) {
        (bool success, bytes memory data) = CREATE2_FACTORY_ADDRESS.call(abi.encodePacked(_generateUint256SaltFromString(_salt), _creationCode));

        if (!success) {
            revert DeploymentFailed(data);
        }

        assembly ("memory-safe") {
            deployedAddress := shr(0x60, mload(add(data, 0x20)))
        }
    }

    function _deployWithSanityChecks(string memory _salt, bytes memory _creationCode) internal returns (address, bool isAlreadyDeployed) {
        address expectedAddress = _generateDeterminsticAddress(_salt, _creationCode);

        if (address(expectedAddress).code.length != 0) {
            console2.log("contract already deployed at: ", expectedAddress);
            return (expectedAddress, true);
        }

        address addr = _deploy(_salt, _creationCode);

        if (addr != expectedAddress) {
            revert NotDeployedToExpectedAddress(expectedAddress, addr);
        }

        if (address(addr).code.length == 0) {
            revert AddressDoesNotContainBytecode(addr);
        }

        return (addr, false);
    }

    function _verifyPointsFactoryDeployment(PointsFactory _pointsFactory) internal view {
        if (address(_pointsFactory) != EXPECTED_POINTS_FACTORY_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_POINTS_FACTORY_ADDRESS, address(_pointsFactory));
        }

        if (_pointsFactory.owner() != ROYCO_OWNER) revert PointsFactoryOwnerIncorrect(ROYCO_OWNER, _pointsFactory.owner());
    }

    function _verifyWrappedVaultDeployment(WrappedVault _wrappedVault) internal pure {
        if (address(_wrappedVault) != EXPECTED_WRAPPED_VAULT_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_WRAPPED_VAULT_ADDRESS, address(_wrappedVault));
        }
    }

    function _verifyWrappedVaultFactoryDeployment(WrappedVaultFactory _wrappedVaultFactory, PointsFactory _pointsFactory, WrappedVault _impl) internal view {
        if (address(_wrappedVaultFactory) != EXPECTED_WRAPPED_VAULT_FACTORY_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_WRAPPED_VAULT_FACTORY_ADDRESS, address(_wrappedVaultFactory));
        }
        if (_wrappedVaultFactory.protocolFeeRecipient() != PROTOCOL_FEE_RECIPIENT) {
            revert WrappedVaultFactoryProtocolFeeRecipientIncorrect(PROTOCOL_FEE_RECIPIENT, _wrappedVaultFactory.protocolFeeRecipient());
        }
        if (_wrappedVaultFactory.protocolFee() != PROTOCOL_FEE) {
            revert WrappedVaultFactoryProtocolFeeIncorrect(PROTOCOL_FEE, _wrappedVaultFactory.protocolFee());
        }
        if (_wrappedVaultFactory.minimumFrontendFee() != MINIMUM_FRONTEND_FEE) {
            revert WrappedVaultFactoryMinimumFrontendFeeIncorrect(MINIMUM_FRONTEND_FEE, _wrappedVaultFactory.minimumFrontendFee());
        }
        if (_wrappedVaultFactory.owner() != ROYCO_OWNER) {
            revert WrappedVaultFactoryOwnerIncorrect(ROYCO_OWNER, _wrappedVaultFactory.owner());
        }
        if (_wrappedVaultFactory.pointsFactory() != address(_pointsFactory)) {
            revert WrappedVaultFactoryPointsFactoryIncorrect(address(_pointsFactory), _wrappedVaultFactory.pointsFactory());
        }
        address actualImpl = address(uint160(uint256(vm.load(address(_wrappedVaultFactory), WRAPPED_VAULT_FACTORY_IMPL_SLOT))));
        if (actualImpl != address(_impl)) {
            revert WrappedVaultFactoryImplementationIncorrect(address(_impl), actualImpl);
        }
    }

    function _verifyWeirollWalletDeployment(WeirollWallet _weirollWallet) internal pure {
        if (address(_weirollWallet) != EXPECTED_WEIROLL_WALLET_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_WEIROLL_WALLET_ADDRESS, address(_weirollWallet));
        }
    }

    function _verifyVaultMarketHubDeployment(VaultMarketHub _vaultMarketHub) internal view {
        if (address(_vaultMarketHub) != EXPECTED_VAULT_MARKET_HUB_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_VAULT_MARKET_HUB_ADDRESS, address(_vaultMarketHub));
        }
        if (_vaultMarketHub.owner() != ROYCO_OWNER) revert VaultMarketHubOwnerIncorrect(ROYCO_OWNER, _vaultMarketHub.owner());
    }

    function _verifyRecipeMarketHubDeployment(RecipeMarketHub _recipeMarketHub, WeirollWallet _weirollWallet, PointsFactory _pointsFactory) internal view {
        if (address(_recipeMarketHub) != EXPECTED_RECIPE_MARKET_HUB_ADDRESS) {
            revert UnexpectedDeploymentAddress(EXPECTED_RECIPE_MARKET_HUB_ADDRESS, address(_recipeMarketHub));
        }
        if (_recipeMarketHub.WEIROLL_WALLET_IMPLEMENTATION() != address(_weirollWallet)) {
            revert RecipeMarketHubWeirollWalletImplementationIncorrect(address(_weirollWallet), _recipeMarketHub.WEIROLL_WALLET_IMPLEMENTATION());
        }
        if (_recipeMarketHub.protocolFee() != PROTOCOL_FEE) {
            revert RecipeMarketHubProtocolFeeIncorrect(PROTOCOL_FEE, _recipeMarketHub.protocolFee());
        }
        if (_recipeMarketHub.minimumFrontendFee() != MINIMUM_FRONTEND_FEE) {
            revert RecipeMarketHubMinimumFrontendFeeIncorrect(MINIMUM_FRONTEND_FEE, _recipeMarketHub.minimumFrontendFee());
        }
        if (_recipeMarketHub.owner() != ROYCO_OWNER) {
            revert RecipeMarketHubOwnerIncorrect(ROYCO_OWNER, _recipeMarketHub.owner());
        }
        if (_recipeMarketHub.POINTS_FACTORY() != address(_pointsFactory)) {
            revert RecipeMarketHubPointsFactoryIncorrect(address(_pointsFactory), _recipeMarketHub.POINTS_FACTORY());
        }
    }

    function run() external {
        uint256 deployerPrivateKey = vm.envUint("PRIVATE_KEY");
        address deployerAddress = vm.addr(deployerPrivateKey);

        console2.log("Deploying with address: ", deployerAddress);
        console2.log("Deployer Balance: ", address(deployerAddress).balance);

        vm.startBroadcast(deployerPrivateKey);

        _checkDeployer();
        console2.log("Deployer is ready\n");

        // Deploy PointsFactory
        console2.log("Deploying PointsFactory");
        bytes memory pointsFactoryCreationCode = abi.encodePacked(vm.getCode("PointsFactory"), abi.encode(ROYCO_OWNER));
        (address deployedContractAddress, bool isAlreadyDeployed) = _deployWithSanityChecks(POINTS_FACTORY_SALT, pointsFactoryCreationCode);
        PointsFactory pointsFactory = PointsFactory(deployedContractAddress);
        if (!isAlreadyDeployed) {
            console2.log("Verifying PointsFactory deployment");
            _verifyPointsFactoryDeployment(pointsFactory);
        }
        console2.log("PointsFactory deployed at: ", address(pointsFactory), "\n");

        // Deploy WrappedVault
        console2.log("Deploying WrappedVault");
        bytes memory wrappedVaultCreationCode = abi.encodePacked(vm.getCode("WrappedVault"));
        (deployedContractAddress, isAlreadyDeployed) = _deployWithSanityChecks(WRAPPED_VAULT_SALT, wrappedVaultCreationCode);
        WrappedVault wrappedVault = WrappedVault(deployedContractAddress);
        if (!isAlreadyDeployed) {
            console2.log("Verifying WrappedVault deployment");
            _verifyWrappedVaultDeployment(wrappedVault);
        }
        console2.log("WrappedVault deployed at: ", address(wrappedVault), "\n");

        // Deploy WrappedVaultFactory
        console2.log("Deploying WrappedVaultFactory");
        bytes memory wrappedVaultFactoryCreationCode = abi.encodePacked(
            vm.getCode("WrappedVaultFactory"),
            abi.encode(wrappedVault, PROTOCOL_FEE_RECIPIENT, PROTOCOL_FEE, MINIMUM_FRONTEND_FEE, ROYCO_OWNER, address(pointsFactory))
        );
        (deployedContractAddress, isAlreadyDeployed) = _deployWithSanityChecks(WRAPPED_VAULT_FACTORY_SALT, wrappedVaultFactoryCreationCode);
        WrappedVaultFactory wrappedVaultFactory = WrappedVaultFactory(deployedContractAddress);
        if (!isAlreadyDeployed) {
            console2.log("Verifying WrappedVaultFactory deployment");
            _verifyWrappedVaultFactoryDeployment(wrappedVaultFactory, pointsFactory, WrappedVault(wrappedVault));
        }
        console2.log("WrappedVaultFactory deployed at: ", address(wrappedVaultFactory), "\n");

        // Deploy WeirollWallet
        console2.log("Deploying WeirollWallet");
        bytes memory weirollWalletCreationCode = abi.encodePacked(vm.getCode("WeirollWallet"));
        (deployedContractAddress, isAlreadyDeployed) = _deployWithSanityChecks(WEIROLL_WALLET_SALT, weirollWalletCreationCode);
        WeirollWallet weirollWallet = WeirollWallet(payable(deployedContractAddress));
        if (!isAlreadyDeployed) {
            console2.log("Verifying WeirollWallet deployment");
            _verifyWeirollWalletDeployment(weirollWallet);
        }
        console2.log("WeirollWallet deployed at: ", address(weirollWallet), "\n");

        // Deploy VaultMarketHub
        console2.log("Deploying VaultMarketHub");
        bytes memory vaultMarketHubCreationCode = abi.encodePacked(vm.getCode("VaultMarketHub"), abi.encode(ROYCO_OWNER));
        (deployedContractAddress, isAlreadyDeployed) = _deployWithSanityChecks(VAULT_MARKET_HUB_SALT, vaultMarketHubCreationCode);
        VaultMarketHub vaultMarketHub = VaultMarketHub(deployedContractAddress);
        if (!isAlreadyDeployed) {
            console2.log("Verifying VaultMarketHub deployment");
            _verifyVaultMarketHubDeployment(vaultMarketHub);
        }
        console2.log("VaultMarketHub deployed at: ", address(vaultMarketHub), "\n");

        // Deploy RecipeMarketHub
        console2.log("Deploying RecipeMarketHub");
        bytes memory recipeMarketHubCreationCode = abi.encodePacked(
            vm.getCode("RecipeMarketHub"), abi.encode(address(weirollWallet), PROTOCOL_FEE, MINIMUM_FRONTEND_FEE, ROYCO_OWNER, address(pointsFactory))
        );
        (deployedContractAddress, isAlreadyDeployed) = _deployWithSanityChecks(RECIPE_MARKET_HUB_SALT, recipeMarketHubCreationCode);
        RecipeMarketHub recipeMarketHub = RecipeMarketHub(deployedContractAddress);
        if (!isAlreadyDeployed) {
            console2.log("Verifying RecipeMarketHub deployment");
            _verifyRecipeMarketHubDeployment(recipeMarketHub, weirollWallet, pointsFactory);
        }
        console2.log("RecipeMarketHub deployed at: ", address(recipeMarketHub), "\n");

        vm.stopBroadcast();
    }
}
