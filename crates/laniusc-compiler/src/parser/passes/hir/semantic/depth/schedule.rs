use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Builds per-round indirect arguments from the actual semantic-tree height.
pub struct HirSemanticDepthSchedulePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticDepthSchedulePass,
    label: "hir_semantic_depth_schedule",
    shader: "parser/hir/semantic/depth/schedule"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticDepthSchedulePass {
    const NAME: &'static str = "hir_semantic_depth_schedule";
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
            ("gHirSemantic".into(), b.hir_params.as_entire_binding()),
            (
                "hir_semantic_dispatch_args".into(),
                b.hir_semantic_dispatch_args.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_block_max".into(),
                b.hir_semantic_depth_block_max.as_entire_binding(),
            ),
            (
                "hir_semantic_pointer_jump_dispatch_args".into(),
                b.hir_semantic_pointer_jump_dispatch_args
                    .as_entire_binding(),
            ),
        ])
    }
}
