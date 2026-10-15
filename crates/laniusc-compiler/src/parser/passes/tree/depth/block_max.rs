use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Summarizes each workgroup's subtree close counts for the exact raw-tree
/// height, and checks that every raw parent link points to an earlier node.
pub struct TreeDepthBlockMaxPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeDepthBlockMaxPass,
    label: "tree_depth_block_max",
    shader: "parser/tree/depth/block_max"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeDepthBlockMaxPass {
    const NAME: &'static str = "tree_depth_block_max";
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
            ("gTree".into(), b.tree_span_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("parent".into(), b.parent.as_entire_binding()),
            (
                "tree_depth_close_count".into(),
                b.tree_depth_close_count.as_entire_binding(),
            ),
            (
                "tree_depth_block_max".into(),
                b.tree_depth_block_max.as_entire_binding(),
            ),
            (
                "tree_depth_block_close".into(),
                b.tree_depth_block_close.as_entire_binding(),
            ),
            (
                "tree_depth_status".into(),
                b.tree_depth_status.as_entire_binding(),
            ),
        ])
    }
}
