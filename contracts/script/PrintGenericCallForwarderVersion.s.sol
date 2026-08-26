// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std-1.16.2/src/Script.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";

/// @title PrintGenericCallForwarderVersion
/// @author Anoma Foundation, 2026
/// @notice A script returning the version the generic call forwarder source compiles to. The release flow reads it to
/// label the published package, so that the label always describes the source it ships.
/// @custom:security-contact security@anoma.foundation
contract PrintGenericCallForwarderVersion is Script {
    /// @notice Returns the version of the generic call forwarder this source compiles to.
    /// @return version The generic call forwarder version.
    function run() public returns (string memory version) {
        // The constructor rejects zero values; the throwaway instance only serves the version read.
        version = new GenericCallForwarder({protocolAdapter: address(1), logicRef: bytes32(uint256(1))}).VERSION();
    }
}
