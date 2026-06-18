# Fetch Positions — All Protocols

> Enumerate all CLMM positions for a wallet across Orca, Raydium, and Meteora in one pass

## Overview

Each protocol stores positions differently:
- **Orca**: position is an SPL NFT — enumerate via `fetchPositionsForOwner()`
- **Raydium**: position is a PDA — enumerate via `getOwnerPositionInfo()`
- **Meteora**: position is a PDA per pool — requires knowing which pools to check

## Orca: Fetch All Positions

```typescript
import { fetchPositionsForOwner, WhirlpoolDeployment, setRpc } from '@orca-so/whirlpools';
import { createSolanaRpc, mainnet, address } from '@solana/kit';

await setRpc('https://api.mainnet-beta.solana.com');
const rpc = createSolanaRpc(mainnet('https://api.mainnet-beta.solana.com'));

const orcaPositions = await fetchPositionsForOwner(
  rpc,
  address(ownerPublicKey),
  WhirlpoolDeployment.mainnet
);

// Normalize to common shape:
const normalized = orcaPositions.map(p => ({
  protocol: 'orca',
  positionId: p.address.toString(),
  poolAddress: p.data.whirlpool.toString(),
  tickLower: p.data.tickLowerIndex,
  tickUpper: p.data.tickUpperIndex,
  liquidity: p.data.liquidity.toString(),
  feeOwedA: p.data.feeOwedA.toString(),
  feeOwedB: p.data.feeOwedB.toString(),
}));
```

## Raydium CLMM: Fetch All Positions

```typescript
import { Raydium, CLMM_PROGRAM_ID } from '@raydium-io/raydium-sdk-v2';
import { Connection, Keypair } from '@solana/web3.js';

const raydium = await Raydium.load({ connection, owner, cluster: 'mainnet' });
const raydiumPositions = await raydium.clmm.getOwnerPositionInfo({
  programId: CLMM_PROGRAM_ID
});

const normalized = raydiumPositions.map(p => ({
  protocol: 'raydium',
  positionId: p.nftMint?.toBase58() ?? p.poolId.toBase58() + '-' + p.tickLower.index,
  poolAddress: p.poolId.toBase58(),
  tickLower: p.tickLower.index,
  tickUpper: p.tickUpper.index,
  liquidity: p.liquidity.toString(),
  feeOwedA: p.tokenFeeAmountA.toString(),
  feeOwedB: p.tokenFeeAmountB.toString(),
}));
```

## Meteora DLMM: Fetch Positions by Pool

Meteora requires iterating over known pools (no global "all positions" query):

```typescript
import DLMM from '@meteora-ag/dlmm';
import { Connection, PublicKey } from '@solana/web3.js';

// Option A: Known pool addresses (hardcode the pools you care about)
const knownPools = [
  'YOUR_POOL_ADDRESS_1',
  'YOUR_POOL_ADDRESS_2',
];

const meteoraPositions = [];
for (const poolAddress of knownPools) {
  const dlmmPool = await DLMM.create(connection, new PublicKey(poolAddress));
  const { userPositions } = await dlmmPool.getPositionsByUserAndLbPair(
    new PublicKey(ownerAddress)
  );
  meteoraPositions.push(...userPositions.map(p => ({
    protocol: 'meteora',
    positionId: p.publicKey.toBase58(),
    poolAddress,
    binLower: p.positionData.lowerBinId,
    binUpper: p.positionData.upperBinId,
    feeOwedX: p.positionData.feeX.toString(),
    feeOwedY: p.positionData.feeY.toString(),
    activeBinId: dlmmPool.lbPair.activeId,
  })));
}

// Option B: Discover all Meteora positions from on-chain accounts
// Use getProgramAccounts filtering by owner on DLMM program:
import { DLMM_PROGRAM_ID } from '@meteora-ag/dlmm';
const accounts = await connection.getProgramAccounts(
  new PublicKey('LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo'),
  {
    filters: [
      { memcmp: { offset: 8 + 32, bytes: ownerAddress } } // owner at offset 40
    ]
  }
);
// Each account is a position — parse with DLMM SDK
```

## Unified Position Monitor

```typescript
interface CLMMPosition {
  protocol: 'orca' | 'raydium' | 'meteora';
  positionId: string;
  poolAddress: string;
  rangeLower: number;     // tick or bin ID
  rangeUpper: number;
  currentTick: number;    // pool's current tick or bin ID
  isInRange: boolean;
  liquidity: string;
  feeOwedA: string;
  feeOwedB: string;
}

async function fetchAllPositions(ownerAddress: string): Promise<CLMMPosition[]> {
  const [orca, raydium, meteora] = await Promise.allSettled([
    fetchOrcaPositions(ownerAddress),
    fetchRaydiumPositions(ownerAddress),
    fetchMeteoraPositions(ownerAddress),
  ]);

  const results: CLMMPosition[] = [];

  if (orca.status === 'fulfilled') results.push(...orca.value);
  if (raydium.status === 'fulfilled') results.push(...raydium.value);
  if (meteora.status === 'fulfilled') results.push(...meteora.value);

  // Use allSettled so one protocol failing doesn't break the others
  return results;
}

// Summary report:
function summarizePositions(positions: CLMMPosition[]) {
  const inRange = positions.filter(p => p.isInRange);
  const outOfRange = positions.filter(p => !p.isInRange);

  console.log(`\n=== Position Summary ===`);
  console.log(`Total: ${positions.length} | In range: ${inRange.length} | Out of range: ${outOfRange.length}`);

  for (const p of outOfRange) {
    const direction = p.currentTick < p.rangeLower ? 'BELOW range' : 'ABOVE range';
    console.log(`⚠️  ${p.protocol.toUpperCase()} ${p.positionId.slice(0, 8)}... — ${direction}`);
  }

  for (const p of inRange) {
    console.log(`✓  ${p.protocol.toUpperCase()} ${p.positionId.slice(0, 8)}... — in range`);
  }
}
```

## Rate Limiting & RPC Considerations

Fetching positions across three protocols in parallel means multiple RPC calls. Use a dedicated RPC node (Helius, Triton, QuickNode) rather than `api.mainnet-beta.solana.com` for production monitors:

```typescript
const RPC_URL = process.env.SOLANA_RPC_URL ?? 'https://api.mainnet-beta.solana.com';
// Helius: https://mainnet.helius-rpc.com/?api-key=YOUR_KEY
// Triton: https://YOUR_NAME.rpcpool.com/YOUR_KEY
```

For Raydium on mainnet, prefer the Data API for pool info (fewer RPC calls) and fall back to direct RPC for real-time price before executing transactions.
