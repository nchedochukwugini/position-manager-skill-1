# Raydium CLMM — Position Manager

> Verified against Raydium docs (docs.raydium.io) and raydium-sdk-V2-demo · June 2026

## Program Constants

```
Program ID (mainnet): CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK
Program ID (devnet):  DRayAUgENGQBKVaX8owNhgzkEDyoHTGVEGHVJT1E9pfH
SDK:                  @raydium-io/raydium-sdk-v2
```

## Key Difference from Orca

Raydium CLMM positions are **not NFTs**. They are PDAs derived from the owner and pool. This means:
- No NFT mint to track — use `getOwnerPositionInfo()` to enumerate positions
- Positions are directly linked to wallet address, simpler to enumerate
- Same tick-based math as Orca (Uniswap V3 style), but different account layout

## SDK Setup

```bash
npm install @raydium-io/raydium-sdk-v2 @solana/web3.js
```

```typescript
import { Raydium, CLMM_PROGRAM_ID } from '@raydium-io/raydium-sdk-v2';
import { Connection, Keypair } from '@solana/web3.js';
import bs58 from 'bs58';

const connection = new Connection('https://api.mainnet-beta.solana.com');
const owner = Keypair.fromSecretKey(bs58.decode(process.env.PRIVATE_KEY!));

const raydium = await Raydium.load({
  connection,
  owner,
  cluster: 'mainnet',   // or 'devnet'
  disableLoadToken: false,
});
```

## Fetch All CLMM Positions for a Wallet

```typescript
// Gets all positions owned by the SDK's loaded wallet
const allPositions = await raydium.clmm.getOwnerPositionInfo({
  programId: CLMM_PROGRAM_ID
});

// Each position includes:
// position.poolId          — pool address
// position.tickLower.index — lower bound tick
// position.tickUpper.index — upper bound tick
// position.liquidity       — current liquidity (BN)
// position.tokenFeeAmountA/B — uncollected fees
```

## Fetch Pool State (for Range Check)

```typescript
// Mainnet: fetch from API (faster, cached)
const poolData = await raydium.api.fetchPoolById({ ids: poolId });
const poolInfo = poolData[0]; // ApiV3PoolInfoConcentratedItem

// Devnet or for real-time price: fetch directly from RPC
const { poolInfo, poolKeys } = await raydium.clmm.getPoolInfoFromRpc(poolId);

// Current tick is at:
// poolInfo.currentPrice  — human-readable price
// Need to derive tickCurrentIndex from currentPrice or fetch pool state from RPC
```

## Check If Position Is In-Range

Raydium CLMM uses the same tick math as Orca (Uniswap V3):

```typescript
function isInRange(
  tickLower: number,
  tickUpper: number,
  tickCurrent: number
): boolean {
  return tickCurrent >= tickLower && tickCurrent < tickUpper;
}

function rangeStatus(
  tickLower: number,
  tickUpper: number,
  tickCurrent: number
): 'in-range' | 'below' | 'above' {
  if (tickCurrent < tickLower) return 'below';   // position is all tokenB
  if (tickCurrent >= tickUpper) return 'above';  // position is all tokenA
  return 'in-range';
}
```

## Tick ↔ Price Conversion

Identical formula to Orca — same Uniswap V3 math:

```typescript
function tickToPrice(tickIndex: number, decimalsA: number, decimalsB: number): number {
  return Math.pow(1.0001, tickIndex) * Math.pow(10, decimalsA - decimalsB);
}

function priceToTick(price: number, decimalsA: number, decimalsB: number): number {
  return Math.floor(
    Math.log(price * Math.pow(10, decimalsB - decimalsA)) / Math.log(1.0001)
  );
  // Must be multiple of pool's tickSpacing
}
```

## Fee Tiers (AmmConfig)

Fee tiers are defined by on-chain `AmmConfig` accounts. Fetch available configs:

```typescript
const clmmConfigs = await raydium.api.getClmmConfigs();
// Each config has: id, tradeFeeRate, tickSpacing, protocolFeeRate, fundFeeRate
// Select config based on desired fee tier when creating a pool
```

Common fee tiers on mainnet:

| tickSpacing | tradeFeeRate | Best for |
|---|---|---|
| 1 | 0.01% | Stable pairs |
| 10 | 0.05% | Correlated assets |
| 60 | 0.25% | Standard volatile |
| 200 | 1.00% | High volatility |

## Decrease Liquidity / Close Position

```typescript
import { isValidClmm } from '@raydium-io/raydium-sdk-v2';

// Verify it's a CLMM pool
if (!isValidClmm(poolInfo.programId)) throw new Error('Not a CLMM pool');

// Get current position
const allPositions = await raydium.clmm.getOwnerPositionInfo({ programId: poolInfo.programId });
const position = allPositions.find(p => p.poolId.toBase58() === poolId);
if (!position) throw new Error('Position not found');

// Decrease liquidity (partial or full)
const { execute } = await raydium.clmm.decreaseLiquidity({
  poolInfo,
  poolKeys,         // only needed on devnet
  ownerPosition: position,
  ownerInfo: {
    useSOLBalance: true,
    closePosition: true,  // true = close position fully after withdrawal
  },
  liquidity: position.liquidity,  // withdraw all
  amountMinA: new BN(0),
  amountMinB: new BN(0),
  // For real-time slippage: fetch getRpcClmmPoolInfo first
});
await execute({ sendAndConfirm: true });
```

## Harvest Fees Only (Without Closing)

```typescript
const { execute } = await raydium.clmm.collectRewards({
  poolInfo,
  ownerPosition: position,
  ownerInfo: { useSOLBalance: true },
});
await execute({ sendAndConfirm: true });
```

## Rebalance: Close + Open at New Range

```typescript
// 1. Close existing position
await raydium.clmm.decreaseLiquidity({
  poolInfo, ownerPosition: position,
  ownerInfo: { useSOLBalance: true, closePosition: true },
  liquidity: position.liquidity,
  amountMinA: new BN(0), amountMinB: new BN(0),
}).then(r => r.execute({ sendAndConfirm: true }));

// 2. Open new position at updated range
await raydium.clmm.openPositionFromLiquidity({
  poolInfo,
  ownerInfo: { useSOLBalance: true },
  tickLower: newTickLower,  // must be multiple of tickSpacing
  tickUpper: newTickUpper,
  liquidity: new BN(targetLiquidity),
  slippage: 0.01,  // 1%
}).then(r => r.execute({ sendAndConfirm: true }));
```

## Important: Avoid Stale Price Issues

On mainnet, `raydium.api.fetchPoolById()` may return cached data. For accurate range checks and slippage calculations before executing a rebalance, fetch real-time pool state:

```typescript
const rpcData = await raydium.clmm.getRpcClmmPoolInfo({ poolId: poolInfo.id });
// Use rpcData.currentPrice for accurate in-range determination before transacting
```

## June 2026 Security Note

A June 2026 exploit targeted Raydium's **legacy AMM V3** (Serum-era pools, deprecated since 2021). Modern CLMM pools (`CAMMCzo5...`) and AMM V4 were **unaffected**. Always validate pool program IDs using `isValidClmm()` before executing position operations.
