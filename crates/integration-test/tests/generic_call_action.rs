//! Chain-free smoke tests for the generic-call action fixtures: the builder
//! produces a well-formed action (one compliance unit) for valid and
//! deliberately-invalid override variants. No prover or chain is needed.

use anoma_generic_call_forwarder_integration_test::fixtures::generic_call;
use anoma_generic_call_witness::GenericCall;

fn sample_calls() -> Vec<GenericCall> {
    vec![GenericCall {
        to: vec![0x11; 20],
        value: 7,
        data: vec![0xaa, 0xbb],
    }]
}

#[test]
fn build_produces_two_logic_witnesses() {
    let built = generic_call::build(
        1,
        vec![0x22; 20],
        sample_calls(),
        generic_call::Overrides::default(),
    )
    .expect("must build");
    assert_eq!(built.witnesses.logic_witnesses.len(), 2);
}

#[test]
fn build_with_invalid_consumed_non_ephemeral_still_builds() {
    let built = generic_call::build(
        2,
        vec![0x33; 20],
        sample_calls(),
        generic_call::Overrides::invalid_consumed_non_ephemeral(),
    )
    .expect("must build invalid action");
    assert_eq!(built.witnesses.logic_witnesses.len(), 2);
}

#[test]
fn build_with_invalid_consumed_label_ref_still_builds() {
    let built = generic_call::build(
        3,
        vec![0x44; 20],
        sample_calls(),
        generic_call::Overrides::invalid_consumed_label_ref(),
    )
    .expect("must build invalid action");
    assert_eq!(built.witnesses.logic_witnesses.len(), 2);
}
