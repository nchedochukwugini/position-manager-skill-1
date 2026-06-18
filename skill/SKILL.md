# CLMM Position Manager Skill

> **AI coding assistant skill** — teaches agents how to build tools that track, monitor, and rebalance concentrated liquidity positions across Solana's three major CLMM protocols.

## Quick Task Router

| What you need to do | Load this file |
|---|---|
| Check if a position is in-range or out-of-range | [range-check.md](./range-check.md) |
| Calculate impermanent loss for a position | [impermanent-loss.md](./impermanent-loss.md) |
| Decide when and how to rebalance | [rebalance-strategy.md](./rebalance-strategy.md) |
| Work with **Orca Whirlpools** specifically | [protocols/orca-whirlpools.md](./protocols/orca-whirlpools.md) |
| Work with **Raydium CLMM** specifically | [protocols/raydium-clmm.md](./protocols/raydium-clmm.md) |
| Work with **Meteora DLMM** specifically | [protocols/meteora-dlmm.md](./protocols/meteora-dlmm.md) |
| Fetch all positions for a wallet (all protocols) | [fetch-positions.md](./fetch-positions.md) |
| SDKs, program IDs, API references | [resources.md](./resources.md) |

---

## What This Skill Covers

Concentrated liquidity positions on Solana's three major CLMMs — **Orca Whirlpools**, **Raydium CLMM**, and **Meteora DLMM** — all share the same core challenge: liquidity only earns fees when the market price is inside the position's defined range. When price moves out of range, the position goes idle and the LP is exposed to impermanent loss without any fee income to compensate.

This skill teaches agents how to:
1. **Detect** whether a position is currently in-range or out-of-range
2. **Quantify** impermanent loss across all three protocols
3. **Decide** when to rebalance (fee income vs. gas cost vs. IL tradeoff)
4. **Execute** rebalance operations via the appropriate SDK

## Protocol Comparison at a Glance

| | Orca Whirlpools | Raydium CLMM | Meteora DLMM |
|---|---|---|---|
| **Program ID (mainnet)** | `whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc` | `CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK` | `LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo` |
| **Price model** | Tick-based (Uniswap V3 style) | Tick-based (Uniswap V3 style) | Bin-based (discrete fixed-price bins) |
| **Position NFT** | Yes — position is an SPL NFT | No — PDA per owner/pool | No — PDA per owner/pool |
| **SDK** | `@orca-so/whirlpools` + `@solana/kit` | `@raydium-io/raydium-sdk-v2` | `@meteora-ag/dlmm` |
| **Range check** | `tickLower <= tickCurrent < tickUpper` | `tickLower <= tickCurrent < tickUpper` | `activeBinId` inside position's bin range |
| **Fee model** | Fixed tiers (0.01%–2%) + Adaptive | Fixed tiers per AmmConfig | Dynamic fees based on volatility |

## Key Concept: In-Range vs Out-of-Range

For Orca and Raydium (tick-based):
```
IN RANGE:  tickLower <= tickCurrentIndex < tickUpper  → earning fees ✓
OUT OF RANGE:  tickCurrentIndex < tickLower  → all tokenB, no fees ✗
              tickCurrentIndex >= tickUpper  → all tokenA, no fees ✗
```

For Meteora (bin-based):
```
IN RANGE:  lbPair.activeId is within [position.lowerBinId, position.upperBinId]  → earning fees ✓
OUT OF RANGE:  activeId outside position bin range  → no fees ✗
```

> **Load protocol-specific files only when needed** — each file is self-contained with verified constants, SDK patterns, and code examples for that protocol only.
