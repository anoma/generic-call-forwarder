# Legacy Deployments

This document specifies the deployments of the generic call forwarder for the legacy protocol adapter. The glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. Differences

Before the Galileo upgrade, release candidates of the forwarder (`contracts/v1.0.1-rc.0`) ran with the legacy protocol adapter on Base Sepolia and Tempo Moderato. Their code has the same behaviour as the code that [`01-contract-and-calls.md`](./01-contract-and-calls.md) specifies. They differ in these points:

- They accept the logic ref of an earlier generic call circuit.
- `getVersion()` returns a `bytes32`, in place of the constant string `VERSION`.
- The legacy protocol adapter makes the external calls in pairs of one consumed and one created resource.

## 2. No migration

The legacy deployments stay on the chains. They accept calls only from the legacy protocol adapter, so they receive no calls after the stop of the legacy protocol adapter. The generic call resources are ephemeral, so no resource of the forwarder exists after its transaction. The forwarder holds no tokens between transactions. So nothing moves from the legacy deployments.
