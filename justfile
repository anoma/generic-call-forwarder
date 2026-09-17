# Show commands before running (helps debug failures)
set shell := ["bash", "-euo", "pipefail", "-c"]

# Default recipe
default:
    @just --list

# --- Contracts ---

# Install contract dependencies
contracts-deps:
    cd contracts && forge soldeer install

# Clean contract dependencies
contracts-deps-clean:
    cd contracts && forge soldeer clean

# Clean contracts
contracts-clean:
    cd contracts && forge clean

# Build contracts
contracts-build *args:
    cd contracts && forge build {{ args }}

# Lint contracts (forge lint + solhint)
contracts-lint:
    cd contracts && forge lint --deny notes
    cd contracts && bunx --bun solhint --config .solhint.json 'src/**/*.sol'
    cd contracts && bunx --bun solhint --config .solhint.other.json 'test/**/*.sol'
    cd contracts && bunx --bun solhint --config .solhint.other.json 'script/**/*.sol'
    cd contracts && bunx --bun solhint --config .solhint.other.json 'generated/**/*.sol'

# Run slither on contracts
contracts-static-analysis:
    cd contracts && slither .
    @echo "Removing slither compilation artifacts..."
    forge clean

# Format contracts
contracts-fmt *args:
    cd contracts && forge fmt {{ args }}

# Check contract formatting
contracts-fmt-check:
    cd contracts && forge fmt --check

# Run contract tests
contracts-test *args:
    cd contracts && forge test {{ args }}

# Regenerate the recorded deployments library from the deployment records
contracts-gen-deployments:
    ./scripts/generate-recorded-deployments.sh

# Regenerate Rust bindings from contracts
contracts-gen-bindings:
    # `forge bind` builds without bytecode, which drops the `deploy` helpers, so
    # build first and let it read those artifacts.
    cd contracts && forge clean && forge build --skip test --skip script && forge bind \
        --skip-build \
        --select '^(GenericCallForwarder|DeploymentParameters)$' \
        --bindings-path ../crates/bindings/src/generated/ \
        --module \
        --overwrite

# Regenerate the recorded deployments library, then the Rust bindings
contracts-gen: contracts-gen-deployments contracts-gen-bindings

# Simulate the deterministic forwarder deployment (dry-run)
contracts-simulate chain *args:
    @echo "IS_PRODUCTION: $IS_PRODUCTION"
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/DeployGenericCallForwarder.s.sol:DeployGenericCallForwarder \
        --sig "run(bool)" $IS_PRODUCTION \
        --rpc-url {{chain}} {{ args }}

# Deploy the forwarder deterministically to the environment selected by IS_PRODUCTION
contracts-deploy deployer chain *args:
    @echo "Cleaning contracts to ensure reproducible build..."
    @just contracts-clean
    cd contracts && forge script script/DeployGenericCallForwarder.s.sol:DeployGenericCallForwarder \
        --sig "run(bool)" $IS_PRODUCTION \
        --broadcast --rpc-url {{chain}} --account {{deployer}} {{ args }}

# Verify on sourcify
contracts-verify-sourcify address chain *args:
    cd contracts && env -u ETHERSCAN_API_KEY forge verify-contract {{address}} \
        src/GenericCallForwarder.sol:GenericCallForwarder \
        --chain {{chain}} --verifier sourcify --watch {{ args }}

# Verify on etherscan
contracts-verify-etherscan address chain *args:
    cd contracts && forge verify-contract {{address}} \
        src/GenericCallForwarder.sol:GenericCallForwarder \
        --chain {{chain}} --verifier etherscan --watch {{ args }}

# Verify on custom explorer
contracts-verify-custom address chain verifier-url *args:
    cd contracts && forge verify-contract {{address}} \
        src/GenericCallForwarder.sol:GenericCallForwarder \
        --chain {{chain}} --verifier-url {{verifier-url}}  --watch {{ args }}

# Verify on both sourcify and etherscan
contracts-verify address chain: (contracts-verify-sourcify address chain) (contracts-verify-etherscan address chain)

