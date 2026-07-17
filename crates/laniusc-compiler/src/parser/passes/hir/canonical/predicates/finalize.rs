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
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_flag".into(),
                b.hir_semantic_flag.as_entire_binding(),
            ),
            (
                "type_arg_owner".into(),
                b.hir_type_arg_owner_a.as_entire_binding(),
            ),
            (
                "subject_anchor".into(),
                b.hir_semantic_parent_value_a.as_entire_binding(),
            ),
            ("hir_core".into(), b.hir_core.as_entire_binding()),
            (
                "family_flag".into(),
                b.hir_method_family_flag.as_entire_binding(),
            ),
        ])
    }
}
