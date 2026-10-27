// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

/// @title Parameters
/// @author Anoma Foundation, 2026
/// @notice The deterministic deployment parameters — the CREATE2 salts and the logic ref the forwarders accept. They fix
/// where a deployment lands and which resources it serves, so they are held once here and read by the deploy script,
/// its tests, and the bindings tests through `DeploymentParameters`.
/// @custom:security-contact security@anoma.foundation
library Parameters {
    /// @notice The CREATE2 salt for the staging environment forwarder deployment.
    bytes32 internal constant FORWARDER_SALT_STAGING = "GenericCallForwarderStaging";

    /// @notice The CREATE2 salt for the production environment forwarder deployment.
    bytes32 internal constant FORWARDER_SALT_PRODUCTION = "GenericCallForwarderProduction";

    /// @notice The logic ref of the generic call circuit, which the forwarders are constructed with.
    bytes32 internal constant LOGIC_REF = 0x781160e88a2b86d3e2192bd491f2b8b1de5d70e85e590112a027bd48f91d9685;
}
