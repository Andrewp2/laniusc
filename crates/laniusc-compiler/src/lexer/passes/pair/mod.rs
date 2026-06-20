/// Applies token-boundary block prefixes.
pub mod apply_block_prefix;
/// Prefix-scans token-boundary block totals.
pub mod scan_block_totals;
/// Counts token boundaries inside blocks.
pub mod sum_inblock;

use crate::gpu::scan::{PingPongScanStep, ScanFinalize, ping_pong_scan_steps};

/// Pair scan block totals are already seeded into the ping buffer by `pair_01`.
///
/// The shared scan planner includes a seed/copy step at `scan_step == 0` for
/// pipelines with a separate block-sum buffer. The lexer pair path reuses the
/// ping buffer as both block totals and scan prefix storage, so `pair_02` starts
/// at the first real stride step.
pub(super) fn block_total_scan_steps(n_blocks: u32) -> Vec<PingPongScanStep> {
    ping_pong_scan_steps(n_blocks, ScanFinalize::None)
        .into_iter()
        .skip(1)
        .collect()
}

/// Returns whether the pair block-prefix scan leaves its final prefix in ping.
pub(super) fn block_total_scan_last_writer_is_ping(n_blocks: u32) -> bool {
    block_total_scan_steps(n_blocks)
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
}
