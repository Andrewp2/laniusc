use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Seeds one parent-or-self link per HIR node before pointer jumping.
pub struct HirExprForestRootInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirExprForestRootInitPass,
    label: "hir_expr_forest_root_init",
    shader: "parser/hir/expr/forest/root_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirExprForestRootInitPass {
    const NAME: &'static str = "hir_expr_forest_root_init";
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
                "gHirExprForest".into(),
                b.hir_expr_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_expr_parent_node".into(),
                b.hir_expr_parent_node.as_entire_binding(),
            ),
            (
                "hir_expr_forest_root_node".into(),
                b.hir_expr_forest_root_node.as_entire_binding(),
            ),
        ])
    }
}
