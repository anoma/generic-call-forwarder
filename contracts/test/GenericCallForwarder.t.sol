// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20Errors} from "@openzeppelin-contracts-5.6.1/interfaces/draft-IERC6093.sol";
import {IERC1271} from "@openzeppelin-contracts-5.6.1/interfaces/IERC1271.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Errors} from "@openzeppelin-contracts-5.6.1/utils/Errors.sol";
import {ReentrancyGuardTransient} from "@openzeppelin-contracts-5.6.1/utils/ReentrancyGuardTransient.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";
import {IForwarder} from "anoma-forwarder-bases-1.0.0-rc.2/src/interfaces/IForwarder.sol";
import {INativeTokenReceiver} from "anoma-forwarder-bases-1.0.0-rc.2/src/interfaces/INativeTokenReceiver.sol";
import {IVersion} from "anoma-forwarder-bases-1.0.0-rc.2/src/interfaces/IVersion.sol";
import {ERC20Forwarder} from "anomapay-erc20-forwarder-1.1.0-rc.1/src/ERC20Forwarder.sol";
import {ERC20ForwarderPermit2} from "anomapay-erc20-forwarder-1.1.0-rc.1/src/ERC20ForwarderPermit2.sol";
import {ERC20Example} from "anomapay-erc20-forwarder-1.1.0-rc.1/test/examples/ERC20.e.sol";
import {Permit2Signature} from "anomapay-erc20-forwarder-1.1.0-rc.1/test/libs/Permit2Signature.sol";
import {DeployPermit2} from "anomapay-erc20-forwarder-1.1.0-rc.1/test/script/DeployPermit2.s.sol";
import {Test, Vm} from "forge-std-1.16.1/src/Test.sol";

