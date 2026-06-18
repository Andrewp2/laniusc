use std::collections::HashMap;

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for one semantic-HIR prefix block scan step.
pub struct Params {
    pub n_blocks: u32,
    pub scan_step: u32,
}

/// Reusable block-prefix scanner for semantic HIR and HIR list-rank scans.
pub struct HirSemanticPrefixBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticPrefixBlocksPass,
    label: "hir_semantic_prefix_01_blocks",
    shader: "parser/hir/semantic/prefix/01_blocks"
);

impl HirSemanticPrefixBlocksPass {
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
            buffers,
            &buffers.hir_semantic_block_count,
            &buffers.hir_semantic_block_prefix_a,
            &buffers.hir_semantic_block_prefix_b,
            "hir_semantic_prefix_01_blocks",
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
            buffers,
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
            buffers,
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
            buffers,
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
            buffers,
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
        buffers: &ParserBuffers,
        block_sum: &crate::gpu::buffers::LaniusBuffer<u32>,
        block_prefix_a: &crate::gpu::buffers::LaniusBuffer<u32>,
        block_prefix_b: &crate::gpu::buffers::LaniusBuffer<u32>,
        label: &'static str,
    ) -> Result<()> {
        for step in &buffers.hir_semantic_prefix_scan_steps {
            let prefix_in = if step.read_from_a {
                block_prefix_a
            } else {
                block_prefix_b
            };
            let prefix_out = if step.write_to_a {
                block_prefix_a
            } else {
                block_prefix_b
            };
            let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gHirSemanticBlocks".into(), step.params.as_entire_binding()),
                (
                    "hir_semantic_block_sum".into(),
                    block_sum.as_entire_binding(),
                ),
                (
                    "hir_semantic_block_prefix_in".into(),
                    prefix_in.as_entire_binding(),
                ),
                (
                    "hir_semantic_block_prefix_out".into(),
                    prefix_out.as_entire_binding(),
                ),
            ]);
            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some(label),
                &self.data.bind_group_layouts[0],
                &self.data.reflection,
                0,
                &resources,
            )?;

            let [tgsx, tgsy, _] = self.data.thread_group_size;
            let (gx, gy, gz) = plan_workgroups(
                DispatchDim::D1,
                InputElements::Elements1D(buffers.tree_n_node_blocks),
                [tgsx, tgsy, 1],
            )?;
            let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(label),
                timestamp_writes: None,
            });
            pass.set_pipeline(&self.data.pipeline);
            pass.set_bind_group(0, Some(&bind_group), &[]);
            pass.dispatch_workgroups(gx, gy, gz);
        }
        Ok(())
    }
}
