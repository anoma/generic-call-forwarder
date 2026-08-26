use alloy::primitives::Address;
use alloy_chains::NamedChain;
use serde::Deserialize;
use std::collections::HashMap;
use std::sync::LazyLock;

/// The deployment environment of a recorded generic call forwarder.
///
/// A release version of this crate describes both environments; a prerelease describes staging only, because
/// production trails on the previous release until the release candidate cycle ends.
#[derive(Clone, Copy, Debug, PartialEq, Eq, Hash)]
pub enum Environment {
    /// The staging environment: forwarders settling through the staging protocol adapter.
    Staging,
    /// The production environment: forwarders settling through the production protocol adapter.
    Production,
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct DeploymentEntry {
    chain_id: u64,
    contract_address: String,
}

#[derive(Deserialize)]
struct Deployments {
    staging: Vec<DeploymentEntry>,
    production: Vec<DeploymentEntry>,
}

static DEPLOYMENTS: LazyLock<HashMap<Environment, HashMap<NamedChain, Address>>> =
    LazyLock::new(|| {
        let deployments: Deployments = serde_json::from_str(include_str!("../deployments.json"))
            .expect("deployments.json: invalid JSON");

        let to_map = |entries: Vec<DeploymentEntry>| {
            entries
                .into_iter()
                .filter_map(|e| {
                    let chain = NamedChain::try_from(e.chain_id).ok()?;
                    let addr: Address = e.contract_address.parse().ok()?;
                    Some((chain, addr))
                })
                .collect()
        };

        HashMap::from([
            (Environment::Staging, to_map(deployments.staging)),
            (Environment::Production, to_map(deployments.production)),
        ])
    });

/// Returns a map of the generic call forwarder deployments recorded for the environment.
pub fn generic_call_forwarder_deployments_map(
    environment: Environment,
) -> HashMap<NamedChain, Address> {
    DEPLOYMENTS[&environment].clone()
}

/// Returns the generic call forwarder recorded for the environment on the provided chain, if any.
pub fn generic_call_forwarder_address(
    environment: Environment,
    chain: &NamedChain,
) -> Option<Address> {
    DEPLOYMENTS[&environment].get(chain).cloned()
}
