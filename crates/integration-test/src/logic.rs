//! The generic-call resource logic: its verifying key and the [`LogicWitness`]
//! adapter over [`GenericCallWitness`] that the generic-call action feeds to the
//! prover.

use anoma_generic_call_library::GenericCallLogic;
use anoma_generic_call_witness::GenericCallWitness;
use anoma_pa_testkit::witness::LogicWitness;
use anoma_rm_risc0::Digest;
use anoma_rm_risc0::logic_instance::LogicInstance;
use anoma_rm_risc0::logic_proof::LogicProver;
use anoma_rm_risc0::resource_logic::LogicCircuit;
use anyhow::Context;

/// Verifying key (image id) of the generic-call resource logic.
#[inline]
pub fn verifying_key() -> Digest {
    GenericCallLogic::verifying_key()
}

/// Adapts a [`GenericCallWitness`] to the testkit's [`LogicWitness`] trait.
pub(crate) struct Witness {
    inner: GenericCallWitness,
}

impl Witness {
    #[inline]
    pub(crate) fn new(inner: GenericCallWitness) -> Self {
        Self { inner }
    }
}

impl LogicWitness for Witness {
    fn verifying_key(&self) -> Digest {
        verifying_key()
    }

    fn constrain(&self) -> anyhow::Result<LogicInstance> {
        LogicCircuit::constrain(&self.inner)
            .map_err(anyhow::Error::from)
            .context("invalid generic call logic witness")
    }

    fn witness_to_vec(&self) -> anyhow::Result<Vec<u32>> {
        risc0_zkvm::serde::to_vec(&self.inner)
            .context("failed to serialize generic call logic witness to risc0 words")
    }

    fn proving_key(&self) -> Vec<u8> {
        GenericCallLogic::proving_key().to_vec()
    }
}
