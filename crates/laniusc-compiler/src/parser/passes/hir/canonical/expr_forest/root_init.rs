use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Decodes compact expression parents and seeds root links.
pub struct HirCanonicalExprForestRootInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalExprForestRootInitPass,
    label: "hir_canonical_expr_forest_root_init",
    shader: "parser/hir/canonical/expr_forest/root_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalExprForestRootInitPass {
    const NAME: &'static str = "hir_canonical_expr_forest_root_init";
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
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "expr_parent_encoded".into(),
                b.hir_canonical_expr_parent_encoded.as_entire_binding(),
            ),
            (
                "expr_parent".into(),
                b.hir_canonical_expr_parent.as_entire_binding(),
            ),
            (
                "expr_root".into(),
                b.hir_canonical_expr_root.as_entire_binding(),
            ),
        ])
    }
}
