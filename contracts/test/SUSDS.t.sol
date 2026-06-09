// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {IERC4626} from "@openzeppelin-contracts-5.6.1/interfaces/IERC4626.sol";
import {IERC20} from "@openzeppelin-contracts-5.6.1/token/ERC20/IERC20.sol";
import {IForwarder} from "anoma-forwarder-bases-1.0.0-rc.2/src/interfaces/IForwarder.sol";
import {ERC20Forwarder} from "anomapay-erc20-forwarder-1.1.0-rc.1/src/ERC20Forwarder.sol";
import {Test} from "forge-std-1.16.1/src/Test.sol";

import {GenericCallForwarder} from "../src/GenericCallForwarder.sol";

/// @notice Sky's `sUSDS` savings vault surface used by these tests: the ERC-4626 entrypoints plus the
///         Sky Savings Rate accumulator (`ssr`/`chi`/`rho`) that makes the share price a pure function of time.
interface ISUsds is IERC4626 {
    /// @notice The Sky Savings Rate: the per-second multiplier by which `chi` grows.
    /// @return rate The per-second rate as a RAY-scaled multiplier (`1e27` == 0% APY; anything above accrues yield).
    function ssr() external view returns (uint256 rate);

    /// @notice The rate accumulator: the USDS value of one sUSDS share, as last settled by `drip`.
    /// @return accumulator The assets-per-share conversion factor in RAY; rises monotonically with elapsed time.
    function chi() external view returns (uint256 accumulator);

    /// @notice The timestamp at which `chi` was last updated by `drip`.
    /// @return timestamp The Unix time of the last accrual; `chi` must be projected from here to `block.timestamp`.
    function rho() external view returns (uint256 timestamp);
}

/// @notice Sky's LitePSM wrapper surface: a fixed-rate swap between the gem (USDC, 6 decimals) and USDS.
interface ILitePsm {
    /// @notice Swaps `gemAmt` of the gem (USDC) for USDS, minting the USDS to `usr`.
    /// @dev Pulls `gemAmt` USDC from the caller and sends the USDS to `usr`, where
    ///      `usdsOutWad = gemAmt * to18ConversionFactor * (WAD - tin) / WAD`.
    /// @param usr The recipient of the minted USDS.
    /// @param gemAmt The amount of gem (USDC, 6 decimals) to sell.
    /// @return usdsOutWad The amount of USDS (18 decimals) minted to `usr`, net of the `tin` fee.
    function sellGem(address usr, uint256 gemAmt) external returns (uint256 usdsOutWad);

    /// @notice The fee charged when selling the gem for USDS (the gem -> USDS direction).
    /// @return fee The fee as a WAD-scaled fraction (`1e18` == 100%); `0` means no fee.
    function tin() external view returns (uint256 fee);

    /// @notice The factor scaling the 6-decimal gem amount up to USDS's 18 decimals.
    /// @return factor The multiplier applied to `gemAmt` (`1e12` for a 6-decimal gem against 18-decimal USDS).
    function to18ConversionFactor() external view returns (uint256 factor);
}

