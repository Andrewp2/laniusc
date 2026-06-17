use crate::gpu::buffers::LaniusBuffer;

pub struct PackOffsetScanStep {
    pub params: LaniusBuffer<super::super::passes::pack::offsets::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackTotalReduceStep {
    pub params: LaniusBuffer<super::super::passes::pack::totals::reduce::Params>,
    pub item_count: u32,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TokenDelimiterScanStep {
    pub params: LaniusBuffer<super::TokenDelimiterParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct HirSemanticPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::hir::semantic::prefix::blocks::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct BracketsHistogramScanStep {
    pub params: LaniusBuffer<super::super::passes::brackets::scan_histograms::Params>,
    pub read_from_offsets: bool,
    pub write_to_offsets: bool,
}

pub struct BracketsBlockPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::brackets::scan_block_prefix::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::tree::prefix::local::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixMaxBuildStep {
    pub params: LaniusBuffer<super::super::passes::tree::prefix::build_max_tree::Params>,
    pub work_items: u32,
}
