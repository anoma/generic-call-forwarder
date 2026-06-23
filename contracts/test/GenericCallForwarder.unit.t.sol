// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Errors} from "@openzeppelin-contracts-5.6.1/interfaces/draft-IERC6093.sol";
import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Errors} from "@openzeppelin-contracts-5.6.1/utils/Errors.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {IVersion} from "anoma-forwarder-bases-1.0.0-rc.3/src/interfaces/IVersion.sol";
import {ERC20Example} from "anomapay-erc20-forwarder-1.1.0-rc.2/test/examples/ERC20.e.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {WETH} from "solady-0.1.26/src/tokens/WETH.sol";
import {SemVerLib} from "solady-0.1.26/src/utils/SemVerLib.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";
import {ReentrantCallerMock} from "./mocks/ReentrantCaller.m.sol";

contract GenericCallForwarderTest is Test {
    address internal constant _PROTOCOL_ADAPTER = address(uint160(1));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;
    bytes internal constant _EXPECTED_OUTPUT = "";

    bytes32 internal _genericCallResourceLogicRef;

    address internal _alice;

    GenericCallForwarder internal _genericCallFwd;

    WETH internal _weth;

    function setUp() public {
        _genericCallResourceLogicRef = bytes32(uint256(2));

        _alice = makeAddr("alice");

        _weth = new WETH();

        // Deploy the generic call forwarder
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _genericCallResourceLogicRef});
    }

    function test_forwardCall_with_functionCall_reverts_when_external_call_reverts() public {
        // Forwarder holds no balance; `transfer` will revert with ERC20InsufficientBalance.
        ERC20Example erc20 = new ERC20Example();

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({
            to: address(erc20), value: 0, data: abi.encodeCall(IERC20.transfer, (_alice, _TRANSFER_AMOUNT))
        });

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert(
            abi.encodeWithSelector(
                IERC20Errors.ERC20InsufficientBalance.selector, address(_genericCallFwd), 0, _TRANSFER_AMOUNT
            ),
            address(erc20)
        );
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
    }

    function test_forwardCall_with_functionCall_succeeds() public {
        ERC20Example erc20 = new ERC20Example();
        erc20.mint({to: address(_genericCallFwd), value: _TRANSFER_AMOUNT});

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({
            to: address(erc20), value: 0, data: abi.encodeCall(IERC20.transfer, (_alice, _TRANSFER_AMOUNT))
        });

        vm.prank(_PROTOCOL_ADAPTER);
        bytes memory output =
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});

        assertEq(keccak256(output), keccak256(_EXPECTED_OUTPUT));
        assertEq(erc20.balanceOf(_alice), _TRANSFER_AMOUNT);
        assertEq(erc20.balanceOf(address(_genericCallFwd)), 0);
    }

    function test_forwardCall_with_functionCallWithValue_reverts_when_target_function_is_not_payable() public {
        // `IERC20.approve` is not payable; the dispatcher reverts with empty data,
        // so OZ's helper raises `Errors.FailedCall`.
        ERC20Example erc20 = new ERC20Example();
        vm.deal(address(_genericCallFwd), 1);

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({
            to: address(erc20), value: 1, data: abi.encodeCall(IERC20.approve, (_alice, _TRANSFER_AMOUNT))
        });

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert(Errors.FailedCall.selector);
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
    }

    function test_forwardCall_with_functionCallWithValue_succeeds() public {
        vm.deal(address(_genericCallFwd), _TRANSFER_AMOUNT);

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({
            to: address(_weth), value: _TRANSFER_AMOUNT, data: abi.encodeCall(WETH.deposit, ())
        });

        vm.prank(_PROTOCOL_ADAPTER);
        bytes memory output =
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});

        assertEq(keccak256(output), keccak256(_EXPECTED_OUTPUT));
        assertEq(_weth.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(address(_genericCallFwd).balance, 0);
    }

    function test_forwardCall_with_sendValue_reverts_when_forwarder_lacks_balance() public {
        // Forwarder has no ETH but the call requests `_TRANSFER_AMOUNT`.
        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({to: _alice, value: _TRANSFER_AMOUNT, data: ""});

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert(abi.encodeWithSelector(Errors.InsufficientBalance.selector, 0, _TRANSFER_AMOUNT));
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
    }

    function test_forwardCall_with_sendValue_succeeds() public {
        vm.deal(address(_genericCallFwd), _TRANSFER_AMOUNT);

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({to: _alice, value: _TRANSFER_AMOUNT, data: ""});

        vm.prank(_PROTOCOL_ADAPTER);
        bytes memory output =
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});

        assertEq(keccak256(output), keccak256(_EXPECTED_OUTPUT));
        assertEq(_alice.balance, _TRANSFER_AMOUNT);
        assertEq(address(_genericCallFwd).balance, 0);
    }

    function test_forwardCall_reverts_on_reentrant_call() public {
        ReentrantCallerMock attacker = new ReentrantCallerMock(_genericCallFwd, _genericCallResourceLogicRef);

        // The inner payload is irrelevant; the `nonReentrant` guard reverts before it is decoded.
        GenericCallForwarder.Call[] memory innerCalls = new GenericCallForwarder.Call[](1);
        innerCalls[0] = GenericCallForwarder.Call({to: _alice, value: 0, data: ""});
        bytes memory innerInput = abi.encode(innerCalls);

        GenericCallForwarder.Call[] memory outerCalls = new GenericCallForwarder.Call[](1);
        outerCalls[0] = GenericCallForwarder.Call({
            to: address(attacker), value: 0, data: abi.encodeCall(ReentrantCallerMock.reenter, (innerInput))
        });

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert(ReentrancyGuardTransient.ReentrancyGuardReentrantCall.selector);
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(outerCalls)});
    }

    function test_forwardCall_emits_Executed_with_calls_and_results() public {
        ERC20Example erc20 = new ERC20Example();
        erc20.mint({to: address(_genericCallFwd), value: _TRANSFER_AMOUNT});

        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({
            to: address(erc20), value: 0, data: abi.encodeCall(IERC20.transfer, (_alice, _TRANSFER_AMOUNT))
        });

        bytes[] memory expectedResults = new bytes[](1);
        expectedResults[0] = abi.encode(true);

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectEmit(address(_genericCallFwd));
        emit GenericCallForwarder.Executed({calls: calls, execResults: expectedResults});
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
    }

    function test_forwardCall_reverts_with_NoOpNotAllowed_on_empty_call() public {
        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
        calls[0] = GenericCallForwarder.Call({to: _alice, value: 0, data: ""});

        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert(GenericCallForwarder.NoOpNotAllowed.selector);
        _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
    }

    function testFuzz_isValidSignature_always_returns_the_ERC1271_magic_value(bytes32 hash, bytes calldata signature)
        public
        view
    {
        assertEq(_genericCallFwd.isValidSignature(hash, signature), IERC1271.isValidSignature.selector);
    }

    function test_check_that_the_current_version_is_a_pre_release_of_v1_0_0() public view {
        int256 lt = -1;
        //int256 eq = 0;
        int256 gt = 1;

        assertEq(SemVerLib.cmp(IVersion(address(_genericCallFwd)).getVersion(), "0.0.0"), gt);
        assertEq(SemVerLib.cmp(IVersion(address(_genericCallFwd)).getVersion(), "1.0.0"), lt);
    }
}

