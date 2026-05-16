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
}

pub struct HirCallFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCallFieldsPass,
    label: "hir_call_fields",
    shader: "hir_call_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCallFieldsPass {
    const NAME: &'static str = "hir_call_fields";
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
                "gHirCall".into(),
                b.hir_call_fields_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_start".into(),
                b.hir_call_arg_start.as_entire_binding(),
            ),
            (
                "hir_call_arg_end".into(),
                b.hir_call_arg_end.as_entire_binding(),
            ),
            (
                "hir_call_arg_count".into(),
                b.hir_call_arg_count.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call".into(),
                b.hir_call_arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_ordinal".into(),
                b.hir_call_arg_ordinal.as_entire_binding(),
            ),
        ])
    }
}
