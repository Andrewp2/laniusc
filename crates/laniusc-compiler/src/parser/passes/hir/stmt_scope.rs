use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that records statement scope ownership for HIR statement nodes.
pub struct HirStmtScopePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirStmtScopePass,
    label: "hir_stmt_scope",
    shader: "parser/hir/stmt_scope"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirStmtScopePass {
    const NAME: &'static str = "hir_stmt_scope";
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
            ("gHirStmtScope".into(), b.hir_params.as_entire_binding()),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_stmt_record".into(),
                b.hir_stmt_record.as_entire_binding(),
            ),
            (
                "hir_nearest_block_node".into(),
                b.hir_nearest_block_node.as_entire_binding(),
            ),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_stmt_scope_end".into(),
                b.hir_stmt_scope_end.as_entire_binding(),
            ),
        ])
    }
}
