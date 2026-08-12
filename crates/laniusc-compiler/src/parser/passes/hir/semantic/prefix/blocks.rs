use anyhow::Result;

use crate::{
    gpu::{buffers::LaniusBuffer, operations::InclusiveBlockScanKernels},
    parser::buffers::ParserBuffers,
};

/// Reusable hierarchical scanner for semantic-HIR and compact-family block
/// sums. Its output remains inclusive to preserve the parser scatter ABI.
pub struct HirSemanticPrefixBlocksPass {
    scan: InclusiveBlockScanKernels,
}

impl HirSemanticPrefixBlocksPass {
    pub fn new(device: &wgpu::Device) -> Result<Self> {
        Ok(Self {
            scan: InclusiveBlockScanKernels::new(device)?,
        })
    }

    /// Records the semantic-HIR compaction block-prefix scan.
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            "hir_semantic_prefix_01_blocks",
        )
    }

    /// Records a scan over token-bounded canonical HIR rows.
    pub fn record_compact_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_canonical_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            "hir_canonical_prefix_01_blocks",
        )
    }

    /// Records the struct-field rank block-prefix scan.
    pub fn record_struct_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_struct_rank_block_sum,
            &buffers.hir_struct_rank_block_prefix_a,
            &buffers.hir_struct_rank_block_prefix_b,
            "hir_struct_rank_prefix_01_blocks",
        )
    }

    /// Records the generic list-rank block-prefix scan.
    pub fn record_list_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_list_rank_block_sum,
            &buffers.hir_list_rank_block_prefix_a,
            &buffers.hir_list_rank_block_prefix_b,
            "hir_list_rank_prefix_01_blocks",
        )
    }

    /// Records the enum-variant rank block-prefix scan.
    pub fn record_enum_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_enum_rank_block_sum,
            &buffers.hir_enum_rank_block_prefix_a,
            &buffers.hir_enum_rank_block_prefix_b,
            "hir_enum_rank_prefix_01_blocks",
        )
    }

    /// Records the match-arm rank block-prefix scan.
    pub fn record_match_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_match_rank_block_sum,
            &buffers.hir_match_rank_block_prefix_a,
            &buffers.hir_match_rank_block_prefix_b,
            "hir_match_rank_prefix_01_blocks",
        )
    }

    fn record_scan_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        plan: &crate::gpu::operations::InclusiveBlockScanPlan,
        block_sum: &LaniusBuffer<u32>,
        block_prefix: &LaniusBuffer<u32>,
        hierarchy: &LaniusBuffer<u32>,
        label: &'static str,
    ) -> Result<()> {
        self.scan.record(
            device,
            encoder,
            label,
            plan,
            block_sum,
            block_prefix,
            hierarchy,
        )
    }
}
