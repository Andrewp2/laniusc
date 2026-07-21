use std::collections::HashMap;

use crate::{
    gpu::passes_core::{DispatchDim, Pass, PassData},
    parser::buffers::ParserBuffers,
};

pub struct HirCanonicalValidatePass {
    data: PassData,
}

crate::gpu::passes_core::impl_static_shader_pass!(
    HirCanonicalValidatePass,
    label: "hir_canonical_validate",
    shader: "parser/hir/canonical/validate"
);

impl Pass<ParserBuffers, crate::parser::debug::DebugOutput> for HirCanonicalValidatePass {
    const NAME: &'static str = "hir_canonical_validate";
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
                "canonical_count".into(),
                b.hir_canonical_count.as_entire_binding(),
            ),
            ("hir_core".into(), b.hir_core.as_entire_binding()),
            ("hir_links".into(), b.hir_links.as_entire_binding()),
            ("hir_payload".into(), b.hir_payload.as_entire_binding()),
            (
                "hir_call_arg_table_count".into(),
                b.hir_call_arg_table_count.as_entire_binding(),
            ),
            ("hir_call_args".into(), b.hir_call_args.as_entire_binding()),
            (
                "hir_param_table_count".into(),
                b.hir_param_table_count.as_entire_binding(),
            ),
            ("hir_params".into(), b.hir_param_rows.as_entire_binding()),
            (
                "hir_param_ranges".into(),
                b.hir_param_ranges.as_entire_binding(),
            ),
            (
                "hir_type_arg_table_count".into(),
                b.hir_type_arg_table_count.as_entire_binding(),
            ),
            (
                "hir_type_args".into(),
                b.hir_type_arg_rows.as_entire_binding(),
            ),
            (
                "hir_type_arg_ranges".into(),
                b.hir_type_arg_ranges.as_entire_binding(),
            ),
            (
                "hir_generic_param_table_count".into(),
                b.hir_generic_param_table_count.as_entire_binding(),
            ),
            (
                "hir_generic_params".into(),
                b.hir_generic_param_rows.as_entire_binding(),
            ),
            (
                "hir_generic_param_ranges".into(),
                b.hir_generic_param_ranges.as_entire_binding(),
            ),
            (
                "hir_path_table_count".into(),
                b.hir_path_table_count.as_entire_binding(),
            ),
            ("hir_paths".into(), b.hir_path_rows.as_entire_binding()),
            (
                "hir_path_segment_table_count".into(),
                b.hir_path_segment_table_count.as_entire_binding(),
            ),
            (
                "hir_path_segments".into(),
                b.hir_path_segment_rows.as_entire_binding(),
            ),
            (
                "hir_field_table_count".into(),
                b.hir_field_table_count.as_entire_binding(),
            ),
            ("hir_fields".into(), b.hir_field_rows.as_entire_binding()),
            (
                "hir_variant_table_count".into(),
                b.hir_variant_table_count.as_entire_binding(),
            ),
            (
                "hir_variants".into(),
                b.hir_variant_rows.as_entire_binding(),
            ),
            (
                "hir_variant_payload_start".into(),
                b.hir_variant_compact_payload_start.as_entire_binding(),
            ),
            (
                "hir_variant_payload_count".into(),
                b.hir_variant_compact_payload_count.as_entire_binding(),
            ),
            (
                "hir_variant_payload_table_count".into(),
                b.hir_variant_payload_table_count.as_entire_binding(),
            ),
            (
                "hir_variant_payloads".into(),
                b.hir_variant_payload_rows.as_entire_binding(),
            ),
            (
                "hir_match_arm_table_count".into(),
                b.hir_match_arm_table_count.as_entire_binding(),
            ),
            (
                "hir_match_arms".into(),
                b.hir_match_arm_rows.as_entire_binding(),
            ),
            (
                "hir_match_payload_start".into(),
                b.hir_match_compact_payload_start.as_entire_binding(),
            ),
            (
                "hir_match_payload_count".into(),
                b.hir_match_compact_payload_count.as_entire_binding(),
            ),
            (
                "hir_match_payload_table_count".into(),
                b.hir_match_payload_table_count.as_entire_binding(),
            ),
            (
                "hir_match_payloads".into(),
                b.hir_match_payload_rows.as_entire_binding(),
            ),
            (
                "hir_array_element_start".into(),
                b.hir_array_compact_element_start.as_entire_binding(),
            ),
            (
                "hir_array_element_count".into(),
                b.hir_array_compact_element_count.as_entire_binding(),
            ),
            (
                "hir_array_element_table_count".into(),
                b.hir_array_element_table_count.as_entire_binding(),
            ),
            (
                "hir_array_elements".into(),
                b.hir_array_element_rows.as_entire_binding(),
            ),
            (
                "hir_string_count".into(),
                b.hir_string_count.as_entire_binding(),
            ),
            (
                "hir_strings".into(),
                b.hir_canonical_string_rows.as_entire_binding(),
            ),
            (
                "hir_string_pool_len".into(),
                b.hir_string_pool_len.as_entire_binding(),
            ),
            (
                "hir_method_count".into(),
                b.hir_method_table_count.as_entire_binding(),
            ),
            (
                "hir_method_cores".into(),
                b.hir_method_core_rows.as_entire_binding(),
            ),
            (
                "hir_method_signatures".into(),
                b.hir_method_signature_rows.as_entire_binding(),
            ),
            (
                "hir_predicate_count".into(),
                b.hir_predicate_table_count.as_entire_binding(),
            ),
            (
                "hir_predicates".into(),
                b.hir_predicate_rows.as_entire_binding(),
            ),
            (
                "hir_expr_parent".into(),
                b.hir_canonical_expr_parent.as_entire_binding(),
            ),
            (
                "hir_expr_root".into(),
                b.hir_canonical_expr_root.as_entire_binding(),
            ),
            (
                "hir_expr_forest_status".into(),
                b.hir_canonical_expr_forest_status.as_entire_binding(),
            ),
            (
                "canonical_status".into(),
                b.hir_canonical_status.as_entire_binding(),
            ),
        ])
    }
}
