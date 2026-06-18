use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    parser::buffers::ParserBuffers,
};

/// Pass that compacts ranked HIR list entries for a caller-selected owner link.
pub struct HirListRankCompactScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirListRankCompactScatterPass,
    label: "hir_list_rank_compact_scatter",
    shader: "parser/hir/list/rank/compact_scatter"
);

impl HirListRankCompactScatterPass {
    /// Records compact scatter work using the provided list-rank parameter buffer.
    pub fn record_for_params<P>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        params: &LaniusBuffer<P>,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gHirList".into(), params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.projected_status.as_entire_binding()
                } else {
                    buffers.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_list_rank_flag".into(),
                buffers.hir_list_rank_flag.as_entire_binding(),
            ),
            (
                "hir_list_rank_local_prefix".into(),
                buffers.hir_list_rank_local_prefix.as_entire_binding(),
            ),
            (
                "hir_list_rank_block_prefix".into(),
                buffers.hir_list_rank_block_prefix_a.as_entire_binding(),
            ),
            (
                "hir_list_rank_node".into(),
                buffers.hir_list_rank_node.as_entire_binding(),
            ),
            (
                "hir_list_rank_count".into(),
                buffers.hir_list_rank_count.as_entire_binding(),
            ),
            (
                "hir_list_rank_dispatch_args".into(),
                buffers.hir_list_rank_dispatch_args.as_entire_binding(),
            ),
        ]);

        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("hir_list_rank_compact_scatter"),
            &self.data.bind_group_layouts[0],
            &self.data.reflection,
            0,
            &resources,
        )?;

        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_n_node_blocks.saturating_mul(256)),
            [tgsx, tgsy, 1],
        )?;

        let mut pass = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("hir_list_rank_compact_scatter"),
            timestamp_writes: None,
        });
        pass.set_pipeline(&self.data.pipeline);
        pass.set_bind_group(0, Some(&bind_group), &[]);
        pass.dispatch_workgroups(gx, gy, gz);
        Ok(())
    }
}
