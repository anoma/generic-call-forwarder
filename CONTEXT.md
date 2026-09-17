# Generic Call Forwarder

The forwarder contract and integration-test layer that lets ARM resources trigger
**arbitrary EVM calls** through the [Anoma EVM protocol adapter](https://github.com/anoma/pa-evm).

## Language

**Generic Call Forwarder**:
The EVM contract through which the protocol adapter executes a list of arbitrary
calls on behalf of an action. Use "generic call forwarder" for the contract.

**Generic Call**:
A single `(to, value, data)` EVM call carried by a resource and executed by the
forwarder. A resource's label commits to the calls it authorizes.

**Forwarder**:
The generic call forwarder contract (above) — the same forwarder role the protocol
adapter drives in other applications.

**Environment**:
One of the two generic call forwarder deployments the repo maintains, each recorded per chain in the deployment record and tracking a branch. Say "environment" (not "network" or "deployment target") — a chain is where an environment lives, not which one it is.

**Staging / Production**:
The two environments. Each environment's forwarder settles through the protocol adapter proxy of the same environment. The forwarder is immutable and has no owner, so a new version is a new deployment, not an upgrade. The branches tracking them keep their own names, `staging` and `main`.

**Promotion**:
Moving a commit unchanged from `next` to `staging`, or from `staging` to `main`. The pull request opening one carries the gate proving the environment it targets runs that commit's source. Changes only ever flow this way.

**Deployment record**:
`crates/bindings/deployments.json` — the forwarder address each environment runs on each chain. A deploy of a new version replaces the chain's entry, and the superseded forwarder stays on the chain unrecorded.

## Note on upstream names

`generic_call_library` and `generic_call_witness` (the resource logic, witness
types, and underlying circuit) live in `anoma/generic-call-resource` and keep those
names — they are immutable from this repo's perspective.

The integration-test crate reuses the AnomaPay ERC20 wrap / transfer / unwrap
fixtures (via a dev-dependency on `anomapay-erc20-forwarder-integration-test`) to
move WETH into a shielded resource before driving a generic call; see that repo's
`CONTEXT.md` for those terms.
