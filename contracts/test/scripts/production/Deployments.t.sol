// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GenericCallForwarder} from "../../../src/GenericCallForwarder.sol";
import {DeploymentsFixture} from "../../fixtures/DeploymentsFixture.sol";

/// @notice Checks the production deployments recorded in `deployments.json`. The forwarder is immutable and unowned,
/// so every check asks the chain and holds only while the deployments are verified, because the source leads them
/// between deployments.
contract DeploymentsProductionTest is DeploymentsFixture {
    /// @notice Skips the test unless the production deployments are verified against this source.
    modifier onlyProduction() {
        vm.skip(!vm.envOr("VERIFY_PRODUCTION_DEPLOYMENTS", false), "VERIFY_PRODUCTION_DEPLOYMENTS is not set");
        _;
    }

    function test_recorded_deployments_run_this_source_under_the_environment_salt() public onlyProduction {
        _expectSourceDeployments({isProduction: true});
    }

    function test_recorded_deployments_run_a_release_version() public onlyProduction {
        Deployment[] memory deployments = _recordedDeployments({isProduction: true});

        for (uint256 i = 0; i < deployments.length; ++i) {
            _selectForkAt(deployments[i].chainId);
            string memory version = GenericCallForwarder(payable(deployments[i].contractAddress)).VERSION();
            string memory context = _deploymentContext({isProduction: true, chainId: deployments[i].chainId});

            assertTrue(_isRelease(version), string.concat(context, ": version is a prerelease: ", version));
        }
    }
}
