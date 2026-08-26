// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibString} from "solady-0.1.26/src/utils/LibString.sol";

import {DeployGenericCallForwarder} from "../../script/DeployGenericCallForwarder.s.sol";
import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";

/// @notice A test fixture providing the generic call forwarder deployments recorded per environment in
/// `deployments.json` — the single source of truth for the deterministic deployments.
abstract contract DeploymentsFixture is Test {
    using LibString for *;

    /// @notice A generic call forwarder deployment recorded in `deployments.json`.
    /// @dev Fields are ordered alphabetically by their JSON key so the struct decodes from `vm.parseJson`, which
    /// encodes object values in that order — the Solidity names themselves are irrelevant.
    struct Deployment {
        uint256 chainId;
        address contractAddress;
    }

    string internal constant _DEPLOYMENTS_PATH = "../crates/bindings/deployments.json";

    /// @notice The supported chain IDs mapped to the network names aliasing their RPC endpoints in `foundry.toml`.
    mapping(uint256 chainId => string networkName) internal _supportedNetworks;

    /// @notice Initializes the supported networks.
    constructor() {
        _supportedNetworks[1] = "mainnet";
        _supportedNetworks[10] = "optimism";
        _supportedNetworks[56] = "bsc";
        _supportedNetworks[97] = "bsc-testnet";
        _supportedNetworks[143] = "monad";
        _supportedNetworks[988] = "stable-mainnet";
        _supportedNetworks[4217] = "tempo";
        _supportedNetworks[4326] = "megaeth";
        _supportedNetworks[8453] = "base";
        _supportedNetworks[10143] = "monad-testnet";
        _supportedNetworks[42161] = "arbitrum";
        _supportedNetworks[42431] = "tempo-moderato";
        _supportedNetworks[84532] = "base-sepolia";
        _supportedNetworks[421614] = "arbitrum-sepolia";
        _supportedNetworks[11155111] = "sepolia";
        _supportedNetworks[11155420] = "optimism-sepolia";
    }

    /// @notice Checks that every recorded forwarder sits at the address this source predicts under the environment
    /// salt from the constructor arguments the chain answers. The forwarder is immutable, so nothing needs genesis
    /// pinning and a match proves both the salt and that the deployment runs this source.
    /// @param isProduction Whether to check the production or the staging environment.
    function _expectSourceDeployments(bool isProduction) internal {
        Deployment[] memory deployments = _recordedDeployments(isProduction);

        for (uint256 i = 0; i < deployments.length; ++i) {
            uint256 chainId = deployments[i].chainId;
            address recorded = deployments[i].contractAddress;
            string memory context = _deploymentContext({isProduction: isProduction, chainId: chainId});

            _selectForkAt(chainId);
            assertGt(recorded.code.length, 0, string.concat(context, ": deployment missing on-chain"));

            GenericCallForwarder forwarder = GenericCallForwarder(payable(recorded));
            address predicted = new DeployGenericCallForwarder()
                .predict({
                isProduction: isProduction,
                protocolAdapter: forwarder.getProtocolAdapter(),
                logicRef: forwarder.getLogicRef()
            });

            assertEq(predicted, recorded, string.concat(context, ": recorded address differs from the prediction"));
        }
    }

    /// @notice Selects a fork of the supported network with the provided chain ID.
    /// @param chainId The chain ID of the supported network to fork.
    function _selectForkAt(uint256 chainId) internal {
        string memory networkName = _supportedNetworks[chainId];
        assertGt(bytes(networkName).length, 0, string.concat(chainId.toString(), ": unsupported network"));

        vm.selectFork(vm.createFork(networkName));
    }

    /// @notice Reads the deployments of an environment recorded in `deployments.json`.
    /// @param isProduction Whether to read the production or the staging environment.
    /// @return deployments The recorded deployments.
    function _recordedDeployments(bool isProduction) internal view returns (Deployment[] memory deployments) {
        string memory environment = string.concat(".", _environmentName(isProduction));

        deployments = abi.decode(vm.parseJson(vm.readFile(_DEPLOYMENTS_PATH), environment), (Deployment[]));
    }

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function _environmentName(bool isProduction) internal pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Returns the `<environment>, <chain ID>` prefix identifying a recorded deployment in assert messages.
    /// @param isProduction Whether the deployment belongs to the production or the staging environment.
    /// @param chainId The chain ID of the deployment.
    /// @return context The assert message prefix.
    function _deploymentContext(bool isProduction, uint256 chainId) internal pure returns (string memory context) {
        context = string.concat(_environmentName(isProduction), ", ", chainId.toString());
    }

    /// @notice Returns whether a version is a release, i.e. carries no prerelease suffix.
    /// @param version The version to check.
    /// @return isRelease Whether the version is a release.
    function _isRelease(string memory version) internal pure returns (bool isRelease) {
        isRelease = version.indexOf("-") == LibString.NOT_FOUND;
    }

    /// @notice Returns whether a version is a release candidate, i.e. carries an `-rc.<number>` prerelease suffix.
    /// Any other prerelease (`-alpha.1`, `-rc`, `-rc.x`) is not one.
    /// @param version The version to check.
    /// @return isReleaseCandidate Whether the version is a release candidate.
    function _isReleaseCandidate(string memory version) internal pure returns (bool isReleaseCandidate) {
        uint256 separator = version.indexOf("-");
        if (separator == LibString.NOT_FOUND) {
            return false;
        }

        string memory suffix = version.slice(separator + 1);
        if (!suffix.startsWith("rc.")) {
            return false;
        }

        string memory number = suffix.slice(3);
        isReleaseCandidate = bytes(number).length != 0 && number.is7BitASCII(LibString.DIGITS_7_BIT_ASCII);
    }
}