/// @title sUSDS mint-and-wrap fork tests
/// @notice Mints sUSDS from USDS (or USDC) inside the GenericCallForwarder and wraps it into an ERC20 resource,
///         against the real Sky deployment on a mainnet fork. The point of interest is determinism: the protocol
///         adapter executes everything in one atomic transaction with all amounts fixed off-chain, yet sUSDS's share
///         price accrues with `block.timestamp`. We commit the wrap amount to the price projected at the action's
///         *deadline* (the worst case), which the Permit2 signature deadline already caps inclusion to, so the wrap is
///         always satisfiable. The `forwardCall`s stay in the test bodies; the helpers only build their `input` bytes.
contract SUsdsForkTest is Test {
    // Canonical mainnet deployments.
    address internal constant _USDS = 0xdC035D45d973E3EC169d2276DDab16f1e407384F;
    address internal constant _SUSDS = 0xa3931d71877C0E7a3148CB7Eb4463524FEc27fbD;
    address internal constant _USDC = 0xA0b86991c6218b36c1d19D4a2e9Eb0cE3606eB48;
    address internal constant _PSM = 0xA188EEC8F81263234dA3622A406892F3D630f98c; // LitePSMWrapper-USDS-USDC
    address internal constant _PERMIT2 = 0x000000000022D473030F116dDEE9F6B43aC78BA3;

    uint256 internal constant _RAY = 1e27;
    uint256 internal constant _WAD = 1e18;

    // Pinned for deterministic CI; needs an archive RPC (override locally with MAINNET_RPC_URL / MAINNET_FORK_BLOCK).
    uint256 internal constant _FORK_BLOCK = 25_278_600;

    // Test actors and resource logic references (opaque to these tests).
    address internal constant _PROTOCOL_ADAPTER = address(uint160(1));
    address internal constant _EMERGENCY_COMMITTEE = address(uint160(2));
    bytes32 internal constant _ERC20_LOGIC_REF = bytes32(uint256(1));
    bytes32 internal constant _GENERIC_CALL_LOGIC_REF = bytes32(uint256(2));
    bytes32 internal constant _ACTION_TREE_ROOT = bytes32(uint256(0));

    uint256 internal constant _AMOUNT = 1000e18; // 1000 USDS deposited / minted in the USDS-route tests
    uint256 internal constant _WINDOW = 1 hours; // action validity window: now .. deadline
    uint256 internal constant _EARLY = 5 minutes; // an inclusion time comfortably before the deadline
    uint256 internal constant _WRAP_NONCE = 456; // any unused Permit2 nonce for the wrap

    /// @dev `_projectChi` was asked to project `chi` to a time before the last `drip`.
    error TimestampBeforeRho(uint256 timestamp, uint256 rho);

    IForwarder internal _erc20Fwd;
    IForwarder internal _genericCallFwd;

    IERC20 internal _usds = IERC20(_USDS);
    IERC20 internal _usdc = IERC20(_USDC);
    ISUsds internal _sUsds = ISUsds(_SUSDS);
    ILitePsm internal _psm = ILitePsm(_PSM);

    function setUp() public {
        // Skip (rather than error) when no mainnet RPC is configured, so a plain `forge test` stays green offline.
        string memory rpc = vm.envOr("MAINNET_RPC_URL", string(""));
        if (bytes(rpc).length == 0) {
            if (bytes(vm.envOr("ALCHEMY_API_KEY", string(""))).length == 0) {
                vm.skip(true);
                return;
            }
            rpc = "mainnet"; // resolve via foundry.toml [rpc_endpoints]
        }
        vm.createSelectFork(rpc, vm.envOr("MAINNET_FORK_BLOCK", _FORK_BLOCK));

        _erc20Fwd = IForwarder(
            address(
                new ERC20Forwarder({
                    protocolAdapter: _PROTOCOL_ADAPTER,
                    emergencyCommittee: _EMERGENCY_COMMITTEE,
                    logicRef: _ERC20_LOGIC_REF
                })
            )
        );
        _genericCallFwd =
            new GenericCallForwarder({protocolAdapter: _PROTOCOL_ADAPTER, logicRef: _GENERIC_CALL_LOGIC_REF});
    }

    // ── Tests ─────────────────────────────────────────────────────────────────────────────────────────────────

    /// @notice Worst-case inclusion: the action lands exactly at its deadline, where the deadline-rate projection is
    ///         bit-exact, so the deposit mints precisely the committed shares and the wrap leaves no dust.
    function test_fork_mint_susds_and_wrap_at_deadline_rate() public {
        uint256 deadline = block.timestamp + _WINDOW;
        uint256 committedShares = _minSharesByDeadline(_AMOUNT, deadline);

        vm.warp(deadline);
        // The off-chain projection reproduces the vault's own quote at the inclusion time, to the wei.
        assertEq(committedShares, _sUsds.convertToShares(_AMOUNT));

        // Phase 1: unwrap USDS into the generic call forwarder.
        deal(_USDS, address(_erc20Fwd), _AMOUNT);
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _unwrapInput(_USDS, _AMOUNT)});
        assertEq(_usds.balanceOf(address(_genericCallFwd)), _AMOUNT);

        // Phase 2: deposit USDS into the vault, then approve Permit2 for the wrap.
        vm.prank(_PROTOCOL_ADAPTER);
        _genericCallFwd.forwardCall({logicRef: _GENERIC_CALL_LOGIC_REF, input: _depositInput(_AMOUNT, committedShares)});
        // `deposit` consumed exactly the unwrapped USDS and minted exactly the committed shares.
        assertEq(_usds.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), committedShares);

        // Phase 3: wrap the sUSDS into a resource.
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _wrapInput(committedShares, deadline)});
        assertEq(_sUsds.balanceOf(address(_erc20Fwd)), committedShares);
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), 0); // no dust at the deadline
    }

    /// @notice Same atomic action, but starting from a USDC resource: USDC -> USDS via the LitePSM, then USDS -> sUSDS
    ///         via the vault. The route now traverses two conversions, but only the vault's `chi` varies with time; the
    ///         PSM fee (`tin`) is a governance constant, so the committed shares still bind to the composed projection
    ///         `convertToShares(usdsOut(usdcIn, tin))` at the deadline, and the wrap again leaves no dust at the bound.
    function test_fork_mint_susds_from_usdc_via_psm_at_deadline_rate() public {
        uint256 usdcAmount = 1000e6; // 1000 USDC (6 decimals)
        uint256 usdsOut = _usdsOutForGem(usdcAmount);
        uint256 deadline = block.timestamp + _WINDOW;
        uint256 committedShares = _minSharesByDeadline(usdsOut, deadline);

        vm.warp(deadline);
        // The composed (PSM fee, then deadline-rate) projection reproduces the vault's quote on the PSM output exactly.
        assertEq(committedShares, _sUsds.convertToShares(usdsOut));

        // Phase 1: unwrap USDC into the generic call forwarder.
        deal(_USDC, address(_erc20Fwd), usdcAmount);
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _unwrapInput(_USDC, usdcAmount)});
        assertEq(_usdc.balanceOf(address(_genericCallFwd)), usdcAmount);

        // Phase 2: USDC -> USDS (PSM) -> sUSDS (vault), then approve Permit2.
        vm.prank(_PROTOCOL_ADAPTER);
        _genericCallFwd.forwardCall({
            logicRef: _GENERIC_CALL_LOGIC_REF, input: _psmSellGemDepositInput(usdcAmount, usdsOut, committedShares)
        });
        assertEq(_usdc.balanceOf(address(_genericCallFwd)), 0);
        assertEq(_usds.balanceOf(address(_genericCallFwd)), 0); // sellGem output fully deposited
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), committedShares);

        // Phase 3: wrap the sUSDS into a resource.
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _wrapInput(committedShares, deadline)});
        assertEq(_sUsds.balanceOf(address(_erc20Fwd)), committedShares);
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), 0); // no dust at the deadline
    }

    /// @notice Earlier inclusion: the action lands before its deadline, so the live rate mints more than committed.
    ///         The wrap still pulls exactly the committed shares; the bounded surplus stays as dust in the forwarder.
    function test_fork_earlier_inclusion_leaves_bounded_dust() public {
        uint256 deadline = block.timestamp + _WINDOW;
        uint256 committedShares = _minSharesByDeadline(_AMOUNT, deadline);

        vm.warp(block.timestamp + _EARLY); // well before the deadline
        uint256 mintedShares = _sUsds.convertToShares(_AMOUNT);
        assertGt(mintedShares, committedShares);

        // Phase 1: unwrap USDS into the generic call forwarder.
        deal(_USDS, address(_erc20Fwd), _AMOUNT);
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _unwrapInput(_USDS, _AMOUNT)});

        // Phase 2: deposit USDS into the vault, then approve Permit2 for the wrap.
        vm.prank(_PROTOCOL_ADAPTER);
        _genericCallFwd.forwardCall({logicRef: _GENERIC_CALL_LOGIC_REF, input: _depositInput(_AMOUNT, committedShares)});
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), mintedShares);

        // Phase 3: wrap exactly the committed shares.
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _wrapInput(committedShares, deadline)});
        assertEq(_sUsds.balanceOf(address(_erc20Fwd)), committedShares);
        // Surplus is the SSR accrued over the unused part of the window — small, bounded, and left behind as dust.
        assertEq(_sUsds.balanceOf(address(_genericCallFwd)), mintedShares - committedShares);
        assertGt(mintedShares - committedShares, 0);
    }

    /// @notice Committing at the *spot* rate (what a build-time quote like `previewMintSUsds` returns) is unsafe: any
    ///         later inclusion accrues `chi`, mints fewer shares than committed, and the wrap reverts pulling them.
    ///         This is exactly the non-determinism the deadline-rate projection removes.
    function test_fork_spot_rate_commitment_reverts() public {
        uint256 deadline = block.timestamp + _WINDOW;
        uint256 committedSpot = _sUsds.convertToShares(_AMOUNT); // spot quote, no deadline projection

        vm.warp(block.timestamp + _EARLY); // the tx lands later; the rate has moved up
        assertLt(_sUsds.convertToShares(_AMOUNT), committedSpot);

        // Phase 1: unwrap USDS into the generic call forwarder.
        deal(_USDS, address(_erc20Fwd), _AMOUNT);
        vm.prank(_PROTOCOL_ADAPTER);
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _unwrapInput(_USDS, _AMOUNT)});

        // Phase 2: deposit (mints fewer shares than committed at this later time), then approve Permit2.
        vm.prank(_PROTOCOL_ADAPTER);
        _genericCallFwd.forwardCall({logicRef: _GENERIC_CALL_LOGIC_REF, input: _depositInput(_AMOUNT, committedSpot)});

        // Phase 3: the forwarder holds fewer sUSDS than `committedSpot`, so Permit2's pull during the wrap reverts.
        vm.prank(_PROTOCOL_ADAPTER);
        vm.expectRevert();
        _erc20Fwd.forwardCall({logicRef: _ERC20_LOGIC_REF, input: _wrapInput(committedSpot, deadline)});
    }

    // ── Action input builders (the forwardCalls themselves stay visible in the tests) ─────────────────────────

    /// @dev ERC20 forwarder Unwrap input: move `amount` of `token` to the generic call forwarder.
    function _unwrapInput(address token, uint256 amount) internal view returns (bytes memory) {
        return abi.encode(
            ERC20Forwarder.CallType.Unwrap,
            token,
            uint128(amount),
            ERC20Forwarder.UnwrapData({receiver: address(_genericCallFwd)})
        );
    }

    /// @dev Generic call forwarder input (USDS route): deposit USDS into the sUSDS vault, then approve Permit2 to pull
    ///      `committedShares` for the wrap. The vault pulls USDS with a plain ERC-20 allowance (no Permit2 on input).
    function _depositInput(uint256 amount, uint256 committedShares) internal view returns (bytes memory) {
        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](3);
        calls[0] =
            GenericCallForwarder.Call({to: _USDS, value: 0, data: abi.encodeCall(IERC20.approve, (_SUSDS, amount))});
        calls[1] = GenericCallForwarder.Call({
            to: _SUSDS, value: 0, data: abi.encodeCall(IERC4626.deposit, (amount, address(_genericCallFwd)))
        });
        calls[2] = GenericCallForwarder.Call({
            to: _SUSDS, value: 0, data: abi.encodeCall(IERC20.approve, (_PERMIT2, committedShares))
        });
        return abi.encode(calls);
    }

    /// @dev Generic call forwarder input (USDC route): swap USDC->USDS via the LitePSM, deposit USDS->sUSDS via the
    ///      vault, then approve Permit2 for the wrap. This is Osero's four-tx two-phase mainnet plan (USDC approve +
    ///      sellGem, then USDS approve + deposit) flattened into one ordered call list, plus the wrap's Permit2 approve.
    function _psmSellGemDepositInput(uint256 usdcAmount, uint256 usdsOut, uint256 committedShares)
        internal
        view
        returns (bytes memory)
    {
        GenericCallForwarder.Call[] memory calls = new GenericCallForwarder.Call[](5);
        calls[0] =
            GenericCallForwarder.Call({to: _USDC, value: 0, data: abi.encodeCall(IERC20.approve, (_PSM, usdcAmount))});
        calls[1] = GenericCallForwarder.Call({
            to: _PSM, value: 0, data: abi.encodeCall(ILitePsm.sellGem, (address(_genericCallFwd), usdcAmount))
        });
        calls[2] =
            GenericCallForwarder.Call({to: _USDS, value: 0, data: abi.encodeCall(IERC20.approve, (_SUSDS, usdsOut))});
        calls[3] = GenericCallForwarder.Call({
            to: _SUSDS, value: 0, data: abi.encodeCall(IERC4626.deposit, (usdsOut, address(_genericCallFwd)))
        });
        calls[4] = GenericCallForwarder.Call({
            to: _SUSDS, value: 0, data: abi.encodeCall(IERC20.approve, (_PERMIT2, committedShares))
        });
        return abi.encode(calls);
    }

    /// @dev ERC20 forwarder Wrap input: wrap `committedShares` sUSDS. The generic call forwarder owns the funds and
    ///      implements ERC-1271 (always returning the magic value), so the dummy r/s/v signature is accepted.
    function _wrapInput(uint256 committedShares, uint256 deadline) internal view returns (bytes memory) {
        return abi.encode(
            ERC20Forwarder.CallType.Wrap,
            _SUSDS,
            uint128(committedShares),
            ERC20Forwarder.WrapData({
                nonce: _WRAP_NONCE,
                deadline: deadline,
                owner: address(_genericCallFwd),
                actionTreeRoot: _ACTION_TREE_ROOT,
                r: bytes32(0),
                s: bytes32(0),
                v: 27
            })
        );
    }

    // ── Sky Savings Rate projection ─────────────────────────────────────────────────────────────────────────

    /// @dev USDS minted by the PSM for `gemAmt` USDC: `gemAmt * to18ConversionFactor * (WAD - tin) / WAD`. The fee
    ///      `tin` is a governance constant (currently 0), read on-chain so the projection stays exact if it changes.
    function _usdsOutForGem(uint256 gemAmt) internal view returns (uint256 usdsOut) {
        usdsOut = gemAmt * _psm.to18ConversionFactor();
        uint256 fee = _psm.tin();
        if (fee > 0) usdsOut -= (usdsOut * fee) / _WAD;
    }

    /// @dev Minimum sUSDS shares a `deposit(assets)` can mint at any inclusion time up to `deadline`. Since `chi`
    ///      only rises with time, the fewest shares occur at the latest legal inclusion — the deadline.
    function _minSharesByDeadline(uint256 assets, uint256 deadline) internal view returns (uint256 shares) {
        shares = (assets * _RAY) / _projectChi(deadline);
    }

    /// @dev Projects the Sky Savings Rate accumulator `chi` forward to `timestamp`, matching `SUsds.drip()`:
    ///      `chi(t) = rpow(ssr, t - rho, RAY) * chi / RAY`.
    function _projectChi(uint256 timestamp) internal view returns (uint256 projectedChi) {
        uint256 lastDrip = _sUsds.rho();
        if (timestamp < lastDrip) revert TimestampBeforeRho(timestamp, lastDrip);
        projectedChi = (_rpow(_sUsds.ssr(), timestamp - lastDrip, _RAY) * _sUsds.chi()) / _RAY;
    }

    /// @dev Maker's fixed-point exponentiation (half-up rounding), the exact routine `SUsds` uses to accrue `chi`.
    ///      See dss `rpow`: https://github.com/makerdao/dss/blob/master/src/jug.sol
    function _rpow(uint256 x, uint256 n, uint256 base) internal pure returns (uint256 z) {
        // solhint-disable-next-line no-inline-assembly
        assembly {
            switch x
            case 0 {
                switch n
                case 0 { z := base }
                default { z := 0 }
            }
            default {
                switch mod(n, 2)
                case 0 { z := base }
                default { z := x }
                let half := div(base, 2)
                for { n := div(n, 2) } n { n := div(n, 2) } {
                    let xx := mul(x, x)
                    if iszero(eq(div(xx, x), x)) { revert(0, 0) }
                    let xxRound := add(xx, half)
                    if lt(xxRound, xx) { revert(0, 0) }
                    x := div(xxRound, base)
                    if mod(n, 2) {
                        let zx := mul(z, x)
                        if and(iszero(iszero(x)), iszero(eq(div(zx, x), z))) { revert(0, 0) }
                        let zxRound := add(zx, half)
                        if lt(zxRound, zx) { revert(0, 0) }
                        z := div(zxRound, base)
                    }
                }
            }
        }
    }
}
