# Orca Whirlpools — Position Manager

> Verified against official Orca docs (docs.orca.so/llms.txt) · June 2026

## Program Constants

```
Program ID (mainnet + Eclipse): whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc
WhirlpoolsConfig (mainnet):     2LecshUwdy9xi7meFgHtFJQNSKk4KdTrcpvaB56dP2NQ
WhirlpoolsConfig (devnet):      FcrweFY1G9HJAHG5inkGB6pKg1HZ6x9UC2WioAfWrGkR
Devnet test pool (SOL/devUSDC): 3KBZiL2g8C7tiJ32hTv5v3KM7aK9htpqTw4cTXz1HvPt
devUSDC mint (devnet):          BRjpCHtyQLNCo8gqRUr8jtdAj5AjPYQaoqbvcZiHok1k
```

## SDK

Use the **new SDK** (`@orca-so/whirlpools` + `@solana/kit`) for all new code.  
The legacy `@orca-so/whirlpools-sdk` still works but is not recommended for new projects.

```bash
npm install @orca-so/whirlpools @solana/kit
```

## Critical: Positions Are NFTs

A Whirlpool position is represented by an **SPL Token NFT** in the owner's wallet.  
The `positionMint` (NFT address) is the key to all position operations — **not** a wallet PDA.

```
Position NFT mint  →  on-chain Position account (PDA derived from NFT mint)
```

You must hold the NFT to adjust, harvest, or close the position.

## Setup

```typescript
import { setRpc, setPayerFromBytes, setDefaultFunder } from '@orca-so/whirlpools';
import secret from "wallet.json";

await setRpc('https://api.mainnet-beta.solana.com');
const signer = await setPayerFromBytes(new Uint8Array(secret));
setDefaultFunder(signer.address);
```

## Fetch All Positions for a Wallet

```typescript
import { fetchPositionsForOwner, WhirlpoolDeployment } from '@orca-so/whirlpools';
import { createSolanaRpc, mainnet } from '@solana/kit';

const rpc = createSolanaRpc(mainnet('https://api.mainnet-beta.solana.com'));
const positions = await fetchPositionsForOwner(rpc, ownerAddress, WhirlpoolDeployment.mainnet);

// Each position includes:
// position.data.tickLowerIndex  — lower bound tick
// position.data.tickUpperIndex  — upper bound tick
// position.data.liquidity       — current liquidity
// position.data.feeOwedA/B      — uncollected fees
```

## Check If Position Is In-Range

```typescript
import { fetchWhirlpool, WhirlpoolDeployment } from '@orca-so/whirlpools';

const pool = await fetchWhirlpool(rpc, poolAddress);
const tickCurrent = pool.data.tickCurrentIndex;

function isInRange(position: any, tickCurrent: number): boolean {
  return tickCurrent >= position.data.tickLowerIndex &&
         tickCurrent < position.data.tickUpperIndex;
}

// Out-of-range direction matters for IL calculation:
function rangeStatus(position: any, tickCurrent: number): 'in-range' | 'below' | 'above' {
  if (tickCurrent < position.data.tickLowerIndex) return 'below';  // all tokenB
  if (tickCurrent >= position.data.tickUpperIndex) return 'above'; // all tokenA
  return 'in-range';
}
```

## Tick ↔ Price Conversion

Ticks are the fundamental price unit. Each tick = 0.01% (1 basis point) price movement.

```typescript
// sqrtPrice is stored as Q64.64 fixed-point integer
// Convert pool's sqrtPrice to human-readable price:
function sqrtPriceToPrice(sqrtPriceX64: bigint, decimalsA: number, decimalsB: number): number {
  const sqrtPrice = Number(sqrtPriceX64) / Math.pow(2, 64);
  return sqrtPrice * sqrtPrice * Math.pow(10, decimalsA - decimalsB);
}

// Convert tick index to price:
function tickToPrice(tickIndex: number, decimalsA: number, decimalsB: number): number {
  return Math.pow(1.0001, tickIndex) * Math.pow(10, decimalsA - decimalsB);
}

// Convert human-readable price to tick index:
function priceToTick(price: number, decimalsA: number, decimalsB: number): number {
  return Math.floor(
    Math.log(price * Math.pow(10, decimalsB - decimalsA)) / Math.log(1.0001)
  );
  // Round to nearest multiple of pool's tickSpacing before using
}
```

## Fee Tiers (Tick Spacing → Fee Rate)

| Tick Spacing | Fee Rate | Best for |
|---|---|---|
| 1 | 0.01% | Pegged stables |
| 2 | 0.02% | Tight stables |
| 4 | 0.04% | Stable pairs |
| 8 | 0.05% | Correlated assets |
| 16 | 0.16% | Moderate volatility |
| 64 | 0.30% | Standard volatile |
| 96 | 0.65% | High volatility |
| 128 | 1.00% | Very high volatility |
| 256 | 2.00% | Exotic pairs |
| 32896 | 1.00% | Splash pools (full-range) |

Fee distribution: 87% to LPs, 12% to Orca DAO, 1% to Climate Fund.

## Harvest Fees (Without Closing Position)

```typescript
import { harvestPosition, WhirlpoolDeployment } from '@orca-so/whirlpools';

const { feesQuote, rewardsQuote, instructions, callback: sendTx } = await harvestPosition(
  positionMint,
  { whirlpoolDeployment: WhirlpoolDeployment.mainnet }
);

console.log(`Claimable: ${feesQuote.feeOwedA} tokenA, ${feesQuote.feeOwedB} tokenB`);
await sendTx();
```

## Rebalance: Close + Reopen at New Range

```typescript
import { closePosition, openConcentratedPosition, WhirlpoolDeployment } from '@orca-so/whirlpools';

// 1. Close existing position (collects fees + removes liquidity + burns NFT)
const { quote: closeQuote, callback: closeTx } = await closePosition(
  positionMint,
  { slippageToleranceBps: 100, whirlpoolDeployment: WhirlpoolDeployment.mainnet }
);
await closeTx();

// 2. Open new position at updated range (human-readable prices)
const { positionMint: newMint, callback: openTx } = await openConcentratedPosition(
  poolAddress,
  { tokenA: BigInt(closeQuote.tokenA) },  // reinvest proceeds
  newLowerPrice,
  newUpperPrice,
  { slippageToleranceBps: 100, whirlpoolDeployment: WhirlpoolDeployment.mainnet }
);
await openTx();
```

## Transaction Costs (Solana mainnet)

| Operation | Typical SOL cost | Refundable? |
|---|---|---|
| Position creation (rent) | 0.0088 SOL | Yes, on close |
| Standard transaction | ~0.000010 SOL | No |
| TickArray initialization (rare) | 0.07 SOL | No |

## Common Errors

| Code | Name | Fix |
|---|---|---|
| `0x177a` | `InvalidTickIndex` | Tick not a multiple of pool's tickSpacing |
| `0x0` | `NotRentExempt` | TickArray for range not initialized — call `initTickArrayForTicks` first |

## MCP / AI Tool Access

Orca provides a live MCP server for semantic doc search:
```
https://docs.orca.so/mcp
```
Tool: `SearchOrcaDocumentation` — no API key required.

## Position Lifecycle

```
openConcentratedPosition  →  positionMint (NFT)
        ↓
fetchPositionsForOwner    →  monitor range status + fees
        ↓
harvestPosition           →  collect fees (keep position open)
        ↓
closePosition             →  collect fees + withdraw liquidity + burn NFT
```
