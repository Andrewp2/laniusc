use std::collections::HashMap;

use encase::ShaderType;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
/// Uniform parameters for extracting HIR array expression fields.
pub struct Params {
    pub n: u32,
    pub uses_status_count: u32,
}

/// Pass that records array expression value ranges and element counts.
pub struct HirArrayFieldsPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirArrayFieldsPass,
    label: "hir_array_fields",
    shader: "parser/hir/array/fields"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirArrayFieldsPass {
    const NAME: &'static str = "hir_array_fields";
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
                "gHirArray".into(),
                b.hir_array_fields_params.as_entire_binding(),
            ),
            (
                "hir_array_lit_first_element".into(),
                b.hir_array_lit_first_element.as_entire_binding(),
            ),
            (
                "hir_array_lit_element_count".into(),
                b.hir_array_lit_element_count.as_entire_binding(),
            ),
            (
                "hir_array_lit_context_stmt_node".into(),
                b.hir_array_lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_array_element_parent_lit".into(),
                b.hir_array_element_parent_lit.as_entire_binding(),
            ),
            (
                "hir_array_element_ordinal".into(),
                b.hir_array_element_ordinal.as_entire_binding(),
            ),
            (
                "hir_array_element_next".into(),
                b.hir_array_element_next.as_entire_binding(),
            ),
        ])
    }
}
