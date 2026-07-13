use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Seeds raw parse-tree depth pointer jumping from the recovered parent array.
pub struct TreeDepthInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeDepthInitPass,
    label: "tree_depth_init",
    shader: "parser/tree/depth/init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeDepthInitPass {
    const NAME: &'static str = "tree_depth_init";
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
                "tree_depth_link_a".into(),
                b.hir_semantic_depth_link_a.as_entire_binding(),
            ),
            (
                "tree_depth_value_a".into(),
                b.hir_semantic_depth_value_a.as_entire_binding(),
            ),
        ])
    }
}
