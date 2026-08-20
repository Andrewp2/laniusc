use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalPredicateFinalizePass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalPredicateFinalizePass, label: "hir_canonical_predicate_finalize", shader: "parser/hir/canonical/predicates/finalize");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalPredicateFinalizePass {
    const NAME: &'static str = "hir_canonical_predicate_finalize";
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
            ("node_kind".into(), b.node_kind.as_entire_binding()),
            ("parent".into(), b.parent.as_entire_binding()),
            ("next_sibling".into(), b.next_sibling.as_entire_binding()),
            (
                "raw_to_hir".into(),
                b.hir_canonical_alias_to_dense.as_entire_binding(),
            ),
            (
                "hir_to_raw".into(),
                b.hir_canonical_dense_to_raw.as_entire_binding(),
            ),
            (
                "type_root_owner".into(),
                b.hir_type_root_owner.as_entire_binding(),
            ),
            ("hir_item_kind".into(), b.hir_item_kind.as_entire_binding()),
            (
                "hir_method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
            (
                "raw_to_item".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "subject_anchor".into(),
                b.hir_variant_payload_rank_a.as_entire_binding(),
            ),
            (
                "owner_value".into(),
                b.hir_type_arg_rank_a.as_entire_binding(),
            ),
            (
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            (
                "canonical_dense_to_raw".into(),
                b.hir_canonical_dense_to_raw.as_entire_binding(),
            ),
            (
                "family_flag".into(),
                b.hir_method_family_flag.as_entire_binding(),
            ),
        ])
    }
}
