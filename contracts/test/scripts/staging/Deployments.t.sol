// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {GenericCallForwarder} from "../../../src/GenericCallForwarder.sol";
import {DeploymentsFixture} from "../../fixtures/DeploymentsFixture.sol";

/// @notice Checks the staging deployments recorded in `deployments.json`. The forwarder is immutable, so every check
/// asks the chain and holds only while the deployments are verified, because the source leads them between
/// deployments.
contract DeploymentsStagingTest is DeploymentsFixture {
    /// @notice Skips the test unless the staging deployments are verified against this source.
    modifier onlyStaging() {
        vm.skip(!vm.envOr("VERIFY_STAGING_DEPLOYMENTS", false), "VERIFY_STAGING_DEPLOYMENTS is not set");
        _;
    }

    function test_recorded_deployments_run_this_source_under_the_environment_salt() public onlyStaging {
        _expectSourceDeployments({isProduction: false});
    }

    function test_recorded_deployments_run_a_release_or_release_candidate_version() public onlyStaging {
        Deployment[] memory deployments = _recordedDeployments({isProduction: false});

        for (uint256 i = 0; i < deployments.length; ++i) {
            _selectForkAt(deployments[i].chainId);
            string memory version = GenericCallForwarder(payable(deployments[i].contractAddress)).VERSION();
            string memory context = _deploymentContext({isProduction: false, chainId: deployments[i].chainId});

            assertTrue(
                _isRelease(version) || _isReleaseCandidate(version),
                string.concat(context, ": version is neither a release nor a release candidate: ", version)
            );
        }
    }
}
