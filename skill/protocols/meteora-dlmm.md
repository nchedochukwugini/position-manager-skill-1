# Meteora DLMM — Position Manager

> Verified against Meteora docs (docs.meteora.ag) · June 2026

## Program Constants

```
Program ID (mainnet + devnet): LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo
SDK:                           @meteora-ag/dlmm
```

Note: Meteora uses the **same program ID on both mainnet and devnet** — this is intentional, not an error.

## Key Difference: Bins, Not Ticks

Meteora DLMM uses a **bin-based** model rather than the continuous tick model of Orca/Raydium.

| Concept | Orca / Raydium | Meteora DLMM |
|---|---|---|
| Price unit | Tick (1 bps per tick) | Bin (fixed-width price bucket) |
| Liquidity curve | Continuous across ticks | Discrete steps per bin |
| Active unit | `tickCurrentIndex` | `activeBinId` |
| In-range check | `tickLower <= tickCurrent < tickUpper` | `lowerBinId <= activeBinId <= upperBinId` |
| Fee model | Fixed tier | Dynamic — increases with volatility |

**Only the active bin earns fees.** All other bins hold one token type only (waiting to be activated or already depleted).

## SDK Setup

```bash
npm install @meteora-ag/dlmm @solana/web3.js
```

```typescript
import DLMM from '@meteora-ag/dlmm';
import { Connection, PublicKey, Keypair } from '@solana/web3.js';

const connection = new Connection('https://api.mainnet-beta.solana.com');
const POOL_ADDRESS = new PublicKey('YOUR_POOL_ADDRESS');

// Load a DLMM pool instance
const dlmmPool = await DLMM.create(connection, POOL_ADDRESS);
```

## Fetch Positions for a Wallet

```typescript
// Get all positions owned by a wallet in this pool
const { userPositions } = await dlmmPool.getPositionsByUserAndLbPair(
  new PublicKey(ownerAddress)
);

// Each position includes:
// position.publicKey              — position account address
// position.positionData.lowerBinId  — lower bound bin ID
// position.positionData.upperBinId  — upper bound bin ID
// position.positionData.feeX/Y      — uncollected fees (tokenA/tokenB)
// position.positionData.totalClaimedFeeXAmount / totalClaimedFeeYAmount
```

## Check If Position Is In-Range

```typescript
// Get current active bin from pool state
await dlmmPool.refetchStates(); // refresh pool state
const activeBinId = dlmmPool.lbPair.activeId;

function isInRange(lowerBinId: number, upperBinId: number, activeBinId: number): boolean {
  return activeBinId >= lowerBinId && activeBinId <= upperBinId;
}

function rangeStatus(
  lowerBinId: number,
  upperBinId: number,
  activeBinId: number
): 'in-range' | 'below' | 'above' {
  if (activeBinId < lowerBinId) return 'below';   // position is all tokenY
  if (activeBinId > upperBinId) return 'above';   // position is all tokenX
  return 'in-range';
}

// Example usage:
const status = rangeStatus(
  position.positionData.lowerBinId,
  position.positionData.upperBinId,
  activeBinId
);
```

## Bin Price Calculation

Each bin has a fixed price step defined by the pool's `binStep` (in basis points):

```typescript
// Bin price formula:
// price(binId) = (1 + binStep / 10000) ^ binId

function binToPrice(binId: number, binStep: number, decimalsX: number, decimalsY: number): number {
  return Math.pow(1 + binStep / 10_000, binId) * Math.pow(10, decimalsX - decimalsY);
}

// Get binStep from pool:
const binStep = dlmmPool.lbPair.binStep; // e.g. 25 = 0.25% per bin

// Active bin price (human-readable):
const activePrice = binToPrice(activeBinId, binStep, decimalsX, decimalsY);
```

## Liquidity Distribution Strategies

When opening a new position, choose a strategy based on market expectations:

| Strategy | Shape | Best for |
|---|---|---|
| **Spot** | Uniform across range | General use, infrequent rebalancers |
| **Curve** | Concentrated at midpoint | Stable pairs, low volatility |
| **Bid-Ask** | Concentrated at range edges | High volatility, mean-reversion plays |

```typescript
import { StrategyType } from '@meteora-ag/dlmm';

// Spot (uniform)
const strategyType = StrategyType.SpotBalanced; // or SpotOneSide

// Curve (concentrated center)
const strategyType = StrategyType.CurveBalanced;

// Bid-Ask (concentrated edges)
const strategyType = StrategyType.BidAskBalanced;
```

## Add Liquidity to a Position

```typescript
const newPosition = Keypair.generate();
const userTokenX = // ATA for tokenX
const userTokenY = // ATA for tokenY

const activeBin = await dlmmPool.getActiveBin();
const minBinId = activeBin.binId - 10;  // 10 bins below active
const maxBinId = activeBin.binId + 10;  // 10 bins above active

const { tx } = await dlmmPool.initializePositionAndAddLiquidityByStrategy({
  positionPubKey: newPosition.publicKey,
  user: ownerKeypair.publicKey,
  totalXAmount: new BN(amountX),
  totalYAmount: new BN(amountY),
  strategy: {
    maxBinId,
    minBinId,
    strategyType: StrategyType.SpotBalanced,
  },
});

await sendAndConfirmTransaction(connection, tx, [ownerKeypair, newPosition]);
```

## Claim Fees (Without Closing)

```typescript
const claimTx = await dlmmPool.claimFee(
  ownerKeypair.publicKey,
  [position.publicKey]
);
await sendAndConfirmTransaction(connection, claimTx, [ownerKeypair]);
```

## Remove Liquidity / Close Position

```typescript
// Remove all liquidity (bps = 10_000 = 100%)
const binIdsToRemove = position.positionData.positionBinData.map(b => b.binId);

const removeTx = await dlmmPool.removeLiquidity({
  position: position.publicKey,
  user: ownerKeypair.publicKey,
  fromBinId: position.positionData.lowerBinId,
  toBinId: position.positionData.upperBinId,
  bps: new BN(10_000),  // 100% removal
  shouldClaimAndClose: true,  // claim fees and close position account
});

for (const tx of Array.isArray(removeTx) ? removeTx : [removeTx]) {
  await sendAndConfirmTransaction(connection, tx, [ownerKeypair]);
}
```

## Dynamic Fees

Unlike Orca/Raydium's fixed fee tiers, Meteora DLMM adjusts fees dynamically:
- Base fee defined per pool at creation
- Fee **increases automatically** during periods of elevated volatility
- Designed to protect LPs from informed traders during volatile markets

Farming rewards follow the same in-range logic: rewards only accrue to positions whose bin range includes the active bin during swaps. If price crosses multiple bins in a swap, rewards are distributed equally across all crossed bins.

## PositionV2 (Current Standard)

Current DLMM supports **PositionV2**, which supports up to **1,400 bins per position** (vs. 70-bin limit in older versions). Positions can be resized dynamically using `rebalance_liquidity` without closing and reopening — this is more gas-efficient than the Orca/Raydium close-then-reopen pattern.

```typescript
// Check if pool supports PositionV2 (all recently created pools do)
// PositionV2 positions use extended byte data allocated on demand as range grows
```
