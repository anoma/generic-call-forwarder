// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.3/generated/RecordedDeployments.sol";
import {Script} from "forge-std-1.16.2/src/Script.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";
import {Parameters} from "./Parameters.sol";

/// @title DeployGenericCallForwarder
/// @author Anoma Foundation, 2026
/// @notice A script to deploy the generic call forwarder deterministically on supported networks. The forwarder is
/// immutable and unowned, so the environments differ only in the CREATE2 salt and the protocol adapter proxy they
/// settle through, which the protocol adapter package records for the same environment on the chain.
/// @custom:security-contact security@anoma.foundation
contract DeployGenericCallForwarder is Script {
    /// @notice The CREATE2 salt for the staging environment deployment.
    bytes32 public constant FORWARDER_SALT_STAGING = Parameters.FORWARDER_SALT_STAGING;

    /// @notice The CREATE2 salt for the production environment deployment.
    bytes32 public constant FORWARDER_SALT_PRODUCTION = Parameters.FORWARDER_SALT_PRODUCTION;

    /// @notice Thrown if the protocol adapter package records no protocol adapter proxy of the environment for this
    /// chain, i.e. the forwarder has no protocol adapter to settle through.
    error ProtocolAdapterNotRecorded(string environment, uint256 chainId);

    /// @notice Thrown if the forwarder of this source version is already deployed.
    error ForwarderAlreadyDeployed(address forwarder);

    /// @notice Deploys the generic call forwarder deterministically.
    /// @param isProduction Whether to deploy the production or the staging environment forwarder, selecting the
    /// CREATE2 salt and the protocol adapter proxy to settle through.
    /// @return forwarder The generic call forwarder contract to interact with.
    function run(bool isProduction) public returns (address forwarder) {
        // Checks
        address protocolAdapter = _protocolAdapter(isProduction);

        forwarder = _predict({isProduction: isProduction, protocolAdapter: protocolAdapter});
        require(forwarder.code.length == 0, ForwarderAlreadyDeployed({forwarder: forwarder}));

        // Deployment
        vm.startBroadcast();
        forwarder = address(
            new GenericCallForwarder{salt: _salt(isProduction)}({
                protocolAdapter: protocolAdapter, logicRef: Parameters.LOGIC_REF
            })
        );
        vm.stopBroadcast();
    }

    /// @notice Predicts the deterministic address the forwarder of this source version deploys to on this chain.
    /// @param isProduction Whether to predict the production or the staging environment forwarder.
    /// @return forwarder The predicted generic call forwarder contract address.
    function predict(bool isProduction) public view returns (address forwarder) {
        forwarder = _predict({isProduction: isProduction, protocolAdapter: _protocolAdapter(isProduction)});
    }

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function environmentName(bool isProduction) public pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Returns the protocol adapter proxy that the protocol adapter package records for the environment on this
    /// chain, which the forwarder settles through, and reverts unless the package records one.
    /// @param isProduction Whether to return the production or the staging environment protocol adapter proxy.
    /// @return protocolAdapter The recorded protocol adapter proxy.
    function _protocolAdapter(bool isProduction) internal view virtual returns (address protocolAdapter) {
        protocolAdapter =
            ProtocolAdapterDeployments.protocolAdapterProxy({isProduction: isProduction, chainId: block.chainid});
        require(protocolAdapter != address(0), ProtocolAdapterNotRecorded(environmentName(isProduction), block.chainid));
    }

    /// @notice Derives the deterministic forwarder address from the environment salt and the constructor arguments.
    /// @param isProduction Whether to derive the production or the staging environment forwarder, selecting the salt.
    /// @param protocolAdapter The protocol adapter proxy of the same environment.
    /// @return forwarder The deterministic generic call forwarder contract address.
    function _predict(bool isProduction, address protocolAdapter) internal pure returns (address forwarder) {
        bytes memory initCode = abi.encodePacked(
            type(GenericCallForwarder).creationCode, abi.encode(protocolAdapter, Parameters.LOGIC_REF)
        );

        forwarder = vm.computeCreate2Address({salt: _salt(isProduction), initCodeHash: keccak256(initCode)});
    }

    /// @notice Returns the CREATE2 salt of an environment.
    /// @param isProduction Whether to return the production or the staging environment salt.
    /// @return salt The environment salt.
    function _salt(bool isProduction) internal pure returns (bytes32 salt) {
        salt = isProduction ? FORWARDER_SALT_PRODUCTION : FORWARDER_SALT_STAGING;
    }
}
