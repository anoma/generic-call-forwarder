use alloy::primitives::U256;
use alloy::providers::Provider;
use anoma_generic_call_forwarder_integration_test as it;
use anoma_pa_evm_integration_test::state::actors::default_signer;

mod common;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::{action, identities};
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::ierc20;
use anomapay_erc20_forwarder_integration_test::fixtures::token::Token;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_transfer_generic_call_e2e_env;
use common::{commitment_root, execute_tx, prove_actions, setup_transfer_generic_call_local_env};
use it::fixtures::{call, generic_call};
use rstest::*;

#[rstest]
#[case::local(setup_transfer_generic_call_local_env())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_transfer_generic_call_e2e_env()))]
#[tokio::test]
async fn execute_unwraps_native_tokens<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let weth = Token::new(&env, "weth")?;
    let gcf = generic_call::Forwarder::new(&env)?;
    let provider = default_signer(&env).context("failed to retrieve default signer")?;

    let amount = 1u128;
    let amount_u256 = U256::from(amount);
    let alice = identities::alice().context("failed to build alice's keychain")?;
    let bob = identities::bob().context("failed to build bob's keychain")?;

    let before_root = commitment_root(&env)?;

    let alice_weth_before = ierc20(weth.address(), provider.clone())
        .balanceOf(alice.address())
        .call()
        .await
        .context("failed to read alice's WETH balance before the wrap")?;
    let erc20_forwarder_weth_before = ierc20(weth.address(), provider.clone())
        .balanceOf(weth.forwarder())
        .call()
        .await
        .context("failed to read the ERC20 forwarder's WETH balance before the wrap")?;

    // 1. Alice wraps WETH into a resource of bob.
    let wrap = weth
        .wrap(&alice, amount)
        .to(&bob)
        .build(&env)
        .context("failed to build the wrap")?;
    let resource = wrap.resources()[1];
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove the wrap")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the wrap")?;

    let alice_weth_after_wrap = ierc20(weth.address(), provider.clone())
        .balanceOf(alice.address())
        .call()
        .await
        .context("failed to read alice's WETH balance after the wrap")?;
    anyhow::ensure!(
        alice_weth_before - alice_weth_after_wrap == amount_u256,
        "alice's WETH must decrease by the wrap amount"
    );
    let erc20_forwarder_weth_after_wrap = ierc20(weth.address(), provider.clone())
        .balanceOf(weth.forwarder())
        .call()
        .await
        .context("failed to read the ERC20 forwarder's WETH balance after the wrap")?;
    anyhow::ensure!(
        erc20_forwarder_weth_after_wrap - erc20_forwarder_weth_before == amount_u256,
        "the ERC20 forwarder's WETH must grow by the wrap amount"
    );

    let bob_eth_before = provider
        .get_balance(bob.address())
        .await
        .context("failed to read bob's ETH balance before the unwrap")?;

    // 2. One action, in the order of its forwarder calls: the unwrap releases bob's WETH to the
    //    generic call forwarder, and the calls turn it into native tokens and send them to bob.
    let calls = [
        call::weth::withdraw(weth.address(), amount_u256),
        call::send(bob.address(), amount),
    ];
    let unwrap = action::build(
        [
            weth.unwrap((&bob, resource))
                .to(gcf.address())
                .resources(&env)?,
            vec![
                gcf.created(calls)
                    .context("failed to build the generic call resource")?,
            ],
        ]
        .into_iter()
        .flatten(),
    )
    .context("failed to build the unwrap action")?;
    let tx = prove_actions(&env, [&unwrap])
        .await
        .context("failed to prove the unwrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the unwrap action")?;

    let erc20_forwarder_weth_after = ierc20(weth.address(), provider.clone())
        .balanceOf(weth.forwarder())
        .call()
        .await
        .context("failed to read the ERC20 forwarder's WETH balance after the unwrap")?;
    anyhow::ensure!(
        erc20_forwarder_weth_after == erc20_forwarder_weth_before,
        "the unwrap must release the WETH of the wrap"
    );
    let gcf_weth_after = ierc20(weth.address(), provider.clone())
        .balanceOf(gcf.address())
        .call()
        .await
        .context("failed to read the generic call forwarder's WETH balance after the calls")?;
    anyhow::ensure!(
        gcf_weth_after == U256::ZERO,
        "the generic call forwarder must hold no WETH after the withdrawal"
    );
    let gcf_eth_after = provider
        .get_balance(gcf.address())
        .await
        .context("failed to read the generic call forwarder's ETH balance after the calls")?;
    anyhow::ensure!(
        gcf_eth_after == U256::ZERO,
        "the generic call forwarder must hold no ETH after sending it"
    );
    let bob_eth_after = provider
        .get_balance(bob.address())
        .await
        .context("failed to read bob's ETH balance after the unwrap")?;
    anyhow::ensure!(
        bob_eth_after - bob_eth_before == amount_u256,
        "bob's ETH must grow by the unwrap amount"
    );

    let after_root = commitment_root(&env)?;
    anyhow::ensure!(
        before_root != after_root,
        "commitment tree root must change"
    );

    Ok(())
}
