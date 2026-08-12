use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Builds indirect dispatch arguments from the recovered parse-tree row count.
pub struct TreeActiveDispatchArgsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    TreeActiveDispatchArgsPass,
    label: "tree_active_dispatch_args",
    shader: "parser/tree/active_dispatch_args"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for TreeActiveDispatchArgsPass {
    const NAME: &'static str = "tree_active_dispatch_args";
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
            ("tree_count_status".into(), b.ll1_status.as_entire_binding()),
            (
                "tree_active_dispatch_args".into(),
                b.tree_active_dispatch_args.as_entire_binding(),
            ),
        ])
    }
}
