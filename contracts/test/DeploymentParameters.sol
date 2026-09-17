// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Parameters} from "../script/Parameters.sol";

/// @title DeploymentParameters
/// @author Anoma Foundation, 2026
/// @notice Exposes the deployment parameters through getters, so the bindings tests read the values the scripts hold
/// instead of restating them.
/// @custom:security-contact security@anoma.foundation
contract DeploymentParameters {
    /// @notice Returns the CREATE2 salt for the staging environment forwarder deployment.
    /// @return salt The staging forwarder salt.
    function FORWARDER_SALT_STAGING() external pure returns (bytes32 salt) {
        salt = Parameters.FORWARDER_SALT_STAGING;
    }

    /// @notice Returns the CREATE2 salt for the production environment forwarder deployment.
    /// @return salt The production forwarder salt.
    function FORWARDER_SALT_PRODUCTION() external pure returns (bytes32 salt) {
        salt = Parameters.FORWARDER_SALT_PRODUCTION;
    }

    /// @notice Returns the logic ref the forwarders are constructed with.
    /// @return logicRef The logic ref of the generic call circuit.
    function LOGIC_REF() external pure returns (bytes32 logicRef) {
        logicRef = Parameters.LOGIC_REF;
    }
}
