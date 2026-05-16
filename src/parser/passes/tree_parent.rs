use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
pub struct Params {
    pub n: u32,
    pub uses_ll1: u32,
    pub n_prefix_blocks: u32,
    pub max_tree_leaf_base: u32,
}

pub struct TreeParentPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeParentPass,
    label: "tree_parent_parallel",
    shader: "tree_parent_parallel"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeParentPass {
    const NAME: &'static str = "tree_parent_parallel";
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
            ("gTree".into(), b.tree_params.as_entire_binding()),
            (
                "emit_stream".into(),
                if b.tree_stream_uses_ll1 {
                    b.ll1_emit.as_entire_binding()
                } else {
                    b.out_emit.as_entire_binding()
                },
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("tree_prefix".into(), b.tree_prefix.as_entire_binding()),
            (
                "prefix_block_max".into(),
                b.tree_prefix_block_max.as_entire_binding(),
            ),
            (
                "prefix_block_max_tree".into(),
                b.tree_prefix_block_max_tree.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
        ])
    }
}
