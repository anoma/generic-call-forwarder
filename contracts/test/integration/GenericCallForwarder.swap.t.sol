// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {Time} from "@openzeppelin-contracts-5.6.1/utils/types/Time.sol";
import {IForwarder} from "anoma-forwarder-bases-1.0.0-rc.4/src/interfaces/IForwarder.sol";
import {ISweepable} from "anoma-forwarder-bases-1.0.0-rc.4/src/interfaces/ISweepable.sol";
import {ERC20Forwarder} from "anomapay-erc20-forwarder-1.1.0-rc.3/src/ERC20Forwarder.sol";
import {ERC20Example} from "anomapay-erc20-forwarder-1.1.0-rc.3/test/examples/ERC20.e.sol";
import {DeployPermit2} from "anomapay-erc20-forwarder-1.1.0-rc.3/test/script/DeployPermit2.s.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {
    IAllowanceTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IAllowanceTransfer.sol";
import {IPermit2} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IPermit2.sol";
import {
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/ISignatureTransfer.sol";

import {GenericCallForwarder} from "../../src/GenericCallForwarder.sol";
import {DexRouterMock} from "../mocks/DexRouter.m.sol";

contract GenericCallForwarderSwapTest is Test {
    address internal constant _PROTOCOL_ADAPTER = address(uint160(1));
    address internal constant _EMERGENCY_COMMITTEE = address(uint160(2));
    uint128 internal constant _TRANSFER_AMOUNT = 1000;
    bytes internal constant _EXPECTED_OUTPUT = "";
    bytes32 internal constant _ACTION_TREE_ROOT = bytes32(uint256(0));

    bytes32 internal _erc20ResourceLogicRef;
    bytes32 internal _genericCallResourceLogicRef;

    IForwarder internal _erc20Fwd;
    IForwarder internal _genericCallFwd;

    IPermit2 internal _permit2;

    ERC20Example internal _tokenA;
    ERC20Example internal _tokenB;
    DexRouterMock internal _dexRouter;
    uint128 internal _minAmountOut;

    function setUp() public {
        _erc20ResourceLogicRef = bytes32(uint256(1));
        _genericCallResourceLogicRef = bytes32(uint256(2));

        // Deploy the Permit2 contract
        _permit2 = new DeployPermit2().run();

        // Deploy the forwarders
        _erc20Fwd = new ERC20Forwarder({
            protocolAdapter: _PROTOCOL_ADAPTER,
            emergencyCommittee: _EMERGENCY_COMMITTEE,
            logicRef: _erc20ResourceLogicRef
        });
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _genericCallResourceLogicRef});

        // Deploy the swap tokens and the DEX router, fund the router with the output token and the ERC20 forwarder
        // with the input token, and assert the initial balances.
        _minAmountOut = _TRANSFER_AMOUNT * 4 / 5;
        _tokenA = new ERC20Example();
        _tokenB = new ERC20Example();
        _dexRouter = new DexRouterMock(address(_permit2));
        _tokenB.mint(address(_dexRouter), _minAmountOut);

        _tokenA.mint(address(_erc20Fwd), _TRANSFER_AMOUNT);

        assertEq(_tokenA.balanceOf(address(_erc20Fwd)), _TRANSFER_AMOUNT);
        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(address(_erc20Fwd)), 0);
    }

    /// @notice Swaps where the DEX router pulls the input token via a classic ERC-20 allowance
    /// (`approve` + `transferFrom`).
    function test_calls_allow_to_swap_erc20s_on_a_dex_with_erc20_approval() public {
        _unwrapTokenIntoGenericCallForwarder({token: _tokenA, amount: _TRANSFER_AMOUNT});

        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), 0);
        {
            // Approve the DEX router to spend tokenA, swap it for tokenB, and approve Permit2 to pull tokenB for the
            // wrap.
            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](3);
            calls[0] = GenericCallForwarder.Call({
                to: address(_tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_dexRouter), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_dexRouter),
                value: 0,
                data: abi.encodeCall(
                    DexRouterMock.swapExactTokensForTokensWithErc20Approval,
                    (_TRANSFER_AMOUNT, _minAmountOut, address(_tokenA), address(_tokenB), address(_genericCallFwd))
                )
            });
            calls[2] = GenericCallForwarder.Call({
                to: address(_tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), _minAmountOut))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
        }
        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), _minAmountOut);

        _wrapTokenFromGenericCallForwarder({token: _tokenB, amount: _minAmountOut});
    }

    /// @notice Swaps where the DEX router pulls the input token via a Permit2 allowance
    /// (`IAllowanceTransfer.approve` + `transferFrom`).
    function test_calls_allow_to_swap_erc20s_on_a_dex_with_permit2_allowance() public {
        _unwrapTokenIntoGenericCallForwarder({token: _tokenA, amount: _TRANSFER_AMOUNT});

        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), 0);
        {
            // Approve Permit2 to spend tokenA, grant the DEX router a Permit2 allowance to pull it, swap it for tokenB,
            // and approve Permit2 to pull tokenB for the subsequent wrap.
            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](4);
            calls[0] = GenericCallForwarder.Call({
                to: address(_tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_permit2), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_permit2),
                value: 0,
                data: abi.encodeCall(
                    IAllowanceTransfer.approve,
                    (address(_tokenA), address(_dexRouter), uint160(_TRANSFER_AMOUNT), uint48(_swapDeadline()))
                )
            });
            calls[2] = GenericCallForwarder.Call({
                to: address(_dexRouter),
                value: 0,
                data: abi.encodeCall(
                    DexRouterMock.swapExactTokensForTokensWithPermit2Allowance,
                    (_TRANSFER_AMOUNT, _minAmountOut, address(_tokenA), address(_tokenB), address(_genericCallFwd))
                )
            });
            calls[3] = GenericCallForwarder.Call({
                to: address(_tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), _minAmountOut))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
        }
        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), _minAmountOut);

        _wrapTokenFromGenericCallForwarder({token: _tokenB, amount: _minAmountOut});
    }

    /// @notice Swaps where the DEX router pulls the input token via a Permit2 signature
    /// (`ISignatureTransfer.permitTransferFrom`). The owner is the generic call forwarder, whose ERC-1271
    /// implementation accepts any signature, so an empty signature is passed.
    function test_calls_allow_to_swap_erc20s_on_a_dex_with_permit2_signature() public {
        _unwrapTokenIntoGenericCallForwarder({token: _tokenA, amount: _TRANSFER_AMOUNT});

        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), _TRANSFER_AMOUNT);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), 0);
        {
            // Approve Permit2 to spend tokenA, swap it for tokenB pulling via a Permit2 signature, and approve Permit2
            // to pull tokenB for the subsequent wrap.
            ISignatureTransfer.PermitTransferFrom memory permit = ISignatureTransfer.PermitTransferFrom({
                permitted: ISignatureTransfer.TokenPermissions({token: address(_tokenA), amount: _TRANSFER_AMOUNT}),
                nonce: 789,
                deadline: _swapDeadline()
            });

            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](3);
            calls[0] = GenericCallForwarder.Call({
                to: address(_tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_permit2), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_dexRouter),
                value: 0,
                data: abi.encodeCall(
                    DexRouterMock.swapExactTokensForTokensWithPermit2Signature,
                    (_minAmountOut, address(_tokenB), address(_genericCallFwd), permit, "")
                )
            });
            calls[2] = GenericCallForwarder.Call({
                to: address(_tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), _minAmountOut))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
        }
        assertEq(_tokenA.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), _minAmountOut);

        _wrapTokenFromGenericCallForwarder({token: _tokenB, amount: _minAmountOut});
    }

    /// @notice A swap returning more than the committed minimum leaves the surplus as residual dust in the generic
    /// call forwarder, which can be swept out with a generic `withdraw` call after the wrap.
    function test_calls_allow_to_withdraw_residual_after_swap() public {
        uint128 surplus = _TRANSFER_AMOUNT / 5;
        address residualRecipient = makeAddr("residualRecipient");

        // Make the DEX pay out `surplus` more than the minimum and fund it to cover the larger payout.
        _dexRouter.setSurplusOut(surplus);
        _tokenB.mint(address(_dexRouter), surplus);

        _unwrapTokenIntoGenericCallForwarder({token: _tokenA, amount: _TRANSFER_AMOUNT});

        // Approve the DEX router to spend tokenA, swap it for tokenB, and approve Permit2 to pull the committed
        // `_minAmountOut` for the wrap.
        {
            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](3);
            calls[0] = GenericCallForwarder.Call({
                to: address(_tokenA),
                value: 0,
                data: abi.encodeCall(IERC20.approve, (address(_dexRouter), _TRANSFER_AMOUNT))
            });
            calls[1] = GenericCallForwarder.Call({
                to: address(_dexRouter),
                value: 0,
                data: abi.encodeCall(
                    DexRouterMock.swapExactTokensForTokensWithErc20Approval,
                    (_TRANSFER_AMOUNT, _minAmountOut, address(_tokenA), address(_tokenB), address(_genericCallFwd))
                )
            });
            calls[2] = GenericCallForwarder.Call({
                to: address(_tokenB), value: 0, data: abi.encodeCall(IERC20.approve, (address(_permit2), _minAmountOut))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
        }
        // The forwarder received more tokenB than the committed minimum.
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), _minAmountOut + surplus);

        // Wrap the committed `_minAmountOut` back into the ERC20 forwarder, leaving `surplus` as residual dust.
        _wrapTokenFromGenericCallForwarder({token: _tokenB, amount: _minAmountOut});

        assertEq(_tokenB.balanceOf(address(_erc20Fwd)), _minAmountOut);
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), surplus);
        assertEq(_tokenB.balanceOf(residualRecipient), 0);

        // Sweep the residual dust out to a recipient via a generic call.
        {
            GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](1);
            calls[0] = GenericCallForwarder.Call({
                to: address(_genericCallFwd),
                value: 0,
                data: abi.encodeCall(ISweepable.sweep, (address(_tokenB), residualRecipient))
            });

            vm.prank(_PROTOCOL_ADAPTER);
            _genericCallFwd.forwardCall({logicRef: _genericCallResourceLogicRef, input: abi.encode(calls)});
        }
        assertEq(_tokenB.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_tokenB.balanceOf(residualRecipient), surplus);
    }

    /// @notice Unwraps `_TRANSFER_AMOUNT` of `token` from the ERC20 forwarder into the generic call forwarder
    /// (triggered by an ERC20 resource) and returns the forwarder output.
    function _unwrapTokenIntoGenericCallForwarder(ERC20Example token, uint256 amount) internal {
        assertEq(token.balanceOf(address(_erc20Fwd)), amount);

        bytes memory unwrapInput = abi.encode(
            ERC20Forwarder.CallType.Unwrap,
            address(token),
            amount,
            ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
        );

        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: unwrapInput});

        assertEq(token.balanceOf(address(_erc20Fwd)), 0);
    }

    /// @notice Wraps `amount` of `token` from the generic call forwarder into the ERC20 forwarder (triggered by an
    /// ERC20 resource) and returns the forwarder output.
    /// @dev The generic call forwarder implements ERC-1271 and always returns the magic value, so any `r, s, v` bytes
    /// are valid.
    function _wrapTokenFromGenericCallForwarder(ERC20Example token, uint128 amount) internal {
        bytes memory wrapInput = abi.encode(
            ERC20Forwarder.CallType.Wrap,
            address(token),
            amount,
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
        _erc20Fwd.forwardCall({logicRef: _erc20ResourceLogicRef, input: wrapInput});
    }

    /// @notice The deadline shared by the swap calls.
    function _swapDeadline() internal view returns (uint256 deadline) {
        deadline = Time.timestamp() + 5 minutes;
    }
}