import {WETH} from "solady-0.1.26/src/tokens/WETH.sol";
import {SemVerLib} from "solady-0.1.26/src/utils/SemVerLib.sol";
import {
    IAllowanceTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IAllowanceTransfer.sol";
import {
    IPermit2,
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";

import {DexRouterMock} from "./mocks/DexRouter.m.sol";
import {ReentrantCallerMock} from "./mocks/ReentrantCaller.m.sol";

contract GenericCallForwarderTest is Test {
    using ERC20ForwarderPermit2 for ERC20ForwarderPermit2.Witness;
    using Permit2Signature for Vm;

    address internal constant _PROTOCOL_ADAPTER = address(uint160(1));
    address internal constant _EMERGENCY_COMMITTEE = address(uint160(2));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;
    bytes internal constant _EXPECTED_OUTPUT = "";
    bytes32 internal constant _ACTION_TREE_ROOT = bytes32(uint256(0));

    bytes32 internal _erc20ResourceLogicRef;
    bytes32 internal _genericCallResourceLogicRef;

    address internal _alice;
    uint256 internal _alicePrivateKey;

    IForwarder internal _erc20Fwd;
    IForwarder internal _genericCallFwd;

    IPermit2 internal _permit2;
    WETH internal _weth;

    ISignatureTransfer.PermitTransferFrom internal _defaultPermit;
    bytes32 internal _defaultPermitSigR;
    bytes32 internal _defaultPermitSigS;
    uint8 internal _defaultPermitSigV;
    bytes internal _defaultWrapInput;
    bytes internal _defaultUnwrapInput;

    function setUp() public {
        _erc20ResourceLogicRef = bytes32(uint256(1));
        _genericCallResourceLogicRef = bytes32(uint256(2));

        _alicePrivateKey = 0xc522337787f3037e9d0dcba4dc4c0e3d4eb7b1c65598d51c425574e8ce64d140;
        _alice = vm.addr(_alicePrivateKey);

        _weth = new WETH();

        // Deploy the Permit2 contract
        _permit2 = new DeployPermit2().run();

        // Deploy the generic call forwarder
        _erc20Fwd = IForwarder( // TODO! replace when anoma/anomapay-erc20-forwarder uses anoma/forwarder-bases
            address(
                new ERC20Forwarder({
                    protocolAdapter: _PROTOCOL_ADAPTER,
                    emergencyCommittee: _EMERGENCY_COMMITTEE,
                    logicRef: _erc20ResourceLogicRef
                })
            )
        );
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _genericCallResourceLogicRef});

        _defaultPermit = ISignatureTransfer.PermitTransferFrom({
            permitted: ISignatureTransfer.TokenPermissions({token: address(_weth), amount: _TRANSFER_AMOUNT}),
            nonce: 123,
            deadline: Time.timestamp() + 5 minutes
        });

        (_defaultPermitSigR, _defaultPermitSigS, _defaultPermitSigV) = vm.permitWitnessTransferFromSignature({
            domainSeparator: _permit2.DOMAIN_SEPARATOR(),
            permit: _defaultPermit,
            privateKey: _alicePrivateKey,
            spender: address(_erc20Fwd),
            witness: ERC20ForwarderPermit2.Witness(_ACTION_TREE_ROOT).hash()
        });

        _defaultWrapInput = abi.encode(
            /*       callType */
            ERC20Forwarder.CallType.Wrap,
            /*          token */
            _defaultPermit.permitted.token,
            /*         amount */
            _defaultPermit.permitted.amount,
            /*      wrap data */
            ERC20Forwarder.WrapData({
                nonce: _defaultPermit.nonce,
                deadline: _defaultPermit.deadline,
                owner: _alice,
                actionTreeRoot: _ACTION_TREE_ROOT,
                r: _defaultPermitSigR,
                s: _defaultPermitSigS,
                v: _defaultPermitSigV
            })
        );

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

    function test_calls_allow_swapping_fund_on_a_dex() public {
        uint128 minAmountOut = _TRANSFER_AMOUNT / 2;
        ERC20Example tokenA = new ERC20Example();
        ERC20Example tokenB = new ERC20Example();
        DexRouterMock dexRouter = new DexRouterMock(address(_permit2));
        tokenB.mint(address(dexRouter), minAmountOut);

        // Fund ERC20Forwarder with tokenA
        tokenA.mint(address(_erc20Fwd), _TRANSFER_AMOUNT);

        assertEq(tokenA.balanceOf(address(_erc20Fwd)), _TRANSFER_AMOUNT);
        assertEq(tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), 0);

        // Unwrap tokenA from ERC20Forwarder into GenericCallForwarder
        {
            bytes memory unwrapInput = abi.encode(
                ERC20Forwarder.CallType.Unwrap,
                address(tokenA),
                _TRANSFER_AMOUNT,
                ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
            );

            vm.prank(_PROTOCOL_ADAPTER);
            bytes memory output1 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: unwrapInput});
            assertEq(keccak256(output1), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenA.balanceOf(address(_erc20Fwd)), 0);
        assertEq(tokenA.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);

        // Swap tokenA for tokenB via MockDexRouter and approve Permit2 to pull tokenB for the subsequent wrap
        {
            uint48 expiration = uint48(Time.timestamp() + 5 minutes);

            address[] memory path = new address[](2);
            path[0] = address(tokenA);
            path[1] = address(tokenB);

            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](4);

            // 3a: Approve Permit2 to spend tokenA, then grant DEX router a Permit2 allowance to pull it
            calls[0] = GenericCallForwarder.Call({
                to: address(tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_permit2), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_permit2),
                value: 0,
                data: abi.encodeCall(
                    IAllowanceTransfer.approve,
                    (address(tokenA), address(dexRouter), uint160(_TRANSFER_AMOUNT), expiration)
                )
            });

            // 3b: Swap _TRANSFER_AMOUNT of tokenA for minAmountOut of tokenB
            calls[2] = GenericCallForwarder.Call({
                to: address(dexRouter),
                value: 0,
                data: abi.encodeCall(
                    DexRouterMock.swapExactTokensForTokens,
                    (_TRANSFER_AMOUNT, minAmountOut, path, address(_genericCallFwd), expiration)
                )
            });

            // 3c: Approve Permit2 to spend tokenB so ERC20Forwarder can wrap it via permitWitnessTransferFrom
            calls[3] = GenericCallForwarder.Call({
                to: address(tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), minAmountOut))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            bytes memory output2 =
                _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
            assertEq(keccak256(output2), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_genericCallFwd)), minAmountOut);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), 0);

        // Wrap tokenB from GenericCallForwarder into ERC20Forwarder.
        // GenericCallForwarder implements ERC-1271 and always returns the magic value, so any r, s, v bytes are valid.
        {
            bytes memory wrapTokenBInput = abi.encode(
                ERC20Forwarder.CallType.Wrap,
                address(tokenB),
                minAmountOut,
                ERC20Forwarder.WrapData({
                    nonce: 456,
                    deadline: Time.timestamp() + 5 minutes,
                    owner: address(_genericCallFwd),
                    actionTreeRoot: _ACTION_TREE_ROOT,
                    r: bytes32(0),
                    s: bytes32(0),
                    v: 27
                })
            );

            vm.prank(_PROTOCOL_ADAPTER);
            bytes memory output3 = _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: wrapTokenBInput});
            assertEq(keccak256(output3), keccak256(_EXPECTED_OUTPUT));
        }

        assertEq(tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(tokenB.balanceOf(address(_erc20Fwd)), minAmountOut);
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

    function test_isValidSignature_always_returns_the_ERC1271_magic_value() public view {
        bytes4 magic = IERC1271.isValidSignature.selector;

        assertEq(IERC1271(address(_genericCallFwd)).isValidSignature(bytes32(0), ""), magic);
        assertEq(IERC1271(address(_genericCallFwd)).isValidSignature(keccak256("anoma"), hex"cafe"), magic);
        assertEq(IERC1271(address(_genericCallFwd)).isValidSignature(bytes32(type(uint256).max), hex"00"), magic);
    }

    function test_check_that_the_current_version_is_a_pre_release_of_v1_0_0() public view {
        int256 lt = -1;
        //int256 eq = 0;
        int256 gt = 1;

        assertEq(SemVerLib.cmp(IVersion(address(_genericCallFwd)).getVersion(), "0.0.0"), gt);
        assertEq(SemVerLib.cmp(IVersion(address(_genericCallFwd)).getVersion(), "1.0.0"), lt);
    }
}

