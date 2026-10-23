// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.12/generated/RecordedDeployments.sol";
import {Script} from "forge-std-1.17.0/src/Script.sol";

/// @title RecordedDeploymentsScript
/// @author Anoma Foundation, 2026
/// @notice The base of the scripts that act on a recorded protocol adapter proxy. The protocol adapter package records
/// the proxy, so `--rpc-url` alone names the chain.
/// @custom:security-contact security@anoma.foundation
abstract contract RecordedDeploymentsScript is Script {
    /// @notice Thrown if the environment records no protocol adapter proxy for the chain.
    error DeploymentNotRecorded(string environment, uint256 chainId);

    /// @notice Returns the name of an environment, which keys its deployments in `deployments.json`.
    /// @param isProduction Whether to name the production or the staging environment.
    /// @return name The environment name.
    function environmentName(bool isProduction) public pure returns (string memory name) {
        name = isProduction ? "production" : "staging";
    }

    /// @notice Returns the protocol adapter proxy the environment records for the chain `--rpc-url` names, and reverts
    /// unless it is recorded.
    /// @param isProduction Whether to read the production or the staging proxy.
    /// @return proxy The recorded protocol adapter proxy.
    function _requireRecordedProxy(bool isProduction) internal view returns (address proxy) {
        proxy = _recordedProxy(isProduction);
        require(proxy != address(0), DeploymentNotRecorded(environmentName(isProduction), block.chainid));
    }

    /// @notice Returns the protocol adapter proxy the environment records for the chain `--rpc-url` names.
    /// @param isProduction Whether to read the production or the staging proxy.
    /// @return proxy The recorded protocol adapter proxy, or the zero address if the environment records none for the
    /// chain.
    function _recordedProxy(bool isProduction) internal view virtual returns (address proxy) {
        proxy = ProtocolAdapterDeployments.protocolAdapterProxy({isProduction: isProduction, chainId: block.chainid});
    }
}
