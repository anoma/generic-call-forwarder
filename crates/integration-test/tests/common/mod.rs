//! Shared scenario setups for the generic-call integration tests.
//!
//! This lives under `tests/` so it is purely test code: it is never compiled
//! into a library and is invisible to dependents. Each integration test
//! includes it with `mod common;`. Reusable helpers (assertions, provisioning)
//! live in the testkit and the integration-test crates instead.

#[cfg(feature = "e2e")]
pub type EvmE2eEnv = anoma_pa_evm_integration_test::envs::e2e::Environment;

pub type EvmLocalEnv = anoma_pa_evm_integration_test::envs::local::Environment;

use alloy::primitives::{B256, U256};
use anoma_generic_call_forwarder_integration_test::deploy::forwarder::deploy_and_insert_generic_call_forwarder;
use anoma_generic_call_forwarder_integration_test::logic as generic_call_logic;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::actors::default_signer_in_state;
use anoma_pa_evm_integration_test::state::pa::pa_address_in_state;
use anoma_pa_testkit::environment::StateBuilder;
use anoma_pa_testkit::fixtures::identities;
use anomapay_erc20_forwarder_integration_test::deploy::erc20::ierc20_bindings::ierc20;
use anomapay_erc20_forwarder_integration_test::deploy::erc20::weth_bindings::deploy_and_insert_weth;
use anomapay_erc20_forwarder_integration_test::deploy::forwarder::deploy_and_insert_erc20_forwarder;
use anomapay_erc20_forwarder_integration_test::deploy::permit2::PERMIT2_CANONICAL_ADDRESS;
use anomapay_erc20_forwarder_integration_test::deploy::permit2::deploy_permit2_canonical_from_state;
use anomapay_erc20_forwarder_integration_test::logic as erc20_logic;
use anyhow::Context;

pub use anoma_pa_testkit::{commitment_root, execute_tx, prove_actions};

pub async fn setup_transfer_generic_call_local_env() -> anyhow::Result<EvmLocalEnv> {
    EvmLocalEnv::setup(async |builder: &mut StateBuilder| {
        deploy_permit2_canonical_from_state(builder.as_state())
            .await
            .context("failed to deploy Permit2 at canonical address")?;
        setup_transfer_generic_call_env_on_builder(builder).await
    })
    .await
}

#[cfg(feature = "e2e")]
pub async fn setup_transfer_generic_call_e2e_env() -> anyhow::Result<EvmE2eEnv> {
    EvmE2eEnv::setup(async |builder: &mut StateBuilder| {
        setup_transfer_generic_call_env_on_builder(builder).await
    })
    .await
}

async fn setup_transfer_generic_call_env_on_builder(
    builder: &mut StateBuilder,
) -> anyhow::Result<()> {
    let provider = default_signer_in_state(builder.as_state())
        .context("failed to retrieve default signer from setup state")?;
    let pa_address = pa_address_in_state(builder.as_state())
        .context("failed to retrieve protocol adapter address from setup state")?;

    let deployer = identities::alice()
        .context("failed to build sender keychain")?
        .address();

    let token = deploy_and_insert_weth(
        builder,
        "weth",
        provider.clone(),
        deployer,
        U256::from(1_000_000u64),
    )
    .await
    .context("failed to deploy and insert WETH9")?;

    let transfer_logic_ref = B256::from(<[u8; 32]>::from(erc20_logic::verifying_key()));
    deploy_and_insert_erc20_forwarder(
        builder,
        provider.clone(),
        pa_address,
        transfer_logic_ref,
        deployer,
    )
    .await
    .context("failed to deploy and insert ERC20 forwarder v1")?;

    let generic_call_logic_ref = B256::from(<[u8; 32]>::from(generic_call_logic::verifying_key()));
    deploy_and_insert_generic_call_forwarder(
        builder,
        provider.clone(),
        pa_address,
        generic_call_logic_ref,
    )
    .await
    .context("failed to deploy and insert generic call forwarder v1")?;

    ierc20(token, provider.clone())
        .approve(PERMIT2_CANONICAL_ADDRESS, U256::MAX)
        .send()
        .await
        .context("failed to submit WETH permit2 approval transaction")?
        .get_receipt()
        .await
        .context("failed to fetch WETH permit2 approval receipt")?;

    Ok(())
}
