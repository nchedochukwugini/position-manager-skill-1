# Range Check — Quick Reference

> Fast reference for checking if a CLMM position is in-range or out-of-range

## Universal Pattern

```
IN RANGE  = current price is inside position bounds → earning fees ✓
OUT OF RANGE = current price is outside bounds → no fees, IL accumulating ✗
```

## Orca / Raydium (Tick-Based)

```typescript
// IN RANGE when:
tickLowerIndex <= tickCurrentIndex < tickUpperIndex

// Check:
const inRange = pool.tickCurrentIndex >= position.tickLowerIndex &&
                pool.tickCurrentIndex < position.tickUpperIndex;

// Direction:
if (pool.tickCurrentIndex < position.tickLowerIndex) {
  // BELOW range — position holds 100% tokenB
} else if (pool.tickCurrentIndex >= position.tickUpperIndex) {
  // ABOVE range — position holds 100% tokenA
}
```

**Fetch current tick:**
- Orca: `(await fetchWhirlpool(rpc, poolAddress)).data.tickCurrentIndex`
- Raydium: `(await raydium.clmm.getRpcClmmPoolInfo({ poolId })).currentPrice` → convert to tick

## Meteora DLMM (Bin-Based)

```typescript
// IN RANGE when:
lowerBinId <= activeBinId <= upperBinId

// Check:
await dlmmPool.refetchStates(); // always refresh before checking
const activeBinId = dlmmPool.lbPair.activeId;
const inRange = activeBinId >= position.positionData.lowerBinId &&
                activeBinId <= position.positionData.upperBinId;

// Direction:
if (activeBinId < position.positionData.lowerBinId) {
  // BELOW range — position holds 100% tokenY
} else if (activeBinId > position.positionData.upperBinId) {
  // ABOVE range — position holds 100% tokenX
}
```

## Common Mistakes

| Mistake | Fix |
|---|---|
| Using `<=` for upper tick on Orca/Raydium | Upper bound is **exclusive**: use `< tickUpper` |
| Using `<` for upper bin on Meteora | Meteora upper bound is **inclusive**: use `<= upperBinId` |
| Not refreshing Meteora pool state | Always call `dlmmPool.refetchStates()` before checking |
| Using cached Raydium pool data | Call `getRpcClmmPoolInfo` for real-time tick before transacting |
| Treating Orca tickCurrentIndex as price | Convert with `tickToPrice(tick, decimalsA, decimalsB)` first |

## Batch Check (All Positions)

```typescript
async function checkAllPositions(positions: CLMMPosition[]): Promise<void> {
  for (const pos of positions) {
    const inRange = pos.isInRange;
    const symbol = inRange ? '✓' : '⚠️ ';
    const status = inRange ? 'IN RANGE' : (
      pos.currentTick < pos.rangeLower ? 'BELOW range' : 'ABOVE range'
    );
    console.log(`${symbol} ${pos.protocol} | ${pos.positionId.slice(0,8)}... | ${status}`);
  }
}
```
