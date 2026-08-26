// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";

/// @title DeployGenericCallForwarder
/// @author Anoma Foundation, 2026
/// @notice A script to deploy the generic call forwarder deterministically on supported networks. The forwarder is
/// immutable and unowned, so the environments differ only in the CREATE2 salt and the protocol adapter they settle
/// through — there is no owner to configure and no proxy to promote.
/// @custom:security-contact security@anoma.foundation
contract DeployGenericCallForwarder is Script {
    /// @notice The CREATE2 salt for the staging environment deployment.
    bytes32 public constant FORWARDER_SALT_STAGING = "GenericCallForwarderStaging";

    /// @notice The CREATE2 salt for the production environment deployment.
    bytes32 public constant FORWARDER_SALT_PRODUCTION = "GenericCallForwarderProduction";

    /// @notice The deployments recorded per environment, relative to the Foundry root.
    string internal constant _DEPLOYMENTS_PATH = "../crates/bindings/deployments.json";

    /// @notice Thrown if the environment already has a deployment recorded for this chain.
    error DeploymentAlreadyRecorded(string environment, uint256 chainId);

    /// @notice Thrown if the forwarder of this source version is already deployed.
    error ForwarderAlreadyDeployed(address forwarder);

    /// @notice Deploys the generic call forwarder deterministically.
    /// @param isProduction Whether to deploy the production or the staging environment forwarder, selecting the
    /// CREATE2 salt.
    /// @param protocolAdapter The protocol adapter proxy of the same environment, the only caller allowed to forward
    /// calls.
    /// @param logicRef The reference to the generic-call resource logic function triggering the forward calls.
    /// @return forwarder The generic call forwarder contract to interact with.
    function run(bool isProduction, address protocolAdapter, bytes32 logicRef) public returns (address forwarder) {
        // Checks
        _requireUnrecorded(isProduction);

        forwarder = predict({isProduction: isProduction, protocolAdapter: protocolAdapter, logicRef: logicRef});
        require(forwarder.code.length == 0, ForwarderAlreadyDeployed({forwarder: forwarder}));

        // Deployment
        vm.startBroadcast();
        forwarder = address(
            new GenericCallForwarder{salt: _salt(isProduction)}({protocolAdapter: protocolAdapter, logicRef: logicRef})
        );
        vm.stopBroadcast();
    }

    /// @notice Predicts the deterministic address the forwarder of this source version deploys to.
    /// @param isProduction Whether to predict the production or the staging environment forwarder.
    /// @param protocolAdapter The protocol adapter proxy of the same environment.
    /// @param logicRef The reference to the generic-call resource logic function triggering the forward calls.
    /// @return forwarder The predicted generic call forwarder contract address.
    function predict(bool isProduction, address protocolAdapter, bytes32 logicRef)
        public
        pure
        returns (address forwarder)
    {
        bytes memory initCode =
            abi.encodePacked(type(GenericCallForwarder).creationCode, abi.encode(protocolAdapter, logicRef));

        forwarder = vm.computeCreate2Address({salt: _salt(isProduction), initCodeHash: keccak256(initCode)});
    }

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function environmentName(bool isProduction) public pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Checks that the environment has no deployment recorded for this chain yet.
    /// @param isProduction Whether to check the production or the staging environment.
    function _requireUnrecorded(bool isProduction) internal view {
        string memory json = vm.readFile(_DEPLOYMENTS_PATH);
        string memory environment = environmentName(isProduction);

        for (uint256 i = 0;; ++i) {
            // solhint-disable-next-line func-named-parameters
            string memory entry = string.concat(".", environment, "[", vm.toString(i), "]");
            if (!vm.keyExistsJson(json, entry)) {
                return;
            }

            require(
                vm.parseJsonUint(json, string.concat(entry, ".chainId")) != block.chainid,
                DeploymentAlreadyRecorded(environment, block.chainid)
            );
        }
    }

    /// @notice Returns the CREATE2 salt of an environment.
    /// @param isProduction Whether to return the production or the staging environment salt.
    /// @return salt The environment salt.
    function _salt(bool isProduction) internal pure returns (bytes32 salt) {
        salt = isProduction ? FORWARDER_SALT_PRODUCTION : FORWARDER_SALT_STAGING;
    }
}
