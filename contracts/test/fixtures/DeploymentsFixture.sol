// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.5/generated/RecordedDeployments.sol";
import {Test} from "forge-std-1.16.2/src/Test.sol";
import {LibString} from "solady-0.1.26/src/utils/LibString.sol";

import {RecordedDeployments} from "../../generated/RecordedDeployments.sol";
import {DeployGenericCallForwarder} from "../../script/DeployGenericCallForwarder.s.sol";
import {Parameters} from "../../script/Parameters.sol";
import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";

/// @notice A test fixture providing the generic call forwarder deployments recorded per environment in
/// `deployments.json` — the single source of truth for the deterministic deployments — through the generated
/// `RecordedDeployments` library.
abstract contract DeploymentsFixture is Test {
    using LibString for *;

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

    /// @notice Checks that every recorded forwarder is the one this source deploys for the environment on its chain: it
    /// settles through the recorded protocol adapter proxy, accepts the logic ref of the parameters, and sits at the
    /// address they determine under the environment salt. The forwarder is immutable, so a match proves that the
    /// deployment runs this source.
    /// @param isProduction Whether to check the production or the staging environment.
    function _expectSourceDeployments(bool isProduction) internal {
        RecordedDeployments.Deployment[] memory deployments = _recordedDeployments(isProduction);

        for (uint256 i = 0; i < deployments.length; ++i) {
            uint256 chainId = deployments[i].chainId;
            address recorded = deployments[i].contractAddress;
            string memory context = _deploymentContext({isProduction: isProduction, chainId: chainId});

            _selectForkAt(chainId);
            assertGt(recorded.code.length, 0, string.concat(context, ": deployment missing on-chain"));

            GenericCallForwarder forwarder = GenericCallForwarder(payable(recorded));
            assertEq(
                forwarder.getProtocolAdapter(),
                ProtocolAdapterDeployments.protocolAdapterProxy({isProduction: isProduction, chainId: chainId}),
                string.concat(context, ": does not settle through the recorded protocol adapter")
            );
            assertEq(forwarder.getLogicRef(), Parameters.LOGIC_REF, string.concat(context, ": logic ref differs"));

            // Deployed after the fork is selected, because selecting one discards the contracts deployed before.
            address predicted = new DeployGenericCallForwarder().predict({isProduction: isProduction});
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

    /// @notice Returns the deployments of an environment, as `RecordedDeployments` records them.
    /// @param isProduction Whether to return the production or the staging environment.
    /// @return deployments The recorded deployments.
    function _recordedDeployments(bool isProduction)
        internal
        pure
        returns (RecordedDeployments.Deployment[] memory deployments)
    {
        deployments = isProduction ? RecordedDeployments.production() : RecordedDeployments.staging();
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
