use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for clearing previous-sibling rows.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Pass that initializes previous-sibling rows before scatter.
pub struct TreePrevSiblingClearPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrevSiblingClearPass,
    label: "tree_prev_sibling_clear",
    shader: "parser/tree/prev/sibling/clear"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreePrevSiblingClearPass {
    const NAME: &'static str = "tree_prev_sibling_clear";
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
                "gTreePrev".into(),
                b.tree_prev_sibling_params.as_entire_binding(),
            ),
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
        ])
    }
}
