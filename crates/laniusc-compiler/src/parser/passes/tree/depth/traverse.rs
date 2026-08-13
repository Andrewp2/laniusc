use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Computes exact raw parse-tree depths with one local parent traversal per node.
pub struct TreeDepthTraversePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeDepthTraversePass,
    label: "tree_depth_traverse",
    shader: "parser/tree/depth/traverse"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeDepthTraversePass {
    const NAME: &'static str = "tree_depth_traverse";
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
                "tree_depth_value_a".into(),
                b.tree_depth.as_entire_binding(),
            ),
            (
                "tree_depth_status".into(),
                b.tree_depth_status.as_entire_binding(),
            ),
        ])
    }
}
