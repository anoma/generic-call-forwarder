//! Integration-test harness for the Anoma generic call forwarder.
//!
//! Exposes the generic-call provisioning helpers (`deploy`, `state`), the
//! resource `logic` (verifying key + witness adapter), and the action `fixtures`.
//! Scenario setups and the scenarios live under `tests/`.

pub mod deploy;
pub mod fixtures;
pub mod logic;
pub mod state;
