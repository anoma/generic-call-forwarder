// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";
import {Address} from "@openzeppelin-contracts-5.6.1/utils/Address.sol";
import {ForwarderBase} from "anoma-forwarder-bases-1.0.0-rc.4/src/ForwarderBase.sol";
import {IVersion} from "anoma-forwarder-bases-1.0.0-rc.4/src/interfaces/IVersion.sol";
import {NativeTokenReceiver} from "anoma-forwarder-bases-1.0.0-rc.4/src/NativeTokenReceiver.sol";
import {TransientFallbackHandler} from "anoma-forwarder-bases-1.0.0-rc.4/src/TransientFallbackHandler.sol";

/// @title GenericCallForwarder
/// @author Anoma Foundation, 2026
/// @notice The generic call forwarder contract - a smart account controlled by Anoma resource machine applications via
/// the protocol adapter. The contract provides the following capabilities:
/// * Execution of arbitrary calls.
/// * Receipt and transfer of tokens, including:
///   * ERC-20 tokens.
///   * Tokens of other ERC standards that require callbacks, which can be supported transiently.
///   * Native assets (e.g., ETH on Ethereum L1 and L2s, BNB on BSC).
/// * ERC-1271 support: All signature validation request are accepted.
///! IMPORTANT: Because any caller can forward and execute arbitrary calls through this contract, funds and other
///! state held by it are only under a given user's control transiently, i.e., for the duration of that user's action.
///! Any funds or state remaining after the action may be modified by subsequent callers.
/// @custom:security-contact security@anoma.foundation
contract GenericCallForwarder is IERC1271, IVersion, ForwarderBase, NativeTokenReceiver, TransientFallbackHandler {
    using Address for address;
    using Address for address payable;

    /// @notice A struct containing data for a generic call to be executed as part of a forwarded call.
    /// @param to The address to call.
    /// @param value The native token value to be sent with the call.
    /// @param data The bytes-encoded function selector and calldata for the call.
    struct Call {
        address to;
        uint256 value;
        bytes data;
    }

    /// @notice Emits the executed calls and their resulting outputs.
    /// @param calls The array of calls executed.
    /// @param execResults The array with the results of the executed calls.
    event Executed(Call[] calls, bytes[] execResults);

    error NoOpNotAllowed();

    /// @notice Initializes the ERC-20 forwarder contract.
    /// @param protocolAdapter The protocol adapter contract that can forward calls.
    /// @param logicRef The reference to the logic function of the resource kind triggering the forward call.
    constructor(address protocolAdapter, bytes32 logicRef) ForwarderBase(protocolAdapter, logicRef) {}

    /// @inheritdoc IVersion
    function getVersion() external pure override returns (bytes32 version) {
        version = "1.0.0-rc.1";
    }

    /// @inheritdoc IERC1271
    /// @dev This method accepts every signature unconditionally by returning the ERC-1271 magic value, without
    /// performing any signer verification. Any required authorization is expected to be enforced on the Anoma.
    function isValidSignature(bytes32 hash, bytes calldata signature)
        external
        pure
        override
        returns (bytes4 magicValue)
    {
        (hash, signature);

        //! IMPORTANT
        //! This method accepts every signature unconditionally by returning the ERC-1271 magic value, without
        //! performing any signer verification. Any required authorization is expected to be enforced on the Anoma
        //! resource machine side through other resources within the same action.
        magicValue = IERC1271.isValidSignature.selector;
    }

    /// @notice Executes an array of generic calls.
    /// @param input Contains the calls to make.
    /// @return output The empty string signaling that the function call has succeeded.
    // @dev This method is reentrancy-protected by the `nonReentrant` modifier in `ForwarderBase.forwardCall`.
    function _forwardCall(bytes calldata input) internal virtual override returns (bytes memory output) {
        (Call[] memory calls) = abi.decode(input, (Call[]));

        uint256 nCalls = calls.length;
        bytes[] memory execResults = new bytes[](nCalls);

        for (uint256 i = 0; i < nCalls;) {
            if (calls[i].data.length != 0) {
                if (calls[i].value == 0) {
                    execResults[i] = calls[i].to.functionCall({data: calls[i].data});
                } else {
                    execResults[i] = calls[i].to.functionCallWithValue({data: calls[i].data, value: calls[i].value});
                }
            } else {
                if (calls[i].value != 0) {
                    payable(calls[i].to).sendValue(calls[i].value);
                } else {
                    revert NoOpNotAllowed();
                }
            }

            unchecked {
                ++i;
            }
        }

        emit Executed({calls: calls, execResults: execResults});

        output = "";
    }
}
