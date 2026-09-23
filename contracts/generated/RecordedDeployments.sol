// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

// forge-lint: disable-next-item(literal-instead-of-constant)
/// @title RecordedDeployments
/// @author Anoma Foundation, 2026
/// @notice The generic call forwarders each environment records.
/// @dev Generated from `crates/bindings/deployments.json`, the single source of truth, which the bindings crate
/// embeds and checks against the chains. Do not edit by hand: run `just contracts-gen`, which CI reruns
/// and fails on any diff. The records live with the bindings because that crate publishes them; this library carries
/// them into Solidity so the contracts package reads nothing outside itself.
/// @custom:security-contact security@anoma.foundation
library RecordedDeployments {
    /// @notice A recorded generic call forwarder deployment.
    struct Deployment {
        uint256 chainId;
        address contractAddress;
    }

    /// @notice Returns whether the environment records a deployment for the chain.
    /// @param isProduction Whether to check the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return recorded Whether the environment records a deployment for the chain.
    function isRecorded(bool isProduction, uint256 chainId) internal pure returns (bool recorded) {
        recorded = genericCallForwarder({isProduction: isProduction, chainId: chainId}) != address(0);
    }

    /// @notice Returns the generic call forwarder an environment records for a chain.
    /// @param isProduction Whether to read the production or the staging environment.
    /// @param chainId The chain ID to look for.
    /// @return forwarder The recorded forwarder, or the zero address if the environment records none for the chain.
    function genericCallForwarder(bool isProduction, uint256 chainId) internal pure returns (address forwarder) {
        Deployment[] memory deployments = isProduction ? production() : staging();

        for (uint256 i = 0; i < deployments.length; ++i) {
            if (deployments[i].chainId == chainId) {
                return deployments[i].contractAddress;
            }
        }
    }

    /// @notice Returns the deployments the staging environment records.
    /// @return deployments The recorded staging deployments.
    function staging() internal pure returns (Deployment[] memory deployments) {
        deployments = new Deployment[](1);
        deployments[0] = Deployment({chainId: 11155111, contractAddress: 0x4d3342bf4975ac8d325087FE631357679a0E3c82});
    }

    /// @notice Returns the deployments the production environment records.
    /// @return deployments The recorded production deployments.
    function production() internal pure returns (Deployment[] memory deployments) {
        deployments = new Deployment[](0);
    }
}
