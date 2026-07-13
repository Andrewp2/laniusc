use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Builds capacity-stable indirect commands from the actual raw-tree height.
pub struct TreeDepthSchedulePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeDepthSchedulePass,
    label: "tree_depth_schedule",
    shader: "parser/tree/depth/schedule"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeDepthSchedulePass {
    const NAME: &'static str = "tree_depth_schedule";
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
                "tree_active_dispatch_args".into(),
                b.tree_active_dispatch_args.as_entire_binding(),
            ),
            (
                "tree_depth_block_max".into(),
                b.hir_semantic_depth_block_max.as_entire_binding(),
            ),
            (
                "tree_pointer_jump_dispatch_args".into(),
                b.tree_pointer_jump_dispatch_args.as_entire_binding(),
            ),
        ])
    }
}
