use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        passes_core::{BindGroupCache, DispatchDim, InputElements, PassData, plan_workgroups},
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
    pub(in crate::parser) fn graph_pass(&self) -> &PassData {
        &self.data
    }

    /// Records compact scatter work using the provided list-rank parameter buffer.
    pub fn record_for_params<P>(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        params: &LaniusBuffer<P>,
        cache: &mut BindGroupCache,
        invocation: super::ListRankInvocation,
    ) -> Result<()> {
        let resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gHirList".into(), params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if buffers.tree_count_uses_status {
                    buffers.partial_parse_status.as_entire_binding()
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

        let operation = invocation.scatter_label();
        let bind_group = cache
            .reflected_for_graph_pass_data(
                device, operation, &self.data, buffers, &resources, None,
            )?
            .into_iter()
            .next()
            .expect("list-rank scatter pass must have one reflected bind group");

        let [tgsx, tgsy, _] = self.data.thread_group_size;
        let (gx, gy, gz) = plan_workgroups(
            DispatchDim::D1,
            InputElements::Elements1D(buffers.tree_n_node_blocks.saturating_mul(256)),
            [tgsx, tgsy, 1],
        )?;

        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
            (gx, gy, gz),
        );
        Ok(())
    }
}
