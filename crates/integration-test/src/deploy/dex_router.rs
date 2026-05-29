use alloy::primitives::Address;
use alloy::providers::Provider;
use alloy::sol;
use anyhow::Context;

sol!(
    #[allow(missing_docs)]
    #[derive(Debug)]
    #[sol(rpc)]
    DexRouterMock,
    "artifacts/DexRouterMock.json"
);

/// Deploys the mock Uniswap-style DEX router used to demo swapping one ERC20 for
/// another from inside the generic-call forwarder. It pulls the input token from
/// the caller via Permit2 and pays out a fixed `amountOutMin` of the output token.
pub async fn deploy_dex_router_mock<P>(provider: P, permit2: Address) -> anyhow::Result<Address>
where
    P: Provider + Clone,
{
    let deployed = DexRouterMock::deploy(provider, permit2)
        .await
        .context("failed to deploy DexRouterMock")?;

    Ok(*deployed.address())
}
