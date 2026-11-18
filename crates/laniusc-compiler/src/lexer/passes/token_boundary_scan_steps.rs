use crate::gpu::scan::{PingPongScanStep, ScanFinalize, ping_pong_scan_steps};

/// Pair scan block totals are already seeded into the ping buffer by `count_token_boundaries_in_blocks`.
///
/// The shared scan planner includes a seed/copy step at `scan_step == 0` for
/// pipelines with a separate block-sum buffer. The lexer pair path reuses the
/// ping buffer as both block totals and scan prefix storage, so `scan_token_boundary_counts` starts
/// at the first real stride step.
pub(crate) fn block_total_scan_steps(n_blocks: u32) -> Vec<PingPongScanStep> {
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
