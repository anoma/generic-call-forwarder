//! Demonstrates a DEX swap routed through the generic-call forwarder: an ERC20
//! resource of token A is unwrapped into the generic-call forwarder, swapped on
//! a (mock) Uniswap-style router for token B, and wrapped back into a resource.
//!
//! Mirrors the Solidity `test_calls_allow_swapping_fund_on_a_dex` in
//! `contracts/test/GenericCallForwarder.t.sol`, but as a full integration test:
//! every step is a risc0-proven transaction executed against a local chain, and
//! the unwrap, the swap and the wrap share one action, in the order of its
//! resources.

use alloy::primitives::aliases::{U48, U160};
use alloy::primitives::{Address, U256};
use alloy::providers::Provider;
use alloy::sol;
use anoma_generic_call_forwarder_integration_test as it;
use anoma_pa_evm_integration_test::state::actors::default_signer;

mod common;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::{action, identities};
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::erc20_example;
use anomapay_erc20_forwarder_integration_test::deploy::permit2::PERMIT2_CANONICAL_ADDRESS;
use anomapay_erc20_forwarder_integration_test::fixtures::token::Token;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_dex_swap_e2e_env;
use common::{commitment_root, execute_tx, prove_actions, setup_dex_swap_local_env};
use it::fixtures::{call, generic_call};
use it::state::addresses::dex_router_address;
use rstest::*;

// The mock router leaves the deadline unnamed, so this interface names it.
sol! {
    interface IDexRouter {
        function swapExactTokensForTokens(
            uint256 amountIn,
            uint256 amountOutMin,
            address[] path,
            address to,
            uint256 deadline
        ) external returns (uint256);
    }
}

async fn erc20_balance<P: Provider + Clone>(
    token: Address,
    holder: Address,
    provider: P,
) -> anyhow::Result<U256> {
    erc20_example(token, provider)
        .balanceOf(holder)
        .call()
        .await
        .context("failed to read ERC20 balance")
}

#[rstest]
#[case::local(setup_dex_swap_local_env())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_dex_swap_e2e_env()))]
#[tokio::test]
async fn calls_allow_to_swap_erc20s_on_a_dex<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let token_a = Token::new(&env, "token_a")?;
    let token_b = Token::new(&env, "token_b")?;
    let router = dex_router_address(&env)?;
    let gcf = generic_call::Forwarder::new(&env)?;
    let provider = default_signer(&env).context("failed to retrieve default signer")?;

    let alice = identities::alice().context("failed to build alice's keychain")?;
    let bob = identities::bob().context("failed to build bob's keychain")?;

    let amount_in = 100u128;
    let amount_out = 50u128; // the mock router pays out a fixed amountOutMin

    let before_root = commitment_root(&env)?;

    // 1. Alice wraps token A into a resource of bob.
    let wrap = token_a
        .wrap(&alice, amount_in)
        .to(&bob)
        .build(&env)
        .context("failed to build the wrap of token A")?;
    let resource = wrap.resources()[1];
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove the wrap of token A")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the wrap of token A")?;

    // 2. One action, in the order of its forwarder calls: the unwrap releases bob's token A to the
    //    generic call forwarder, the calls swap it for token B, and the wrap pulls token B from the
    //    forwarder into a resource of bob.
    let calls = [
        call::erc20::approve(
            token_a.address(),
            PERMIT2_CANONICAL_ADDRESS,
            U256::from(amount_in),
        ),
        call::permit2::approve(token_a.address(), router, U160::from(amount_in), U48::MAX),
        call::function(
            router,
            IDexRouter::swapExactTokensForTokensCall {
                amountIn: U256::from(amount_in),
                amountOutMin: U256::from(amount_out),
                path: vec![token_a.address(), token_b.address()],
                to: gcf.address(),
                deadline: U256::MAX,
            },
        ),
        call::erc20::approve(
            token_b.address(),
            PERMIT2_CANONICAL_ADDRESS,
            U256::from(amount_out),
        ),
    ];
    let swap = action::build(
        [
            token_a
                .unwrap((&bob, resource))
                .to(gcf.address())
                .resources(&env)?,
            vec![
                gcf.consumed(calls)
                    .context("failed to build the generic call resource")?,
            ],
            token_b
                .wrap(&bob, amount_out)
                .from_account(gcf.address())
                .resources(&env)?,
        ]
        .into_iter()
        .flatten(),
    )
    .context("failed to build the swap action")?;
    let tx = prove_actions(&env, [&swap])
        .await
        .context("failed to prove the swap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the swap action")?;

    anyhow::ensure!(
        erc20_balance(token_a.address(), router, provider.clone()).await? == U256::from(amount_in),
        "DEX router must have pulled token A during the swap"
    );
    anyhow::ensure!(
        erc20_balance(token_a.address(), gcf.address(), provider.clone()).await? == U256::ZERO,
        "generic-call forwarder must hold no token A after the swap"
    );
    anyhow::ensure!(
        erc20_balance(token_a.address(), token_a.forwarder(), provider.clone()).await?
            == U256::ZERO,
        "ERC20 forwarder must hold no token A after the unwrap"
    );

    anyhow::ensure!(
        erc20_balance(token_b.address(), token_b.forwarder(), provider.clone()).await?
            == U256::from(amount_out),
        "ERC20 forwarder must hold token B after the wrap-back"
    );
    anyhow::ensure!(
        erc20_balance(token_b.address(), gcf.address(), provider.clone()).await? == U256::ZERO,
        "generic-call forwarder must hold no token B after the wrap-back"
    );

    let after_root = commitment_root(&env)?;
    anyhow::ensure!(
        before_root != after_root,
        "commitment tree root must change"
    );

    Ok(())
}
