#[cfg(test)]
extern crate dotenvy;

use alloy::primitives::{Address, B256, b256};
use alloy::providers::{DynProvider, Provider, ProviderBuilder};
use alloy_chains::NamedChain;
use anoma_generic_call_forwarder_bindings::generated::generic_call_forwarder;
use anoma_pa_evm_bindings::addresses::protocol_adapter_address;
use anoma_pa_evm_bindings::helpers::alchemy_url;
use anoma_generic_call_forwarder_bindings::addresses::generic_call_forwarder_deployments_map;
use anoma_generic_call_forwarder_bindings::contract::generic_call_forwarder;
use anoma_generic_call_forwarder_bindings::generated::generic_call_forwarder::GenericCallForwarder::GenericCallForwarderInstance;

// The token transfer circuit verifying key taken from
// https://github.com/anoma/generic-call-resource/blob/d42619e5225ba4bf314d32775a3c408540b63bc5/generic_call_library/src/lib.rs#L21.
const GENERIC_CALL_CIRCUIT_ID: B256 =
    b256!("9297d442214bc0f2e97125106df27b946482754e56c15fd34a6fc3c54b5deaf8");

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

        // Check that the logic ref in the deployed forwarder matches the expected one from the transfer library.
        assert_eq!(
            actual_logic_ref, GENERIC_CALL_CIRCUIT_ID,
            "Logic address mismatch on network '{chain}': expected {GENERIC_CALL_CIRCUIT_ID}, actual: {actual_logic_ref}."
        );
    }
}

#[tokio::test]
async fn versions_of_deployed_forwarders_match_the_expected_version() {
    // Iterate over all supported chains
    for chain in generic_call_forwarder_deployments_map().keys() {
        let existing_fwd = fwd_instance(chain).await;

        let current_fwd = generic_call_forwarder::GenericCallForwarder::deploy(
            existing_fwd.provider(),
            existing_fwd
                .getProtocolAdapter()
                .call()
                .await
                .expect("Couldn't get protocol adapter"),
            GENERIC_CALL_CIRCUIT_ID,
        )
        .await
        .expect("Couldn't deploy generic call forwarder");

        let expected_version = current_fwd
            .getVersion()
            .call()
            .await
            .expect("Couldn't get version");

        let actual_version: alloy::primitives::FixedBytes<32> = existing_fwd
            .getVersion()
            .call()
            .await
            .expect("Couldn't get protocol adapter version");

        //  Check that the deployed generic call forwarder version matches the expected version.
        assert_eq!(
            decode_bytes32_to_utf8(actual_version),
            decode_bytes32_to_utf8(expected_version),
            "Generic call forwarder version mismatch on network '{chain}'."
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

fn decode_bytes32_to_utf8(encoded_string: B256) -> String {
    let bytes = alloy::hex::decode(encoded_string.to_string()).expect("Couldn't decode hex string");

    let trimmed = bytes
        .split(|b| *b == 0)
        .next()
        .expect("No null byte found in bytes");
    str::from_utf8(trimmed)
        .expect("Conversion to UTF-8 failed.")
        .to_string()
}
