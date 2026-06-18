# Rebalance Strategy — CLMM Positions

> When to rebalance, how wide to set the new range, and protocol-specific execution patterns

## The Core Decision

Rebalancing means closing an existing position and opening a new one centered around the current price. It has costs:
- **Gas**: transaction fees (~0.0088 SOL rent creation + tx fees on Orca/Raydium)
- **Slippage**: reinvesting proceeds into a new range at current market price
- **Timing risk**: price may move further during the rebalance transaction

Rebalancing is only worth it when the benefit (resumed fee income, reduced IL exposure) exceeds these costs.

## Decision Framework

```typescript
interface RebalanceDecision {
  shouldRebalance: boolean;
  reason: string;
  urgency: 'immediate' | 'soon' | 'monitor' | 'hold';
}

function evaluateRebalance(params: {
  isInRange: boolean;
  hoursOutOfRange: number;
  dailyFeeRateAPR: number;     // e.g. 0.50 = 50% APR from fees
  positionValueUSD: number;
  estimatedGasCostUSD: number;
  ilPercent: number;           // negative number, e.g. -0.023
  feesCoveredIL: boolean;
}): RebalanceDecision {
  const { isInRange, hoursOutOfRange, dailyFeeRateAPR, positionValueUSD,
          estimatedGasCostUSD, ilPercent, feesCoveredIL } = params;

  // Daily fee income estimate
  const dailyFeeUSD = positionValueUSD * (dailyFeeRateAPR / 365);

  // Days until gas cost is recovered from fee income
  const daysToRecoverGas = estimatedGasCostUSD / dailyFeeUSD;

  if (isInRange) {
    // Position is earning — only rebalance if range is dangerously narrow
    return { shouldRebalance: false, reason: 'In range, earning fees', urgency: 'monitor' };
  }

  if (hoursOutOfRange < 2) {
    // Too early to tell — could be temporary wick
    return { shouldRebalance: false, reason: 'Recently out of range, monitoring', urgency: 'monitor' };
  }

  if (daysToRecoverGas > 30) {
    // Gas cost too high relative to position size
    return {
      shouldRebalance: false,
      reason: `Gas recovery (${daysToRecoverGas.toFixed(0)}d) exceeds 30-day threshold`,
      urgency: 'hold'
    };
  }

  if (!feesCoveredIL && Math.abs(ilPercent) > 0.10) {
    // More than 10% IL and fees haven't caught up — urgent rebalance
    return { shouldRebalance: true, reason: 'IL > 10%, fees insufficient', urgency: 'immediate' };
  }

  if (hoursOutOfRange > 24) {
    // Out of range for over a day — resume fee income
    return { shouldRebalance: true, reason: 'Out of range > 24h, lost fee income', urgency: 'soon' };
  }

  return { shouldRebalance: false, reason: 'Monitoring', urgency: 'monitor' };
}
```

## Range Width Strategy

Range width is the biggest lever for LP strategy. Tighter = more fees when in range, more rebalances needed. Wider = fewer rebalances, less fee income per dollar deployed.

```typescript
/**
 * Calculate tick bounds for a new position centered at current price.
 * @param currentPrice  Current pool price
 * @param rangeWidthPct Desired range as ± percentage (e.g. 0.10 = ±10%)
 * @param tickSpacing   Pool's tick spacing (must divide evenly)
 * @param decimalsA     Token A decimals
 * @param decimalsB     Token B decimals
 */
function calculateNewRange(
  currentPrice: number,
  rangeWidthPct: number,
  tickSpacing: number,
  decimalsA: number,
  decimalsB: number
): { tickLower: number; tickUpper: number; priceLower: number; priceUpper: number } {
  const priceLower = currentPrice * (1 - rangeWidthPct);
  const priceUpper = currentPrice * (1 + rangeWidthPct);

  const rawTickLower = Math.floor(
    Math.log(priceLower * Math.pow(10, decimalsB - decimalsA)) / Math.log(1.0001)
  );
  const rawTickUpper = Math.floor(
    Math.log(priceUpper * Math.pow(10, decimalsB - decimalsA)) / Math.log(1.0001)
  );

  // Snap to valid tick spacing
  const tickLower = Math.floor(rawTickLower / tickSpacing) * tickSpacing;
  const tickUpper = Math.ceil(rawTickUpper / tickSpacing) * tickSpacing;

  return {
    tickLower,
    tickUpper,
    priceLower: Math.pow(1.0001, tickLower) * Math.pow(10, decimalsA - decimalsB),
    priceUpper: Math.pow(1.0001, tickUpper) * Math.pow(10, decimalsA - decimalsB),
  };
}
```

