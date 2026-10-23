use anoma_generic_call_library::GenericCall;
use anoma_generic_call_library::GenericCallLogic;
use anoma_pa_testkit::witness::{ActionWitnesses, LogicWitness};
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::resource::Resource;
use anomapay_erc20_forwarder_integration_test::fixtures::action::{self, Logic, Part};

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

/// The resources of a generic call: the consumed ephemeral resource, whose
/// label commits to the forwarder calls, and the created ephemeral resource,
/// which carries no calls.
pub struct Parts {
    pub consumed: Part,
    pub created: Part,
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
    let Parts { consumed, created } = parts(seed, forwarder_addr, calls, overrides)?;
    let action = action::build(vec![consumed, created])?;
    let [consumed_ephemeral, created_ephemeral] = <[Resource; 2]>::try_from(action.resources)
        .map_err(|resources| {
            anyhow::anyhow!("a generic call has 2 resources, not {}", resources.len())
        })?;

    Ok(ActionData {
        witnesses: action.witnesses,
        consumed_ephemeral,
        created_ephemeral,
    })
}

/// The resources of a generic-call action, for an action that
/// [`action::build`] assembles from several kinds.
pub fn parts(
    seed: u8,
    forwarder_addr: Vec<u8>,
    calls: Vec<GenericCall>,
    overrides: Overrides,
) -> anyhow::Result<Parts> {
    let created_calls: Vec<GenericCall> = Vec::new();

    let nf_key = resource::nullifier_key(seed);
    let nk_commitment = nf_key.commit();

    let consumed = resource::consumed(seed, nk_commitment, &forwarder_addr, &calls, &overrides)?;
    let created = resource::created(
        seed,
        nk_commitment,
        &forwarder_addr,
        &created_calls,
        &overrides,
    )?;

    let consumed_nf_key = nf_key.clone();
    let consumed_forwarder_addr = forwarder_addr.clone();
    let consumed_logic: Logic = Box::new(
        move |resource: Resource,
              action_tree_root: Digest|
              -> anyhow::Result<Box<dyn LogicWitness>> {
            Ok(Box::new(logic::Witness::new(
                GenericCallLogic::consumed_ephemeral_resource_logic(
                    resource,
                    action_tree_root,
                    consumed_nf_key,
                    consumed_forwarder_addr,
                    calls,
                )
                .witness,
            )))
        },
    );
    let created_logic: Logic = Box::new(
        move |resource: Resource,
              action_tree_root: Digest|
              -> anyhow::Result<Box<dyn LogicWitness>> {
            Ok(Box::new(logic::Witness::new(
                GenericCallLogic::created_ephemeral_resource_logic(
                    resource,
                    action_tree_root,
                    forwarder_addr,
                    created_calls,
                )
                .witness,
            )))
        },
    );

    Ok(Parts {
        consumed: Part::Consumed {
            resource: consumed,
            nf_key,
            merkle_path: None,
            logic: consumed_logic,
        },
        created: Part::Created {
            resource: created,
            nonce: overrides.created_nonce,
            logic: created_logic,
        },
    })
}
