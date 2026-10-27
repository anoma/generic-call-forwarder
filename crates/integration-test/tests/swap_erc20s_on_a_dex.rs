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
use alloy::sol;
use alloy::sol_types::SolCall;
use anoma_generic_call_forwarder_integration_test as it;
use anoma_pa_evm_integration_test::state::actors::default_signer;

mod common;
use anoma_pa_evm_integration_test::keychain::EvmSigner;
use anoma_pa_evm_integration_test::state::chains::chain_id;
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::{action, identities};
use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::{
    deploy_and_mint_example_erc20, erc20_example,
};
use anomapay_erc20_forwarder_integration_test::deploy::permit2::PERMIT2_CANONICAL_ADDRESS;
use anomapay_erc20_forwarder_integration_test::fixtures::{ephemeral, persistent};
use anomapay_erc20_forwarder_integration_test::state::forwarder::erc20_forwarder_address;
use anyhow::Context;
#[cfg(feature = "e2e")]
use common::setup_transfer_generic_call_e2e_env;
use common::{
    commitment_path, commitment_root, execute_tx, prove_actions,
    setup_transfer_generic_call_local_env,
};
use it::deploy::dex_router::deploy_dex_router_mock;
use it::fixtures::generic_call;
use it::state::addresses::generic_call_forwarder_address;
use rstest::*;

use anoma_generic_call_witness::GenericCall;

