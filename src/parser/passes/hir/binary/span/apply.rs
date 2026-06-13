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
    pub uses_status_count: u32,
}

pub struct HirBinarySpanApplyPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirBinarySpanApplyPass,
    label: "hir_binary_span_apply",
    shader: "parser/hir/binary/span/apply"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirBinarySpanApplyPass {
    const NAME: &'static str = "hir_binary_span_apply";
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
                "gHirExpr".into(),
                b.hir_expr_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_binary_span_start_a".into(),
                b.hir_binary_span_start_a.as_entire_binding(),
            ),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
        ])
    }
}
