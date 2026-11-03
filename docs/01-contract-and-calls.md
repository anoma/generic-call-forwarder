# Contract and Calls

This document specifies the generic call forwarder: its resources, the calls that it makes, and its other functions. The code is in [`contracts/src/GenericCallForwarder.sol`](../contracts/src/GenericCallForwarder.sol). The [overview](./README.md) lists the other documents.

## 1. Resources and calls

The resource logic of the forwarder is the generic call circuit. A generic call resource is ephemeral, and its value commits to the list of calls. When the protocol adapter processes the resource, it makes an external call to the forwarder, and the forwarder makes the calls in the order of the list.

The protocol adapter makes the external calls in the order of the resources of the action. So one action can unwrap tokens to the forwarder, swap them, and wrap the result.

The kind tree of each chain gives the generic call kind its own kind point, so that the compliance circuit does not calculate it. This entry makes no alias.

## 2. Contract

`GenericCallForwarder` is immutable and has no owner. Its constructor takes the protocol adapter and the accepted logic ref, which `ForwarderBase` stores as immutables. The constant string `VERSION` names its version.

- **`forwardCall(logicRef, input)`** accepts calls only from its protocol adapter and only with its logic ref. It decodes the input as a list of calls `Call{to, value, data}` and makes them in order: a call with data, with or without a value, or a transfer of native tokens. A call without data and without value reverts with `NoOpNotAllowed`. It emits `Executed` and returns an empty output.
- **`isValidSignature`** accepts every signature (ERC-1271). For example, Permit2 then accepts a transfer of tokens that the forwarder holds, if the forwarder gave Permit2 an allowance earlier in the same transaction.
- **`sweep(token, to)`** sends the native or ERC20 balance of the forwarder to any address. Anyone can call it.
- **`registerSelector`** registers a callback for the duration of a transaction. Only the forwarder itself can call it, through a call of the list.

## 3. Trust assumptions

- **Any prover can make the forwarder call any contract.** The in-circuit checks of the generic call circuit cover only that the resource is ephemeral, that its label ref names the forwarder, and that its value commits to the calls. Other resources of the same action must authorize what the calls do, for example the signature of the user on an unwrap.
- **Tokens that stay in the forwarder belong to nobody.** After a transaction, anyone can move them with `sweep` or with the calls of a later transaction. A transaction must leave no tokens and no allowances in the forwarder.
- **Each signature check through the forwarder passes.** A contract that trusts `isValidSignature` of the forwarder must get its authorization from the action, not from the signature.
