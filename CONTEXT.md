# Generic Call Forwarder

The forwarder contract and integration-test layer that lets resources of the Anoma Resource Machine (ARM) trigger **arbitrary EVM calls** through the protocol adapter.

## Language

**Generic Call Forwarder**:
The contract that makes a list of calls to other contracts for a resource, when the protocol adapter calls it. Use "generic call forwarder" for the contract.

**Generic Call**:
A single `(to, value, data)` EVM call carried by a resource and executed by the forwarder. A resource's value commits to the calls it authorizes.

**Forwarder**:
A contract of an application that the protocol adapter calls. In this repository, the generic call forwarder.

**Protocol adapter**:
The contract that verifies transactions on a chain.

**External call**:
A call that the protocol adapter makes to a forwarder when it processes a resource.

**Ephemeral resource**:
A resource that exists only in one transaction.

**Resource logic**:
The circuit that decides when a transaction can create or consume a resource.

**Logic ref**:
The hash that identifies the code of a resource logic.

**Label ref**:
The hash of the data that separates the resources of one resource logic.

**Kind**:
The hash to curve of the logic ref and the label ref of a resource.

**Kind base**:
The point that the compliance circuit multiplies by the quantity of a resource.
_Avoid_: kind point

**Kind tree**:
A Merkle tree that gives kinds their kind bases. Two kinds with the same kind base are aliases.

**In-circuit check**:
A check that a circuit makes: a proof of the circuit is valid only if the check holds. For example, the generic call circuit checks that the value of a resource commits to its calls.

**Out-of-circuit check**:
A check outside the circuits, for example a check that the forwarder makes on chain.

**Environment**:
One of the two generic call forwarder deployments the repo maintains, each recorded per chain in the deployment record and tracking a branch. Say "environment" (not "network" or "deployment target") — a chain is where an environment lives, not which one it is.

**Staging / Production**:
The two environments. Each environment's forwarder accepts calls only from the protocol adapter proxy of the same environment. The forwarder is immutable and has no owner, so a new version is a new deployment, not an upgrade. The branches tracking them keep their own names, `staging` and `main`.

**Promotion**:
Moving a commit unchanged from `next` to `staging`, or from `staging` to `main`. The pull request opening one carries the gate proving the environment it targets runs that commit's source. Changes only ever flow this way.

**Deployment record**:
`crates/bindings/deployments.json` — the forwarder address each environment runs on each chain. A deploy of a new version replaces the chain's entry, and the superseded forwarder stays on the chain unrecorded.

**Legacy protocol adapter**:
The immutable protocol adapter that a chain used before the Galileo upgrade.

**Galileo upgrade**:
The replacement of the legacy protocol adapter of a chain with the protocol adapter, once for each chain.

## Note on upstream names

`generic_call_library` and `generic_call_witness` (the resource logic, witness types, and underlying circuit) live in `anoma/generic-call-resource` and keep those names — they are immutable from this repo's perspective.

The integration-test crate reuses the AnomaPay ERC20 resource constructors, `persistent` and `ephemeral` (via a dependency on `anomapay-erc20-forwarder-integration-test`), to wrap, transfer and unwrap tokens around a generic call; see that repo's `CONTEXT.md` for those terms.
