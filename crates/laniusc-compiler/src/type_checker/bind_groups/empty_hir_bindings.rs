use super::super::*;

/// Minimal HIR buffers used when type checking runs without parser item tables.
pub(super) struct EmptyHirBindings {
    compact_param_count: LaniusBuffer<u32>,
    compact_params: LaniusBuffer<u32>,
    compact_param_ranges: LaniusBuffer<u32>,
    compact_path_count: LaniusBuffer<u32>,
    compact_paths: LaniusBuffer<u32>,
    compact_path_segment_count: LaniusBuffer<u32>,
    compact_path_segments: LaniusBuffer<u32>,
    compact_generic_param_count: LaniusBuffer<u32>,
    compact_generic_params: LaniusBuffer<u32>,
    compact_generic_param_ranges: LaniusBuffer<u32>,
}

impl EmptyHirBindings {
    /// Creates placeholder HIR resources that satisfy every reflected binding.
    pub(super) fn new(device: &wgpu::Device, uses_hir_items: bool, hir_node_capacity: u32) -> Self {
        let _ = (uses_hir_items, hir_node_capacity);
        let compact_generic_param_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_param_count.empty",
            &[0],
        );
        let compact_generic_params = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_params.empty",
            &[u32::MAX; 4],
        );
        let compact_generic_param_ranges = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_generic_param_ranges.empty",
            &[u32::MAX, 0],
        );
        let compact_param_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_param_count.empty",
            &[0],
        );
        let compact_params = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_params.empty",
            &[u32::MAX; 4],
        );
        let compact_param_ranges = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_param_ranges.empty",
            &[u32::MAX, 0],
        );
        let compact_path_count =
            storage_ro_from_u32s(device, "type_check.resident.compact_path_count.empty", &[0]);
        let compact_paths = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_paths.empty",
            &[u32::MAX; 4],
        );
        let compact_path_segment_count = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_path_segment_count.empty",
            &[0],
        );
        let compact_path_segments = storage_ro_from_u32s(
            device,
            "type_check.resident.compact_path_segments.empty",
            &[u32::MAX; 4],
        );

        Self {
            compact_param_count,
            compact_params,
            compact_param_ranges,
            compact_path_count,
            compact_paths,
            compact_path_segment_count,
            compact_path_segments,
            compact_generic_param_count,
            compact_generic_params,
            compact_generic_param_ranges,
        }
    }
}

/// Registers real parser HIR item buffers under the shader resource names.
pub(super) fn register_hir_item_resources<'a>(
    resources: &mut ResourceMap<'a>,
    hir_items: GpuTypeCheckHirItemBuffers<'a>,
) {
    resources.buffer("compact_hir_count", &hir_items.hir.count);
    resources.buffer("compact_hir_core", &hir_items.hir.core);
    resources.buffer("compact_hir_links", &hir_items.hir.links);
    resources.buffer("compact_hir_payload", &hir_items.hir.payload);
    resources.buffer(
        "compact_hir_predicate_facts",
        &hir_items.hir.predicate_facts,
    );
    resources.buffer("compact_hir_scope_end", &hir_items.hir.scope_end);
    resources.buffer("compact_hir_nearest_loop", &hir_items.hir.nearest_loop);
    resources.buffer("compact_hir_nearest_block", &hir_items.hir.nearest_block);
    resources.buffer(
        "compact_hir_nearest_control",
        &hir_items.hir.nearest_control,
    );
    resources.buffer("compact_hir_nearest_fn", &hir_items.hir.nearest_fn);
    resources.buffer("compact_hir_expr_parent", &hir_items.hir.expr_parent);
    resources.buffer("compact_hir_expr_root", &hir_items.hir.expr_root);
    resources.buffer("compact_call_arg_count", &hir_items.hir.call_arg_count);
    resources.buffer("compact_call_args", &hir_items.hir.call_args);
    resources.buffer("compact_fn_return_type", &hir_items.hir.fn_return_type);
    resources.buffer("compact_type_root_owner", &hir_items.hir.type_root_owner);
    resources.buffer(
        "compact_type_alias_target",
        &hir_items.hir.type_alias_target,
    );
    resources.buffer("compact_const_type", &hir_items.hir.const_type);
    resources.buffer("compact_param_count", &hir_items.hir.param_count);
    resources.buffer("compact_params", &hir_items.hir.params);
    resources.buffer("compact_param_ranges", &hir_items.hir.param_ranges);
    resources.buffer("compact_method_count", &hir_items.hir.method_count);
    resources.buffer("compact_method_cores", &hir_items.hir.method_cores);
    resources.buffer(
        "compact_method_signatures",
        &hir_items.hir.method_signatures,
    );
    resources.buffer("compact_predicate_count", &hir_items.hir.predicate_count);
    resources.buffer("compact_predicates", &hir_items.hir.predicates);
    resources.buffer("compact_type_arg_count", &hir_items.hir.type_arg_count);
    resources.buffer("compact_type_args", &hir_items.hir.type_args);
    resources.buffer("compact_type_arg_ranges", &hir_items.hir.type_arg_ranges);
    resources.buffer("compact_path_count", &hir_items.hir.path_count);
    resources.buffer("compact_paths", &hir_items.hir.paths);
    resources.buffer(
        "compact_path_segment_count",
        &hir_items.hir.path_segment_count,
    );
    resources.buffer("compact_path_segments", &hir_items.hir.path_segments);
    resources.buffer(
        "compact_generic_param_count",
        &hir_items.hir.generic_param_count,
    );
    resources.buffer("compact_generic_params", &hir_items.hir.generic_params);
    resources.buffer(
        "compact_generic_param_ranges",
        &hir_items.hir.generic_param_ranges,
    );
    resources.buffer("compact_field_count", &hir_items.hir.field_count);
    resources.buffer("compact_fields", &hir_items.hir.fields);
    resources.buffer("compact_variant_count", &hir_items.hir.variant_count);
    resources.buffer("compact_variants", &hir_items.hir.variants);
    resources.buffer(
        "compact_variant_payload_start",
        &hir_items.hir.variant_payload_start,
    );
    resources.buffer(
        "compact_variant_payload_count",
        &hir_items.hir.variant_payload_count,
    );
    resources.buffer(
        "compact_variant_payload_row_count",
        &hir_items.hir.variant_payload_row_count,
    );
    resources.buffer("compact_variant_payloads", &hir_items.hir.variant_payloads);
    resources.buffer("compact_match_arm_count", &hir_items.hir.match_arm_count);
    resources.buffer("compact_match_arms", &hir_items.hir.match_arms);
    resources.buffer(
        "compact_match_payload_start",
        &hir_items.hir.match_payload_start,
    );
    resources.buffer(
        "compact_match_payload_count",
        &hir_items.hir.match_payload_count,
    );
    resources.buffer(
        "compact_match_payload_row_count",
        &hir_items.hir.match_payload_row_count,
    );
    resources.buffer("compact_match_payloads", &hir_items.hir.match_payloads);
    resources.buffer(
        "compact_array_element_start",
        &hir_items.hir.array_element_start,
    );
    resources.buffer(
        "compact_array_element_count",
        &hir_items.hir.array_element_count,
    );
    resources.buffer(
        "compact_array_element_row_count",
        &hir_items.hir.array_element_row_count,
    );
    resources.buffer("compact_array_elements", &hir_items.hir.array_elements);
}

