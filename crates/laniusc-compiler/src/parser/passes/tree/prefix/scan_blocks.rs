use std::collections::HashMap;

use anyhow::Result;

use crate::{
    gpu::passes_core::{BindGroupCache, DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that scans per-block tree-prefix sums.
pub struct TreePrefixScanBlocksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrefixScanBlocksPass,
    label: "tree_prefix_02_scan_blocks",
    shader: "parser/tree/prefix/02_scan_blocks"
);

impl TreePrefixScanBlocksPass {
    /// Records the block-prefix scan: one workgroup scans every block
    /// (parser/tree/prefix/02_scan_blocks.slang).
    pub fn record_scan(
        &self,
        device: &wgpu::Device,
        encoder: &mut wgpu::CommandEncoder,
        buffers: &ParserBuffers,
        cache: &mut BindGroupCache,
    ) -> Result<()> {
        let resources = self.create_resource_map(buffers);
        let operation = crate::parser::compiler_graph::TREE_PREFIX_SCAN;
        let bind_group = cache
            .reflected_for_graph_invocation(
                device,
                operation,
                operation,
                &self.data,
                buffers,
                &resources,
                None,
            )?
            .into_iter()
            .next()
            .expect("tree-prefix scan pass must have one reflected bind group");
        crate::gpu::passes_core::record_or_defer_compute_direct(
            encoder,
            &self.data,
            bind_group.as_ref(),
            operation,
            (1, 1, 1),
        );
        Ok(())
    }
}

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreePrefixScanBlocksPass {
    const NAME: &'static str = "tree_prefix_02_scan_blocks";
    const DIM: DispatchDim = DispatchDim::D1;

    fn from_data(data: PassData) -> Self {
        Self { data }
    }

    fn data(&self) -> &PassData {
        &self.data
    }

    fn create_resource_map<'a>(
        &self,
        b: &'a ParserBuffers,
    ) -> HashMap<String, wgpu::BindingResource<'a>> {
        HashMap::from([
            ("gTree".into(), b.tree_prefix_params.as_entire_binding()),
            ("block_sum".into(), b.tree_block_sum.as_entire_binding()),
            (
                "block_prefix".into(),
                b.tree_block_prefix.as_entire_binding(),
            ),
        ])
    }
}
