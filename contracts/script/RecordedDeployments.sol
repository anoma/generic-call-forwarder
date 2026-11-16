// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeploymentRecords} from "./DeploymentRecords.sol";

/// @title RecordedDeployments
/// @author Anoma Foundation, 2026
/// @notice Reads the generic call forwarders each environment records, from `crates/bindings/deployments.json`.
/// @dev The file is the only record. The bindings crate embeds it and checks it against the chains.
/// @custom:security-contact security@anoma.foundation
library RecordedDeployments {
    /// @notice A recorded generic call forwarder deployment.
    struct Deployment {
        uint256 chainId;
        address contractAddress;
    }

    /// @notice The directory of the bindings package that holds the records, relative to the project root.
    string internal constant _DIRECTORY = "../crates/bindings";

    /// @notice The name of the bindings package.
    string internal constant _PACKAGE_NAME = "anoma-generic-call-forwarder-bindings";

    /// @notice Returns the deployments the staging environment records.
    /// @return deployments The recorded staging deployments.
    function staging() internal view returns (Deployment[] memory deployments) {
        deployments = _deployments({isProduction: false});
    }

    /// @notice Returns the deployments the production environment records.
    /// @return deployments The recorded production deployments.
    function production() internal view returns (Deployment[] memory deployments) {
        deployments = _deployments({isProduction: true});
    }

    /// @notice Returns the deployments an environment records.
    /// @param isProduction Whether to return the production or the staging environment.
    /// @return deployments The recorded deployments.
    function _deployments(bool isProduction) private view returns (Deployment[] memory deployments) {
        bytes memory encoded =
            DeploymentRecords.entries({json: _records(), key: DeploymentRecords.environment(isProduction)});
        deployments = abi.decode(encoded, (Deployment[]));
    }

    /// @notice Returns the content of the records file.
    /// @return json The JSON text of the file.
    function _records() private view returns (string memory json) {
        json = DeploymentRecords.read({directory: _DIRECTORY, packageName: _PACKAGE_NAME});
    }
}
