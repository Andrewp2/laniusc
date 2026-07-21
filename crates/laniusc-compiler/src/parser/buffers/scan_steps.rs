use crate::gpu::buffers::LaniusBuffer;

/// One ping-pong scan step for packed stream offsets.
pub struct PackOffsetScanStep {
    pub params: LaniusBuffer<super::super::passes::pack::offsets::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One reduction step for packed stream total counts.
pub struct PackTotalReduceStep {
    pub params: LaniusBuffer<super::super::passes::pack::totals::reduce::Params>,
    pub item_count: u32,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One ping-pong scan step for token delimiter context.
pub struct TokenDelimiterScanStep {
    pub params: LaniusBuffer<super::TokenDelimiterParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One ping-pong scan step for semantic-HIR prefix counts.
pub struct HirSemanticPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::hir::semantic::prefix::blocks::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One ping-pong scan step over bracket block prefixes.
pub struct BracketsBlockPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::brackets::scan_block_prefix::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One ping-pong scan step for tree prefix counts.
pub struct TreePrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::tree::prefix::local::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// One max-tree build step used by tree parent recovery.
pub struct TreePrefixMaxBuildStep {
    pub params: LaniusBuffer<super::super::passes::tree::prefix::build_max_tree::Params>,
    pub work_items: u32,
}
