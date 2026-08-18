use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        operations::InclusiveBlockScanKernels,
        passes_core::BindGroupCache,
    },
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

    pub(in crate::parser) fn graph_passes(
        &self,
    ) -> (
        &crate::gpu::passes_core::PassData,
        &crate::gpu::passes_core::PassData,
    ) {
        self.scan.graph_passes()
    }

    /// Records the semantic-HIR compaction block-prefix scan.
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            crate::parser::compiler_graph::HIR_SEMANTIC_SCAN_UP,
            crate::parser::compiler_graph::HIR_SEMANTIC_SCAN_DOWN,
        )
    }

    /// Records a tree-capacity semantic scan under the semantic name of a
    /// caller-selected use of the shared prefix kernels.
    pub fn record_semantic_scan_as(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            up_label,
            down_label,
        )
    }

    /// Records a scan over token-bounded canonical HIR rows.
    pub fn record_compact_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_canonical_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            up_label,
            down_label,
        )
    }

    /// Scans canonical-identity marks over raw parser rows.
    pub fn record_canonical_identity_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            crate::parser::compiler_graph::HIR_CANONICAL_IDENTITY_SCAN_UP,
            crate::parser::compiler_graph::HIR_CANONICAL_IDENTITY_SCAN_DOWN,
        )
    }

    /// Records the struct-field rank block-prefix scan.
    pub fn record_struct_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_struct_rank_block_sum,
            &buffers.hir_struct_rank_block_prefix_a,
            &buffers.hir_struct_rank_block_prefix_b,
            crate::parser::compiler_graph::HIR_STRUCT_RANK_SCAN_UP,
            crate::parser::compiler_graph::HIR_STRUCT_RANK_SCAN_DOWN,
        )
    }

    /// Records the generic list-rank block-prefix scan.
    pub fn record_list_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        invocation: crate::parser::passes::hir::list::rank::ListRankInvocation,
    ) -> Result<()> {
        let (up, down) = invocation.scan_labels();
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_list_rank_block_sum,
            &buffers.hir_list_rank_block_prefix_a,
            &buffers.hir_list_rank_block_prefix_b,
            up,
            down,
        )
    }

    /// Records the enum-variant rank block-prefix scan.
    pub fn record_enum_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_enum_rank_block_sum,
            &buffers.hir_enum_rank_block_prefix_a,
            &buffers.hir_enum_rank_block_prefix_b,
            crate::parser::compiler_graph::HIR_ENUM_RANK_SCAN_UP,
            crate::parser::compiler_graph::HIR_ENUM_RANK_SCAN_DOWN,
        )
    }

    /// Records the match-arm rank block-prefix scan.
    pub fn record_match_rank_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_match_rank_block_sum,
            &buffers.hir_match_rank_block_prefix_a,
            &buffers.hir_match_rank_block_prefix_b,
            crate::parser::compiler_graph::HIR_MATCH_RANK_SCAN_UP,
            crate::parser::compiler_graph::HIR_MATCH_RANK_SCAN_DOWN,
        )
    }

    fn record_scan_inner(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        cache: &mut BindGroupCache,
        graph_buffers: &ParserBuffers,
        plan: &crate::gpu::operations::InclusiveBlockScanPlan,
        block_sum: &LaniusBuffer<u32>,
        block_prefix: &LaniusBuffer<u32>,
        hierarchy: &LaniusBuffer<u32>,
        up_label: &'static str,
        down_label: &'static str,
    ) -> Result<()> {
        self.scan.record_graph(
            device,
            encoder,
            cache,
            graph_buffers,
            up_label,
            down_label,
            plan,
            block_sum,
            block_prefix,
            hierarchy,
        )
    }
}
