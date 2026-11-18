/// Active adjacent-pair parse table pass.
pub mod find_token_pair_actions;
/// Scatter pass for packed variable-length parser streams.
pub mod pack_stack_changes_and_productions;
/// Status validation for packed parser offset scans.
pub mod publish_pack_offset_status;
/// Status pass for packed stream totals.
pub mod publish_pack_total_status;
/// Multi-step reduction pass for block totals.
pub mod reduce_pack_length_sums;
/// Prefix-scan passes for variable-length parser stream offsets.
pub mod scan_pack_offsets;
/// Per-block total counting pass.
pub mod sum_pack_lengths_in_blocks;
