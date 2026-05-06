// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {SafeERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/utils/SafeERC20.sol";
import {SafeCast} from "@openzeppelin-contracts-5.6.1/utils/math/SafeCast.sol";

import {
    IAllowanceTransfer
} from "uniswap-permit2-0x000000000022D473030F116dDEE9F6B43aC78BA3/src/interfaces/IAllowanceTransfer.sol";

contract DexRouterMock {
    using SafeERC20 for IERC20;

    IAllowanceTransfer internal immutable _PERMIT2;

    constructor(address permit2) {
        _PERMIT2 = IAllowanceTransfer(permit2);
    }

    function swapExactTokensForTokens(
        uint256 amountIn,
        uint256 amountOutMin,
        address[] calldata path,
        address to,
        uint256 /*deadline*/
    ) external returns (uint256 amountOut) {
        _PERMIT2.transferFrom(msg.sender, address(this), SafeCast.toUint160(amountIn), path[0]);
        amountOut = amountOutMin;
        IERC20(path[path.length - 1]).safeTransfer(to, amountOut);
    }
}
