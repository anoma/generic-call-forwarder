pub const KEY_GENERIC_CALL_FORWARDER_ADDRESS: &str = "evm.forwarder.generic-call";
pub const KEY_DEX_ROUTER_ADDRESS: &str = "evm.dex-router";

#[inline]
pub fn generic_call_forwarder_addr_key() -> &'static str {
    KEY_GENERIC_CALL_FORWARDER_ADDRESS
}

#[inline]
pub fn dex_router_addr_key() -> &'static str {
    KEY_DEX_ROUTER_ADDRESS
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn generic_call_forwarder_key_format() {
        assert_eq!(
            generic_call_forwarder_addr_key(),
            "evm.forwarder.generic-call"
        );
    }
}
