use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirEnumVariantLinksPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirEnumVariantLinksPass,
    label: "hir_enum_variant_links",
    shader: "hir_enum_variant_links"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirEnumVariantLinksPass {
    const NAME: &'static str = "hir_enum_variant_links";
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
                "ll1_status".into(),
                if b.tree_count_uses_status && !b.tree_stream_uses_ll1 {
                    b.projected_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("first_child".into(), b.first_child.as_entire_binding()),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            (
                "hir_variant_owner_a".into(),
                b.hir_variant_owner_a.as_entire_binding(),
            ),
            (
                "hir_variant_link_a".into(),
                b.hir_variant_link_a.as_entire_binding(),
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
                "hir_variant_payload_link_a".into(),
                b.hir_variant_payload_link_a.as_entire_binding(),
            ),
            (
                "hir_variant_payload_rank_a".into(),
                b.hir_variant_payload_rank_a.as_entire_binding(),
            ),
        ])
    }
}
