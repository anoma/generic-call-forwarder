//! Generic-call action: consumes an ephemeral resource carrying the forwarder
//! calls and creates an ephemeral resource, driving arbitrary calls through the
//! generic-call forwarder.

mod action;
mod resource;

pub use action::{ActionData, build};
pub use resource::Overrides;
