// susds-resource.ts
//
// Bridge Osero's `mintSUsds` ExecutionPlan into the Anoma GenericCallForwarder +
// ERC20Forwarder wrap flow, producing the two pre-determined inputs a single
// atomic protocol-adapter transaction needs:
//
//   1. `genericCallInput` — the GenericCallForwarder.forwardCall payload: Osero's
//      mint steps (flattened) followed by the Permit2 approve for the wrap.
//   2. `wrapInput` — the ERC20Forwarder.forwardCall payload that wraps the minted
//      sUSDS into a resource.
//
// Determinism note: we do NOT use Osero's `previewMintSUsds` to size the wrap.
// That is a *spot* quote and goes stale the instant it is read — if the tx lands
// even one second later, sUSDS's `chi` has accrued and fewer shares are minted
// than committed, reverting the wrap. Instead we commit the shares to the price
// projected at the action's *deadline* (the worst case), which the Permit2
// signature deadline already caps inclusion to. The deposit then mints >= the
// committed amount for any legal inclusion time; the bounded surplus is dust.
//
// Peer deps (not installed in this repo): `viem` (v2) and `@osero/client`.

import {
  mintSUsds,
  type ExecutionPlan,
  type OseroClient,
  type TransactionRequest,
} from '@osero/client';
import {
  encodeAbiParameters,
  encodeFunctionData,
  erc20Abi,
  type Address,
  type Hex,
  type PublicClient,
} from 'viem';

// Canonical Permit2 (same address on every chain).
const PERMIT2 = '0x000000000022D473030F116dDEE9F6B43aC78BA3' as const;

const RAY = 10n ** 27n;

// ── ABI fragments ───────────────────────────────────────────────────────────

// GenericCallForwarder.Call — abi types only (names are irrelevant to encoding).
const CALL_TUPLE = {
  type: 'tuple[]',
  components: [
    { name: 'to', type: 'address' },
    { name: 'value', type: 'uint256' },
    { name: 'data', type: 'bytes' },
  ],
} as const;

// ERC20Forwarder.WrapData — a fully static struct, so it encodes inline right
// after the `uint128 amount`, matching `abi.encode(CallType, token, amount, data)`.
const WRAP_DATA_TUPLE = {
  type: 'tuple',
  components: [
    { name: 'nonce', type: 'uint256' },
    { name: 'deadline', type: 'uint256' },
    { name: 'owner', type: 'address' },
    { name: 'actionTreeRoot', type: 'bytes32' },
    { name: 'r', type: 'bytes32' },
    { name: 's', type: 'bytes32' },
    { name: 'v', type: 'uint8' },
  ],
} as const;

