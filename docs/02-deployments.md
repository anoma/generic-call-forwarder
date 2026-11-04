# Deployments

This document specifies the deployments of the generic call forwarder and their parameters. The [overview](./README.md) lists the other documents, and the glossary [`CONTEXT.md`](../CONTEXT.md#language) defines the terms.

## 1. One deployment for each protocol adapter

Each chain and environment has one deployment, for the protocol adapter of that environment. The deploy script reads the protocol adapter from the deployment record of pa-evm. The deployment accepts `Parameters.LOGIC_REF`, the logic ref of the generic call circuit that the crates of this repository pin. The contract is immutable, so a new version or a new protocol adapter needs a new deployment.

## 2. Parameters

| Name                                   | Value                                            | Use                                        |
| -------------------------------------- | ------------------------------------------------ | ------------------------------------------ |
| `Parameters.FORWARDER_SALT_STAGING`    | `"GenericCallForwarderStaging"`                  | CREATE2 salt of the staging deployments    |
| `Parameters.FORWARDER_SALT_PRODUCTION` | `"GenericCallForwarderProduction"`               | CREATE2 salt of the production deployments |
| `Parameters.LOGIC_REF`                 | The logic ref of the pinned generic call circuit | The logic ref that the forwarder accepts   |

The deployment record, [`crates/bindings/deployments.json`](../crates/bindings/deployments.json), lists the deployments of each environment.
