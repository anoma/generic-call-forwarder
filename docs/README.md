# Generic Call Forwarder

This folder specifies the generic call forwarder and its deployments. The glossary of this repository, [`CONTEXT.md`](../CONTEXT.md#language), defines the terms. [`RELEASE_CHECKLIST.md`](../RELEASE_CHECKLIST.md) has the commands.

## 1. Summary

The generic call forwarder makes calls to other contracts for a transaction, for example a token swap on an exchange. It can send native tokens, receive tokens, and accept signatures for contracts that check them with ERC-1271. It is immutable and has no owner. Each protocol adapter has its own deployment.

## 2. Documents

| Document                                                 | Content                                                                          |
| -------------------------------------------------------- | -------------------------------------------------------------------------------- |
| [`01-contract-and-calls.md`](./01-contract-and-calls.md) | The resources of the forwarder, the calls that it makes, and its other functions |
| [`02-deployments.md`](./02-deployments.md)               | One deployment for each protocol adapter, and its parameters                     |
| [`03-legacy-deployments.md`](./03-legacy-deployments.md) | The deployments for the legacy protocol adapter, and why nothing moves from them |