## Range Width Guidance by Asset Type

| Pair type | Suggested range | Rebalance frequency |
|---|---|---|
| Stablecoin/stablecoin (USDC/USDT) | ±0.5% | Rare |
| Liquid staking (SOL/mSOL) | ±3–5% | Monthly |
| Major volatile (SOL/USDC) | ±10–20% | Weekly |
| High volatility / new token | ±30–50% | As needed |

## Protocol-Specific Rebalance Notes

### Orca Whirlpools
- Rebalance = `closePosition` → `openConcentratedPosition`
- Atomic close+open is **not** possible in a single transaction — there's a gap between close and open where funds sit in wallet
- Cost: ~0.0088 SOL rent (refunded from close, re-paid on open = net zero), plus tx fees
- Watch for `0x0` (NotRentExempt) if TickArray for new range needs initialization first

### Raydium CLMM
- Rebalance = `decreaseLiquidity` (with `closePosition: true`) → `openPositionFromLiquidity`
- **Always fetch live pool price** via `getRpcClmmPoolInfo` before opening new position — API cache can be stale
- On mainnet: verify `isValidClmm(poolInfo.programId)` before any operation

### Meteora DLMM
- **Prefer `rebalance_liquidity`** over close + open when possible — single instruction, more gas-efficient
- `rebalance_liquidity` supports `shrink_mode` to reduce position bin count without full close
- For major rebalances: `removeLiquidity` (with `shouldClaimAndClose: true`) → `initializePositionAndAddLiquidityByStrategy`
- New range: use bin IDs, not ticks — calculate with `binToPrice()` / `priceToBin()`

## Automated Agent Loop Pattern

```typescript
async function lpManagementLoop(
  walletAddress: string,
  rpc: SolanaRpc,
  intervalMs: number = 60_000
) {
  while (true) {
    // 1. Fetch all positions
    const positions = await fetchAllPositions(walletAddress, rpc);

    for (const pos of positions) {
      // 2. Check range status
      const poolState = await fetchPoolState(pos.poolAddress, rpc);
      const status = getRangeStatus(pos, poolState);

      // 3. Calculate IL and fees
      const il = approximateIL(pos.entryPrice, poolState.currentPrice);
      const feesUSD = estimateFeesUSD(pos.feesOwed, tokenPrices);

      // 4. Evaluate rebalance
      const decision = evaluateRebalance({
        isInRange: status === 'in-range',
        hoursOutOfRange: pos.hoursOutOfRange,
        dailyFeeRateAPR: pos.pool.feeApr,
        positionValueUSD: pos.valueUSD,
        estimatedGasCostUSD: 0.15,  // ~0.009 SOL at current prices
        ilPercent: il,
        feesCoveredIL: feesUSD > Math.abs(il) * pos.valueUSD,
      });

      // 5. Execute if needed
      if (decision.shouldRebalance) {
        console.log(`Rebalancing position ${pos.id}: ${decision.reason}`);
        await rebalancePosition(pos, poolState, rpc);
      } else {
        console.log(`Position ${pos.id}: ${decision.reason} [${decision.urgency}]`);
      }
    }

    await new Promise(resolve => setTimeout(resolve, intervalMs));
  }
}
```

## Harvest-Only Strategy

If rebalancing is too expensive (small position, high gas) but fees have accumulated, harvesting without closing preserves the position and captures income:

- **Orca**: `harvestPosition(positionMint)` — collects fees, keeps position open
- **Raydium**: `collectRewards()` — collects fees, keeps position open
- **Meteora**: `claimFee(user, [positionPubKey])` — collects fees, keeps position open

Harvest when: fee income > harvest gas cost. Typically worth it when fees > $1–2 for mainnet.
