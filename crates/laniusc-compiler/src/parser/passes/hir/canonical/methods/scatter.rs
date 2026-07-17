use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};
pub struct HirCanonicalMethodScatterPass {
    data: PassData,
}
crate::gpu::passes_core::impl_static_shader_pass!(HirCanonicalMethodScatterPass, label: "hir_canonical_method_scatter", shader: "parser/hir/canonical/methods/scatter");
impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalMethodScatterPass {
    const NAME: &'static str = "hir_canonical_method_scatter";
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
            (
                "raw_to_hir".into(),
                b.hir_canonical_raw_to_dense.as_entire_binding(),
            ),
            (
                "canonical_anchor_owner".into(),
                b.hir_canonical_anchor_owner.as_entire_binding(),
            ),
            ("hir_kind".into(), b.hir_kind.as_entire_binding()),
            ("hir_token_pos".into(), b.hir_token_pos.as_entire_binding()),
            ("hir_token_end".into(), b.hir_token_end.as_entire_binding()),
            (
                "hir_expr_record".into(),
                b.hir_expr_record.as_entire_binding(),
            ),
            (
                "hir_call_callee_node".into(),
                b.hir_call_callee_node.as_entire_binding(),
            ),
            (
                "method_owner".into(),
                b.hir_method_owner_node.as_entire_binding(),
            ),
            (
                "method_impl".into(),
                b.hir_method_impl_node.as_entire_binding(),
            ),
            (
                "method_name_token".into(),
                b.hir_method_name_token.as_entire_binding(),
            ),
            (
                "method_first_param_token".into(),
                b.hir_method_first_param_token.as_entire_binding(),
            ),
            (
                "method_receiver_mode".into(),
                b.hir_method_receiver_mode.as_entire_binding(),
            ),
            (
                "method_visibility".into(),
                b.hir_method_visibility.as_entire_binding(),
            ),
            (
                "method_signature_flags".into(),
                b.hir_method_signature_flags.as_entire_binding(),
            ),
            (
                "method_impl_receiver_type".into(),
                b.hir_method_impl_receiver_type_node.as_entire_binding(),
            ),
            (
                "family_count".into(),
                b.hir_method_table_count.as_entire_binding(),
            ),
            (
                "method_cores".into(),
                b.hir_method_core_rows.as_entire_binding(),
            ),
            (
                "method_signatures".into(),
                b.hir_method_signature_rows.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
