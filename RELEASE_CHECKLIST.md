# Release Checklist

Releases of the packages contained in this monorepo follow the [SemVer convention](https://semver.org/spec/v2.0.0.html).

> [!NOTE]
> The `contracts` and `bindings` are independently versioned with `X.Y.Z` and `A.B.C`, respectively. Both versions can include release candidates (suffixed with `-rc.N`).

We distinguish between three release cases:

- Releasing a **new** generic call forwarder version resulting in a new
  - `contracts/vX.Y.Z` version
  - `bindings/vA.0.0` version

- Deploying an **existing** generic call forwarder version to a chain new to an environment resulting in a new
  - `bindings/vA.B.0` version

- Maintaining the bindings resulting in a new
  - `bindings/vA.B.C` version

## Branches and Environments

The generic call forwarder runs in two environments, recorded per chain in [`./crates/bindings/deployments.json`](./crates/bindings/deployments.json):

| Environment  | CREATE2 salt                     | Branch    |
| ------------ | -------------------------------- | --------- |
| `staging`    | `GenericCallForwarderStaging`    | `staging` |
| `production` | `GenericCallForwarderProduction` | `main`    |

The forwarder is immutable and unowned, so the environments differ only in the CREATE2 salt and the protocol adapter they settle through: each environment's forwarder is constructed with the protocol adapter proxy of the **same** environment.

Changes flow one way, `next` → `staging` → `main`, and the promotion pull request is the gate:

- **`next`** integrates feature branches. Nothing is asserted about deployments, so a version bump is green before anything is deployed.
- **`staging`** receives `next`. A pull request into it requires every entry in the staging section to run the source version, checked with `VERIFY_STAGING_DEPLOYMENTS`.
- **`main`** receives `staging`. A pull request into it requires every entry in the production section to run the source version and carry no prerelease suffix, checked with `VERIFY_PRODUCTION_DEPLOYMENTS`.

The flags gate the deployment tests in the contracts and the crates suites alike; unset, the gated tests skip and no chain is forked.

Deploy **every** chain of an environment before opening its promotion pull request — one chain left behind blocks the promotion for all of them.

`VERSION` is a `string public constant`, so it is part of the creation code and every version is a different contract at a different address. Bumping it is a redeploy, and stripping an `-rc.N` suffix is a redeploy too, which is why a release costs one extra staging deploy round.

An entry pins the address an environment currently runs and nothing else — the deployment tests recompute the CREATE2 prediction from the salt and the constructor arguments the chain answers, so nothing needs genesis pinning. Every deploy therefore **replaces** the chain's entry, and superseded versions simply remain on-chain unrecorded.

## Prerequisites

These apply to all three cases and are done once per session.

- [ ] Visit https://www.soliditylang.org/ and check that the Solidity compiler version used in [`./contracts/foundry.toml`](./contracts/foundry.toml) has no [known vulnerabilities](https://docs.soliditylang.org/en/latest/bugs.html).

- [ ] Install the dependencies with

  ```sh
  just contracts-deps
  ```

- [ ] Check that the dependencies are up-to-date and have no known vulnerabilities.

- [ ] Check that the bindings are up-to-date with

  ```sh
  just bindings-check
  ```

- [ ] Check out a new git branch branching off from `next`, and check that there are no staged or unstaged changes by running `git status`.

- [ ] Check that the deployer wallet is funded and add it to `cast` with

  ```sh
  cast wallet import deployer --private-key <PRIVATE_KEY>
  ```

  or

  ```sh
  cast wallet import deployer --mnemonic <MNEMONIC>
  ```

- [ ] Set the Alchemy RPC provider by exporting

  ```sh
  export ALCHEMY_API_KEY=<KEY>
  ```

- [ ] Set the Etherscan key

  ```sh
  export ETHERSCAN_API_KEY=<KEY>
  ```

- [ ] Select the environment. It picks the CREATE2 salt in [`DeployGenericCallForwarder.s.sol`](./contracts/script/DeployGenericCallForwarder.s.sol), and is deliberately not persisted anywhere so that it is a conscious choice per session.

  ```sh
  export IS_PRODUCTION=false
  ```

  Only `just contracts-simulate` and `just contracts-deploy` read it.

## Releasing a new Generic Call Forwarder Version

A release candidate and a release go through the same cycle. Steps 1 to 5 are repeated for each release candidate; steps 6 to 9 lift the last candidate to a release and carry it to production.

### 1. Bump the Version

- [ ] Bump `VERSION` in [`./contracts/src/GenericCallForwarder.sol`](./contracts/src/GenericCallForwarder.sol) following [SemVer](https://semver.org/spec/v2.0.0.html).

- [ ] Bump the `bindings` package version in [`./crates/bindings/Cargo.toml`](./crates/bindings/Cargo.toml) to `A.0.0-rc.N`, where `A` is the last `MAJOR` version number incremented by 1.

- [ ] Regenerate the bindings with `just contracts-gen-bindings`, then run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change.

- [ ] Open a pull request into `next` and merge it once green. The deploy is a separate mechanical step afterwards.

### 2. Test the Contracts

- [ ] Run the checks and test suites CI runs with

  ```sh
  just all-lint all-test
  ```

### 3. Deploy Staging

For each chain in the `staging` section of the record:

- [ ] Look up the two values the forwarder commits to:
  - `<PROTOCOL_ADAPTER>` — the **staging** protocol adapter proxy on this chain, recorded in [`anoma/pa-evm` `crates/bindings/deployments.json`](https://github.com/anoma/pa-evm/blob/main/crates/bindings/deployments.json) on the branch tracking the environment.
  - `<GENERIC_CALL_CIRCUIT_ID>` — the verifying key of the [`generic_call_library`](https://github.com/anoma/generic-call-resource) version pinned in [`./Cargo.toml`](./Cargo.toml).

- [ ] **Simulate** the deployment by running

  ```sh
  just contracts-simulate <CHAIN> <PROTOCOL_ADAPTER> <GENERIC_CALL_CIRCUIT_ID>
  ```

- [ ] After successful simulation, **deploy** the contract by running

  ```sh
  just contracts-deploy deployer <CHAIN> <PROTOCOL_ADAPTER> <GENERIC_CALL_CIRCUIT_ID>
  ```

- [ ] Export the address of the newly deployed forwarder with

  ```sh
  export FWD_ADDRESS=<ADDRESS>
  ```

- [ ] Verify the contract on sourcify and Etherscan by running

  ```sh
  just contracts-verify $FWD_ADDRESS <CHAIN>
  ```

  and check that the verification worked (e.g. on https://sourcify.dev/#/lookup).

- [ ] Replace the chain's entry in the `staging` section of [`./crates/bindings/deployments.json`](./crates/bindings/deployments.json) with the new address.

After the last chain:

- [ ] Confirm the promotion gate locally by running

  ```sh
  VERIFY_STAGING_DEPLOYMENTS=true just contracts-test bindings-test
  ```

  the same checks the promotion pull request runs.

- [ ] Open a pull request with the record update into `next` and merge it once green.

> [!NOTE]
> Deploying to a chain that has no entry yet is not part of this cycle — see [Deploying a Version to a Chain new to an Environment](#deploying-a-version-to-a-chain-new-to-an-environment).

### 4. Promote `next` into `staging`

- [ ] Open a pull request from `next` into `staging`. CI sets `VERIFY_STAGING_DEPLOYMENTS`, so the deployment tests fork every chain in the staging section and check that it runs the address this source predicts under the environment salt.

- [ ] Merge it once green.

### 5. Tag and Publish the Release Candidate

- [ ] Create the tags on the promoted commit:
  - [ ] `contracts/vX.Y.Z-rc.N`, where `X.Y.Z-rc.N` must match the generic call forwarder `VERSION`, and
  - [ ] `bindings/vA.0.0-rc.N`.

- [ ] Create new [GH releases](https://github.com/anoma/generic-call-forwarder/releases) for both packages.

- [ ] Publish the `contracts` package on https://soldeer.xyz/ with

  ```sh
  just contracts-publish --dry-run
  ```

  and check the resulting `contracts.zip` file. If everything is correct, remove the `--dry-run` flag and publish the package.

- [ ] Publish the `anoma-generic-call-forwarder-bindings` package on https://crates.io/ with

  ```sh
  just bindings-publish --dry-run
  ```

  and check the result. If everything is correct, remove the `--dry-run` flag and publish the package.

> [!IMPORTANT]
> A prerelease of the bindings describes **staging only**. Production trails on the previous release until the candidate cycle ends, so the generated ABI need not match what production runs.

### 6. Lift the Release Candidate to a Release

- [ ] On a branch off `next`, strip the `-rc.N` suffix from `VERSION` and from the `bindings` package version, and merge it into `next`.

- [ ] Repeat steps 2 to 4. The release version is a different contract at a different address, so it has to be deployed to staging and promoted like any other candidate. This is the extra staging deploy round a release costs, and it is what lets production run the exact source staging validated.

### 7. Deploy Production

- [ ] Select the production environment with

  ```sh
  export IS_PRODUCTION=true
  ```

- [ ] For each chain in the `production` section of the record, simulate, deploy, verify, and replace the chain's entry as in step 3 — with the **production** protocol adapter proxy as `<PROTOCOL_ADAPTER>`.

- [ ] After the last chain, confirm the promotion gate locally by running

  ```sh
  VERIFY_PRODUCTION_DEPLOYMENTS=true just contracts-test bindings-test
  ```

- [ ] Open a pull request with the record update into `next` and merge it once green.

### 8. Promote `staging` into `main`

- [ ] Promote `next` into `staging` so the production record update rides along — the staging gate is indifferent to production entries and staging still runs this source.

- [ ] Open a pull request from `staging` into `main`. CI sets `VERIFY_PRODUCTION_DEPLOYMENTS`, so the deployment tests check that every chain in the production section runs this source and carries no prerelease suffix.

- [ ] Merge it once green.

### 9. Tag and Publish the Release

- [ ] Create the tags on the promoted commit:
  - [ ] `contracts/vX.Y.Z`, where `X.Y.Z` must match the generic call forwarder `VERSION`, and
  - [ ] `bindings/vA.0.0`, where `A` is the last `MAJOR` version number incremented by 1.

- [ ] Create new [GH releases](https://github.com/anoma/generic-call-forwarder/releases) for both packages, and publish both as in step 5.

## Deploying a Version to a Chain new to an Environment

A chain can be new to one environment and not to the other. The deploy is the same either way — the environment picks the CREATE2 salt and the protocol adapter the forwarder settles through.

### 1. Deploy and Verify the Generic Call Forwarder

For **staging**:

- [ ] Select the environment with

  ```sh
  export IS_PRODUCTION=false
  ```

For **production**:

- [ ] Check that `VERSION` carries no `-rc.N` suffix. Recording a production entry arms the release check on the next promotion into `main`.

- [ ] Select the environment with

  ```sh
  export IS_PRODUCTION=true
  ```

For **both**:

- [ ] Run the checks and test suites as in step 2 of the release cycle.

- [ ] Look up `<PROTOCOL_ADAPTER>` and `<GENERIC_CALL_CIRCUIT_ID>`, then simulate, deploy, and verify as in step 3 of the release cycle.

### 2. Record the Entry

- [ ] Add an entry to the environment's section of [`./crates/bindings/deployments.json`](./crates/bindings/deployments.json):

  ```json
  {
    "chainId": <CHAIN_ID>,
    "contractAddress": "<FWD_ADDRESS>"
  }
  ```

- [ ] Bump the `bindings` package version in [`./crates/bindings/Cargo.toml`](./crates/bindings/Cargo.toml) to `A.B.0`, where `A` is the last `MAJOR` version and `B` is the last `MINOR` version number incremented by 1.

- [ ] Run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change, then run the tests with `just bindings-test`.

- [ ] Open a pull request into `next` and merge it once green. The CREATE2 derivation of the new entry is checked at the promotions, so deploy before promoting.

### 3. Promote and Publish

- [ ] Promote `next` into `staging`, then `staging` into `main`, as in the release cycle. Each gate now includes the new chain, so the section it was added to has become a rollout commitment.

- [ ] Create a `bindings/vA.B.0` tag on the commit promoted to `main`, create a new [GH release](https://github.com/anoma/generic-call-forwarder/releases), and publish the package as in step 5 of the release cycle.

## Maintaining the Bindings

For changes that touch only the bindings crate and leave `VERSION` alone.

### 1. Bump the Version

- [ ] Change the `bindings` package version number in [`./crates/bindings/Cargo.toml`](./crates/bindings/Cargo.toml) to `A.B.C`, where `A` and `B` are the last `MAJOR` and `MINOR` version numbers and `C` is the last `PATCH` version number incremented by 1.

- [ ] Run `just bindings-build` and check that the `Cargo.lock` file reflects the version number change.

- [ ] Run the tests with `just bindings-test`.

- [ ] Open a pull request into `next` and merge it once green.

### 2. Promote

- [ ] Promote `next` into `staging`, then `staging` into `main`. Neither promotion needs a deploy round: `VERSION` did not change, so both environments already run the source version and both gates are satisfied as they stand.

### 3. Tag and Publish a new `bindings` Package

- [ ] Create a new `bindings/vA.B.C` tag on the commit promoted to `main` and a new [GH release](https://github.com/anoma/generic-call-forwarder/releases).

- [ ] Publish the `anoma-generic-call-forwarder-bindings` package on https://crates.io/ with

  ```sh
  just bindings-publish --dry-run
  ```

  and check the result. If everything is correct, remove the `--dry-run` flag and publish the package.