// Sky Savings Rate accumulator accessors on the sUSDS vault.
const SUSDS_RATE_ABI = [
  { type: 'function', name: 'ssr', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'chi', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
  { type: 'function', name: 'rho', stateMutability: 'view', inputs: [], outputs: [{ type: 'uint256' }] },
] as const;

// ── Types ─────────────────────────────────────────────────────────────────

export type Call = { to: Address; value: bigint; data: Hex };

export type WrapData = {
  nonce: bigint;
  deadline: bigint;
  owner: Address;
  actionTreeRoot: Hex;
  r: Hex;
  s: Hex;
  v: number;
};

// CallType.Wrap == 0 in ERC20Forwarder.
const CALL_TYPE_WRAP = 0;

// ── Plan flattening ─────────────────────────────────────────────────────────

// Osero's ExecutionPlan union: a single TransactionRequest | { approvals[],
// originalTransaction } (L2) | { steps[] } (mainnet, where each step is itself
// one of the first two). Flatten to an ordered list of plain transactions.
export function flattenPlan(plan: ExecutionPlan): TransactionRequest[] {
  switch (plan.__typename) {
    case 'TransactionRequest':
      return [plan];
    case 'Erc20ApprovalRequired':
      return [...plan.approvals.map((a) => a.byTransaction), plan.originalTransaction];
    case 'MultiStepExecution':
      return plan.steps.flatMap((step) =>
        step.__typename === 'TransactionRequest'
          ? [step]
          : [...step.approvals.map((a) => a.byTransaction), step.originalTransaction],
      );
  }
}

// Map one Osero tx onto one forwarder Call. The forwarder is the executor, so
// `from`/`operation` are dropped; `operation` is a *semantic* tag (APPROVE_ERC20,
// MINT_USDS, DEPOSIT_USDS_FOR_SUSDS, …), never delegatecall, so every step is
// safe to embed as a plain call.
export function txToCall(tx: TransactionRequest, expectedChainId: number): Call {
  if (tx.chainId !== expectedChainId) {
    throw new Error(`plan step on chain ${tx.chainId}, expected ${expectedChainId}`);
  }
  return { to: tx.to, value: tx.value, data: tx.data };
}

// ── ABI encoding ──────────────────────────────────────────────────────────

export function encodeGenericCalls(calls: Call[]): Hex {
  return encodeAbiParameters([CALL_TUPLE], [calls]);
}

// abi.encode(CallType.Wrap /*=0*/, token, uint128 amount, WrapData).
export function buildWrapInput(token: Address, amount: bigint, wrap: WrapData): Hex {
  return encodeAbiParameters(
    [{ type: 'uint8' }, { type: 'address' }, { type: 'uint128' }, WRAP_DATA_TUPLE],
    [CALL_TYPE_WRAP, token, amount, wrap],
  );
}

// ── Sky Savings Rate projection ─────────────────────────────────────────────

// Maker-style RAY exponentiation; round the result UP so chi(deadline) is never
// under-estimated (under-estimating chi over-estimates the shares and risks a
// revert). Mirrors SUsds's `_rpow` but with conservative rounding.
function rpowUp(x: bigint, n: bigint): bigint {
  let z = n % 2n === 0n ? RAY : x;
  for (n /= 2n; n > 0n; n /= 2n) {
    x = (x * x + RAY - 1n) / RAY;
    if (n % 2n === 1n) z = (z * x + RAY - 1n) / RAY;
  }
  return z;
}

// Minimum sUSDS shares a `deposit(assets)` can mint at any inclusion time up to
// `deadline`. Since `chi` only rises with time, the fewest shares occur at the
// latest legal inclusion — the deadline. Reads ssr/chi/rho from the vault.
export async function minSharesByDeadline(args: {
  client: PublicClient;
  sUsds: Address;
  assets: bigint;
  deadline: bigint;
}): Promise<bigint> {
  const { client, sUsds, assets, deadline } = args;
  const [ssr, chi, rho] = await Promise.all([
    client.readContract({ address: sUsds, abi: SUSDS_RATE_ABI, functionName: 'ssr' }),
    client.readContract({ address: sUsds, abi: SUSDS_RATE_ABI, functionName: 'chi' }),
    client.readContract({ address: sUsds, abi: SUSDS_RATE_ABI, functionName: 'rho' }),
  ]);
  if (deadline < rho) throw new Error('deadline precedes vault rho');
  const chiAtDeadline = (rpowUp(ssr, deadline - rho) * chi) / RAY;
  const m = (assets * RAY) / chiAtDeadline; // floor
  return m - 1n; // 1-wei safety margin against rpow rounding
}

// ── Orchestrator ────────────────────────────────────────────────────────────

export async function buildSUsdsResourceInputs(args: {
  oseroClient: OseroClient;
  publicClient: PublicClient;
  chainId: number;
  sUsds: Address; // the sUSDS token on `chainId`
  usdsAmount: bigint; // USDS already sitting in the GenericCallForwarder
  forwarder: Address; // GenericCallForwarder address
  wrap: Omit<WrapData, 'owner'>; // nonce/deadline/actionTreeRoot/r/s/v from the Anoma action
}): Promise<{ genericCallInput: Hex; wrapInput: Hex; shares: bigint }> {
  const { oseroClient, publicClient, chainId, sUsds, usdsAmount, forwarder, wrap } = args;

  // Commit the wrap amount to the deadline-rate floor (NOT a spot quote). The
  // same deadline gates inclusion via the Permit2 signature, so the deposit is
  // guaranteed to mint >= `shares` for any block the tx can land in.
  const shares = await minSharesByDeadline({
    client: publicClient,
    sUsds,
    assets: usdsAmount,
    deadline: wrap.deadline,
  });

  // Build the mint plan. sender = receiver = the forwarder, so (a) the minted
  // sUSDS lands in the forwarder ready to wrap, and (b) any allowance Osero reads
  // is the forwarder's (~0 inside the atomic action), so the approval is included.
  const plan = await mintSUsds(oseroClient, {
    chainId,
    amount: usdsAmount,
    sender: forwarder,
    receiver: forwarder,
    slippageBps: 0,
  });
  if (plan.isErr()) throw plan.error;

  const mintCalls = flattenPlan(plan.value).map((tx) => txToCall(tx, chainId));

  // Append the plain ERC-20 approve so Permit2 can pull sUSDS during the wrap.
  const permit2Approve: Call = {
    to: sUsds,
    value: 0n,
    data: encodeFunctionData({ abi: erc20Abi, functionName: 'approve', args: [PERMIT2, shares] }),
  };

  const genericCallInput = encodeGenericCalls([...mintCalls, permit2Approve]);
  const wrapInput = buildWrapInput(sUsds, shares, { ...wrap, owner: forwarder });

  return { genericCallInput, wrapInput, shares };
}
