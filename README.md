# Oracle Pool

Ergo-inspired oracle pool protocol for Cardano. On-chain data aggregation with
transparent individual oracle submissions, consumed by dApps via CIP-31 reference
inputs at zero cost.

**Status:** Specification — contracts not yet implemented.

## What This Is

A fully on-chain oracle pool where:

- Multiple oracle operators independently post data points as individual UTxOs
- A smart contract aggregates them (average with outlier filtering)
- Any dApp reads the finalized value via reference inputs (free, no contention)
- Every individual submission is visible on-chain (full transparency)
- Oracle operators earn reward tokens for timely, accurate data

This differs from existing Cardano oracles (Orcfax, Charli3) which aggregate
off-chain and only post the final value. Here, aggregation is deterministic,
verifiable, and enforced by validators.

## Architecture

5 validators governing 5 UTxO types:

| Validator | Purpose |
|-----------|---------|
| **Pool** | Holds finalized aggregated rate, consumed via reference input |
| **Refresh** | Triggers epoch transitions, validates and aggregates data points |
| **Oracle** | One per operator — posts data, accumulates rewards |
| **Ballot** | Governance voting for parameter changes |
| **Update** | Contract upgrade mechanism |

See [docs/SPECIFICATION.md](docs/SPECIFICATION.md) for the full design.

## Building

```sh
aiken build
```

## Testing

```sh
aiken check
```

## Project Structure

```
oracle_pool/
├── docs/
│   └── SPECIFICATION.md    # Full protocol specification
├── validators/             # Aiken validator contracts (Phase 1)
├── lib/                    # Shared types and helpers
├── aiken.toml              # Project config (Plutus V3, stdlib v3.0.0)
└── README.md
```

## Implementation Phases

1. **Core Contracts** — Pool, Oracle, Refresh validators + bootstrap mint
2. **Off-Chain Tooling** — Oracle operator CLI, monitoring
3. **Governance** — Ballot and Update validators
4. **Testnet Deployment** — Preview testnet with ADAvault SPO operators
5. **Hardening** — Security audit, edge cases, execution budget optimization

## Background

Adapted from [Ergo Oracle Pools v2 (EIP-0023)](https://github.com/ergoplatform/eips/pull/41)
for Cardano's eUTXO model using CIP-31 reference inputs, CIP-32 inline datums,
and CIP-33 reference scripts.

## License

Apache-2.0
