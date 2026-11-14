use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        operations::InclusiveBlockScanKernels,
        passes_core::BindGroupCache,
    },
    parser::buffers::ParserBuffers,
};

/// Reusable one-workgroup scanner for semantic-HIR and compact-family block
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

    pub(in crate::parser) fn graph_pass(&self) -> &crate::gpu::passes_core::PassData {
        self.scan.graph_pass()
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
            crate::parser::compiler_graph::HIR_SEMANTIC_SCAN,
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
        label: &'static str,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            label,
        )
    }

    /// Records a scan over token-bounded canonical HIR rows.
    pub fn record_compact_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
        label: &'static str,
    ) -> Result<()> {
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_canonical_prefix_scan,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            label,
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
            crate::parser::compiler_graph::HIR_CANONICAL_IDENTITY_SCAN,
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
            crate::parser::compiler_graph::HIR_STRUCT_RANK_SCAN,
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
        let label = invocation.scan_label();
        self.record_scan_inner(
            device,
            encoder,
            cache,
            buffers,
            &buffers.hir_semantic_prefix_scan,
            &buffers.hir_list_rank_block_sum,
            &buffers.hir_list_rank_block_prefix_a,
            label,
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
            crate::parser::compiler_graph::HIR_ENUM_RANK_SCAN,
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
            crate::parser::compiler_graph::HIR_MATCH_RANK_SCAN,
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
        label: &'static str,
    ) -> Result<()> {
        self.scan.record_graph(
            device,
            encoder,
            cache,
            graph_buffers,
            label,
            plan,
            block_sum,
            block_prefix,
        )
    }
}
