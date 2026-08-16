use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalStmtCompactPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalStmtCompactPass,
    label: "hir_canonical_stmt_compact",
    shader: "parser/hir/canonical/stmt_compact"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalStmtCompactPass {
    const NAME: &'static str = "hir_canonical_stmt_compact";
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
                "gCanonical".into(),
                b.hir_canonical_params.as_entire_binding(),
            ),
            (
                "canonical_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "canonical_raw_to_dense".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "raw_stmt_record".into(),
                b.hir_stmt_record.as_entire_binding(),
            ),
            (
                "raw_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "compact_stmt_record".into(),
                b.hir_canonical_stmt_record.as_entire_binding(),
            ),
            (
                "compact_expr_record".into(),
                b.hir_canonical_expr_record.as_entire_binding(),
            ),
        ])
    }
}
