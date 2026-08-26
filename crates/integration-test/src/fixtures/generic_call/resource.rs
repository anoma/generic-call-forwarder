use anoma_generic_call_witness::GenericCall;
use anoma_generic_call_witness::calculate_label_ref;
use anoma_generic_call_witness::calculate_value_ref;
use anoma_generic_call_witness::encode_generic_call_forwarder_input;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::nullifier_key::NullifierKey;
use anoma_rm_risc0::nullifier_key::NullifierKeyCommitment;
use anoma_rm_risc0::resource::Resource;
use anyhow::Context;

use crate::logic;

#[derive(Clone, Debug, Default)]
pub struct Overrides {
    pub consumed_quantity: Option<u128>,
    pub created_quantity: Option<u128>,
    pub consumed_value_ref: Option<Digest>,
    pub created_value_ref: Option<Digest>,
    pub consumed_label_ref: Option<Digest>,
    pub created_label_ref: Option<Digest>,
    pub consumed_is_ephemeral: Option<bool>,
    pub created_is_ephemeral: Option<bool>,
    pub consumed_nonce: Option<[u8; 32]>,
    pub created_nonce: Option<[u8; 32]>,
}

impl Overrides {
    pub fn invalid_consumed_non_ephemeral() -> Self {
        Self {
            consumed_is_ephemeral: Some(false),
            ..Self::default()
        }
    }

    pub fn invalid_created_non_ephemeral() -> Self {
        Self {
            created_is_ephemeral: Some(false),
            ..Self::default()
        }
    }

    pub fn invalid_consumed_label_ref() -> Self {
        Self {
            consumed_label_ref: Some(Digest::default()),
            ..Self::default()
        }
    }
}

pub(super) fn consumed(
    seed: u8,
    nk_commitment: NullifierKeyCommitment,
    forwarder_addr: &[u8],
    calls: &[GenericCall],
    overrides: &Overrides,
) -> anyhow::Result<Resource> {
    let encoded_calls =
        encode_generic_call_forwarder_input(calls).context("failed to encode generic calls")?;

    let value_ref = overrides
        .consumed_value_ref
        .unwrap_or(calculate_value_ref(&encoded_calls));

    let label_ref = overrides
        .consumed_label_ref
        .unwrap_or(calculate_label_ref(forwarder_addr));

    Ok(Resource {
        logic_ref: logic::verifying_key(),
        label_ref,
        quantity: overrides.consumed_quantity.unwrap_or(0),
        value_ref,
        is_ephemeral: overrides.consumed_is_ephemeral.unwrap_or(true),
        nonce: overrides.consumed_nonce.unwrap_or([seed; 32]),
        nk_commitment,
        rand_seed: [seed.wrapping_add(11); 32],
    })
}

pub(super) fn created(
    seed: u8,
    nk_commitment: NullifierKeyCommitment,
    consumed_nullifier: Digest,
    forwarder_addr: &[u8],
    calls: &[GenericCall],
    overrides: &Overrides,
) -> anyhow::Result<Resource> {
    let encoded_calls =
        encode_generic_call_forwarder_input(calls).context("failed to encode generic calls")?;

    let value_ref = overrides
        .created_value_ref
        .unwrap_or(calculate_value_ref(&encoded_calls));

    let label_ref = overrides
        .created_label_ref
        .unwrap_or(calculate_label_ref(forwarder_addr));

    let default_nonce: [u8; 32] = consumed_nullifier
        .as_bytes()
        .try_into()
        .context("nullifier must be 32 bytes")?;

    Ok(Resource {
        logic_ref: logic::verifying_key(),
        label_ref,
        quantity: overrides.created_quantity.unwrap_or(0),
        value_ref,
        is_ephemeral: overrides.created_is_ephemeral.unwrap_or(true),
        nonce: overrides.created_nonce.unwrap_or(default_nonce),
        nk_commitment,
        rand_seed: [seed.wrapping_add(33); 32],
    })
}

pub(super) fn nullifier_key(seed: u8) -> NullifierKey {
    NullifierKey::from_bytes([seed; 32])
}
