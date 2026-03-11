# Oracle Pool Protocol — Specification

**Version:** 0.1.0 (Draft)
**Target:** Cardano (Plutus V3 / Aiken v1.1.21)
**Inspired by:** Ergo Oracle Pools v2 (EIP-0023)

---

## Overview

An on-chain oracle pool protocol for Cardano where multiple independent oracle
operators post data points as individual UTxOs. A smart contract aggregates them
into a single finalized value that any dApp can consume via CIP-31 reference
inputs — at zero cost.

This is distinct from existing Cardano oracles (Orcfax, Charli3) which aggregate
off-chain and only post the final value. Here, every individual oracle submission
is on-chain and the aggregation is deterministic, verifiable, and enforced by
validators.

### Design Goals

1. **Full transparency** — every oracle data point visible on-chain
2. **On-chain aggregation** — deterministic, verifiable, no trusted aggregator
3. **Free consumption** — dApps read oracle data via reference inputs (CIP-31)
4. **SPO-friendly** — natural fit for stake pool operators as oracle providers
5. **Minimal trust** — smart contracts enforce all rules, no off-chain consensus

---

## Architecture

### Contract Types

The protocol uses 5 validator contracts governing 5 UTxO types:

```
┌─────────────┐     reference input (CIP-31)
│  Pool Box    │◄──────────────────────────── dApps read finalized rate
│  (1 UTxO)    │
└──────┬───────┘
       │ spent + recreated by refresh tx
       │
┌──────┴───────┐     spends oracle boxes
│ Refresh Box  │◄─── triggers aggregation
│  (1 UTxO)    │     any oracle can submit
└──────────────┘
       │ reads N oracle boxes
       │
┌──────────────┐
│ Oracle Boxes │     one per operator (5-7 initially)
│  (N UTxOs)   │     each posts individual data point
└──────────────┘

┌──────────────┐     ┌──────────────┐
│ Ballot Boxes │     │  Update Box  │
│  (N UTxOs)   │     │  (1 UTxO)    │
└──────────────┘     └──────────────┘
     governance voting        contract upgrades
```

### Token Inventory

| Token | Quantity | Purpose |
|-------|----------|---------|
| Pool NFT | 1 | Identifies the canonical pool UTxO |
| Refresh NFT | 1 | Identifies the refresh UTxO, gates aggregation |
| Update NFT | 1 | Identifies the update UTxO, gates governance |
| Oracle Token | N (one per operator) | Identifies oracle UTxOs, proves membership |
| Ballot Token | N (one per operator) | Voting rights for governance |
| Reward Token | Large supply (e.g. 100M) | Epoch rewards for oracle operators |

All tokens are minted in a single bootstrap transaction.

---

## Data Types

### Pool Datum

```aiken
pub type PoolDatum {
  /// Finalized aggregated rate (e.g. ADA/USD price in millionths)
  rate: Int,
  /// Epoch counter — incremented each refresh
  epoch: Int,
}
```

### Oracle Datum

```aiken
pub type OracleDatum {
  /// Operator's verification key hash (28 bytes)
  owner: ByteArray,
  /// Epoch counter when this data point was posted
  epoch: Int,
  /// The oracle's reported rate
  rate: Int,
}
```

### Refresh Redeemer

```aiken
pub type RefreshRedeemer {
  /// Sorted list of (oracle_index, rate) from tx inputs
  /// Validator checks each against the actual input data
  oracle_data: List<Pair<Int, Int>>,
}
```

### Ballot Datum

```aiken
pub type BallotDatum {
  /// Voter's verification key hash
  voter: ByteArray,
  /// Hash of the proposed new pool script
  new_pool_script_hash: ByteArray,
  /// Creation slot of the update box this vote targets
  update_slot: Int,
}
```

### Pool Parameters (compile-time or parameterized)

```aiken
pub type PoolParams {
  /// Minimum oracle submissions required for a valid refresh
  min_data_points: Int,
  /// Maximum allowed deviation: (max - min) <= max * max_deviation_pct / 100
  max_deviation_pct: Int,
  /// Minimum slots between refreshes (epoch length)
  epoch_length: Int,
  /// Reward tokens distributed per refresh: 2N (N per oracle + N bonus to collector)
  reward_per_oracle: Int,
  /// Policy ID of the oracle tokens
  oracle_token_policy: ByteArray,
  /// Pool NFT policy ID
  pool_nft_policy: ByteArray,
  /// Refresh NFT policy ID
  refresh_nft_policy: ByteArray,
}
```

---

## Validator Logic

### 1. Pool Validator (spend)

The pool box holds the finalized rate. It can only be spent when accompanied by
either the refresh NFT or the update NFT in the same transaction.

```
Validation:
  - Second input contains refresh_nft OR update_nft
  - Pool NFT preserved in output
  - (All other rules enforced by refresh/update validators)
```

This minimal design keeps the pool validator small (cheap to reference) and
delegates complex logic to the refresh and update validators.

### 2. Refresh Validator (spend)

The refresh box triggers epoch transitions. When spent, it:

