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

pub struct HirMemberFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirMemberFieldsPass,
    label: "hir_member_fields",
    shader: "hir_member_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirMemberFieldsPass {
    const NAME: &'static str = "hir_member_fields";
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
                "gHirMember".into(),
                b.hir_member_fields_params.as_entire_binding(),
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
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("subtree_end".into(), b.subtree_end.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_member_receiver_node".into(),
                b.hir_member_receiver_node.as_entire_binding(),
            ),
            (
                "hir_member_receiver_token".into(),
                b.hir_member_receiver_token.as_entire_binding(),
            ),
            (
                "hir_member_name_token".into(),
                b.hir_member_name_token.as_entire_binding(),
            ),
        ])
    }
}
