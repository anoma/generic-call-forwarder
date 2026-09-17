// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {DeployGenericCallForwarder} from "../../script/DeployGenericCallForwarder.s.sol";

/// @notice The deploy script, settling through the given protocol adapter instead of the recorded one. The records are
/// compiled in, so they name no test deployment.
contract DeployGenericCallForwarderMock is DeployGenericCallForwarder {
    address internal immutable _PROTOCOL_ADAPTER;

    constructor(address protocolAdapter) {
        _PROTOCOL_ADAPTER = protocolAdapter;
    }

    function _protocolAdapter(bool) internal view override returns (address protocolAdapter) {
        protocolAdapter = _PROTOCOL_ADAPTER;
    }
}
