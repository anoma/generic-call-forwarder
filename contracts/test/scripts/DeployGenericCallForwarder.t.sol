// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployGenericCallForwarder} from "../../script/DeployGenericCallForwarder.s.sol";
import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";
import {DeploymentsFixture} from "../fixtures/DeploymentsFixture.sol";

/// @notice Checks the deploy script against a fresh chain. The deployments it records are checked in
/// `Deployments.t.sol` and its promotion gates instead.
contract DeployGenericCallForwarderTest is DeploymentsFixture {
    bytes32 internal constant _LOGIC_REF = bytes32(uint256(1));

    address internal immutable _PROTOCOL_ADAPTER = makeAddr("protocol adapter");

    function test_run_succeeds_for_a_staging_deployment() public {
        _expectDeployment({isProduction: false});
    }

    function test_run_succeeds_for_a_production_deployment() public {
        _expectDeployment({isProduction: true});
    }

    function test_run_deploys_distinct_forwarders_per_environment() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarder();
        address staging = script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
        address production = script.run({isProduction: true, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        assertNotEq(staging, production, "staging and production forwarder addresses are equal");
    }

    function test_run_reverts_if_the_chain_has_a_recorded_deployment() public {
        Deployment[] memory deployments = _recordedDeployments({isProduction: false});

        for (uint256 i = 0; i < deployments.length; ++i) {
            vm.chainId(deployments[i].chainId);

            DeployGenericCallForwarder script = new DeployGenericCallForwarder();

            vm.expectRevert(
                abi.encodeWithSelector(
                    DeployGenericCallForwarder.DeploymentAlreadyRecorded.selector,
                    _environmentName({isProduction: false}),
                    deployments[i].chainId
                )
            );
            script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
        }
    }

    function test_run_reverts_if_the_forwarder_is_already_deployed() public {
        DeployGenericCallForwarder script = new DeployGenericCallForwarder();
        address forwarder = script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        vm.expectRevert(abi.encodeWithSelector(DeployGenericCallForwarder.ForwarderAlreadyDeployed.selector, forwarder));
        script.run({isProduction: false, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});
    }

    /// @notice Runs the deploy script for the environment and checks that the forwarder lands at the predicted
    /// deterministic address and commits to the provided protocol adapter and logic reference.
    /// @param isProduction Whether to deploy the production or the staging environment forwarder.
    function _expectDeployment(bool isProduction) private {
        DeployGenericCallForwarder script = new DeployGenericCallForwarder();
        address forwarder =
            script.run({isProduction: isProduction, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

        address predicted =
            script.predict({isProduction: isProduction, protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _LOGIC_REF});

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
            _LOGIC_REF,
            string.concat(environment, ": logic ref differs")
        );
    }
}