1. **Reads oracle boxes** from tx inputs (identified by oracle tokens)
2. **Validates data points:**
   - Count >= `min_data_points`
   - All rates > 0
   - Rates sorted ascending (enforced by redeemer, checked against inputs)
   - Deviation check: `(max_rate - min_rate) * 100 <= max_rate * max_deviation_pct`
3. **Computes average** of all valid rates
4. **Creates new pool box** with:
   - `rate` = computed average
   - `epoch` = previous epoch + 1
   - Pool NFT preserved
   - Reward tokens decreased by `2N` (distributed to oracles)
5. **Distributes rewards:**
   - Collector (tx submitter) receives `N + reward_per_oracle` reward tokens
   - Each participating oracle box output receives `reward_per_oracle` tokens
6. **Recreates refresh box** with refresh NFT

```
Timing check:
  - tx.validity_range lower bound >= pool_creation_slot + epoch_length
  - This ensures sufficient time has passed since last refresh
```

### 3. Oracle Validator (spend)

Each oracle box can be spent in two contexts:

**A. Collection (refresh transaction):**
- First input is the pool box (identified by pool NFT)
- Oracle box output preserves: oracle token, owner
- Reward tokens in output >= reward tokens in input + reward_per_oracle
- Epoch counter in output is cleared (prevents replay)

**B. Owner action (signed by owner):**
- Owner's signature in `tx.extra_signatories`
- Can: post new data point (update rate + epoch), extract reward tokens, transfer ownership

### 4. Ballot Validator (spend)

Each ballot box represents a governance vote:

- Ballot token holder can create/update vote by signing
- Vote targets a specific update proposal (identified by update_slot)
- New pool script hash stored in datum

### 5. Update Validator (spend)

Governance contract for protocol upgrades:

- Counts ballot boxes in tx inputs that vote for the same new_pool_script_hash
- Requires threshold (e.g. supermajority: `votes * 3 >= total_oracles * 2`)
- Replaces pool box script (via spending and recreating at new script address)
- Preserves pool NFT, rate, epoch

---

## Epoch Lifecycle

```
Slot 0          Slot E          Slot E+B        Slot 2E
│                │                │                │
│  Oracle posts  │  Refresh       │  Oracle posts  │
│  data points   │  eligible      │  data points   │
│                │                │                │
├────────────────┼────────────────┼────────────────┤
    Epoch 1          Collection       Epoch 2
                     window
```

1. **Post phase** — During the epoch, each oracle posts their data point by
   spending their oracle box and creating a new one with updated `rate` and
   current `epoch` counter.

2. **Refresh eligible** — Once `epoch_length` slots have passed since the pool
   box was last refreshed, any oracle can submit the refresh transaction.

3. **Collection race** — The first oracle to get the refresh tx into a block
   receives double rewards. This incentivizes fast finalization.

4. **New epoch** — Pool box is recreated with the aggregated rate and incremented
   epoch counter. Oracle boxes are recreated with accumulated rewards.

### Timing

| Parameter | Suggested Default | Notes |
|-----------|-------------------|-------|
| `epoch_length` | 900 slots (15 min) | Cardano has 1-second slots |
| `min_data_points` | 3 | For initial 5-7 oracle pool |
| `max_deviation_pct` | 5 | Outlier range |
| `reward_per_oracle` | 1 token | Per-epoch payout |

---

## Cardano-Specific Adaptations

### vs. Ergo Original

| Aspect | Ergo (EIP-0023) | Cardano Adaptation |
|--------|-----------------|-------------------|
| Data storage | Registers R4-R9 | Inline datums (CIP-32) |
| Read-only access | Data-inputs | Reference inputs (CIP-31) |
| Script referencing | N/A | Reference scripts (CIP-33) |
| Epoch timing | Block height | Slot-based validity intervals |
| Token model | Box-embedded | Native multi-asset |
| Script language | ErgoScript | Aiken (Plutus V3) |
| Max oracles | 15 | 5-7 initially (tx size budget) |

### Transaction Size Budget

The refresh transaction is the most complex:

```
Inputs:  1 pool box + 1 refresh box + N oracle boxes + 1 fee input
Outputs: 1 pool box + 1 refresh box + N oracle boxes + change

With reference scripts (CIP-33):
  - Pool validator: ~2-3 KB (referenced, not included)
  - Refresh validator: ~5-8 KB (referenced, not included)
  - Oracle validator: ~3-4 KB (referenced, not included)
  - Datum per oracle: ~100 bytes
  - Redeemer: ~50 + N*20 bytes

For N=7 oracles:
  Inputs:  10 UTxOs × ~100 bytes = ~1 KB
  Outputs: 10 UTxOs × ~200 bytes = ~2 KB
  Redeemer: ~200 bytes
  Overhead: ~1 KB
  Total: ~4-5 KB (well within 16 KB limit)
```

### Execution Budget

The refresh validator must:
- Parse N oracle datums: O(N) memory
- Validate sorting: O(N) comparisons
- Deviation check: 2 multiplications + 1 comparison
- Compute average: N additions + 1 division
- Verify reward distribution: N output checks

Estimated for N=7: ~15M CPU, ~200K memory (within Plutus V3 limits).

