use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for local tree-prefix counting.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
    pub n_node_blocks: u32,
    pub n_prefix_blocks: u32,
    pub scan_step: u32,
}

/// Pass that locally counts emitted tree nodes per block.
pub struct TreePrefixLocalPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreePrefixLocalPass,
    label: "tree_prefix_01_local",
    shader: "parser/tree/prefix/01_local"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreePrefixLocalPass {
    const NAME: &'static str = "tree_prefix_01_local";
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
            ("emit_stream".into(), b.out_emit.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("prod_arity".into(), b.prod_arity.as_entire_binding()),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "prefix_inblock".into(),
                b.tree_prefix_inblock.as_entire_binding(),
            ),
            ("block_sum".into(), b.tree_block_sum.as_entire_binding()),
        ])
    }
}
