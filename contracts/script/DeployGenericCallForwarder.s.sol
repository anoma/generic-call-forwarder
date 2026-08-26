// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";

/// @title DeployGenericCallForwarder {
/// @author Anoma Foundation, 2025
/// @notice A script to deploy the generic call forwarder contract.
/// @custom:security-contact security@anoma.foundation
contract DeployGenericCallForwarder is Script {
    function run(bool isTestDeployment, address protocolAdapter, bytes32 logicRef)
        public
        returns (address genericCallForwarder)
    {
        vm.startBroadcast();

        if (isTestDeployment) {
            // Deploy regularly.
            genericCallForwarder =
                address(new GenericCallForwarder({protocolAdapter: protocolAdapter, logicRef: logicRef}));
        } else {
            // Deploy deterministically.
            genericCallForwarder = address(
                new GenericCallForwarder{salt: keccak256(abi.encode("GenericCallForwarder"))}({
                    protocolAdapter: protocolAdapter, logicRef: logicRef
                })
            );
        }

        vm.stopBroadcast();
    }
}