/// Registers placeholder HIR resources for modes without parser item metadata.
pub(super) fn register_empty_hir_resources<'a>(
    resources: &mut ResourceMap<'a>,
    empty_hir: &'a EmptyHirBindings,
) {
    resources.buffer("compact_hir_count", &empty_hir.compact_generic_param_count);
    resources.buffer("compact_hir_core", &empty_hir.compact_generic_params);
    resources.buffer("compact_hir_links", &empty_hir.compact_generic_params);
    resources.buffer("compact_hir_payload", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_hir_predicate_facts",
        &empty_hir.compact_generic_params,
    );
    resources.buffer("compact_hir_scope_end", &empty_hir.compact_params);
    resources.buffer("compact_hir_nearest_loop", &empty_hir.compact_params);
    resources.buffer("compact_hir_nearest_block", &empty_hir.compact_params);
    resources.buffer("compact_hir_nearest_control", &empty_hir.compact_params);
    resources.buffer("compact_hir_nearest_fn", &empty_hir.compact_params);
    resources.buffer("compact_hir_expr_parent", &empty_hir.compact_params);
    resources.buffer("compact_hir_expr_root", &empty_hir.compact_params);
    resources.buffer("compact_call_arg_count", &empty_hir.compact_param_count);
    resources.buffer("compact_call_args", &empty_hir.compact_params);
    resources.buffer("compact_fn_return_type", &empty_hir.compact_params);
    resources.buffer("compact_type_root_owner", &empty_hir.compact_params);
    resources.buffer("compact_type_alias_target", &empty_hir.compact_params);
    resources.buffer("compact_const_type", &empty_hir.compact_params);
    resources.buffer("compact_param_count", &empty_hir.compact_param_count);
    resources.buffer("compact_params", &empty_hir.compact_params);
    resources.buffer("compact_param_ranges", &empty_hir.compact_param_ranges);
    resources.buffer("compact_method_count", &empty_hir.compact_param_count);
    resources.buffer("compact_method_cores", &empty_hir.compact_params);
    resources.buffer("compact_method_signatures", &empty_hir.compact_params);
    resources.buffer("compact_predicate_count", &empty_hir.compact_param_count);
    resources.buffer("compact_predicates", &empty_hir.compact_params);
    resources.buffer("compact_type_arg_count", &empty_hir.compact_param_count);
    resources.buffer("compact_type_args", &empty_hir.compact_params);
    resources.buffer("compact_type_arg_ranges", &empty_hir.compact_param_ranges);
    resources.buffer("compact_path_count", &empty_hir.compact_path_count);
    resources.buffer("compact_paths", &empty_hir.compact_paths);
    resources.buffer(
        "compact_path_segment_count",
        &empty_hir.compact_path_segment_count,
    );
    resources.buffer("compact_path_segments", &empty_hir.compact_path_segments);
    resources.buffer(
        "compact_generic_param_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_generic_params", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_generic_param_ranges",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_field_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_fields", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_variant_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_variants", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_variant_payload_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_variant_payload_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_variant_payload_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_variant_payloads",
        &empty_hir.compact_generic_params,
    );
    resources.buffer(
        "compact_match_arm_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_match_arms", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_match_payload_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_match_payload_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_match_payload_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_match_payloads", &empty_hir.compact_generic_params);
    resources.buffer(
        "compact_array_element_start",
        &empty_hir.compact_generic_param_ranges,
    );
    resources.buffer(
        "compact_array_element_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer(
        "compact_array_element_row_count",
        &empty_hir.compact_generic_param_count,
    );
    resources.buffer("compact_array_elements", &empty_hir.compact_generic_params);
}
