# position-manager-skill

> A Solana AI Kit skill for building CLMM position management tools — track impermanent loss, detect out-of-range positions, and suggest rebalances across **Orca Whirlpools**, **Raydium CLMM**, and **Meteora DLMM**.

## The Problem

Concentrated liquidity positions only earn fees when the market price is inside a defined range. When price moves out of range, the position goes idle — no fee income, but impermanent loss continues to grow. Builders creating LP dashboards, position bots, or DeFi tools need to reason correctly across all three major Solana CLMMs, each with different account structures, math models, and SDKs.

There was no single reference that covered all three protocols together with current SDK patterns, verified program IDs, and actionable decision logic. This skill fills that gap.

## What This Skill Teaches

- How to **detect** in-range vs. out-of-range status for Orca, Raydium, and Meteora positions
- How to **calculate impermanent loss** across tick-based (Orca/Raydium) and bin-based (Meteora) models
- How to **decide when to rebalance** based on fee income vs. IL vs. gas cost tradeoffs
- How to **execute rebalances** using each protocol's current SDK (not deprecated patterns)
- How to **enumerate all positions** for a wallet across all three protocols in a unified way

## Structure

```
position-manager-skill/
├── README.md
├── install.sh
├── skill/
│   ├── SKILL.md                      # Entry point — task router
│   ├── range-check.md                # Quick reference for in/out-of-range checks
│   ├── impermanent-loss.md           # IL formulas and fee break-even analysis
│   ├── rebalance-strategy.md         # When/how to rebalance, range width guidance
│   ├── fetch-positions.md            # Cross-protocol wallet position enumeration
│   ├── resources.md                  # Program IDs, SDKs, RPC, doc links
│   └── protocols/
│       ├── orca-whirlpools.md        # Orca-specific constants, SDK patterns, errors
│       ├── raydium-clmm.md           # Raydium-specific constants and SDK patterns
│       └── meteora-dlmm.md           # Meteora bin model, strategies, SDK patterns
└── agents/
    └── position-analyst.md           # Agent config for LP position analysis
```

The skill uses **progressive loading** — `SKILL.md` routes to the minimal set of files needed for each task, avoiding unnecessary context consumption.

## Install

```bash
chmod +x install.sh && ./install.sh
```

Or manually copy the `skill/` folder into your `.claude/skills/` directory:

```bash
cp -r skill/ /path/to/your/project/.claude/skills/position-manager-skill/
```

## Usage with Claude Code

After installing, reference the skill in your Claude Code session:

```
Load the position-manager-skill and help me build a script that checks 
all my Orca Whirlpools positions for out-of-range status.
```

Or use the agent directly:

```
Use the position-analyst agent to analyze my wallet's LP positions 
and recommend any rebalances.
```

## Protocol Coverage

| Protocol | Program ID (mainnet) | Model | SDK |
|---|---|---|---|
| Orca Whirlpools | `whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc` | Tick-based | `@orca-so/whirlpools` + `@solana/kit` |
| Raydium CLMM | `CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK` | Tick-based | `@raydium-io/raydium-sdk-v2` |
| Meteora DLMM | `LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo` | Bin-based | `@meteora-ag/dlmm` |

## Content Accuracy

All program IDs, SDK function signatures, and protocol constants are verified against official documentation as of **June 2026**:
- Orca: [docs.orca.so/llms.txt](https://docs.orca.so/llms.txt)
- Raydium: [docs.raydium.io/raydium/build/developer-guides/clmm](https://docs.raydium.io/raydium/build/developer-guides/clmm)
- Meteora: [docs.meteora.ag/developer-guide/guides/dlmm/overview](https://docs.meteora.ag/developer-guide/guides/dlmm/overview)

## License

MIT — Copyright (c) 2026