# Publish contracts at the version `GenericCallForwarder` compiles to
contracts-publish *args:
    #!/usr/bin/env bash
    set -euo pipefail
    echo "Cleaning contracts to ensure reproducible build..."
    just contracts-clean
    just contracts-build
    cd contracts
    version="$(forge script script/PrintGenericCallForwarderVersion.s.sol:PrintGenericCallForwarderVersion --sig 'run()(string)' --json \
        | jq -ser '[.[] | select(has("returns")) | .returns.version.value] | if length == 1 then .[0] else error("expected one version, found \(length)") end')"
    if [[ ! "$version" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
        printf '{{RED}}The generic call forwarder reports "%s", which is not a version.{{NORMAL}}\n' "$version"
        exit 1
    fi
    printf '{{GREEN}}Publishing anoma-generic-call-forwarder~%s{{NORMAL}}\n' "$version"
    forge soldeer push "anoma-generic-call-forwarder~$version" {{ args }}

# --- Bindings ---

# Clean bindings
bindings-clean:
    cd crates/bindings && cargo clean

# Build bindings
bindings-build *args:
    cd crates/bindings && cargo build {{ args }}

# Test bindings
bindings-test *args:
    cd crates/bindings && cargo test {{ args }}

# Check bindings are up-to-date
bindings-check: contracts-gen-bindings
    git diff --exit-code crates/bindings/src/generated/

# Check the recorded deployments library is up-to-date
contracts-deployments-check: contracts-gen-deployments
    git diff --exit-code contracts/generated/RecordedDeployments.sol

# Publish bindings
bindings-publish *args:
    cd crates/bindings && cargo publish {{ args }}

# Lint bindings (clippy)
bindings-lint:
    cd crates/bindings && cargo clippy --no-deps -- -Dwarnings
    cd crates/bindings && cargo clippy --no-deps --tests -- -Dwarnings

# Format bindings
bindings-fmt:
    cargo fmt

# Check bindings formatting
bindings-fmt-check:
    cargo fmt -- --check

# --- Crates (workspace-wide Rust) ---

# Clean all crates
crates-clean:
    cargo clean

# Build all crates
crates-build *args:
    cargo build {{ args }}

# Test all crates
crates-test *args:
    cargo test {{ args }}

# Lint all crates (clippy)
crates-lint:
    cargo clippy --all-targets --no-deps -- -Dwarnings

# Format all crates
crates-fmt *args:
    cargo fmt --all {{ args }}

# Check all crates formatting
crates-fmt-check:
    cargo fmt --all -- --check

# --- All ---

# Lint all (contracts + crates)
all-lint:
    @echo "==> Linting contracts..."
    @just contracts-lint
    @echo "==> Linting crates..."
    @just crates-lint

# Format all (contracts + crates)
all-fmt:
    @echo "==> Formatting contracts..."
    @just contracts-fmt
    @echo "==> Formatting crates..."
    @just crates-fmt

# Check formatting for all (contracts + crates)
all-fmt-check:
    @echo "==> Checking contract formatting..."
    @just contracts-fmt-check
    @echo "==> Checking crates formatting..."
    @just crates-fmt-check

# Build all (contracts + crates)
all-build:
    @echo "==> Building contracts..."
    @just contracts-build
    @echo "==> Building crates..."
    @just crates-build

# Test all (contracts + crates)
all-test:
    @echo "==> Testing contracts..."
    @just contracts-test
    @echo "==> Testing crates..."
    @just crates-test

# Prerequisites check (mirrors CI)
all-check:
    git status
    @echo "==> Static analysis with slither..."
    @just contracts-static-analysis
    @echo "==> Checking formatting..."
    @just all-fmt-check
    @echo "==> Linting..."
    @just all-lint
    @echo "==> Checking the recorded deployments library is up-to-date..."
    @just contracts-deployments-check
    @echo "==> Checking bindings are up-to-date..."
    @just bindings-check
