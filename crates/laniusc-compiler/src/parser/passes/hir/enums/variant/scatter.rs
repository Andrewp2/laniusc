use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirEnumVariantScatterPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirEnumVariantScatterPass,
    label: "hir_enum_variant_scatter",
    shader: "parser/hir/enum/variant/scatter"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirEnumVariantScatterPass {
    const NAME: &'static str = "hir_enum_variant_scatter";
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
                "gHirEnum".into(),
                b.hir_enum_match_fields_params.as_entire_binding(),
            ),
            (
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            (
                "hir_variant_owner_a".into(),
                b.hir_variant_owner_a.as_entire_binding(),
            ),
            (
                "hir_variant_rank_a".into(),
                b.hir_variant_rank_a.as_entire_binding(),
            ),
            (
                "hir_variant_payload_owner_a".into(),
                b.hir_variant_payload_owner_a.as_entire_binding(),
            ),
            (
                "hir_variant_payload_rank_a".into(),
                b.hir_variant_payload_rank_a.as_entire_binding(),
            ),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_variant_parent_enum".into(),
                b.hir_variant_parent_enum.as_entire_binding(),
            ),
            (
                "hir_variant_ordinal".into(),
                b.hir_variant_ordinal.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start".into(),
                b.hir_variant_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count".into(),
                b.hir_variant_payload_count.as_entire_binding(),
            ),
            (
                "hir_variant_payload_node".into(),
                b.hir_variant_payload_node.as_entire_binding(),
            ),
        ])
    }
}
