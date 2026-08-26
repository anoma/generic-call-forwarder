use crate::addresses::{Environment, generic_call_forwarder_address};
use crate::generated::generic_call_forwarder::GenericCallForwarder::GenericCallForwarderInstance;
use alloy::providers::{DynProvider, Provider};
use alloy_chains::NamedChain;
use serde::Serialize;
use thiserror::Error;

pub type BindingsResult<T> = Result<T, BindingsError>;

#[derive(Error, Debug, Serialize)]
pub enum BindingsError {
    #[error("The RPC transport returned an error.")]
    RpcTransportError(String),
    #[error("The chain ID {0} is not in the list of named chains.")]
    ChainIdUnknown(u64),
    #[error(
        "The current protocol adapter version has not been deployed on the provided chain '{0}'."
    )]
    UnsupportedChain(String),
}

/// Returns a generic call forwarder instance of the environment for the given provider.
pub async fn generic_call_forwarder(
    provider: &DynProvider,
    environment: Environment,
) -> BindingsResult<GenericCallForwarderInstance<DynProvider>> {
    let chain_id = provider
        .get_chain_id()
        .await
        .map_err(|err| BindingsError::RpcTransportError(err.to_string()))?;

    let named_chain =
        NamedChain::try_from(chain_id).map_err(|_| BindingsError::ChainIdUnknown(chain_id))?;

    match generic_call_forwarder_address(environment, &named_chain) {
        Some(address) => Ok(GenericCallForwarderInstance::new(address, provider.clone())),
        None => Err(BindingsError::UnsupportedChain(named_chain.to_string())),
    }
}
