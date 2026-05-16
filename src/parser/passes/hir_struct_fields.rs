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

pub struct HirStructFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStructFieldsPass,
    label: "hir_struct_fields",
    shader: "hir_struct_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStructFieldsPass {
    const NAME: &'static str = "hir_struct_fields";
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
                "gHirStruct".into(),
                b.hir_struct_fields_params.as_entire_binding(),
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
                "hir_struct_field_parent_struct".into(),
                b.hir_struct_field_parent_struct.as_entire_binding(),
            ),
            (
                "hir_struct_field_ordinal".into(),
                b.hir_struct_field_ordinal.as_entire_binding(),
            ),
            (
                "hir_struct_field_type_node".into(),
                b.hir_struct_field_type_node.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_start".into(),
                b.hir_struct_decl_field_start.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_count".into(),
                b.hir_struct_decl_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_head_node".into(),
                b.hir_struct_lit_head_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_start".into(),
                b.hir_struct_lit_field_start.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_count".into(),
                b.hir_struct_lit_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit".into(),
                b.hir_struct_lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_value_node".into(),
                b.hir_struct_lit_field_value_node.as_entire_binding(),
            ),
        ])
    }
}
