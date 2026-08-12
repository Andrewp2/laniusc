use crate::{gpu::buffers::LaniusBuffer, parser::passes::pack::offsets::HierarchyParams};

/// Capacity-dependent paired hierarchy for packed stream offsets.
pub struct PackOffsetScanPlan {
    pub params: LaniusBuffer<super::super::passes::pack::offsets::Params>,
    pub up: Vec<PackOffsetHierarchyStep>,
    pub down: Vec<PackOffsetHierarchyStep>,
}

/// One level of the paired stack-change/emit offset hierarchy.
pub struct PackOffsetHierarchyStep {
    pub params: LaniusBuffer<HierarchyParams>,
    pub work_items: u32,
}

/// One reduction step for packed stream total counts.
pub struct PackTotalReduceStep {
    pub params: LaniusBuffer<super::super::passes::pack::totals::reduce::Params>,
    pub item_count: u32,
    pub read_from_a: bool,
    pub write_to_a: bool,
}

/// Capacity-dependent hierarchy shared by associative token-block scans.
pub struct TokenBlockScanPlan {
    pub up: Vec<TokenBlockScanStep>,
    pub down: Vec<TokenBlockScanStep>,
}

/// One level of an associative token-block scan.
pub struct TokenBlockScanStep {
    pub params: LaniusBuffer<TokenBlockScanHierarchyParams>,
    pub work_items: u32,
}

#[repr(C)]
#[derive(Clone, Copy, encase::ShaderType)]
pub struct TokenBlockScanHierarchyParams {
    pub n_blocks: u32,
    pub level_divisor: u32,
    pub level_offset: u32,
    pub parent_divisor: u32,
    pub parent_offset: u32,
    pub reserved0: u32,
    pub reserved1: u32,
    pub reserved2: u32,
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
