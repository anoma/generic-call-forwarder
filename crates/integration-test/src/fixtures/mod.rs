//! The generic call resource, which a test lists with the resources of other applications for
//! [`anoma_pa_testkit::fixtures::action::build`], and the [`call`]s that it makes. The verifying key
//! of its logic lives in [`crate::logic`].

pub mod call;
pub mod generic_call;

/// The random seed of a created resource; its derived nonce already makes the commitment unique.
const CREATED_RAND_SEED: [u8; 32] = [0; 32];
