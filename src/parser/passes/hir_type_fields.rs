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

pub const HIR_TYPE_FORM_NONE: u32 = 0;
pub const HIR_TYPE_FORM_PATH: u32 = 1;
pub const HIR_TYPE_FORM_ARRAY: u32 = 2;
pub const HIR_TYPE_FORM_SLICE: u32 = 3;
pub const HIR_TYPE_FORM_REF: u32 = 4;

pub struct HirTypeFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeFieldsPass,
    label: "hir_type_fields",
    shader: "hir_type_fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeFieldsPass {
    const NAME: &'static str = "hir_type_fields";
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
                "gHirType".into(),
                b.hir_type_fields_params.as_entire_binding(),
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
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "hir_token_file_id".into(),
                b.hir_token_file_id.as_entire_binding(),
            ),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_type_value_node".into(),
                b.hir_type_value_node.as_entire_binding(),
            ),
            (
                "hir_type_len_token".into(),
                b.hir_type_len_token.as_entire_binding(),
            ),
            (
                "hir_type_file_id".into(),
                b.hir_type_file_id.as_entire_binding(),
            ),
        ])
    }
}
