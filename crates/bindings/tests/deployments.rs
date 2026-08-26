use alloy::primitives::Address;
use alloy_chains::NamedChain;
use anoma_generic_call_forwarder_bindings::addresses::{
    Environment, generic_call_forwarder_address, generic_call_forwarder_deployments_map,
};
use std::collections::HashSet;

#[derive(serde::Deserialize)]
#[serde(rename_all = "camelCase")]
struct RawEntry {
    chain_id: u64,
    contract_address: String,
}

#[derive(serde::Deserialize)]
struct RawDeployments {
    staging: Vec<RawEntry>,
    production: Vec<RawEntry>,
}

fn raw_environments() -> [(Environment, Vec<RawEntry>); 2] {
    let raw: RawDeployments = serde_json::from_str(include_str!("../deployments.json"))
        .expect("deployments.json: invalid JSON");
    [
        (Environment::Staging, raw.staging),
        (Environment::Production, raw.production),
    ]
}

#[test]
fn all_entries_have_valid_chain_ids() {
    for (environment, entries) in raw_environments() {
        for entry in entries {
            NamedChain::try_from(entry.chain_id).unwrap_or_else(|_| {
                panic!(
                    "chain ID {} of environment {environment:?} does not map to a known NamedChain variant",
                    entry.chain_id
                )
            });
        }
    }
}

#[test]
fn all_entries_have_valid_addresses() {
    for (environment, entries) in raw_environments() {
        for entry in entries {
            entry
                .contract_address
                .parse::<Address>()
                .unwrap_or_else(|_| {
                    panic!(
                        "invalid contract address '{}' for chain ID '{}' of environment {environment:?}",
                        entry.contract_address, entry.chain_id
                    )
                });
        }
    }
}

#[test]
fn no_duplicate_chain_ids() {
    for (environment, entries) in raw_environments() {
        let mut seen = HashSet::new();
        for entry in &entries {
            assert!(
                seen.insert(entry.chain_id),
                "duplicate chain ID {} in environment {environment:?}",
                entry.chain_id
            );
        }
    }
}

#[test]
fn deployments_map_has_expected_count() {
    for (environment, entries) in raw_environments() {
        let map = generic_call_forwarder_deployments_map(environment);
        assert_eq!(
            map.len(),
            entries.len(),
            "deployments map size ({}) does not match JSON entries ({}) in environment {environment:?}",
            map.len(),
            entries.len()
        );
    }
}

#[test]
fn each_chain_is_individually_addressable() {
    for (environment, _) in raw_environments() {
        let map = generic_call_forwarder_deployments_map(environment);
        for chain in map.keys() {
            assert!(
                generic_call_forwarder_address(environment, chain).is_some(),
                "generic_call_forwarder_address returned None for chain '{chain}' of environment {environment:?}"
            );
        }
    }
}
