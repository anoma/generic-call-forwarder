#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::{Address, b256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_pa_evm_bindings::addresses::protocol_adapter_address;
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anoma_generic_call_forwarder_bindings::addresses::generic_call_forwarder_deployments_map;
use anoma_generic_call_forwarder_bindings::contract::generic_call_forwarder;
use anoma_generic_call_forwarder_bindings::generated::generic_call_forwarder::GenericCallForwarder::GenericCallForwarderInstance;

#[tokio::test]
async fn deployed_forwarders_point_to_the_current_protocol_adapter_contract() {
    // Iterate over all supported chains
    for chain in generic_call_forwarder_deployments_map().keys() {
        let fwd_referenced_protocol_adapter: Address = fwd_instance(chain)
            .await
            .getProtocolAdapter()
            .call()
            .await
            .expect("Couldn't get protocol adapter address");

        let deployed_protocol_adapter = protocol_adapter_address(chain).unwrap();

        //  Check that the referenced and deployed protocol adapter addresses match.
        assert_eq!(
            fwd_referenced_protocol_adapter, deployed_protocol_adapter,
            "Protocol adapter address mismatch on network '{chain}'."
        );
    }
}

#[tokio::test]
async fn deployed_forwarders_reference_the_expected_logic_ref() {
    // Iterate over all supported chains
    for chain in generic_call_forwarder_deployments_map().keys() {
        let actual_logic_ref = fwd_instance(chain)
            .await
            .getLogicRef()
            .call()
            .await
            .expect("Couldn't get logic ref");

        // The token transfer circuit verifying key taken from
        // TODO! MISSING LINK
        let expected_logic_ref =
            b256!("0x0000000000000000000000000000000000000000000000000000000000000000");

        // Check that the logic ref in the deployed forwarder matches the expected one from the transfer library.
        assert_eq!(
            actual_logic_ref, expected_logic_ref,
            "Logic address mismatch on network '{chain}': expected {expected_logic_ref}, actual: {actual_logic_ref}."
        );
    }
}

async fn fwd_instance(chain: &NamedChain) -> GenericCallForwarderInstance<DynProvider> {
    let rpc_url = alchemy_url(chain).unwrap();

    let provider = ProviderBuilder::new()
        .connect_anvil_with_wallet_and_config(|a| a.fork(rpc_url))
        .expect("Couldn't create anvil provider")
        .erased();
    generic_call_forwarder(&provider).await.unwrap()
}
