# Resources & References

> Verified links and package versions — June 2026

## Program IDs (Mainnet)

| Protocol | Program ID |
|---|---|
| Orca Whirlpools | `whirLbMiicVdio4qvUfM5KAg6Ct8VwpYzGff3uctyCc` |
| Raydium CLMM | `CAMMCzo5YL8w4VFF8KVHrK22GGUsp5VTaW7grrKgrWqK` |
| Meteora DLMM | `LBUZKhRxPF3XUpBCjp4YzTKgLccjZhTSDM9YuVaPwxo` |

## SDKs

| Protocol | Package | Install |
|---|---|---|
| Orca (current) | `@orca-so/whirlpools` + `@solana/kit` | `npm install @orca-so/whirlpools @solana/kit` |
| Orca (legacy, Web3.js v1) | `@orca-so/whirlpools-sdk` | `npm install @orca-so/whirlpools-sdk` |
| Raydium | `@raydium-io/raydium-sdk-v2` | `npm install @raydium-io/raydium-sdk-v2` |
| Meteora DLMM | `@meteora-ag/dlmm` | `npm install @meteora-ag/dlmm` |

> **Note on Orca SDKs**: `@orca-so/whirlpools` uses `@solana/kit` (Web3.js v2). The legacy `@orca-so/whirlpools-sdk` uses `@solana/web3.js` (v1) and remains supported but is not recommended for new projects.

## Official Documentation

### Orca
- Docs: https://docs.orca.so
- LLM-friendly index: https://docs.orca.so/llms.txt
- MCP server (AI tool): `https://docs.orca.so/mcp` — tool: `SearchOrcaDocumentation`
- SDK GitHub: https://github.com/orca-so/whirlpools
- AI agents guide: https://docs.orca.so/reference/ai-agents
- Position monitoring: https://docs.orca.so/developers/sdks/positions/monitor-positions
- REST API explorer: https://api.orca.so/docs

### Raydium
- Docs: https://docs.raydium.io
- CLMM guide: https://docs.raydium.io/raydium/build/developer-guides/clmm
- SDK GitHub: https://github.com/raydium-io/raydium-sdk-V2
- Demo repo: https://github.com/raydium-io/raydium-sdk-V2-demo/tree/master/src/clmm

### Meteora
- Docs: https://docs.meteora.ag
- DLMM overview: https://docs.meteora.ag/developer-guide/guides/dlmm/overview
- SDK GitHub: https://github.com/meteora-ag/dlmm-sdk

## Devnet Test Pools

| Protocol | Pool | Pair |
|---|---|---|
| Orca | `3KBZiL2g8C7tiJ32hTv5v3KM7aK9htpqTw4cTXz1HvPt` | SOL/devUSDC (tick spacing 8) |
| Raydium | Use `DEVNET_PROGRAM_ID.CLMM_PROGRAM_ID` + `getClmmConfigs()` to create |  |
| Meteora | Same program ID as mainnet — create a pool via SDK |  |

## Common Token Mints

| Token | Mint |
|---|---|
| Wrapped SOL | `So11111111111111111111111111111111111111112` |
| USDC (mainnet) | `EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v` |
| devUSDC (devnet) | `BRjpCHtyQLNCo8gqRUr8jtdAj5AjPYQaoqbvcZiHok1k` |

## RPC Providers (Recommended for Production)

| Provider | Notes |
|---|---|
| Helius | https://helius.dev — Solana-native, good for `getProgramAccounts` |
| Triton | https://triton.one — High throughput |
| QuickNode | https://quicknode.com — Multi-chain |

Avoid `api.mainnet-beta.solana.com` for production position monitors — rate limits will cause failures on multi-protocol fetches.

## Related Skills in Solana AI Kit

- `solana-dev-skill` — core Solana setup, wallet, RPC, testing
- `sendaifun/skills` — broader DeFi protocol integrations (Jupiter, Kamino, perps)
- `jup-ag/agent-skills` — Jupiter swap integration
