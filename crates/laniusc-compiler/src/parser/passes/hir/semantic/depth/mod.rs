/// Workgroup reduction of dense semantic-node depths.
pub mod block_max;
/// Semantic depth seed pass.
pub mod init;
/// GPU-resident indirect schedule derived from the actual maximum depth.
pub mod schedule;
/// Semantic depth pointer-jump pass.
pub mod step;
