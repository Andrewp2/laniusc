use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirTypeAliasOwnerInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirTypeAliasOwnerInitPass,
    label: "hir_type_alias_owner_init",
    shader: "hir_type_alias_owner_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirTypeAliasOwnerInitPass {
    const NAME: &'static str = "hir_type_alias_owner_init";
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
                "gHirTypeAliasOwner".into(),
                b.hir_params.as_entire_binding(),
            ),
            (
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
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
                "hir_semantic_parent".into(),
                b.hir_semantic_parent.as_entire_binding(),
            ),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_type_alias_owner_link_a".into(),
                b.hir_type_alias_owner_link_a.as_entire_binding(),
            ),
            (
                "hir_type_alias_owner_value_a".into(),
                b.hir_type_alias_owner_value_a.as_entire_binding(),
            ),
        ])
    }
}
