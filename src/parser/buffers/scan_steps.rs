use crate::gpu::buffers::LaniusBuffer;

pub struct LL1EmitPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::ll1_blocks_01::LL1BlocksParams>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackOffsetScanStep {
    pub params: LaniusBuffer<super::super::passes::pack_offsets::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct PackTotalReduceStep {
    pub params: LaniusBuffer<super::super::passes::pack_totals_reduce::Params>,
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
    pub params: LaniusBuffer<super::super::passes::hir_semantic_prefix_blocks::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct BracketsHistogramScanStep {
    pub params: LaniusBuffer<super::super::passes::brackets_05::Params>,
    pub read_from_offsets: bool,
    pub write_to_offsets: bool,
}

pub struct BracketsBlockPrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::brackets_02::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixScanStep {
    pub params: LaniusBuffer<super::super::passes::tree_prefix_01::Params>,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

pub struct TreePrefixMaxBuildStep {
    pub params: LaniusBuffer<super::super::passes::tree_prefix_04::Params>,
    pub work_items: u32,
}
