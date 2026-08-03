// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IForwarder} from "anoma-forwarder-bases-1.0.0/src/interfaces/IForwarder.sol";
import {INativeTokenReceiver} from "anoma-forwarder-bases-1.0.0/src/interfaces/INativeTokenReceiver.sol";
import {ERC20Forwarder} from "anomapay-erc20-forwarder-1.1.0-rc.5/src/ERC20Forwarder.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {WETH} from "solady-0.1.26/src/tokens/WETH.sol";

import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";

contract GenericCallForwarderNativeTest is Test {
    address internal constant _PROTOCOL_ADAPTER = address(uint160(1));
    address internal constant _EMERGENCY_COMMITTEE = address(uint160(2));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;
    bytes internal constant _EXPECTED_OUTPUT = "";

    bytes32 internal _erc20ResourceLogicRef;
    bytes32 internal _genericCallResourceLogicRef;

    address internal _alice;

    IForwarder internal _erc20Fwd;
    IForwarder internal _genericCallFwd;

    WETH internal _weth;

    bytes internal _defaultUnwrapInput;

    function setUp() public {
        _erc20ResourceLogicRef = bytes32(uint256(1));
        _genericCallResourceLogicRef = bytes32(uint256(2));

        _alice = makeAddr("alice");

        _weth = new WETH();

        // Deploy the forwarders
        _erc20Fwd = new ERC20Forwarder({
            protocolAdapter: _PROTOCOL_ADAPTER,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            logicRef: _erc20ResourceLogicRef
        });
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _genericCallResourceLogicRef});

        _defaultUnwrapInput = abi.encode( /* callType */
            ERC20Forwarder.CallType.Unwrap,
            /*       token */
            address(_weth),
            /*      amount */
            _TRANSFER_AMOUNT,
            /* unwrap data */
            ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
        );
    }

    function test_calls_allow_to_unwrap_native_tokens() public {
        // Fund Generic Call Forwarder with WETH
        {
            vm.deal(address(_erc20Fwd), _TRANSFER_AMOUNT);
            vm.prank(address(_erc20Fwd));
            _weth.deposit{value: _TRANSFER_AMOUNT}();
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), _TRANSFER_AMOUNT);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_alice.balance, 0);

        // Mock ERC20Forwarder call (triggered by TokenTransfer resource)
        {
            // Unwrap WETH-R into the generic call forwarder
            vm.prank(_PROTOCOL_ADAPTER);
            bytes memory output1 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: _defaultUnwrapInput});
            assertEq(keccak256(output1), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), 0);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(_alice.balance, 0);

        // Mock GenericCallForwarder call (triggered by GenericCall resource)
        {
            GenericCallForwarder.Call[] memory genericCalls = new GenericCallForwarder.Call[](2);
            // Call 1: Unwrap WETH
            genericCalls[0] = GenericCallForwarder.Call({
                to: address(_weth), value: 0, data: abi.encodeCall(WETH.withdraw, uint256(_TRANSFER_AMOUNT))
            });
            // Call 2: Transfer ETH
            genericCalls[1] = GenericCallForwarder.Call({to: _alice, value: _TRANSFER_AMOUNT, data: ""});
            bytes memory _unwrapWethAndTransferEthInput = abi.encode(genericCalls);

            vm.prank(_PROTOCOL_ADAPTER);
            vm.expectEmit(address(_genericCallFwd));
            emit INativeTokenReceiver.NativeTokenReceived({sender: address(_weth), amount: _TRANSFER_AMOUNT});

            bytes memory output2 = _genericCallFwd.forwardCall({
                logicRef: _genericCallResourceLogicRef, input: _unwrapWethAndTransferEthInput
            });
            assertEq(keccak256(output2), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(_weth.balanceOf(address(_erc20Fwd)), 0);
        assertEq(_weth.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_alice.balance, _TRANSFER_AMOUNT);
    }
}
