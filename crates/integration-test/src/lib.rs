//! Integration-test harness for the Anoma generic call forwarder.
//!
//! Exposes the generic-call provisioning helpers (`deploy`, `state`), the
//! verifying key of the resource `logic`, and the generic call resource in `fixtures`.
//! Scenario setups and the scenarios live under `tests/`.

pub mod deploy;
pub mod fixtures;
pub mod logic;
pub mod state;
