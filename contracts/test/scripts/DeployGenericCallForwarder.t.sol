// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {
    RecordedDeployments as ProtocolAdapterDeployments
} from "anoma-pa-evm-2.0.0-rc.5/generated/RecordedDeployments.sol";

import {DeployGenericCallForwarder} from "../../script/DeployGenericCallForwarder.s.sol";
import {Parameters} from "../../script/Parameters.sol";
import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";
import {DeploymentsFixture} from "../fixtures/DeploymentsFixture.sol";
import {DeployGenericCallForwarderMock} from "../mocks/DeployGenericCallForwarder.m.sol";

/// @notice Checks the deploy script against a fresh chain, settling through a given protocol adapter because the
/// records name no test deployment. The deployments it records are checked in `Deployments.t.sol` and its promotion
/// gates instead.
contract DeployGenericCallForwarderTest is DeploymentsFixture {
    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    function test_run_succeeds_for_a_staging_deployment() public {
        _expectDeployment({isProduction: false});
    }

    function test_run_succeeds_for_a_production_deployment() public {
        _expectDeployment({isProduction: true});
    }

    function test_run_deploys_the_predicted_forwarder() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarderMock(_PROTOCOL_ADAPTER);
        address predicted = script.predict({isProduction: false});

        address forwarder = script.run({isProduction: false});

        assertEq(forwarder, predicted, "the forwarder lands at another address");
    }

    function test_run_deploys_distinct_forwarders_per_environment() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarderMock(_PROTOCOL_ADAPTER);
        address staging = script.run({isProduction: false});
        address production = script.run({isProduction: true});

        assertNotEq(staging, production, "staging and production forwarder addresses are equal");
    }

    function test_run_settles_through_the_recorded_protocol_adapter() public {
        _expectRecordedProtocolAdapters({isProduction: false});
        _expectRecordedProtocolAdapters({isProduction: true});
    }

    function test_run_reverts_if_the_records_name_no_protocol_adapter() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarder();

        vm.expectRevert(
            abi.encodeWithSelector(
                DeployGenericCallForwarder.ProtocolAdapterNotRecorded.selector,
                _environmentName({isProduction: false}),
                block.chainid
            )
        );
        script.run({isProduction: false});
    }

    function test_run_reverts_if_the_forwarder_is_already_deployed() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarderMock(_PROTOCOL_ADAPTER);
        address forwarder = script.run({isProduction: false});

        vm.expectRevert(abi.encodeWithSelector(DeployGenericCallForwarder.ForwarderAlreadyDeployed.selector, forwarder));
        script.run({isProduction: false});
    }

    /// @notice Runs the deploy script for the environment and checks that the forwarder lands at the deterministic
    /// address of the environment salt and commits to the protocol adapter and the logic ref.
    /// @param isProduction Whether to deploy the production or the staging environment forwarder.
    function _expectDeployment(bool isProduction) private {
        DeployGenericCallForwarder script = new DeployGenericCallForwarderMock(_PROTOCOL_ADAPTER);
        address forwarder = script.run({isProduction: isProduction});

        address predicted = vm.computeCreate2Address(
            isProduction ? Parameters.FORWARDER_SALT_PRODUCTION : Parameters.FORWARDER_SALT_STAGING,
            keccak256(
                abi.encodePacked(
                    type(GenericCallForwarder).creationCode, abi.encode(_PROTOCOL_ADAPTER, Parameters.LOGIC_REF)
                )
            )
        );

        string memory environment = _environmentName(isProduction);

        assertEq(forwarder, predicted, string.concat(environment, ": forwarder address differs from the prediction"));
        assertGt(forwarder.code.length, 0, string.concat(environment, ": forwarder is not deployed"));
        assertEq(
            GenericCallForwarder(payable(forwarder)).getProtocolAdapter(),
            _PROTOCOL_ADAPTER,
            string.concat(environment, ": protocol adapter differs")
        );
        assertEq(
            GenericCallForwarder(payable(forwarder)).getLogicRef(),
            Parameters.LOGIC_REF,
            string.concat(environment, ": logic ref differs")
        );
    }

    /// @notice Runs the deploy script on every chain the protocol adapter package records for the environment and
    /// checks that the forwarder settles through the recorded protocol adapter proxy.
    /// @param isProduction Whether to deploy the production or the staging environment forwarders.
    function _expectRecordedProtocolAdapters(bool isProduction) private {
        ProtocolAdapterDeployments.Deployment[] memory deployments =
            isProduction ? ProtocolAdapterDeployments.production() : ProtocolAdapterDeployments.staging();

        for (uint256 i = 0; i < deployments.length; ++i) {
            vm.chainId(deployments[i].chainId);

            address forwarder = new DeployGenericCallForwarder().run({isProduction: isProduction});

            assertEq(
                GenericCallForwarder(payable(forwarder)).getProtocolAdapter(),
                deployments[i].proxy.addr,
                string.concat(
                    _deploymentContext({isProduction: isProduction, chainId: deployments[i].chainId}),
                    ": protocol adapter differs from the record"
                )
            );
        }
    }
}
