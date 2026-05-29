use alloy::primitives::U256;
use alloy::providers::Provider;
use alloy::sol_types::SolCall;
use anoma_generic_call_forwarder_integration_test as it;
use anoma_pa_evm_integration_test::state::actors::default_signer;

mod common;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::environment::CommitmentTree;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::environment::ProtocolAdapter;
use anoma_pa_testkit::fixtures::identities;
use anomapay_erc20_forwarder_integration_test::deploy::erc20::ierc20_bindings::ierc20;
use anomapay_erc20_forwarder_integration_test::deploy::erc20::weth_bindings::WETH9;
use anomapay_erc20_forwarder_integration_test::fixtures::{transfer, unwrap, wrap};
use anomapay_erc20_forwarder_integration_test::state::erc20::addresses::erc20_address;
use anomapay_erc20_forwarder_integration_test::state::forwarder::addresses::erc20_forwarder_v1_address;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_transfer_generic_call_e2e_env;
use common::{commitment_root, execute_tx, prove_actions, setup_transfer_generic_call_local_env};
use it::fixtures::generic_call;
use it::state::addresses::generic_call_forwarder_v1_address;
use rstest::*;

use anoma_generic_call_witness::GenericCall;

#[rstest]
#[case::local(setup_transfer_generic_call_local_env())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_transfer_generic_call_e2e_env()))]
#[tokio::test]
async fn calls_allow_to_unwrap_native_tokens<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let erc20_forwarder = erc20_forwarder_v1_address(&env)?;
    let generic_forwarder = generic_call_forwarder_v1_address(&env)?;
    let weth = erc20_address(&env, "weth")?;
    let provider = default_signer(&env).context("failed to retrieve default signer")?;

    let amount = 1u128;
    let amount_u256 = U256::from(amount);
    let sender = identities::alice().context("failed to build sender keychain")?;
    let recipient = identities::bob().context("failed to build recipient keychain")?;

    let before_root = commitment_root(&env)?;

    let sender_weth_before = ierc20(weth, provider.clone())
        .balanceOf(sender.address())
        .call()
        .await
        .context("failed to read sender WETH balance before wrap")?;
    let erc20_forwarder_weth_before_wrap = ierc20(weth, provider.clone())
        .balanceOf(erc20_forwarder)
        .call()
        .await
        .context("failed to read ERC20 forwarder WETH balance before wrap")?;
    let generic_forwarder_weth_before_unwrap = ierc20(weth, provider.clone())
        .balanceOf(generic_forwarder)
        .call()
        .await
        .context("failed to read generic call forwarder WETH balance before unwrap")?;
    let rand_seed = 11;

    let wrap = wrap::build(
        chain_id,
        erc20_forwarder,
        weth,
        amount,
        rand_seed,
        wrap::Overrides::default(),
    )
    .await
    .context("failed to build wrap action")?;
    let tx = prove_actions(&env, &[wrap.witnesses])
        .await
        .context("failed to prove wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute wrap action")?;

    let sender_weth_after_wrap = ierc20(weth, provider.clone())
        .balanceOf(sender.address())
        .call()
        .await
        .context("failed to read sender WETH balance after wrap")?;
    anyhow::ensure!(
        sender_weth_before - sender_weth_after_wrap == amount_u256,
        "sender WETH must decrease by wrap amount"
    );

    let erc20_forwarder_weth_after_wrap = ierc20(weth, provider.clone())
        .balanceOf(erc20_forwarder)
        .call()
        .await
        .context("failed to read ERC20 forwarder WETH balance after wrap")?;
    anyhow::ensure!(
        erc20_forwarder_weth_after_wrap - erc20_forwarder_weth_before_wrap == amount_u256,
        "ERC20 forwarder WETH must equal wrap amount"
    );

    let created_persistent_merkle_path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(wrap.created_persistent.commitment())
        .context("failed to generate transfer merkle path")?;

    let rand_seed = 17;

    let transfer = transfer::build(
        wrap.created_persistent,
        erc20_forwarder,
        weth,
        rand_seed,
        Some(created_persistent_merkle_path),
        transfer::Overrides::default(),
    )
    .context("failed to build transfer action")?;
    let tx = prove_actions(&env, &[transfer.witnesses])
        .await
        .context("failed to prove transfer action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute transfer action")?;

    let unwrap_merkle_path = env
        .protocol_adapter()
        .commitment_tree()
        .path_to(transfer.created_persistent.commitment())
        .context("failed to generate unwrap merkle path")?;

    let rand_seed = 21;

    let unwrap = unwrap::build(
        transfer.created_persistent,
        erc20_forwarder,
        weth,
        rand_seed,
        Some(unwrap_merkle_path),
        unwrap::Overrides {
            ethereum_account_addr: Some(generic_forwarder.to_vec()),
            ..unwrap::Overrides::default()
        },
    )
    .context("failed to build unwrap action")?;

    let calls = vec![
        GenericCall {
            to: weth.to_vec(),
            value: 0,
            data: WETH9::withdrawCall { wad: amount_u256 }.abi_encode(),
        },
        GenericCall {
            to: recipient.address().to_vec(),
            value: amount,
            data: Vec::new(),
        },
    ];

    let rand_seed = 31;

    let generic_call_action = generic_call::build(
        rand_seed,
        generic_forwarder.to_vec(),
        calls,
        generic_call::Overrides::default(),
    )
    .context("failed to build generic call action")?
    .witnesses;

    let tx = prove_actions(&env, &[unwrap.witnesses])
        .await
        .context("failed to prove unwrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute unwrap action")?;

    let generic_forwarder_weth_after_unwrap = ierc20(weth, provider.clone())
        .balanceOf(generic_forwarder)
        .call()
        .await
        .context("failed to read generic call forwarder WETH balance after unwrap")?;
    anyhow::ensure!(
        generic_forwarder_weth_after_unwrap - generic_forwarder_weth_before_unwrap == amount_u256,
        "generic call forwarder WETH must equal unwrap amount before generic call"
    );

    let recipient_eth_before = provider
        .get_balance(recipient.address())
        .await
        .context("failed to read recipient ETH balance before")?;

    let tx = prove_actions(&env, &[generic_call_action])
        .await
        .context("failed to prove generic call action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute generic call action")?;

    let erc20_forwarder_weth_after = ierc20(weth, provider.clone())
        .balanceOf(erc20_forwarder)
        .call()
        .await
        .context("failed to read ERC20 forwarder WETH balance after generic call")?;
    anyhow::ensure!(
        erc20_forwarder_weth_after == U256::ZERO,
        "ERC20 forwarder WETH should be zero after unwrap"
    );

    let generic_forwarder_weth_after = ierc20(weth, provider.clone())
        .balanceOf(generic_forwarder)
        .call()
        .await
        .context("failed to read generic call forwarder WETH balance after generic call")?;
    anyhow::ensure!(
        generic_forwarder_weth_after == U256::ZERO,
        "generic call forwarder WETH should be zero after withdraw"
    );

    let generic_forwarder_eth_after = provider
        .get_balance(generic_forwarder)
        .await
        .context("failed to read generic call forwarder ETH balance after generic call")?;
    anyhow::ensure!(
        generic_forwarder_eth_after == U256::ZERO,
        "generic call forwarder ETH should be zero after forwarding"
    );

    let recipient_eth_after = provider
        .get_balance(recipient.address())
        .await
        .context("failed to read recipient ETH balance after")?;
    anyhow::ensure!(
        recipient_eth_after - recipient_eth_before == amount_u256,
        "recipient ETH must increase by transfer amount"
    );

    let after_root = commitment_root(&env)?;
    anyhow::ensure!(
        before_root != after_root,
        "commitment tree root must change"
    );

    Ok(())
}
