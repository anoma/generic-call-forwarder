//! The generic call resource, which is ephemeral. Consumed or created, its forwarder call has the
//! generic call forwarder make the calls that its value commits to.

use alloy::primitives::Address;
use anoma_generic_call_library::GenericCallLogic;
use anoma_generic_call_witness::{
    GenericCall, calculate_label_ref, calculate_value_ref, encode_generic_call_forwarder_input,
};
use anoma_pa_testkit::fixtures::action::{ActionResource, ResourceToCreate};
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::nullifier_key::{NullifierKey, NullifierKeyCommitment};
use anoma_rm_risc0::resource::Resource;
use anyhow::Context;

use crate::logic;

/// A consumed generic call resource whose forwarder call has `forwarder` make `calls`. `seed`
/// sets its nonce, its nullifier key and its random fields.
pub fn consumed(
    forwarder: Address,
    calls: Vec<GenericCall>,
    seed: u8,
) -> anyhow::Result<ActionResource> {
    let nf_key = NullifierKey::from_bytes([seed; 32]);
    let resource = Resource {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref()),
        // Zero, so that the resource balances without another resource.
        quantity: 0,
        value_ref: value_ref(&calls)?,
        is_ephemeral: true,
        nonce: [seed; 32],
        nk_commitment: nf_key.commit(),
        rand_seed: [seed; 32],
    };
    let logic_nf_key = nf_key.clone();
    Ok(ActionResource::consumed(
        resource,
        nf_key,
        MerklePath::empty(),
        move |resource, action_tree_root| {
            Ok(GenericCallLogic::consumed_ephemeral_resource_logic(
                resource,
                action_tree_root,
                logic_nf_key,
                forwarder.to_vec(),
                calls,
            ))
        },
    ))
}

/// A created generic call resource whose forwarder call has `forwarder` make `calls`. `seed` sets
/// its random fields.
pub fn created(
    forwarder: Address,
    calls: Vec<GenericCall>,
    seed: u8,
) -> anyhow::Result<ActionResource> {
    let resource = ResourceToCreate {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref()),
        // Zero, so that the resource balances without another resource.
        quantity: 0,
        value_ref: value_ref(&calls)?,
        is_ephemeral: true,
        // No one consumes the resource, so any nullifier key commitment works.
        nk_commitment: NullifierKeyCommitment::default(),
        rand_seed: [seed; 32],
    };
    Ok(ActionResource::created(
        resource,
        move |resource, action_tree_root| {
            Ok(GenericCallLogic::created_ephemeral_resource_logic(
                resource,
                action_tree_root,
                forwarder.to_vec(),
                calls,
            ))
        },
    ))
}

fn value_ref(calls: &[GenericCall]) -> anyhow::Result<Digest> {
    let encoded_calls =
        encode_generic_call_forwarder_input(calls).context("failed to encode the generic calls")?;
    Ok(calculate_value_ref(&encoded_calls))
}
