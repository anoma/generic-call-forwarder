//! Generic-call action fixtures. The single [`generic_call`] kind exposes the
//! single-builder surface of testkit ADR-0003 — `build`, the derived-data
//! bundle `ActionData`, and `Overrides` with named `invalid_*` variants for negative
//! tests. The shared resource logic (verifying key + witness adapter) lives in
//! [`crate::logic`].

pub mod generic_call;
