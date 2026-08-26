// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";

import {
    IAllowanceTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IAllowanceTransfer.sol";
import {
    ISignatureTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/ISignatureTransfer.sol";

/// @notice A minimal DEX router mock swapping `amountIn` of `tokenIn` for a fixed `amountOutMin` of `tokenOut`.
/// The variants differ only in how the input token is pulled from the caller: a classic ERC-20 allowance,
/// a Permit2 allowance, or a Permit2 signature.
contract DexRouterMock {
    using SafeERC20 for IERC20;

    address internal immutable _PERMIT2;

    /// @notice The amount paid out on top of `amountOutMin`, modeling a real swap returning more than the minimum and
    /// thereby leaving residual dust in the recipient. Defaults to zero (output equals the minimum).
    uint256 internal _surplusOut;

    constructor(address permit2) {
        _PERMIT2 = permit2;
        _surplusOut = 0;
    }

    /// @notice Sets the surplus paid out on top of `amountOutMin` on subsequent swaps.
    function setSurplusOut(uint256 surplusOut) external {
        _surplusOut = surplusOut;
    }

    /// @notice Swaps pulling the input token via a classic ERC-20 allowance (`approve` + `transferFrom`).
    function swapExactTokensForTokensWithErc20Approval(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to
    ) external returns (uint256 amountOut) {
        IERC20(tokenIn).safeTransferFrom(msg.sender, address(this), amountIn);
        amountOut = amountOutMin + _surplusOut;
        IERC20(tokenOut).safeTransfer(to, amountOut);
    }

    /// @notice Swaps pulling the input token via a Permit2 allowance (`IAllowanceTransfer.approve` + `transferFrom`).
    function swapExactTokensForTokensWithPermit2Allowance(
        uint256 amountIn,
        uint256 amountOutMin,
        address tokenIn,
        address tokenOut,
        address to
    ) external returns (uint256 amountOut) {
        IAllowanceTransfer(_PERMIT2).transferFrom(msg.sender, address(this), SafeCast.toUint160(amountIn), tokenIn);
        amountOut = amountOutMin + _surplusOut;
        IERC20(tokenOut).safeTransfer(to, amountOut);
    }

    /// @notice Swaps pulling the input token via a Permit2 signature (`ISignatureTransfer.permitTransferFrom`).
    /// The input token is taken from `permit.permitted.token`.
    function swapExactTokensForTokensWithPermit2Signature(
        uint256 amountOutMin,
        address tokenOut,
        address to,
        ISignatureTransfer.PermitTransferFrom calldata permit,
        bytes calldata signature
    ) external returns (uint256 amountOut) {
        ISignatureTransfer(_PERMIT2)
            .permitTransferFrom({
            permit: permit,
            transferDetails: ISignatureTransfer.SignatureTransferDetails({
            to: address(this), requestedAmount: permit.permitted.amount
        }),
            owner: msg.sender,
            signature: signature
        });
        amountOut = amountOutMin + _surplusOut;
        IERC20(tokenOut).safeTransfer(to, amountOut);
    }
}
