use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct TreePrevSiblingScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrevSiblingScatterPass,
    label: "tree_prev_sibling_scatter",
    shader: "tree_prev_sibling_scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreePrevSiblingScatterPass {
    const NAME: &'static str = "tree_prev_sibling_scatter";
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
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("prev_sibling".into(), b.prev_sibling.as_entire_binding()),
        ])
    }
}
