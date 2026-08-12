use super::super::*;

/// Registers the compact HIR as the type checker's sole frontend input.
pub(super) fn register_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    input: GpuTypeCheckHirItemBuffers<'a>,
) {
    let hir = input.hir;
    resources.buffer("compact_hir_count", &hir.count);
    resources.buffer("compact_hir_core", &hir.core);
    resources.buffer("compact_hir_links", &hir.links);
    resources.buffer("compact_hir_payload", &hir.payload);
    resources.buffer("type_decl_hir_node_by_token", &hir.type_decl_by_name_token);
    resources.buffer("compact_hir_semantic_facts", &hir.semantic_facts);
    resources.buffer("compact_hir_scope_end", &hir.scope_end);
    resources.buffer("compact_hir_nearest_loop", &hir.nearest_loop);
    resources.buffer("compact_hir_nearest_block", &hir.nearest_block);
    resources.buffer("compact_hir_nearest_control", &hir.nearest_control);
    resources.buffer("compact_hir_nearest_fn", &hir.nearest_fn);
    resources.buffer("compact_hir_expr_parent", &hir.expr_parent);
    resources.buffer("compact_hir_expr_root", &hir.expr_root);
    resources.buffer("compact_call_arg_count", &hir.call_arg_count);
    resources.buffer("compact_call_args", &hir.call_args);
    resources.buffer("compact_fn_return_type", &hir.fn_return_type);
    resources.buffer("compact_type_root_owner", &hir.type_root_owner);
    resources.buffer("compact_type_alias_target", &hir.type_alias_target);
    resources.buffer("compact_const_type", &hir.const_type);
    resources.buffer("compact_const_value", &hir.const_value);
    resources.buffer("compact_param_count", &hir.param_count);
    resources.buffer("compact_params", &hir.params);
    resources.buffer("compact_param_ranges", &hir.param_ranges);
    resources.buffer("compact_method_count", &hir.method_count);
    resources.buffer("compact_method_cores", &hir.method_cores);
    resources.buffer("compact_method_signatures", &hir.method_signatures);
    resources.buffer("compact_predicate_count", &hir.predicate_count);
    resources.buffer("compact_predicates", &hir.predicates);
    resources.buffer("compact_type_arg_count", &hir.type_arg_count);
    resources.buffer("compact_type_args", &hir.type_args);
    resources.buffer("compact_type_arg_ranges", &hir.type_arg_ranges);
    resources.buffer("compact_path_count", &hir.path_count);
    resources.buffer("compact_paths", &hir.paths);
    resources.buffer("compact_path_segment_count", &hir.path_segment_count);
    resources.buffer("compact_path_segments", &hir.path_segments);
    resources.buffer("compact_generic_param_count", &hir.generic_param_count);
    resources.buffer("compact_generic_params", &hir.generic_params);
    resources.buffer("compact_generic_param_ranges", &hir.generic_param_ranges);
    resources.buffer("compact_field_count", &hir.field_count);
    resources.buffer("compact_fields", &hir.fields);
    resources.buffer("compact_variant_count", &hir.variant_count);
    resources.buffer("compact_variants", &hir.variants);
    resources.buffer("compact_variant_payload_start", &hir.variant_payload_start);
    resources.buffer("compact_variant_payload_count", &hir.variant_payload_count);
    resources.buffer(
        "compact_variant_payload_row_count",
        &hir.variant_payload_row_count,
    );
    resources.buffer("compact_variant_payloads", &hir.variant_payloads);
    resources.buffer("compact_match_arm_count", &hir.match_arm_count);
    resources.buffer("compact_match_arms", &hir.match_arms);
    resources.buffer("compact_match_payload_start", &hir.match_payload_start);
    resources.buffer("compact_match_payload_count", &hir.match_payload_count);
    resources.buffer(
        "compact_match_pattern_payload_count",
        &hir.match_pattern_payload_count,
    );
    resources.buffer(
        "compact_match_payload_row_count",
        &hir.match_payload_row_count,
    );
    resources.buffer("compact_match_payloads", &hir.match_payloads);
    resources.buffer("compact_array_element_start", &hir.array_element_start);
    resources.buffer("compact_array_element_count", &hir.array_element_count);
    resources.buffer(
        "compact_array_element_row_count",
        &hir.array_element_row_count,
    );
    resources.buffer("compact_array_elements", &hir.array_elements);
}
