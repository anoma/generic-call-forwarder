//! The generic call resource, which is ephemeral. Consumed or created, its forwarder call has the
//! generic call forwarder make the calls that its value commits to.

use std::cell::Cell;

use alloy::primitives::{Address, keccak256};
use anoma_generic_call_library::GenericCallLogic;
use anoma_generic_call_witness::{
    GenericCall, calculate_label_ref, calculate_value_ref, encode_generic_call_forwarder_input,
};
use anoma_pa_testkit::environment::Environment;
use anoma_pa_testkit::fixtures::action::{ActionResource, ResourceToCreate};
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::merkle_path::MerklePath;
use anoma_rm_risc0::nullifier_key::{NullifierKey, NullifierKeyCommitment};
use anoma_rm_risc0::resource::Resource;
use anyhow::Context;

use crate::fixtures::CREATED_RAND_SEED;
use crate::logic;
use crate::state::addresses::generic_call_forwarder_address;

/// The generic call forwarder of an environment. It numbers its consumed resources, and the number
/// gives each its nonce, so a test creates one `Forwarder`.
pub struct Forwarder {
    address: Address,
    consumed: Cell<u64>,
}

impl Forwarder {
    /// The generic call forwarder that the environment records.
    pub fn new<Env: Environment>(env: &Env) -> anyhow::Result<Self> {
        Ok(Self {
            address: generic_call_forwarder_address(env)?,
            consumed: Cell::new(0),
        })
    }

    pub fn address(&self) -> Address {
        self.address
    }

    /// A consumed generic call resource whose forwarder call makes `calls`.
    pub fn consumed(
        &self,
        calls: impl IntoIterator<Item = GenericCall>,
    ) -> anyhow::Result<ActionResource> {
        let number = self.consumed.get() + 1;
        self.consumed.set(number);
        let nonce = keccak256([self.address.as_slice(), &number.to_be_bytes()].concat()).0;
        consumed(self.address, calls, nonce)
    }

    /// A created generic call resource whose forwarder call makes `calls`.
    pub fn created(
        &self,
        calls: impl IntoIterator<Item = GenericCall>,
    ) -> anyhow::Result<ActionResource> {
        created(self.address, calls)
    }
}

/// A consumed generic call resource whose forwarder call has `forwarder` make `calls`. `nonce`
/// sets its nonce, its nullifier key and its random seed.
pub fn consumed(
    forwarder: Address,
    calls: impl IntoIterator<Item = GenericCall>,
    nonce: [u8; 32],
) -> anyhow::Result<ActionResource> {
    let calls: Vec<GenericCall> = calls.into_iter().collect();
    let nf_key = NullifierKey::from_bytes(nonce);
    let resource = Resource {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref()),
        // Zero, so that the resource balances without another resource.
        quantity: 0,
        value_ref: value_ref(&calls)?,
        is_ephemeral: true,
        nonce,
        nk_commitment: nf_key.commit(),
        rand_seed: nonce,
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

/// A created generic call resource whose forwarder call has `forwarder` make `calls`.
pub fn created(
    forwarder: Address,
    calls: impl IntoIterator<Item = GenericCall>,
) -> anyhow::Result<ActionResource> {
    let calls: Vec<GenericCall> = calls.into_iter().collect();
    let resource = ResourceToCreate {
        logic_ref: logic::verifying_key(),
        label_ref: calculate_label_ref(forwarder.as_ref()),
        // Zero, so that the resource balances without another resource.
        quantity: 0,
        value_ref: value_ref(&calls)?,
        is_ephemeral: true,
        // No one consumes the resource, so any nullifier key commitment works.
        nk_commitment: NullifierKeyCommitment::default(),
        rand_seed: CREATED_RAND_SEED,
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
