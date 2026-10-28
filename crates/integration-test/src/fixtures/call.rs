//! The calls that a generic call resource has the generic call forwarder make. A call sends `value`
//! native tokens and `data` to `to`.

use alloy::primitives::Address;
use alloy::sol_types::SolCall;
use anoma_generic_call_witness::GenericCall;

/// A call of a function of `to` that sends no native tokens.
pub fn function(to: Address, call: impl SolCall) -> GenericCall {
    function_with_value(to, 0, call)
}

/// A call of a function of `to` that sends `value` native tokens.
pub fn function_with_value(to: Address, value: u128, call: impl SolCall) -> GenericCall {
    GenericCall {
        to: to.to_vec(),
        value,
        data: call.abi_encode(),
    }
}

/// A transfer of `value` native tokens to `to`, with no data.
pub fn send(to: Address, value: u128) -> GenericCall {
    GenericCall {
        to: to.to_vec(),
        value,
        data: Vec::new(),
    }
}

/// Calls of an ERC20 token.
pub mod erc20 {
    use alloy::primitives::{Address, U256};
    use anoma_generic_call_witness::GenericCall;
    use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::IERC20;

    use super::function;

    /// Lets `spender` take `amount` tokens of `token` from the generic call forwarder.
    pub fn approve(token: Address, spender: Address, amount: U256) -> GenericCall {
        function(
            token,
            IERC20::approveCall {
                spender,
                value: amount,
            },
        )
    }

    /// Sends `amount` tokens of `token` from the generic call forwarder to `to`.
    pub fn transfer(token: Address, to: Address, amount: U256) -> GenericCall {
        function(token, IERC20::transferCall { to, value: amount })
    }
}

/// Calls of the canonical Permit2.
pub mod permit2 {
    use alloy::primitives::Address;
    use alloy::primitives::aliases::{U48, U160};
    use alloy::sol;
    use anoma_generic_call_witness::GenericCall;
    use anomapay_erc20_forwarder_integration_test::deploy::permit2::PERMIT2_CANONICAL_ADDRESS;

    use super::function;

    sol! {
        interface IAllowanceTransfer {
            function approve(address token, address spender, uint160 amount, uint48 expiration) external;
        }
    }

    /// Lets `spender` take `amount` tokens of `token` from the generic call forwarder through
    /// Permit2 until `expiration`.
    pub fn approve(token: Address, spender: Address, amount: U160, expiration: U48) -> GenericCall {
        function(
            PERMIT2_CANONICAL_ADDRESS,
            IAllowanceTransfer::approveCall {
                token,
                spender,
                amount,
                expiration,
            },
        )
    }
}

/// Calls of WETH9.
pub mod weth {
    use alloy::primitives::{Address, U256};
    use anoma_generic_call_witness::GenericCall;
    use anomapay_erc20_forwarder_integration_test::deploy::erc20_bindings::WETH9;

    use super::{function, function_with_value};

    /// Turns `amount` native tokens of the generic call forwarder into WETH of `weth`.
    pub fn deposit(weth: Address, amount: u128) -> GenericCall {
        function_with_value(weth, amount, WETH9::depositCall {})
    }

    /// Turns `amount` WETH of `weth` back into native tokens of the generic call forwarder.
    pub fn withdraw(weth: Address, amount: U256) -> GenericCall {
        function(weth, WETH9::withdrawCall { wad: amount })
    }
}
