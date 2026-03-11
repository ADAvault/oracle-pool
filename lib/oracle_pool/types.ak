/// Oracle Pool Protocol — Shared Types
///
/// All datum and redeemer types used across the protocol's validators.

/// Pool box datum — holds the finalized aggregated oracle rate.
pub type PoolDatum {
  /// Aggregated rate (e.g. ADA/USD price in millionths: 350000 = $0.35)
  rate: Int,
  /// Epoch counter — strictly monotonically increasing, incremented each refresh
  epoch: Int,
}

/// Oracle box datum — holds one operator's data point submission.
pub type OracleDatum {
  /// Operator's verification key hash (28 bytes, Blake2b-224)
  owner: ByteArray,
  /// Epoch counter when this data point was posted (matches pool epoch at time of posting)
  epoch: Int,
  /// The oracle's reported rate
  rate: Int,
}

/// Refresh redeemer — provides the collector's claim about oracle data ordering.
/// The refresh validator checks each entry against the actual input data.
pub type RefreshRedeemer {
  /// Input indices of oracle boxes, in ascending rate order.
  /// Validator verifies: inputs at these indices have oracle tokens,
  /// their rates match the claimed order, and the order is ascending.
  oracle_indices: List<Int>,
}

/// Oracle box redeemer — controls how the oracle box is spent.
pub type OracleRedeemer {
  /// Oracle box is being collected during a refresh transaction
  Collect
  /// Owner is updating the data point or extracting rewards
  OwnerAction
}

/// Ballot box datum — governance vote for protocol updates.
pub type BallotDatum {
  /// Voter's verification key hash
  voter: ByteArray,
  /// Hash of the proposed new pool validator script
  new_pool_script_hash: ByteArray,
  /// Slot when the update box was created (ties vote to specific proposal)
  update_slot: Int,
}

/// Update redeemer — governance update mechanism.
pub type UpdateRedeemer {
  /// Number of ballot boxes in this transaction
  ballot_count: Int,
}
