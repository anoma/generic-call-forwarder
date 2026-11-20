//! The generic-call resource logic: the verifying key of its circuit.

use anoma_generic_call_library::GenericCallLogic;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::logic_proof::LogicProver;

/// Verifying key (image id) of the generic-call resource logic.
#[inline]
pub fn verifying_key() -> Digest {
    GenericCallLogic::verifying_key()
}