// Calldata interfaces for the calls the generic-call forwarder makes during the
// swap. Only the function selectors matter for encoding, so these are declared
// locally rather than pulled from full contract bindings.
sol! {
    interface IErc20 {
        function approve(address spender, uint256 amount) external returns (bool);
    }
    interface IPermit2 {
        function approve(address token, address spender, uint160 amount, uint48 expiration) external;
    }
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

async fn erc20_balance<P: alloy::providers::Provider + Clone>(
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
#[case::local(setup_transfer_generic_call_local_env())]
#[cfg_attr(feature = "e2e", case::e2e_test(setup_transfer_generic_call_e2e_env()))]
#[tokio::test]
async fn calls_allow_to_swap_erc20s_on_a_dex<Env: Environment>(
    #[future(awt)]
    #[case]
    env_with_setup: anyhow::Result<Env>,
) -> anyhow::Result<()> {
    let mut env = env_with_setup.context("env setup failed")?;
    let chain_id = chain_id(&env)?;
    let erc20_forwarder = erc20_forwarder_address(&env)?;
    let generic_forwarder = generic_call_forwarder_address(&env)?;
    let provider = default_signer(&env).context("failed to retrieve default signer")?;

    let sender = identities::alice().context("failed to build sender keychain")?;
    let receiver = identities::bob().context("failed to build receiver keychain")?;

    let amount_in = 100u128;
    let amount_out = 50u128; // the mock router pays out a fixed amountOutMin
    let amount_in_u256 = U256::from(amount_in);
    let amount_out_u256 = U256::from(amount_out);

    // Deploy token A (minted to the wrapper), the DEX router, and token B (minted
    // to the router so it can pay out the swap).
    let token_a = deploy_and_mint_example_erc20(provider.clone(), sender.address(), amount_in_u256)
        .await
        .context("failed to deploy token A")?;
    let dex_router = deploy_dex_router_mock(provider.clone(), PERMIT2_CANONICAL_ADDRESS)
        .await
        .context("failed to deploy DEX router")?;
    let token_b = deploy_and_mint_example_erc20(provider.clone(), dex_router, amount_out_u256)
        .await
        .context("failed to deploy token B")?;

    // The wrapper grants Permit2 an allowance so the wrap can pull token A.
    erc20_example(token_a, provider.clone())
        .approve(PERMIT2_CANONICAL_ADDRESS, U256::MAX)
        .send()
        .await
        .context("failed to submit token A Permit2 approval")?
        .get_receipt()
        .await
        .context("failed to fetch token A Permit2 approval receipt")?;

    let before_root = commitment_root(&env)?;

    // 1. Wrap token A into a shielded resource.
    let wrap = action::build([
        ephemeral::consumed(
            &sender,
            chain_id,
            erc20_forwarder,
            token_a,
            amount_in,
            11,
            ephemeral::Overrides::default(),
        ),
        persistent::created(&sender, erc20_forwarder, token_a, amount_in, 12),
    ])
    .context("failed to build token A wrap action")?;
    let tx = prove_actions(&env, [&wrap])
        .await
        .context("failed to prove token A wrap action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute token A wrap action")?;

    // 2. Transfer the resource (sender -> receiver) so the receiver can unwrap it.
    let wrapped = wrap.resources()[1];
    let transfer_path = commitment_path(&env, wrapped.commitment())
        .context("failed to generate transfer merkle path")?;
    let transfer = action::build([
        persistent::consumed(&sender, wrapped, transfer_path, None),
        persistent::created(&receiver, erc20_forwarder, token_a, wrapped.quantity, 17),
    ])
    .context("failed to build transfer action")?;
    let tx = prove_actions(&env, [&transfer])
        .await
        .context("failed to prove transfer action")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute transfer action")?;

    // 3. Unwrap token A into the generic-call forwarder, swap it for token B, and wrap token B back, in one
    //    action. The protocol adapter runs the calls in the order of its resources: the unwrap, the generic call,
    //    the wrap.
    //
    //    The generic call, from inside the forwarder, approves Permit2 and the router to pull token A, swaps token A
    //    for token B (paid back to the forwarder), and approves Permit2 to spend token B for the wrap.
    let expiration = U48::from(4_294_967_295u64);
    let calls = vec![
        GenericCall {
            to: token_a.to_vec(),
            value: 0,
            data: IErc20::approveCall {
                spender: PERMIT2_CANONICAL_ADDRESS,
                amount: amount_in_u256,
            }
            .abi_encode(),
        },
        GenericCall {
            to: PERMIT2_CANONICAL_ADDRESS.to_vec(),
            value: 0,
            data: IPermit2::approveCall {
                token: token_a,
                spender: dex_router,
                amount: U160::from(amount_in),
                expiration,
            }
            .abi_encode(),
        },
        GenericCall {
            to: dex_router.to_vec(),
            value: 0,
            data: IDexRouter::swapExactTokensForTokensCall {
                amountIn: amount_in_u256,
                amountOutMin: amount_out_u256,
                path: vec![token_a, token_b],
                to: generic_forwarder,
                deadline: U256::from(4_294_967_295u64),
            }
            .abi_encode(),
        },
        GenericCall {
            to: token_b.to_vec(),
            value: 0,
            data: IErc20::approveCall {
                spender: PERMIT2_CANONICAL_ADDRESS,
                amount: amount_out_u256,
            }
            .abi_encode(),
        },
    ];

    let transferred = transfer.resources()[1];
    let unwrap_path = commitment_path(&env, transferred.commitment())
        .context("failed to generate unwrap merkle path")?;

    // The forwarder authorizes the Permit2 pull of the wrap via ERC-1271, so the permit signature is an accepted
    // 65-byte placeholder.
    let mut dummy_permit_sig = vec![0u8; 65];
    dummy_permit_sig[64] = 27;

    let swap_action = action::build([
        persistent::consumed(&receiver, transferred, unwrap_path, None),
        ephemeral::created(
            generic_forwarder,
            erc20_forwarder,
            token_a,
            transferred.quantity,
            21,
        ),
        generic_call::consumed(generic_forwarder, calls, 31)
            .context("failed to build the consumed generic call resource")?,
        generic_call::created(generic_forwarder, Vec::new(), 32)
            .context("failed to build the created generic call resource")?,
        ephemeral::consumed(
            &receiver,
            chain_id,
            erc20_forwarder,
            token_b,
            amount_out,
            41,
            ephemeral::Overrides {
                ethereum_account_addr: Some(generic_forwarder),
                permit_signature: Some(dummy_permit_sig),
            },
        ),
        persistent::created(&receiver, erc20_forwarder, token_b, amount_out, 42),
    ])
    .context("failed to build the swap action")?;
    let tx = prove_actions(&env, [&swap_action])
        .await
        .context("failed to prove the swap transaction")?;
    execute_tx(&mut env, tx)
        .await
        .context("failed to execute the swap transaction")?;

    anyhow::ensure!(
        erc20_balance(token_a, dex_router, provider.clone()).await? == amount_in_u256,
        "DEX router must have pulled token A during the swap"
    );
    anyhow::ensure!(
        erc20_balance(token_a, generic_forwarder, provider.clone()).await? == U256::ZERO,
        "generic-call forwarder must hold no token A after the swap"
    );
    anyhow::ensure!(
        erc20_balance(token_a, erc20_forwarder, provider.clone()).await? == U256::ZERO,
        "ERC20 forwarder must hold no token A after the unwrap"
    );

    anyhow::ensure!(
        erc20_balance(token_b, erc20_forwarder, provider.clone()).await? == amount_out_u256,
        "ERC20 forwarder must hold token B after the wrap-back"
    );
    anyhow::ensure!(
        erc20_balance(token_b, generic_forwarder, provider.clone()).await? == U256::ZERO,
        "generic-call forwarder must hold no token B after the wrap-back"
    );

    let after_root = commitment_root(&env)?;
    anyhow::ensure!(
        before_root != after_root,
        "commitment tree root must change"
    );

    Ok(())
}
