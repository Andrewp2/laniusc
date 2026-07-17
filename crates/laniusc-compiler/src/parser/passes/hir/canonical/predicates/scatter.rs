use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalPredicateScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalPredicateScatterPass, label: "hir_canonical_predicate_scatter", shader: "parser/hir/canonical/predicates/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalPredicateScatterPass {
    const NAME: &'static str = "hir_canonical_predicate_scatter";
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
                "family_flag".into(),
                b.hir_method_family_flag.as_entire_binding(),
            ),
            (
                "family_local_prefix".into(),
                b.hir_semantic_local_prefix.as_entire_binding(),
            ),
            (
                "family_block_prefix".into(),
                b.hir_semantic_block_prefix_a.as_entire_binding(),
            ),
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "subject_anchor".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
            (
                "owner_value".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            ("hir_links".into(), b.hir_links.as_entire_binding()),
            (
                "family_count".into(),
                b.hir_predicate_table_count.as_entire_binding(),
            ),
            (
                "predicates".into(),
                b.hir_predicate_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
