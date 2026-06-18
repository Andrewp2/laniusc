use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

/// Pass that records the target type node for each type alias item.
pub struct HirTypeAliasTargetPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeAliasTargetPass,
    label: "hir_type_alias_target",
    shader: "parser/hir/type/alias/target"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeAliasTargetPass {
    const NAME: &'static str = "hir_type_alias_target";
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
                "gHirTypeAliasTarget".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            (
                "hir_semantic_dense_node".into(),
                b.hir_semantic_dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_count".into(),
                b.hir_semantic_count.as_entire_binding(),
            ),
            (
                "hir_type_alias_owner_value".into(),
                b.hir_type_alias_owner_value_a.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            ("hir_type_form".into(), b.hir_type_form.as_entire_binding()),
            (
                "hir_type_alias_target_node".into(),
                b.hir_type_alias_target_node.as_entire_binding(),
            ),
        ])
    }
}
