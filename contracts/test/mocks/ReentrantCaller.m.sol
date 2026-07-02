// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IForwarder} from "anoma-forwarder-bases-1.0.0/src/interfaces/IForwarder.sol";

contract ReentrantCallerMock {
    IForwarder internal immutable _FORWARDER;
    bytes32 internal immutable _LOGIC_REF;

    constructor(IForwarder forwarder, bytes32 logicRef) {
        _FORWARDER = forwarder;
        _LOGIC_REF = logicRef;
    }

    function reenter(bytes calldata input) external {
        _FORWARDER.forwardCall(_LOGIC_REF, input);
    }
}
