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
    bytes32 internal constant LOGIC_REF = 0xdc64937e533f5eccf6041da5f49c905e6a28f76111ae2a5bc24160e67bd50dea;
}
