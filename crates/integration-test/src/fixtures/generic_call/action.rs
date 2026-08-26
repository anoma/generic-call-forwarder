use anoma_generic_call_library::GenericCall;
use anoma_generic_call_library::GenericCallLogic;
use anoma_pa_testkit::witness::ActionWitnesses;
use anoma_rm_risc0::action_tree::ActionTree as ArmTree;
use anoma_rm_risc0::compliance::ComplianceWitness;
use anoma_rm_risc0::resource::{ConsumedResourceWitness, Resource};
use anyhow::Context;

use super::resource;
use super::resource::Overrides;
use crate::logic;

/// The derived data of a built generic-call action: the action witnesses
/// plus the ephemeral resources it consumes and creates.
pub struct ActionData {
    pub witnesses: ActionWitnesses,
    pub consumed_ephemeral: Resource,
    pub created_ephemeral: Resource,
}

/// Build a generic-call action: consumes an ephemeral resource whose label
/// commits to the forwarder `calls` and creates an ephemeral resource carrying
/// no calls.
pub fn build(
    seed: u8,
    forwarder_addr: Vec<u8>,
    calls: Vec<GenericCall>,
    overrides: Overrides,
) -> anyhow::Result<ActionData> {
    let created_calls: Vec<GenericCall> = Vec::new();

    let nf_key = resource::nullifier_key(seed);
    let nk_commitment = nf_key.commit();

    let consumed_ephemeral =
        resource::consumed(seed, nk_commitment, &forwarder_addr, &calls, &overrides)?;
    let consumed_nullifier = consumed_ephemeral
        .nullifier(&nf_key)
        .context("failed to compute consumed nullifier")?;
    let created_ephemeral = resource::created(
        seed,
        nk_commitment,
        consumed_nullifier,
        &forwarder_addr,
        &created_calls,
        &overrides,
    )?;

    let consumed_witness =
        ConsumedResourceWitness::from_resource(consumed_ephemeral, nf_key.clone());
    let compliance_witness = ComplianceWitness::from_resources(
        &[consumed_witness],
        &[created_ephemeral],
        resource::kind_table(),
    );

    let action_tree_root = ArmTree::new(vec![consumed_nullifier, created_ephemeral.commitment()])
        .root()
        .context("failed to compute action tree root")?;

    let consumed_logic_witness = GenericCallLogic::consumed_ephemeral_resource_logic(
        consumed_ephemeral,
        action_tree_root,
        nf_key,
        forwarder_addr.clone(),
        calls.clone(),
    )
    .witness;

    let created_logic_witness = GenericCallLogic::created_ephemeral_resource_logic(
        created_ephemeral,
        action_tree_root,
        forwarder_addr,
        created_calls,
    )
    .witness;

    let witnesses = ActionWitnesses {
        compliance_witness: Box::new(compliance_witness),
        logic_witnesses: vec![
            Box::new(logic::Witness::new(consumed_logic_witness)),
            Box::new(logic::Witness::new(created_logic_witness)),
        ],
    };

    Ok(ActionData {
        witnesses,
        consumed_ephemeral,
        created_ephemeral,
    })
}
