use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalRelationsInitPass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalRelationsInitPass,
    label: "hir_canonical_relations_init",
    shader: "parser/hir/canonical/relations_init"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalRelationsInitPass {
    const NAME: &'static str = "hir_canonical_relations_init";
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
                "tree_count_status".into(),
                if b.tree_count_uses_status {
                    b.partial_parse_status.as_entire_binding()
                } else {
                    b.ll1_status.as_entire_binding()
                },
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
            (
                "raw_to_hir".into(),
                b.hir_canonical_alias_to_dense.as_entire_binding(),
            ),
            (
                "raw_to_item".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "canonical_prefix_before_raw".into(),
                b.hir_canonical_prefix_before_raw.as_entire_binding(),
            ),
            (
                "relation_link_a".into(),
                b.hir_semantic_parent_link_a.as_entire_binding(),
            ),
            (
                "canonical_parent_a".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
            (
                "generic_owner_a".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            (
                "predicate_subject_a".into(),
                b.hir_variant_payload_rank_a.as_entire_binding(),
            ),
        ])
    }
}
