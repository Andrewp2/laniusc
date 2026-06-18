use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for struct declaration field extraction.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Pass that records field-list metadata for struct declarations.
pub struct HirStructFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStructFieldsPass,
    label: "hir_struct_fields",
    shader: "parser/hir/struct/fields"
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
                "hir_struct_lit_context_stmt_node".into(),
                b.hir_struct_lit_context_stmt_node.as_entire_binding(),
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