### MinUTXO Considerations

Each oracle box must hold at least ~1.5 ADA (minUTXO with datum + tokens).
For 7 oracles: ~10.5 ADA locked in oracle boxes.
Pool box: ~2 ADA. Refresh box: ~2 ADA. Total protocol lockup: ~15 ADA.

This is trivial compared to Ergo's ERG lockup requirements.

The dApp-funded micro-fee model from Ergo is **not practical** on Cardano due
to minUTXO (~1.5 ADA per output). Alternative funding approaches:
- **Fee pot:** A single accumulator UTxO that dApps contribute to
- **Subscription:** Protocols pay a periodic fee for oracle access (off-chain)
- **SPO rewards:** Oracle operation funded from SPO block rewards (community good)
- **Treasury:** Cardano treasury funding via governance proposal

---

## Implementation Phases

### Phase 1: Core Contracts (MVP)
- Pool validator (datum: rate + epoch)
- Oracle validator (post data point, collect rewards)
- Refresh validator (aggregation, deviation check, reward distribution)
- Bootstrap minting policy (one-shot mint of all tokens)
- Comprehensive unit tests

### Phase 2: Off-Chain Tooling
- Oracle operator CLI (fetch price, post data point, submit refresh)
- Pool monitoring (epoch status, oracle participation, staleness alerts)
- dApp integration example (consume pool via reference input)

### Phase 3: Governance
- Ballot validator
- Update validator
- Parameter change workflow

### Phase 4: Testnet Deployment
- Deploy on preview testnet
- Run 3-5 oracle operators (ADAvault pools)
- Monitor for epoch transitions, reward distribution, data accuracy
- Stress test: deliberately post outliers, test deviation rejection

### Phase 5: Hardening
- Security audit (aiken-skill audit methodology)
- Edge cases: all oracles post same value, only min_data_points post,
  epoch boundary race conditions
- Execution budget optimization

---

## Security Considerations

### Threat Model

| Threat | Mitigation |
|--------|------------|
| Oracle collusion (N oracles post fake price) | Deviation check limits damage; governance can remove oracles |
| Data copying (oracle copies another's data) | Commit-reveal scheme (Phase 5) |
| Refresh DoS (spam invalid refresh txs) | Refresh NFT ensures only one refresh per epoch |
| Pool box contention | Reference inputs for reads; only refresh tx writes |
| Stale data | dApps check epoch counter; staleness = epoch_length exceeded |
| Governance capture | Supermajority threshold (67%); ballot tokens tied to oracle tokens |
| Reward token extraction | Oracle validator enforces reward only increases during collection |

### Invariants

1. Pool NFT is always in exactly one UTxO (the pool box)
2. Pool epoch counter is strictly monotonically increasing
3. Reward token total across all boxes is conserved (no minting after bootstrap)
4. Oracle count never exceeds the number of oracle tokens minted at bootstrap
5. Rate in pool box is always the arithmetic mean of the most recent valid submissions
6. Each oracle can contribute at most one data point per epoch

---

## Open Questions

1. **Average vs. Median?** — Ergo uses average with outlier filtering. Median is
   more robust but harder to compute on-chain (requires sorting). With small N
   (5-7), average + deviation check may suffice. Revisit at Phase 5.

2. **Oracle incentive without separate token?** — Could oracle rewards be paid
   in ADA directly from the pool box, avoiding the need for reward tokens?
   Trade-off: simpler economics vs. pool box ADA depletion.

3. **SPO identity binding?** — Should oracle tokens be linked to active stake
   pool registration? This would prevent Sybil attacks but adds complexity
   (checking pool registration certificates on-chain).

4. **Multi-feed support?** — Single pool per data feed, or one pool contract
   supporting multiple feeds? Start with single feed (ADA/USD), expand later.

5. **Data source agreement?** — How do oracles agree on which data sources to
   query? Off-chain social consensus (documented in pool metadata), or on-chain
   source registry?

---

## References

- [EIP-0023: Oracle Pool v2.0](https://github.com/ergoplatform/eips/pull/41) — Ergo specification
- [Emurgo Oracle Pools Research](https://github.com/Emurgo/Emurgo-Research/blob/master/oracles/Oracle-Pools.md) — Robert Kornacki (2020)
- [oracle-core](https://github.com/ergoplatform/oracle-core) — Ergo off-chain implementation (Rust)
- [CIP-31: Reference Inputs](https://cips.cardano.org/cips/cip31/) — Cardano read-only UTxO references
- [CIP-32: Inline Datums](https://cips.cardano.org/cips/cip32/) — Datum attached to outputs
- [CIP-33: Reference Scripts](https://cips.cardano.org/cips/cip33/) — Script stored in UTxO
- [Cardano Open Oracle Protocol](https://github.com/mlabs-haskell/cardano-open-oracle-protocol) — MLabs/Orcfax SDK
- [Orcfax Documentation](https://docs.orcfax.io/) — Existing Cardano oracle
- [Charli3 Node Setup](https://github.com/Charli3-Official/charli3-node-operator-setup) — Existing Cardano oracle
