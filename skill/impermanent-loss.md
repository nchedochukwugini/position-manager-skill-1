# Impermanent Loss — CLMM Positions

> Applies to Orca Whirlpools, Raydium CLMM, and Meteora DLMM

## What Is Impermanent Loss in a CLMM?

In a standard AMM (x*y=k), IL affects LPs across the full price range. In a CLMM, IL is **amplified** because capital is concentrated in a narrow range — the same price move causes proportionally more IL within that range.

Additionally, CLMM positions have three states with different IL behavior:
- **In range**: actively earning fees; IL is accumulating but partially offset by fees
- **Out of range (below)**: position becomes 100% tokenB; no fees earned; IL is "locked"
- **Out of range (above)**: position becomes 100% tokenA; no fees earned; IL is "locked"

## Core IL Formula (In-Range)

For a CLMM position, impermanent loss when price moves from `P₀` to `P₁`:

```typescript
/**
 * Calculate impermanent loss for a CLMM position.
 * Returns IL as a negative percentage (e.g. -0.023 = -2.3% loss)
 *
 * @param P0 - Entry price (tokenA per tokenB)
 * @param P1 - Current price
 * @param Pa - Lower bound price of position
 * @param Pb - Upper bound price of position
 */
function calculateCLMMImpermanentLoss(
  P0: number,
  P1: number,
  Pa: number,
  Pb: number
): number {
  // Clamp prices to position range (out-of-range positions use boundary price)
  const P0c = Math.max(Pa, Math.min(Pb, P0));
  const P1c = Math.max(Pa, Math.min(Pb, P1));

  const sqrtP0 = Math.sqrt(P0c);
  const sqrtP1 = Math.sqrt(P1c);
  const sqrtPa = Math.sqrt(Pa);
  const sqrtPb = Math.sqrt(Pb);

  // Value of position at P0 (as LP)
  const L = 1; // normalized liquidity unit
  const valueLP_P0 = L * (sqrtP0 - sqrtPa) + L * (1/sqrtP0 - 1/sqrtPb);

  // Value of position at P1 (as LP)
  const valueLP_P1 = L * (sqrtP1 - sqrtPa) + L * (1/sqrtP1 - 1/sqrtPb);

  // Value if held (not providing liquidity) — based on initial token split at P0
  // Simplified: use standard IL formula adjusted for CLMM range
  const priceRatio = P1 / P0;
  const sqrtRatio = Math.sqrt(priceRatio);

  // Standard CLMM IL relative to holding
  const valueHeld = valueLP_P0 * (sqrtRatio + 1/sqrtRatio) / 2;
  // Approximation — see note below for exact formula

  return (valueLP_P1 - valueHeld) / valueHeld;
}
```

## Simplified IL Formula (Practical Approximation)

For quick estimates, the classic AMM IL formula gives a good directional signal:

```typescript
/**
 * Classic IL formula — good approximation for in-range CLMM positions.
 * Returns IL as a decimal (e.g. -0.023 = -2.3%)
 */
function approximateIL(entryPrice: number, currentPrice: number): number {
  const priceRatio = currentPrice / entryPrice;
  const sqrtRatio = Math.sqrt(priceRatio);
  // IL = 2*sqrt(r) / (1+r) - 1
  return (2 * sqrtRatio) / (1 + priceRatio) - 1;
}

// Reference values:
// 1.25x price move → ~0.6% IL
// 1.50x price move → ~2.0% IL
// 2.00x price move → ~5.7% IL
// 3.00x price move → ~13.4% IL
// 5.00x price move → ~25.5% IL
```

## IL vs. Fees: Break-Even Analysis

IL only represents a real loss if it exceeds accumulated fees. Break-even check:

```typescript
interface PositionSnapshot {
  entryPrice: number;
  currentPrice: number;
  priceLower: number;
  priceUpper: number;
  feesCollectedUSD: number;
  initialValueUSD: number;
}

function isILCoveredByFees(snapshot: PositionSnapshot): {
  ilPct: number;
  ilUSD: number;
  netPnL: number;
  recommendation: string;
} {
  const ilPct = approximateIL(snapshot.entryPrice, snapshot.currentPrice);
  const ilUSD = Math.abs(ilPct) * snapshot.initialValueUSD;
  const netPnL = snapshot.feesCollectedUSD - ilUSD;

  return {
    ilPct,
    ilUSD,
    netPnL,
    recommendation: netPnL > 0
      ? `Profitable: fees (+$${snapshot.feesCollectedUSD.toFixed(2)}) exceed IL (-$${ilUSD.toFixed(2)})`
      : `Loss: IL (-$${ilUSD.toFixed(2)}) exceeds fees (+$${snapshot.feesCollectedUSD.toFixed(2)}). Consider rebalancing.`
  };
}
```

## Out-of-Range IL: Single-Asset Exposure

When a position is fully out of range, it holds only one token. IL at this point is the difference between:
- Holding both tokens at original split
- Holding only one token (what the position actually holds)

```typescript
/**
 * IL when position is fully out of range.
 * outOfRangeToken: 'A' = price above range (holds all tokenA)
 *                  'B' = price below range (holds all tokenB)
 */
function outOfRangeIL(
  entryPrice: number,
  currentPrice: number,
  boundaryPrice: number,   // tickUpper price if above, tickLower price if below
  outOfRangeToken: 'A' | 'B'
): number {
  const priceAtExit = boundaryPrice;  // position stopped changing at the boundary
  const holdValue = (entryPrice + currentPrice) / 2; // approx hold value per unit

  if (outOfRangeToken === 'A') {
    // All in tokenA — if price dropped below range, tokenA lost value
    return (currentPrice / entryPrice) - 1;  // pure price exposure in tokenA
  } else {
    // All in tokenB — if price rose above range, missed upside in tokenA
    return (entryPrice / currentPrice) - 1;  // opportunity cost
  }
}
```

## Meteora DLMM: Bin-Based IL

For Meteora, the concepts are the same but price uses bin math:

```typescript
// Convert bin IDs to prices first, then apply same IL formulas
const entryPrice = binToPrice(entryBinId, binStep, decimalsX, decimalsY);
const currentPrice = binToPrice(activeBinId, binStep, decimalsX, decimalsY);
const lowerPrice = binToPrice(lowerBinId, binStep, decimalsX, decimalsY);
const upperPrice = binToPrice(upperBinId, binStep, decimalsX, decimalsY);

// Then use same IL formulas above with these prices
const il = approximateIL(entryPrice, currentPrice);
```

## Key Takeaways

1. CLMM IL is **amplified** vs. standard AMM IL — narrower range = more capital efficiency = more IL on same price move
2. Out-of-range positions have **frozen IL** — the loss stops growing but so does fee income
3. Fees are the natural hedge against IL — compare accumulated fees vs. IL before rebalancing
4. Meteora's dynamic fees are designed to increase during high-volatility periods — exactly when IL is highest
