use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Reduces semantic-HIR depths to one maximum per dispatched workgroup.
pub struct HirSemanticDepthBlockMaxPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirSemanticDepthBlockMaxPass,
    label: "hir_semantic_depth_block_max",
    shader: "parser/hir/semantic/depth/block_max"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirSemanticDepthBlockMaxPass {
    const NAME: &'static str = "hir_semantic_depth_block_max";
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
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_semantic_depth".into(),
                b.hir_semantic_depth.as_entire_binding(),
            ),
            (
                "hir_semantic_depth_block_max".into(),
                b.hir_semantic_depth_block_max.as_entire_binding(),
            ),
        ])
    }
}
