//! Resources and operations that refine semantic HIR after dense identity.

use super::{
    clear,
    external,
    indirect,
    input,
    output,
    reflected,
    retained_hir_output,
    static_pass,
    workspace,
    workspace_indirect,
};

fn canonical_family_flag(name: &str) -> bool {
    matches!(
        name,
        "hir_call_arg_family_flag"
            | "hir_param_family_flag"
            | "hir_type_arg_family_flag"
            | "hir_generic_param_family_flag"
            | "hir_method_family_flag"
            | "hir_path_family_flag"
            | "hir_variant_family_flag"
            | "hir_variant_payload_family_flag"
            | "hir_array_element_family_flag"
            | "hir_match_arm_family_flag"
            | "hir_match_payload_family_flag"
            | "hir_field_family_flag"
    )
}

const MATCH_WORKSPACE_RESOURCES: &[&str] = &[
    "hir_match_arm_owner_a",
    "hir_match_arm_owner_b",
    "hir_match_arm_link_a",
    "hir_match_arm_link_b",
    "hir_match_arm_rank_a",
    "hir_match_arm_rank_b",
    "hir_match_arm_previous",
    "hir_match_payload_owner_a",
    "hir_match_payload_owner_b",
    "hir_match_payload_link_a",
    "hir_match_payload_link_b",
    "hir_match_payload_rank_a",
    "hir_match_payload_rank_b",
    "hir_match_pattern_parent",
    "hir_match_pattern_parent_b",
    "hir_match_rank_flag",
    "hir_match_rank_local_prefix",
    "hir_match_rank_block_sum",
    "hir_match_rank_block_prefix_a",
    "hir_match_rank_block_prefix_b",
    "hir_match_rank_node",
    "hir_match_rank_count",
];

const MATCH_RAW_RESOURCES: &[&str] = &[
    "hir_match_scrutinee_node",
    "hir_match_arm_pattern_node",
    "hir_match_arm_result_node",
    "hir_match_arm_start",
    "hir_match_arm_count",
    "hir_match_arm_next",
    "hir_match_arm_payload_start",
    "hir_match_arm_payload_count",
    "hir_match_pattern_owner_arm",
    "hir_match_payload_owner_arm",
    "hir_match_payload_match_node",
    "hir_match_payload_ordinal",
    "hir_match_arm_raw_to_row",
];

fn graph_owned_hir_workspace(name: &str) -> bool {
    canonical_family_flag(name)
        || MATCH_WORKSPACE_RESOURCES.contains(&name)
        || MATCH_RAW_RESOURCES.contains(&name)
        || matches!(
            name,
            "hir_type_arg_owner_a"
                | "hir_type_arg_owner_b"
                | "hir_type_arg_link_a"
                | "hir_type_arg_link_b"
                | "hir_type_arg_rank_a"
                | "hir_type_arg_rank_b"
                | "hir_type_arg_previous"
                | "hir_type_root_owner"
                | "hir_type_alias_owner_link_a"
                | "hir_type_alias_owner_link_b"
                | "hir_type_alias_owner_value_a"
                | "hir_type_alias_owner_value_b"
                | "hir_fn_signature_owner_link_a"
                | "hir_fn_signature_owner_link_b"
                | "hir_fn_signature_return_owner_a"
                | "hir_fn_signature_return_owner_b"
                | "hir_fn_signature_function_owner_a"
                | "hir_fn_signature_function_owner_b"
                | "hir_param_owner_a"
                | "hir_param_link_a"
                | "hir_param_rank_a"
                | "hir_param_rank_b"
                | "hir_call_arg_owner_a"
                | "hir_call_arg_owner_b"
                | "hir_call_arg_link_a"
                | "hir_call_arg_link_b"
                | "hir_call_arg_rank_a"
                | "hir_call_arg_rank_b"
                | "hir_array_element_owner_a"
                | "hir_array_element_owner_b"
                | "hir_array_element_link_a"
                | "hir_array_element_link_b"
                | "hir_array_element_rank_a"
                | "hir_array_element_rank_b"
                | "hir_array_element_previous"
                | "hir_array_lit_first_element"
                | "hir_array_lit_element_count"
                | "hir_array_element_parent_lit"
                | "hir_array_element_ordinal"
                | "hir_array_element_next"
                | "hir_variant_owner_a"
                | "hir_variant_owner_b"
                | "hir_variant_link_a"
                | "hir_variant_link_b"
                | "hir_variant_rank_a"
                | "hir_variant_rank_b"
                | "hir_variant_payload_owner_a"
                | "hir_variant_payload_owner_b"
                | "hir_variant_payload_link_a"
                | "hir_variant_payload_link_b"
                | "hir_variant_payload_rank_a"
                | "hir_variant_payload_rank_b"
                | "hir_struct_field_owner_a"
                | "hir_struct_field_owner_b"
                | "hir_struct_field_link_a"
                | "hir_struct_field_link_b"
                | "hir_struct_field_rank_a"
                | "hir_struct_field_rank_b"
                | "hir_struct_lit_field_owner_a"
                | "hir_struct_lit_field_owner_b"
                | "hir_struct_lit_field_link_a"
                | "hir_struct_lit_field_link_b"
                | "hir_struct_lit_field_rank_a"
                | "hir_struct_lit_field_rank_b"
                | "hir_struct_lit_field_previous"
                | "hir_semantic_parent_link_a"
                | "hir_semantic_parent_link_b"
                | "hir_semantic_parent_value_a"
                | "hir_semantic_parent_value_b"
                | "hir_path_root_owner"
                | "hir_path_segment_owner_a"
                | "hir_path_segment_owner_b"
                | "hir_path_segment_link_a"
                | "hir_path_segment_link_b"
                | "hir_path_segment_rank_a"
                | "hir_path_segment_rank_b"
                | "hir_path_segment_count"
                | "hir_stmt_context_link_a"
                | "hir_stmt_context_link_b"
                | "hir_contextual_stmt_value_a"
                | "hir_contextual_stmt_value_b"
                | "hir_nearest_stmt_value_a"
                | "hir_nearest_stmt_value_b"
                | "hir_nearest_block_value_a"
                | "hir_nearest_block_value_b"
                | "hir_nearest_enclosing_control_value_a"
                | "hir_nearest_enclosing_control_value_b"
                | "hir_nearest_loop_value_a"
                | "hir_nearest_loop_value_b"
                | "hir_nearest_fn_value_a"
                | "hir_nearest_fn_value_b"
                | "hir_nearest_array_element_value_a"
                | "hir_nearest_array_element_value_b"
                | "hir_binary_span_link_a"
                | "hir_binary_span_link_b"
                | "hir_binary_span_start_a"
                | "hir_binary_span_start_b"
                | "hir_expr_int_value"
                | "hir_expr_float_bits"
                | "hir_expr_string_start"
                | "hir_expr_string_len"
                | "hir_string_data_offset"
                | "hir_string_decoded_len"
                | "hir_string_node"
                | "hir_list_rank_flag"
                | "hir_list_rank_local_prefix"
                | "hir_list_rank_block_sum"
                | "hir_list_rank_block_prefix_a"
                | "hir_list_rank_block_prefix_b"
                | "hir_list_rank_node"
                | "hir_list_rank_count"
                | "hir_enum_rank_flag"
                | "hir_enum_rank_local_prefix"
                | "hir_enum_rank_block_sum"
                | "hir_enum_rank_block_prefix_a"
                | "hir_enum_rank_block_prefix_b"
                | "hir_enum_rank_node"
                | "hir_enum_rank_count"
                | "hir_struct_rank_flag"
                | "hir_struct_rank_local_prefix"
                | "hir_struct_rank_block_sum"
                | "hir_struct_rank_block_prefix_a"
                | "hir_struct_rank_block_prefix_b"
                | "hir_struct_rank_node"
                | "hir_struct_rank_count"
                | "hir_item_kind"
                | "hir_canonical_context_stmt"
                | "hir_canonical_semantic_dense_node"
                | "hir_canonical_expr_parent_encoded"
                | "hir_canonical_expr_root_scratch"
                | "hir_variant_parent_enum"
                | "hir_variant_ordinal"
                | "hir_variant_payload_start"
                | "hir_variant_payload_count"
                | "hir_variant_payload_node"
                | "hir_variant_raw_to_row"
                | "hir_struct_field_parent_struct"
                | "hir_struct_field_ordinal"
                | "hir_struct_field_type_node"
                | "hir_struct_decl_field_start"
                | "hir_struct_decl_field_count"
                | "hir_struct_lit_head_node"
                | "hir_struct_lit_field_start"
                | "hir_struct_lit_field_count"
                | "hir_struct_lit_field_parent_lit"
                | "hir_struct_lit_field_value_node"
        )
}
use crate::{
    gpu::{
        compiler_graph::{
            AccessMode,
            CompilerGraphBuilder,
            CompilerPhase,
            PassAccess,
            PassDesc,
            ResourceDomain,
        },
        scan::hierarchical_scan_levels,
    },
    parser::{
        compiler_graph::ParserGraphCapacity,
        passes::{ParserPasses, hir::list::rank::ListRankInvocation},
    },
};

pub(in crate::parser) const ITEM_KIND_CLEAR: &str = "parser.hir_item_kind.clear";
pub(in crate::parser) const PATH_ROOT_OWNER_CLEAR: &str = "parser.hir_path_root_owner.clear";
pub(in crate::parser) const PATH_SEGMENT_COUNT_CLEAR: &str = "parser.hir_path_segment_count.clear";
pub(in crate::parser) const STRING_DECODED_LEN_CLEAR: &str = "parser.hir_string_decoded_len.clear";
pub(in crate::parser) const STRING_DATA_WORDS_CLEAR: &str = "parser.hir_string_data_words.clear";
pub(in crate::parser) const CALL_ARG_COUNT_CLEAR: &str = "parser.hir_call_arg_count.clear";
pub(in crate::parser) const TYPE_ARG_OWNER_B_CLEAR: &str = "parser.hir_type_arg_owner_b.clear";
pub(in crate::parser) const TYPE_ARG_LINK_B_CLEAR: &str = "parser.hir_type_arg_link_b.clear";
pub(in crate::parser) const TYPE_ARG_RANK_B_CLEAR: &str = "parser.hir_type_arg_rank_b.clear";
pub(in crate::parser) const CANONICAL_VARIANT_CLEAR: &str = "parser.hir_canonical.variants.clear";
pub(in crate::parser) const CANONICAL_VARIANT_PAYLOAD_CLEAR: &str =
    "parser.hir_canonical.variant_payloads.clear";
pub(in crate::parser) const CANONICAL_CALL_ARGUMENT_CLEAR: &str =
    "parser.hir_canonical.call_arguments.clear";
pub(in crate::parser) const CANONICAL_ARRAY_ELEMENT_CLEAR: &str =
    "parser.hir_canonical.array_elements.clear";
pub(in crate::parser) const CANONICAL_MATCH_OUTPUTS_CLEAR: &str =
    "parser.hir_canonical.match_outputs.clear";
pub(in crate::parser) const CANONICAL_MATCH_ARM_CLEAR: &str =
    "parser.hir_canonical.match_arms.clear";
pub(in crate::parser) const CANONICAL_MATCH_PAYLOAD_CLEAR: &str =
    "parser.hir_canonical.match_payloads.clear";
pub(in crate::parser) const CANONICAL_FIELD_CLEAR: &str = "parser.hir_canonical.fields.clear";
pub(in crate::parser) const CANONICAL_PARAMETER_CLEAR: &str =
    "parser.hir_canonical.parameters.clear";
pub(in crate::parser) const CANONICAL_TYPE_ARGUMENT_CLEAR: &str =
    "parser.hir_canonical.type_arguments.clear";
pub(in crate::parser) const CANONICAL_EXPR_FOREST_CLEAR: &str =
    "parser.hir_canonical.expr_forest.clear";
pub(in crate::parser) const CANONICAL_GENERIC_PARAMETER_CLEAR: &str =
    "parser.hir_canonical.generic_parameters.clear";
pub(in crate::parser) const CANONICAL_PATH_SEGMENT_CLEAR: &str =
    "parser.hir_canonical.path_segments.clear";
pub(in crate::parser) const CANONICAL_PATH_CLEAR: &str = "parser.hir_canonical.paths.clear";
pub(in crate::parser) const CANONICAL_METHOD_CLEAR: &str = "parser.hir_canonical.methods.clear";
pub(in crate::parser) const CANONICAL_PREDICATE_CLEAR: &str =
    "parser.hir_canonical.predicates.clear";

pub(super) fn register_resources(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
) -> Result<(), String> {
    let tree_rows = u64::from(capacity.tree_capacity.max(1));
    let tree_blocks = u64::from(capacity.tree_node_blocks.max(1));
    let canonical_rows = u64::from(capacity.token_capacity.max(1));

    input(
        graph,
        "source_bytes",
        ResourceDomain::Bytes,
        u64::from(capacity.source_capacity.max(1)),
    )?;

    for name in [
        "hir_type_arg_owner_a",
        "hir_type_arg_owner_b",
        "hir_type_arg_link_a",
        "hir_type_arg_link_b",
        "hir_type_arg_rank_a",
        "hir_type_arg_rank_b",
        "hir_type_arg_previous",
        "hir_type_root_owner",
        "hir_param_owner_a",
        "hir_param_link_a",
        "hir_param_rank_a",
        "hir_param_rank_b",
        "hir_call_arg_owner_a",
        "hir_call_arg_owner_b",
        "hir_call_arg_link_a",
        "hir_call_arg_link_b",
        "hir_call_arg_rank_a",
        "hir_call_arg_rank_b",
        "hir_call_arg_family_flag",
        "hir_array_element_owner_a",
        "hir_array_element_owner_b",
        "hir_array_element_link_a",
        "hir_array_element_link_b",
        "hir_array_element_rank_a",
        "hir_array_element_rank_b",
        "hir_array_element_previous",
        "hir_array_lit_first_element",
        "hir_array_lit_element_count",
        "hir_array_element_parent_lit",
        "hir_array_element_ordinal",
        "hir_array_element_next",
        "hir_array_element_family_flag",
        "hir_match_scrutinee_node",
        "hir_match_arm_pattern_node",
        "hir_match_arm_result_node",
        "hir_match_arm_start",
        "hir_match_arm_count",
        "hir_match_arm_next",
        "hir_match_arm_payload_start",
        "hir_match_arm_payload_count",
        "hir_match_pattern_owner_arm",
        "hir_match_arm_owner_a",
        "hir_match_arm_owner_b",
        "hir_match_arm_link_a",
        "hir_match_arm_link_b",
        "hir_match_arm_rank_a",
        "hir_match_arm_rank_b",
        "hir_match_arm_previous",
        "hir_match_payload_owner_a",
        "hir_match_payload_owner_b",
        "hir_match_payload_link_a",
        "hir_match_payload_link_b",
        "hir_match_payload_rank_a",
        "hir_match_payload_rank_b",
        "hir_match_pattern_parent",
        "hir_match_pattern_parent_b",
        "hir_match_payload_owner_arm",
        "hir_match_payload_match_node",
        "hir_match_payload_ordinal",
        "hir_match_rank_flag",
        "hir_match_rank_local_prefix",
        "hir_match_rank_node",
        "hir_match_arm_family_flag",
        "hir_match_arm_raw_to_row",
        "hir_match_compact_payload_start",
        "hir_match_compact_payload_count",
        "hir_match_payload_family_flag",
        "hir_match_pattern_payload_count",
        "hir_struct_field_parent_struct",
        "hir_struct_field_ordinal",
        "hir_struct_field_type_node",
        "hir_struct_decl_field_start",
        "hir_struct_decl_field_count",
        "hir_struct_lit_head_node",
        "hir_struct_lit_field_start",
        "hir_struct_lit_field_count",
        "hir_struct_lit_field_parent_lit",
        "hir_struct_lit_field_value_node",
        "hir_struct_field_owner_a",
        "hir_struct_field_owner_b",
        "hir_struct_field_link_a",
        "hir_struct_field_link_b",
        "hir_struct_field_rank_a",
        "hir_struct_field_rank_b",
        "hir_struct_lit_field_owner_a",
        "hir_struct_lit_field_owner_b",
        "hir_struct_lit_field_link_a",
        "hir_struct_lit_field_link_b",
        "hir_struct_lit_field_rank_a",
        "hir_struct_lit_field_rank_b",
        "hir_struct_lit_field_previous",
        "hir_struct_rank_flag",
        "hir_struct_rank_local_prefix",
        "hir_struct_rank_node",
        "hir_field_family_flag",
        "hir_stmt_context_link_a",
        "hir_stmt_context_link_b",
        "hir_contextual_stmt_value_a",
        "hir_contextual_stmt_value_b",
        "hir_nearest_stmt_value_a",
        "hir_nearest_stmt_value_b",
        "hir_nearest_block_value_a",
        "hir_nearest_block_value_b",
        "hir_nearest_enclosing_control_value_a",
        "hir_nearest_enclosing_control_value_b",
        "hir_nearest_loop_value_a",
        "hir_nearest_loop_value_b",
        "hir_nearest_fn_value_a",
        "hir_nearest_fn_value_b",
        "hir_nearest_array_element_value_a",
        "hir_nearest_array_element_value_b",
        "hir_canonical_nearest_loop",
        "hir_canonical_nearest_block",
        "hir_canonical_nearest_control",
        "hir_canonical_nearest_fn",
        "hir_canonical_context_stmt",
        "hir_canonical_const_type",
        "hir_canonical_const_value",
        "hir_canonical_fn_return_type",
        "hir_canonical_scope_end",
        "hir_canonical_type_alias_target",
        "hir_canonical_type_root_owner",
        "hir_canonical_semantic_dense_node",
        "hir_canonical_expr_parent_encoded",
        "hir_canonical_expr_parent",
        "hir_canonical_expr_root",
        "hir_canonical_expr_root_scratch",
        "hir_param_family_flag",
        "hir_type_arg_family_flag",
        "hir_generic_param_family_flag",
        "hir_method_family_flag",
        "hir_path_family_flag",
        "hir_variant_parent_enum",
        "hir_variant_ordinal",
        "hir_variant_payload_start",
        "hir_variant_payload_count",
        "hir_variant_payload_node",
        "hir_variant_owner_a",
        "hir_variant_owner_b",
        "hir_variant_link_a",
        "hir_variant_link_b",
        "hir_variant_rank_a",
        "hir_variant_rank_b",
        "hir_variant_payload_owner_a",
        "hir_variant_payload_owner_b",
        "hir_variant_payload_link_a",
        "hir_variant_payload_link_b",
        "hir_variant_payload_rank_a",
        "hir_variant_payload_rank_b",
        "hir_enum_rank_flag",
        "hir_enum_rank_local_prefix",
        "hir_enum_rank_node",
        "hir_list_rank_flag",
        "hir_list_rank_local_prefix",
        "hir_list_rank_node",
        "hir_item_kind",
        "hir_path_root_owner",
        "hir_path_segment_owner_a",
        "hir_path_segment_owner_b",
        "hir_path_segment_link_a",
        "hir_path_segment_link_b",
        "hir_path_segment_rank_a",
        "hir_path_segment_rank_b",
        "hir_path_segment_count",
        "hir_type_alias_owner_link_a",
        "hir_type_alias_owner_link_b",
        "hir_type_alias_owner_value_a",
        "hir_type_alias_owner_value_b",
        "hir_fn_signature_owner_link_a",
        "hir_fn_signature_owner_link_b",
        "hir_fn_signature_return_owner_a",
        "hir_fn_signature_return_owner_b",
        "hir_fn_signature_function_owner_a",
        "hir_fn_signature_function_owner_b",
        "hir_binary_span_link_a",
        "hir_binary_span_link_b",
        "hir_binary_span_start_a",
        "hir_binary_span_start_b",
        "hir_expr_int_value",
        "hir_expr_float_bits",
        "hir_expr_string_start",
        "hir_expr_string_len",
        "hir_string_data_offset",
        "hir_string_decoded_len",
        "hir_string_node",
        "hir_semantic_parent_link_a",
        "hir_semantic_parent_link_b",
        "hir_semantic_parent_value_a",
        "hir_semantic_parent_value_b",
        "hir_variant_family_flag",
        "hir_variant_raw_to_row",
        "hir_variant_compact_payload_start",
        "hir_variant_compact_payload_count",
        "hir_variant_payload_family_flag",
    ] {
        let bytes = if matches!(name, "hir_variant_raw_to_row" | "hir_match_arm_raw_to_row") {
            canonical_rows * 4
        } else if matches!(name, "hir_variant_parent_enum" | "hir_variant_ordinal") {
            if capacity.parser_feature_flags
                & (crate::lexer::features::PARSER_FEATURE_ENUMS
                    | crate::lexer::features::PARSER_FEATURE_MATCHES)
                == 0
            {
                4
            } else {
                tree_rows * 4
            }
        } else if matches!(
            name,
            "hir_variant_payload_start" | "hir_variant_payload_count"
        ) {
            if capacity.retain_debug_hir_buffers
                && capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0
            {
                tree_rows * 4
            } else {
                4
            }
        } else if name == "hir_variant_payload_node" {
            if capacity.retain_debug_hir_buffers
                && capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_ENUMS != 0
            {
                tree_rows * 16
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_match_scrutinee_node"
                | "hir_match_arm_pattern_node"
                | "hir_match_arm_result_node"
                | "hir_match_pattern_owner_arm"
                | "hir_match_payload_owner_arm"
                | "hir_match_payload_match_node"
                | "hir_match_payload_ordinal"
        ) {
            if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0 {
                tree_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_match_arm_start"
                | "hir_match_arm_count"
                | "hir_match_arm_next"
                | "hir_match_arm_payload_start"
                | "hir_match_arm_payload_count"
        ) {
            if capacity.retain_debug_hir_buffers
                && capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES
                    != 0
            {
                tree_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_struct_field_parent_struct"
                | "hir_struct_field_ordinal"
                | "hir_struct_field_type_node"
                | "hir_struct_lit_head_node"
        ) {
            if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS != 0 {
                tree_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_struct_decl_field_start"
                | "hir_struct_decl_field_count"
                | "hir_struct_lit_field_start"
                | "hir_struct_lit_field_count"
        ) {
            if capacity.retain_debug_hir_buffers
                && capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS
                    != 0
            {
                tree_rows * 4
            } else {
                4
            }
        } else if matches!(
            name,
            "hir_struct_lit_field_parent_lit" | "hir_struct_lit_field_value_node"
        ) {
            if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRUCTS == 0 {
                4
            } else if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                canonical_rows * 4
            }
        } else if matches!(
            name,
            "hir_expr_int_value"
                | "hir_expr_float_bits"
                | "hir_expr_string_start"
                | "hir_expr_string_len"
        ) {
            if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                canonical_rows * 4
            }
        } else if matches!(name, "hir_string_data_offset" | "hir_string_decoded_len") {
            if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRING_EXPRS
                == 0
            {
                4
            } else if capacity.retain_debug_hir_buffers {
                tree_rows * 4
            } else {
                canonical_rows * 4
            }
        } else if name == "hir_string_node" {
            if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_STRING_EXPRS
                == 0
            {
                4
            } else {
                tree_rows * 4
            }
        } else if canonical_family_flag(name) {
            canonical_rows * 4
        } else if name == "hir_item_kind" && !capacity.retain_debug_hir_buffers {
            canonical_rows * 4
        } else if !capacity.retain_debug_hir_buffers
            && matches!(
                name,
                "hir_array_lit_first_element"
                    | "hir_array_lit_element_count"
                    | "hir_array_element_next"
            )
        {
            4
        } else {
            tree_rows * 4
        };
        if retained_hir_output(name) {
            output(graph, name, ResourceDomain::HirNodes, bytes)?;
        } else if graph_owned_hir_workspace(name) {
            if capacity.retain_debug_hir_buffers {
                output(graph, name, ResourceDomain::HirNodes, bytes)?;
            } else {
                workspace(graph, name, ResourceDomain::HirNodes, bytes)?;
            }
        } else {
            external(graph, name, ResourceDomain::HirNodes, bytes)?;
        }
    }
    graph.add_resource_alias(
        "hir_struct_lit_field_next",
        graph
            .resource_id("prev_sibling")
            .expect("raw previous-sibling graph resource"),
    )?;
    for name in [
        "hir_list_rank_block_sum",
        "hir_list_rank_block_prefix_a",
        "hir_list_rank_block_prefix_b",
        "hir_enum_rank_block_sum",
        "hir_enum_rank_block_prefix_a",
        "hir_enum_rank_block_prefix_b",
        "hir_match_rank_block_sum",
        "hir_match_rank_block_prefix_a",
        "hir_match_rank_block_prefix_b",
        "hir_struct_rank_block_sum",
        "hir_struct_rank_block_prefix_a",
        "hir_struct_rank_block_prefix_b",
    ] {
        if graph_owned_hir_workspace(name) {
            workspace(graph, name, ResourceDomain::HirNodes, tree_blocks * 4)?;
        } else {
            external(graph, name, ResourceDomain::HirNodes, tree_blocks * 4)?;
        }
    }
    workspace(graph, "hir_list_rank_count", ResourceDomain::HirNodes, 4)?;
    workspace(graph, "hir_enum_rank_count", ResourceDomain::HirNodes, 4)?;
    output(graph, "hir_string_count", ResourceDomain::HirNodes, 4)?;
    output(graph, "hir_string_pool_len", ResourceDomain::HirNodes, 4)?;
    output(
        graph,
        "hir_variant_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(
        graph,
        "hir_call_arg_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(
        graph,
        "hir_array_element_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    workspace(graph, "hir_match_rank_count", ResourceDomain::HirNodes, 4)?;
    output(
        graph,
        "hir_match_arm_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(
        graph,
        "hir_match_payload_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    workspace(graph, "hir_struct_rank_count", ResourceDomain::HirNodes, 4)?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES == 0 {
        for name in MATCH_WORKSPACE_RESOURCES
            .iter()
            .copied()
            .chain(MATCH_RAW_RESOURCES.iter().copied())
            .chain(["hir_match_arm_family_flag", "hir_match_payload_family_flag"])
        {
            graph.mark_zero_initialized(
                graph
                    .resource_id(name)
                    .expect("optional match graph resource"),
            )?;
        }
    }
    output(graph, "hir_field_table_count", ResourceDomain::HirNodes, 4)?;
    output(graph, "hir_param_table_count", ResourceDomain::HirNodes, 4)?;
    output(
        graph,
        "hir_type_arg_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(
        graph,
        "hir_generic_param_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(graph, "hir_method_table_count", ResourceDomain::HirNodes, 4)?;
    output(
        graph,
        "hir_predicate_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(graph, "hir_path_table_count", ResourceDomain::HirNodes, 4)?;
    output(
        graph,
        "hir_path_segment_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    if capacity.retain_debug_hir_buffers {
        output(
            graph,
            "hir_canonical_expr_forest_status",
            ResourceDomain::HirNodes,
            4,
        )?;
    } else {
        workspace(
            graph,
            "hir_canonical_expr_forest_status",
            ResourceDomain::HirNodes,
            4,
        )?;
    }
    output(
        graph,
        "hir_variant_payload_table_count",
        ResourceDomain::HirNodes,
        4,
    )?;
    output(
        graph,
        "hir_string_data_words",
        ResourceDomain::Bytes,
        u64::from(capacity.source_capacity.max(1).div_ceil(4)) * 4,
    )?;
    for name in ["hir_canonical_stmt_record", "hir_canonical_expr_record"] {
        let bytes = u64::from(capacity.token_capacity.max(1)) * 16;
        if capacity.retain_debug_hir_buffers {
            output(graph, name, ResourceDomain::HirNodes, bytes)?;
        } else {
            workspace(graph, name, ResourceDomain::HirNodes, bytes)?;
        }
    }
    for name in [
        "hir_variant_rows",
        "hir_variant_payload_rows",
        "hir_call_args",
        "hir_array_element_rows",
        "hir_match_arm_rows",
        "hir_match_payload_rows",
        "hir_field_rows",
    ] {
        output(
            graph,
            name,
            ResourceDomain::HirNodes,
            u64::from(capacity.token_capacity.max(1)) * 16,
        )?;
    }
    for name in [
        "hir_param_rows",
        "hir_type_arg_rows",
        "hir_generic_param_rows",
        "hir_path_rows",
        "hir_path_segment_rows",
        "hir_method_core_rows",
        "hir_method_signature_rows",
        "hir_predicate_rows",
        "hir_canonical_string_rows",
    ] {
        output(
            graph,
            name,
            ResourceDomain::HirNodes,
            u64::from(capacity.token_capacity.max(1)) * 16,
        )?;
    }
    for name in ["hir_core", "hir_links", "hir_payload"] {
        output(
            graph,
            name,
            ResourceDomain::HirNodes,
            u64::from(capacity.token_capacity.max(1)) * 16,
        )?;
    }
    output(
        graph,
        "hir_canonical_semantic_facts",
        ResourceDomain::HirNodes,
        u64::from(capacity.token_capacity.max(1)) * 28,
    )?;
    output(
        graph,
        "hir_generic_param_ranges",
        ResourceDomain::HirNodes,
        u64::from(capacity.token_capacity.max(1)) * 8,
    )?;
    workspace_indirect(graph, "hir_list_rank_dispatch_args", 12)?;
    workspace_indirect(graph, "hir_enum_rank_dispatch_args", 12)?;
    let match_dispatch = workspace_indirect(graph, "hir_match_rank_dispatch_args", 12)?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES == 0 {
        graph.mark_zero_initialized(match_dispatch)?;
    }
    workspace_indirect(graph, "hir_struct_rank_dispatch_args", 12)?;
    Ok(())
}

#[derive(Clone, Copy)]
struct PingPongBinding {
    input_binding: &'static str,
    output_binding: &'static str,
    a: &'static str,
    b: &'static str,
}

#[allow(clippy::too_many_arguments)]
fn register_ping_pong_walk(
    graph: &mut CompilerGraphBuilder,
    data: &crate::gpu::passes_core::PassData,
    a_to_b: &'static str,
    b_to_a: &'static str,
    a_to_b_final: &'static str,
    finalize: &'static str,
    dispatch_args: &'static str,
    indirect_dispatch: bool,
    steps: u32,
    common: &[(&'static str, &'static str, Option<AccessMode>)],
    bindings: &[PingPongBinding],
) -> Result<(), String> {
    let aliases = |read_a: bool| {
        let mut aliases = common.to_vec();
        for binding in bindings {
            let (input, output) = if read_a {
                (binding.a, binding.b)
            } else {
                (binding.b, binding.a)
            };
            aliases.push((binding.input_binding, input, None));
            aliases.push((binding.output_binding, output, Some(AccessMode::Write)));
        }
        aliases
    };

    if steps >= 2 {
        reflected(
            graph,
            a_to_b,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            data,
            &aliases(true),
        )?;
        if indirect_dispatch {
            indirect(graph, a_to_b, dispatch_args)?;
        }
        reflected(
            graph,
            b_to_a,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            data,
            &aliases(false),
        )?;
        if indirect_dispatch {
            indirect(graph, b_to_a, dispatch_args)?;
        }
        graph.repeat_pass_range(steps / 2, a_to_b, b_to_a)?;
    }
    if steps % 2 == 1 {
        reflected(
            graph,
            a_to_b_final,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            data,
            &aliases(true),
        )?;
        if indirect_dispatch {
            indirect(graph, a_to_b_final, dispatch_args)?;
        }
        let mut accesses = Vec::with_capacity(bindings.len() * 2);
        for binding in bindings {
            accesses.push(PassAccess::read(
                binding.b,
                graph.resource_id(binding.b).unwrap(),
            ));
            accesses.push(PassAccess::write(
                binding.a,
                graph.resource_id(binding.a).unwrap(),
            ));
        }
        graph.add_pass(PassDesc {
            name: finalize,
            phase: CompilerPhase::Hir,
            dispatch_domain: ResourceDomain::HirNodes,
            accesses,
        })?;
    }
    Ok(())
}

pub(super) fn register_post_identity_schedule(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    register_type_argument_ranking(graph, capacity, passes)
}

fn register_list_rank_compaction(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
    invocation: ListRankInvocation,
    owner_a: &'static str,
    link_a: &'static str,
) -> Result<(), String> {
    reflected(
        graph,
        invocation.local_label(),
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        passes.hir_list_rank_prefix_local.graph_pass(),
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_list_owner_a", owner_a, None),
            ("hir_list_link_a", link_a, None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        invocation.local_label(),
        &[
            "hir_list_rank_flag",
            "hir_list_rank_local_prefix",
            "hir_list_rank_block_sum",
        ],
    )?;

    register_list_rank_scan(graph, capacity, passes, invocation)?;

    reflected(
        graph,
        invocation.scatter_label(),
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        passes.hir_list_rank_compact_scatter.graph_pass(),
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_list_rank_block_prefix",
                "hir_list_rank_block_prefix_a",
                None,
            ),
            (
                "hir_list_rank_dispatch_args",
                "hir_list_rank_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        invocation.scatter_label(),
        &[
            "hir_list_rank_node",
            "hir_list_rank_count",
            "hir_list_rank_dispatch_args",
        ],
    )
}

fn register_list_rank_scan(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
    invocation: ListRankInvocation,
) -> Result<(), String> {
    let levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (up_name, down_name) = invocation.scan_labels();
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let scan_aliases = [
        ("block_sum", "hir_list_rank_block_sum", None),
        ("block_prefix", "hir_list_rank_block_prefix_a", None),
        ("block_hierarchy", "hir_list_rank_block_prefix_b", None),
    ];
    reflected(
        graph,
        up_name,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &scan_aliases,
    )?;
    // Level zero reads only `block_sum`; it establishes both scan outputs
    // before subsequent hierarchy levels read them.
    graph.mark_pass_bindings_first_invocation_skips_read(
        up_name,
        &["block_prefix", "block_hierarchy"],
    )?;
    graph.repeat_pass_range(levels.len() as u32, up_name, up_name)?;
    if levels.len() > 1 {
        reflected(
            graph,
            down_name,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &scan_aliases,
        )?;
        graph.repeat_pass_range((levels.len() - 1) as u32, down_name, down_name)?;
    }

    Ok(())
}

fn register_canonical_compaction_prefix(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
    construct: crate::parser::passes::CanonicalConstruct,
    family_flag: &'static str,
) -> Result<(), String> {
    reflected(
        graph,
        construct.label(),
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &passes.exclusive_u32_local_scan,
        &[
            ("input", family_flag, None),
            (
                "output_prefix",
                "hir_semantic_local_prefix",
                Some(AccessMode::Write),
            ),
            (
                "block_sum",
                "hir_semantic_block_sum",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    let levels = hierarchical_scan_levels(capacity.token_capacity.max(1).div_ceil(256));
    let (up_name, down_name) = construct.scan_labels();
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let aliases = [
        ("block_sum", "hir_semantic_block_sum", None),
        ("block_prefix", "hir_semantic_block_prefix_a", None),
        ("block_hierarchy", "hir_semantic_block_prefix_b", None),
    ];
    reflected(
        graph,
        up_name,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &aliases,
    )?;
    graph.repeat_pass_range(levels.len() as u32, up_name, up_name)?;
    if levels.len() > 1 {
        reflected(
            graph,
            down_name,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &aliases,
        )?;
        graph.repeat_pass_range((levels.len() - 1) as u32, down_name, down_name)?;
    }
    Ok(())
}

#[allow(clippy::too_many_arguments)]
fn register_list_rank_propagation(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
    invocation: ListRankInvocation,
    owner_a: &'static str,
    owner_b: &'static str,
    link_a: &'static str,
    link_b: &'static str,
    rank_a: &'static str,
    rank_b: &'static str,
) -> Result<(), String> {
    let (a_to_b, b_to_a) = invocation.step_labels();
    let steps = crate::parser::passes::hir::list::rank::step::list_rank_step_capacity(
        capacity.tree_capacity,
    );
    register_ping_pong_walk(
        graph,
        passes.hir_list_rank_step.graph_pass(),
        a_to_b,
        b_to_a,
        a_to_b,
        a_to_b,
        "hir_list_rank_dispatch_args",
        true,
        steps,
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "list_owner_in",
                output_binding: "list_owner_out",
                a: owner_a,
                b: owner_b,
            },
            PingPongBinding {
                input_binding: "list_link_in",
                output_binding: "list_link_out",
                a: link_a,
                b: link_b,
            },
            PingPongBinding {
                input_binding: "list_rank_in",
                output_binding: "list_rank_out",
                a: rank_a,
                b: rank_b,
            },
        ],
    )
}

fn register_type_argument_ranking(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    let invocation = ListRankInvocation::TypeArguments;
    static_pass(
        graph,
        &passes.hir_type_arg_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_type_arg_links",
        &[
            "hir_type_arg_owner_a",
            "hir_type_arg_link_a",
            "hir_type_arg_rank_a",
            "hir_type_arg_previous",
        ],
    )?;
    indirect(graph, "hir_type_arg_links", "tree_active_dispatch_args")?;

    for (name, resource) in [
        (TYPE_ARG_OWNER_B_CLEAR, "hir_type_arg_owner_b"),
        (TYPE_ARG_LINK_B_CLEAR, "hir_type_arg_link_b"),
        (TYPE_ARG_RANK_B_CLEAR, "hir_type_arg_rank_b"),
    ] {
        clear(graph, name, CompilerPhase::Hir, &[(resource, resource)])?;
    }
    register_list_rank_compaction(
        graph,
        capacity,
        passes,
        invocation,
        "hir_type_arg_owner_a",
        "hir_type_arg_link_a",
    )?;
    register_list_rank_propagation(
        graph,
        capacity,
        passes,
        invocation,
        "hir_type_arg_owner_a",
        "hir_type_arg_owner_b",
        "hir_type_arg_link_a",
        "hir_type_arg_link_b",
        "hir_type_arg_rank_a",
        "hir_type_arg_rank_b",
    )?;

    static_pass(
        graph,
        &passes.hir_type_arg_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_type_arg_scatter", "tree_active_dispatch_args")?;
    register_type_root_owner(graph, capacity, passes)?;
    Ok(())
}

fn register_type_root_owner(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::hir::types::root::step::{A_TO_B, A_TO_B_FINAL, B_TO_A, FINALIZE};

    static_pass(
        graph,
        &passes.hir_type_root_owner_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_type_arg_owner", "hir_type_arg_owner_a", None),
            ("hir_type_root_link_a", "hir_type_arg_link_a", None),
            ("hir_type_root_owner_a", "hir_type_root_owner", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_type_root_owner_init",
        &["hir_type_root_link_a", "hir_type_root_owner_a"],
    )?;
    indirect(
        graph,
        "hir_type_root_owner_init",
        "tree_active_dispatch_args",
    )?;

    let steps = crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity);
    register_ping_pong_walk(
        graph,
        passes.hir_type_root_owner_step.graph_pass(),
        A_TO_B,
        B_TO_A,
        A_TO_B_FINAL,
        FINALIZE,
        "tree_active_dispatch_args",
        true,
        steps,
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "hir_type_root_link_in",
                output_binding: "hir_type_root_link_out",
                a: "hir_type_arg_link_a",
                b: "hir_type_arg_link_b",
            },
            PingPongBinding {
                input_binding: "hir_type_root_owner_in",
                output_binding: "hir_type_root_owner_out",
                a: "hir_type_root_owner",
                b: "hir_type_arg_owner_b",
            },
        ],
    )?;
    register_enum_ranking(graph, capacity, passes)?;
    Ok(())
}

fn register_enum_ranking(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::hir::enums::variant::rank_step::{
        A_TO_B,
        A_TO_B_FINAL,
        B_TO_A,
        FINALIZE,
    };

    static_pass(
        graph,
        &passes.hir_enum_variant_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_enum_variant_links",
        &[
            "hir_variant_owner_a",
            "hir_variant_owner_b",
            "hir_variant_link_a",
            "hir_variant_link_b",
            "hir_variant_rank_a",
            "hir_variant_rank_b",
            "hir_variant_payload_owner_a",
            "hir_variant_payload_owner_b",
            "hir_variant_payload_link_a",
            "hir_variant_payload_link_b",
            "hir_variant_payload_rank_a",
            "hir_variant_payload_rank_b",
            "hir_variant_parent_enum",
            "hir_variant_ordinal",
            "hir_variant_payload_start",
            "hir_variant_payload_count",
            "hir_variant_payload_node",
        ],
    )?;
    indirect(graph, "hir_enum_variant_links", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_enum_rank_prefix_local,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_enum_rank_prefix_00_local",
        &[
            "hir_enum_rank_flag",
            "hir_enum_rank_local_prefix",
            "hir_enum_rank_block_sum",
        ],
    )?;

    let levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let scan_aliases = [
        ("block_sum", "hir_enum_rank_block_sum", None),
        ("block_prefix", "hir_enum_rank_block_prefix_a", None),
        ("block_hierarchy", "hir_enum_rank_block_prefix_b", None),
    ];
    reflected(
        graph,
        super::HIR_ENUM_RANK_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &scan_aliases,
    )?;
    graph.mark_pass_bindings_first_invocation_skips_read(
        super::HIR_ENUM_RANK_SCAN_UP,
        &["block_prefix", "block_hierarchy"],
    )?;
    graph.repeat_pass_range(
        levels.len() as u32,
        super::HIR_ENUM_RANK_SCAN_UP,
        super::HIR_ENUM_RANK_SCAN_UP,
    )?;
    if levels.len() > 1 {
        reflected(
            graph,
            super::HIR_ENUM_RANK_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &scan_aliases,
        )?;
        graph.repeat_pass_range(
            (levels.len() - 1) as u32,
            super::HIR_ENUM_RANK_SCAN_DOWN,
            super::HIR_ENUM_RANK_SCAN_DOWN,
        )?;
    }
    static_pass(
        graph,
        &passes.hir_enum_rank_compact_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_enum_rank_block_prefix",
                "hir_enum_rank_block_prefix_a",
                None,
            ),
            (
                "hir_enum_rank_dispatch_args",
                "hir_enum_rank_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_enum_rank_compact_scatter",
        &[
            "hir_enum_rank_node",
            "hir_enum_rank_count",
            "hir_enum_rank_dispatch_args",
        ],
    )?;

    let steps = crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity);
    register_ping_pong_walk(
        graph,
        passes.hir_enum_variant_rank_step.graph_pass(),
        A_TO_B,
        B_TO_A,
        A_TO_B_FINAL,
        FINALIZE,
        "hir_enum_rank_dispatch_args",
        true,
        steps,
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "hir_variant_owner_in",
                output_binding: "hir_variant_owner_out",
                a: "hir_variant_owner_a",
                b: "hir_variant_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_variant_link_in",
                output_binding: "hir_variant_link_out",
                a: "hir_variant_link_a",
                b: "hir_variant_link_b",
            },
            PingPongBinding {
                input_binding: "hir_variant_rank_in",
                output_binding: "hir_variant_rank_out",
                a: "hir_variant_rank_a",
                b: "hir_variant_rank_b",
            },
            PingPongBinding {
                input_binding: "hir_variant_payload_owner_in",
                output_binding: "hir_variant_payload_owner_out",
                a: "hir_variant_payload_owner_a",
                b: "hir_variant_payload_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_variant_payload_link_in",
                output_binding: "hir_variant_payload_link_out",
                a: "hir_variant_payload_link_a",
                b: "hir_variant_payload_link_b",
            },
            PingPongBinding {
                input_binding: "hir_variant_payload_rank_in",
                output_binding: "hir_variant_payload_rank_out",
                a: "hir_variant_payload_rank_a",
                b: "hir_variant_payload_rank_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_enum_variant_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(
        graph,
        "hir_enum_variant_scatter",
        "tree_active_dispatch_args",
    )?;
    register_item_paths_and_type_aliases(graph, capacity, passes)?;
    Ok(())
}

fn register_item_paths_and_type_aliases(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    clear(
        graph,
        ITEM_KIND_CLEAR,
        CompilerPhase::Hir,
        &[("hir_item_kind", "hir_item_kind")],
    )?;
    static_pass(
        graph,
        &passes.hir_item_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("raw_to_hir", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    indirect(graph, "hir_item_fields", "hir_semantic_dispatch_args")?;

    clear(
        graph,
        PATH_ROOT_OWNER_CLEAR,
        CompilerPhase::Hir,
        &[("hir_path_root_owner", "hir_path_root_owner")],
    )?;
    clear(
        graph,
        PATH_SEGMENT_COUNT_CLEAR,
        CompilerPhase::Hir,
        &[("hir_path_segment_count", "hir_path_segment_count")],
    )?;
    static_pass(
        graph,
        &passes.hir_path_segment_root,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_path_segment_root",
        &["hir_path_segment_owner_a", "hir_path_segment_rank_a"],
    )?;
    indirect(graph, "hir_path_segment_root", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_path_segment_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize("hir_path_segment_links", &["hir_path_segment_link_a"])?;
    indirect(graph, "hir_path_segment_links", "tree_active_dispatch_args")?;

    use crate::parser::passes::hir::path::segment::step::{
        A_TO_B as PATH_A_TO_B,
        A_TO_B_FINAL as PATH_A_TO_B_FINAL,
        B_TO_A as PATH_B_TO_A,
        FINALIZE as PATH_FINALIZE,
    };
    register_ping_pong_walk(
        graph,
        passes.hir_path_segment_step.graph_pass(),
        PATH_A_TO_B,
        PATH_B_TO_A,
        PATH_A_TO_B_FINAL,
        PATH_FINALIZE,
        "tree_active_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "hir_path_segment_owner_in",
                output_binding: "hir_path_segment_owner_out",
                a: "hir_path_segment_owner_a",
                b: "hir_path_segment_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_path_segment_link_in",
                output_binding: "hir_path_segment_link_out",
                a: "hir_path_segment_link_a",
                b: "hir_path_segment_link_b",
            },
            PingPongBinding {
                input_binding: "hir_path_segment_rank_in",
                output_binding: "hir_path_segment_rank_out",
                a: "hir_path_segment_rank_a",
                b: "hir_path_segment_rank_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_path_segment_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(
        graph,
        "hir_path_segment_scatter",
        "tree_active_dispatch_args",
    )?;

    static_pass(
        graph,
        &passes.hir_type_alias_owner_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("raw_to_hir", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_type_alias_owner_init",
        &[
            "hir_type_alias_owner_link_a",
            "hir_type_alias_owner_value_a",
        ],
    )?;
    indirect(
        graph,
        "hir_type_alias_owner_init",
        "hir_semantic_dispatch_args",
    )?;

    use crate::parser::passes::hir::types::alias::owner::step::{
        A_TO_B as ALIAS_A_TO_B,
        A_TO_B_FINAL as ALIAS_A_TO_B_FINAL,
        B_TO_A as ALIAS_B_TO_A,
        FINALIZE as ALIAS_FINALIZE,
    };
    register_ping_pong_walk(
        graph,
        passes.hir_type_alias_owner_step.graph_pass(),
        ALIAS_A_TO_B,
        ALIAS_B_TO_A,
        ALIAS_A_TO_B_FINAL,
        ALIAS_FINALIZE,
        "hir_semantic_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_semantic_count", "hir_semantic_count", None),
        ],
        &[
            PingPongBinding {
                input_binding: "hir_type_alias_owner_link_in",
                output_binding: "hir_type_alias_owner_link_out",
                a: "hir_type_alias_owner_link_a",
                b: "hir_type_alias_owner_link_b",
            },
            PingPongBinding {
                input_binding: "hir_type_alias_owner_value_in",
                output_binding: "hir_type_alias_owner_value_out",
                a: "hir_type_alias_owner_value_a",
                b: "hir_type_alias_owner_value_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_type_alias_target,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_type_alias_owner_value",
                "hir_type_alias_owner_value_a",
                None,
            ),
            ("raw_to_hir", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    indirect(graph, "hir_type_alias_target", "hir_semantic_dispatch_args")?;
    register_function_signatures(graph, capacity, passes)?;
    Ok(())
}

fn register_function_signatures(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::hir::semantic::parent::step::FN_SIGNATURE_OWNER;

    static_pass(
        graph,
        &passes.hir_fn_signature_owner_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_fn_signature_owner_init",
        &[
            "hir_fn_signature_owner_link_a",
            "hir_fn_signature_return_owner_a",
            "hir_fn_signature_function_owner_a",
        ],
    )?;
    indirect(
        graph,
        "hir_fn_signature_owner_init",
        "tree_active_dispatch_args",
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_tree_relations.graph_pair_pass(),
        FN_SIGNATURE_OWNER.a_to_b,
        FN_SIGNATURE_OWNER.b_to_a,
        FN_SIGNATURE_OWNER.a_to_b_final,
        FN_SIGNATURE_OWNER.finalize,
        "tree_active_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "relation_link_in",
                output_binding: "relation_link_out",
                a: "hir_fn_signature_owner_link_a",
                b: "hir_fn_signature_owner_link_b",
            },
            PingPongBinding {
                input_binding: "first_value_in",
                output_binding: "first_value_out",
                a: "hir_fn_signature_return_owner_a",
                b: "hir_fn_signature_return_owner_b",
            },
            PingPongBinding {
                input_binding: "second_value_in",
                output_binding: "second_value_out",
                a: "hir_fn_signature_function_owner_a",
                b: "hir_fn_signature_function_owner_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_fn_return_type,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_fn_signature_return_owner",
                "hir_fn_signature_return_owner_a",
                None,
            ),
            (
                "hir_fn_signature_function_owner",
                "hir_fn_signature_function_owner_a",
                None,
            ),
            ("raw_to_hir", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    indirect(graph, "hir_fn_return_type", "hir_semantic_dispatch_args")?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_PREDICATES != 0 {
        static_pass(
            graph,
            &passes.hir_method_signature_status,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            &[
                ("tree_count_status", "partial_parse_status", None),
                (
                    "hir_fn_signature_function_owner",
                    "hir_fn_signature_function_owner_a",
                    None,
                ),
            ],
        )?;
        indirect(
            graph,
            "hir_method_signature_status",
            "tree_active_dispatch_args",
        )?;
    }
    register_parameters(graph, capacity, passes)?;
    Ok(())
}

fn register_parameters(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    static_pass(
        graph,
        &passes.hir_param_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_param_links",
        &["hir_param_owner_a", "hir_param_link_a"],
    )?;
    indirect(graph, "hir_param_links", "tree_active_dispatch_args")?;
    register_list_rank_compaction(
        graph,
        capacity,
        passes,
        ListRankInvocation::Parameters,
        "hir_param_owner_a",
        "hir_param_link_a",
    )?;
    static_pass(
        graph,
        &passes.hir_param_id_clear,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[],
    )?;
    graph.mark_pass_bindings_initialize("hir_param_id_clear", &["hir_param_rank_b"])?;
    indirect(graph, "hir_param_id_clear", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_param_id_base,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_param_id_base", "hir_list_rank_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_param_id_apply,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize("hir_param_id_apply", &["hir_param_rank_a"])?;
    indirect(graph, "hir_param_id_apply", "hir_list_rank_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_param_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_param_fields", "hir_semantic_dispatch_args")?;
    register_expression_and_statement_fields(graph, capacity, passes)?;
    Ok(())
}

fn register_expression_and_statement_fields(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::hir::expr::result_root_step::{
        A_TO_B as RESULT_A_TO_B,
        A_TO_B_FINAL as RESULT_A_TO_B_FINAL,
        B_TO_A as RESULT_B_TO_A,
        FINALIZE as RESULT_FINALIZE,
    };
    register_ping_pong_walk(
        graph,
        passes.hir_expr_result_root_step.graph_pass(),
        RESULT_A_TO_B,
        RESULT_B_TO_A,
        RESULT_A_TO_B_FINAL,
        RESULT_FINALIZE,
        "tree_active_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[("tree_count_status", "partial_parse_status", None)],
        &[PingPongBinding {
            input_binding: "hir_expr_result_root_in",
            output_binding: "hir_expr_result_root_out",
            a: "hir_expr_result_root_node",
            b: "hir_expr_result_root_scratch_node",
        }],
    )?;
    static_pass(
        graph,
        &passes.hir_binary_spans,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_binary_spans",
        &["hir_binary_span_link_a", "hir_binary_span_start_a"],
    )?;
    indirect(graph, "hir_binary_spans", "hir_semantic_dispatch_args")?;

    use crate::parser::passes::hir::binary::span::step::{
        A_TO_B as BINARY_A_TO_B,
        A_TO_B_FINAL as BINARY_A_TO_B_FINAL,
        B_TO_A as BINARY_B_TO_A,
        FINALIZE as BINARY_FINALIZE,
    };
    register_ping_pong_walk(
        graph,
        passes.hir_binary_span_step.graph_pass(),
        BINARY_A_TO_B,
        BINARY_B_TO_A,
        BINARY_A_TO_B_FINAL,
        BINARY_FINALIZE,
        "hir_semantic_dispatch_args",
        true,
        crate::parser::passes::hir::binary::span::step::pointer_jump_steps_for_items(
            capacity.tree_capacity,
        ),
        &[("hir_semantic_count", "hir_semantic_count", None)],
        &[
            PingPongBinding {
                input_binding: "hir_binary_span_link_in",
                output_binding: "hir_binary_span_link_out",
                a: "hir_binary_span_link_a",
                b: "hir_binary_span_link_b",
            },
            PingPongBinding {
                input_binding: "hir_binary_span_start_in",
                output_binding: "hir_binary_span_start_out",
                a: "hir_binary_span_start_a",
                b: "hir_binary_span_start_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_binary_span_apply,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_binary_span_apply", "hir_semantic_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_postfix_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_postfix_fields", "hir_semantic_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_member_spans,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_member_spans", "hir_semantic_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_stmt_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("raw_to_hir", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    indirect(graph, "hir_stmt_fields", "hir_semantic_dispatch_args")?;
    register_literals_and_raw_expression_records(graph, capacity, passes)?;
    Ok(())
}

fn register_literals_and_raw_expression_records(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    reflected(
        graph,
        "parser_hir_literal_values",
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        passes.hir_literal_values.graph_pass(),
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "parser_hir_literal_values",
        &[
            "hir_expr_int_value",
            "hir_expr_float_bits",
            "hir_expr_string_start",
            "hir_expr_string_len",
        ],
    )?;
    indirect(
        graph,
        "parser_hir_literal_values",
        "tree_active_dispatch_args",
    )?;

    static_pass(
        graph,
        &passes.hir_string_compact_local,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    register_list_rank_scan(graph, capacity, passes, ListRankInvocation::StringRecords)?;
    static_pass(
        graph,
        &passes.hir_string_compact_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_list_rank_block_prefix",
                "hir_list_rank_block_prefix_a",
                None,
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_string_compact_scatter",
        &[
            "hir_string_node",
            "hir_string_count",
            "hir_list_rank_dispatch_args",
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_string_offset_local,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    register_list_rank_scan(graph, capacity, passes, ListRankInvocation::StringOffsets)?;
    static_pass(
        graph,
        &passes.hir_string_offset_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[(
            "hir_list_rank_block_prefix",
            "hir_list_rank_block_prefix_a",
            None,
        )],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_string_offset_scatter",
        &["hir_string_data_offset", "hir_string_pool_len"],
    )?;
    clear(
        graph,
        STRING_DECODED_LEN_CLEAR,
        CompilerPhase::Hir,
        &[("hir_string_decoded_len", "hir_string_decoded_len")],
    )?;
    clear(
        graph,
        STRING_DATA_WORDS_CLEAR,
        CompilerPhase::Hir,
        &[("hir_string_data_words", "hir_string_data_words")],
    )?;
    reflected(
        graph,
        "parser_hir_string_decode",
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        passes.hir_string_decode.graph_pass(),
        &[],
    )?;
    indirect(
        graph,
        "parser_hir_string_decode",
        "hir_list_rank_dispatch_args",
    )?;

    static_pass(
        graph,
        &passes.hir_call_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_call_fields",
        &[
            "hir_call_callee_node",
            "hir_call_callee_path_node",
            "hir_call_parent_by_callee",
            "hir_call_arg_start",
        ],
    )?;
    indirect(graph, "hir_call_fields", "hir_semantic_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_call_spans,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
        ],
    )?;
    indirect(graph, "hir_call_spans", "hir_semantic_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_range_spans,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_range_spans", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_struct_lit_spans,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(graph, "hir_struct_lit_spans", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_canonical_stmt_compact,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_flag", "hir_semantic_flag", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            ("raw_stmt_record", "hir_stmt_record", None),
            ("raw_expr_record", "hir_expr_record", None),
            ("compact_stmt_record", "hir_canonical_stmt_record", None),
            ("compact_expr_record", "hir_canonical_expr_record", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_stmt_compact",
        &["compact_stmt_record", "compact_expr_record"],
    )?;
    register_canonical_variants(graph, capacity, passes)?;
    Ok(())
}

fn register_canonical_variants(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::{
        CanonicalConstruct,
        hir::semantic::parent::step::{
            CANONICAL_VARIANT_PAYLOAD_OWNER,
            canonical_relation_step_capacity,
        },
    };

    clear(
        graph,
        CANONICAL_VARIANT_CLEAR,
        CompilerPhase::Hir,
        &[
            ("hir_variant_table_count", "hir_variant_table_count"),
            ("hir_variant_family_flag", "hir_variant_family_flag"),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
            ("hir_variant_raw_to_row", "hir_variant_raw_to_row"),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_variant_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("variant_parent_enum", "hir_variant_parent_enum", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_variant_family_flag", None),
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::Variant,
        "hir_variant_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_variant_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_variant_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("variant_parent_enum", "hir_variant_parent_enum", None),
            ("variant_ordinal", "hir_variant_ordinal", None),
            ("raw_to_variant", "hir_variant_raw_to_row", None),
            (
                "variant_payload_start",
                "hir_variant_compact_payload_start",
                None,
            ),
            (
                "variant_payload_count",
                "hir_variant_compact_payload_count",
                None,
            ),
            ("family_count", "hir_variant_table_count", None),
            ("hir_variants", "hir_variant_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;

    clear(
        graph,
        CANONICAL_VARIANT_PAYLOAD_CLEAR,
        CompilerPhase::Hir,
        &[
            (
                "hir_variant_payload_table_count",
                "hir_variant_payload_table_count",
            ),
            (
                "hir_variant_payload_family_flag",
                "hir_variant_payload_family_flag",
            ),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_variant_payload_owner_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_variant_payload_family_flag", None),
            ("owner_link_a", "hir_semantic_parent_link_a", None),
            ("owner_value_a", "hir_semantic_parent_value_a", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_variant_payload_owner_init",
        &["owner_link_a", "owner_value_a"],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_tree_relations.graph_single_pass(),
        CANONICAL_VARIANT_PAYLOAD_OWNER.a_to_b,
        CANONICAL_VARIANT_PAYLOAD_OWNER.b_to_a,
        CANONICAL_VARIANT_PAYLOAD_OWNER.a_to_b_final,
        CANONICAL_VARIANT_PAYLOAD_OWNER.finalize,
        "tree_active_dispatch_args",
        true,
        canonical_relation_step_capacity(capacity.tree_capacity),
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "hir_semantic_parent_link_in",
                output_binding: "hir_semantic_parent_link_out",
                a: "hir_semantic_parent_link_a",
                b: "hir_semantic_parent_link_b",
            },
            PingPongBinding {
                input_binding: "hir_semantic_parent_value_in",
                output_binding: "hir_semantic_parent_value_out",
                a: "hir_semantic_parent_value_a",
                b: "hir_semantic_parent_value_b",
            },
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::VariantPayload,
        "hir_variant_payload_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_variant_payload_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_variant_payload_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("payload_owner_raw", "hir_semantic_parent_value_a", None),
            ("raw_to_variant", "hir_variant_raw_to_row", None),
            (
                "variant_payload_start",
                "hir_variant_compact_payload_start",
                None,
            ),
            (
                "variant_payload_count",
                "hir_variant_compact_payload_count",
                None,
            ),
            ("family_count", "hir_variant_payload_table_count", None),
            ("hir_variant_payloads", "hir_variant_payload_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_variant_payload_ordinal,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            (
                "payload_table_count",
                "hir_variant_payload_table_count",
                None,
            ),
            (
                "variant_payload_start",
                "hir_variant_compact_payload_start",
                None,
            ),
            (
                "variant_payload_count",
                "hir_variant_compact_payload_count",
                None,
            ),
            ("hir_variant_payloads", "hir_variant_payload_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    register_call_arguments(graph, capacity, passes)?;
    Ok(())
}

fn register_call_arguments(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    clear(
        graph,
        CALL_ARG_COUNT_CLEAR,
        CompilerPhase::Hir,
        &[("hir_call_arg_count", "hir_call_arg_count")],
    )?;
    static_pass(
        graph,
        &passes.hir_call_arg_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_call_arg_links",
        &[
            "hir_call_arg_owner_a",
            "hir_call_arg_link_a",
            "hir_call_arg_rank_a",
            "hir_call_arg_owner_b",
            "hir_call_arg_link_b",
            "hir_call_arg_rank_b",
        ],
    )?;
    indirect(graph, "hir_call_arg_links", "tree_active_dispatch_args")?;
    register_list_rank_compaction(
        graph,
        capacity,
        passes,
        ListRankInvocation::CallArguments,
        "hir_call_arg_owner_a",
        "hir_call_arg_link_a",
    )?;
    register_list_rank_propagation(
        graph,
        capacity,
        passes,
        ListRankInvocation::CallArguments,
        "hir_call_arg_owner_a",
        "hir_call_arg_owner_b",
        "hir_call_arg_link_a",
        "hir_call_arg_link_b",
        "hir_call_arg_rank_a",
        "hir_call_arg_rank_b",
    )?;
    static_pass(
        graph,
        &passes.hir_call_arg_ordinal_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    clear(
        graph,
        CANONICAL_CALL_ARGUMENT_CLEAR,
        CompilerPhase::Hir,
        &[("hir_call_arg_table_count", "hir_call_arg_table_count")],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_call_arg_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            ("family_flag", "hir_call_arg_family_flag", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_call_arg_mark", &["family_flag"])?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        crate::parser::passes::CanonicalConstruct::CallArgument,
        "hir_call_arg_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_call_arg_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_call_arg_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("family_count", "hir_call_arg_table_count", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    register_array_elements(graph, capacity, passes)
}

fn register_array_elements(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    static_pass(
        graph,
        &passes.hir_array_element_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_array_element_links",
        &[
            "hir_array_element_owner_a",
            "hir_array_element_owner_b",
            "hir_array_element_link_a",
            "hir_array_element_link_b",
            "hir_array_element_rank_a",
            "hir_array_element_rank_b",
            "hir_array_element_previous",
            "hir_array_lit_first_element",
            "hir_array_lit_element_count",
            "hir_array_element_parent_lit",
            "hir_array_element_ordinal",
            "hir_array_element_next",
        ],
    )?;
    indirect(
        graph,
        "hir_array_element_links",
        "tree_active_dispatch_args",
    )?;
    register_list_rank_compaction(
        graph,
        capacity,
        passes,
        ListRankInvocation::ArrayElements,
        "hir_array_element_owner_a",
        "hir_array_element_link_a",
    )?;
    register_list_rank_propagation(
        graph,
        capacity,
        passes,
        ListRankInvocation::ArrayElements,
        "hir_array_element_owner_a",
        "hir_array_element_owner_b",
        "hir_array_element_link_a",
        "hir_array_element_link_b",
        "hir_array_element_rank_a",
        "hir_array_element_rank_b",
    )?;
    static_pass(
        graph,
        &passes.hir_array_element_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    clear(
        graph,
        CANONICAL_ARRAY_ELEMENT_CLEAR,
        CompilerPhase::Hir,
        &[
            (
                "hir_array_element_table_count",
                "hir_array_element_table_count",
            ),
            (
                "hir_array_element_family_flag",
                "hir_array_element_family_flag",
            ),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_array_element_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("element_owner", "hir_array_element_parent_lit", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_array_element_family_flag", None),
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        crate::parser::passes::CanonicalConstruct::ArrayElement,
        "hir_array_element_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_array_element_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_array_element_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("expr_result_root", "hir_expr_result_root_node", None),
            ("element_owner", "hir_array_element_parent_lit", None),
            ("element_ordinal", "hir_array_element_ordinal", None),
            (
                "array_element_start",
                "hir_array_compact_element_start",
                None,
            ),
            (
                "array_element_count",
                "hir_array_compact_element_count",
                None,
            ),
            ("family_count", "hir_array_element_table_count", None),
            ("hir_array_elements", "hir_array_element_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    clear(
        graph,
        CANONICAL_MATCH_OUTPUTS_CLEAR,
        CompilerPhase::Hir,
        &[
            ("hir_match_arm_table_count", "hir_match_arm_table_count"),
            (
                "hir_match_payload_table_count",
                "hir_match_payload_table_count",
            ),
            (
                "hir_match_pattern_payload_count",
                "hir_match_pattern_payload_count",
            ),
        ],
    )?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_MATCHES != 0 {
        register_matches(graph, capacity, passes)?;
    }
    register_struct_fields(graph, capacity, passes)
}

fn register_matches(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::{
        CanonicalConstruct,
        hir::{
            matches::arm::rank_step::{A_TO_B, A_TO_B_FINAL, B_TO_A, FINALIZE},
            nodes::SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
            semantic::parent::step::{MATCH_ARM_OWNER, bounded_walk_steps_after_local_span},
        },
    };

    static_pass(
        graph,
        &passes.hir_match_arm_owner_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_match_nearest_arm", "hir_match_pattern_owner_arm", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_match_arm_owner_init",
        &["hir_semantic_parent_link_a", "hir_match_nearest_arm"],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_tree_relations.graph_single_pass(),
        MATCH_ARM_OWNER.a_to_b,
        MATCH_ARM_OWNER.b_to_a,
        MATCH_ARM_OWNER.a_to_b_final,
        MATCH_ARM_OWNER.finalize,
        "tree_active_dispatch_args",
        true,
        bounded_walk_steps_after_local_span(
            capacity.tree_capacity,
            SEMANTIC_PARENT_LOCAL_ANCESTOR_SPAN,
        ),
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "hir_semantic_parent_link_in",
                output_binding: "hir_semantic_parent_link_out",
                a: "hir_semantic_parent_link_a",
                b: "hir_semantic_parent_link_b",
            },
            PingPongBinding {
                input_binding: "hir_semantic_parent_value_in",
                output_binding: "hir_semantic_parent_value_out",
                a: "hir_match_pattern_owner_arm",
                b: "hir_semantic_parent_value_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_match_arm_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_match_arm_links",
        &[
            "hir_match_scrutinee_node",
            "hir_match_arm_pattern_node",
            "hir_match_arm_result_node",
            "hir_match_arm_start",
            "hir_match_arm_count",
            "hir_match_arm_next",
            "hir_match_arm_payload_start",
            "hir_match_arm_payload_count",
            "hir_match_arm_owner_a",
            "hir_match_arm_owner_b",
            "hir_match_arm_link_a",
            "hir_match_arm_link_b",
            "hir_match_arm_rank_a",
            "hir_match_arm_rank_b",
            "hir_match_arm_previous",
            "hir_match_payload_owner_a",
            "hir_match_payload_owner_b",
            "hir_match_payload_link_a",
            "hir_match_payload_link_b",
            "hir_match_payload_rank_a",
            "hir_match_payload_rank_b",
            "hir_match_pattern_parent",
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_match_rank_prefix_local,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_match_rank_prefix_00_local",
        &[
            "hir_match_rank_flag",
            "hir_match_rank_local_prefix",
            "hir_match_rank_block_sum",
        ],
    )?;

    let levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let scan_aliases = [
        ("block_sum", "hir_match_rank_block_sum", None),
        ("block_prefix", "hir_match_rank_block_prefix_a", None),
        ("block_hierarchy", "hir_match_rank_block_prefix_b", None),
    ];
    reflected(
        graph,
        super::HIR_MATCH_RANK_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &scan_aliases,
    )?;
    graph.mark_pass_bindings_first_invocation_skips_read(
        super::HIR_MATCH_RANK_SCAN_UP,
        &["block_prefix", "block_hierarchy"],
    )?;
    graph.repeat_pass_range(
        levels.len() as u32,
        super::HIR_MATCH_RANK_SCAN_UP,
        super::HIR_MATCH_RANK_SCAN_UP,
    )?;
    if levels.len() > 1 {
        reflected(
            graph,
            super::HIR_MATCH_RANK_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &scan_aliases,
        )?;
        graph.repeat_pass_range(
            (levels.len() - 1) as u32,
            super::HIR_MATCH_RANK_SCAN_DOWN,
            super::HIR_MATCH_RANK_SCAN_DOWN,
        )?;
    }
    static_pass(
        graph,
        &passes.hir_match_rank_compact_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_match_rank_block_prefix",
                "hir_match_rank_block_prefix_a",
                None,
            ),
            (
                "hir_match_rank_dispatch_args",
                "hir_match_rank_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_match_rank_compact_scatter",
        &[
            "hir_match_rank_node",
            "hir_match_rank_count",
            "hir_match_rank_dispatch_args",
        ],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_match_arm_rank_step.graph_pass(),
        A_TO_B,
        B_TO_A,
        A_TO_B_FINAL,
        FINALIZE,
        "hir_match_rank_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_match_rank_node", "hir_match_rank_node", None),
            ("hir_match_rank_count", "hir_match_rank_count", None),
        ],
        &[
            PingPongBinding {
                input_binding: "hir_match_arm_owner_in",
                output_binding: "hir_match_arm_owner_out",
                a: "hir_match_arm_owner_a",
                b: "hir_match_arm_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_match_arm_link_in",
                output_binding: "hir_match_arm_link_out",
                a: "hir_match_arm_link_a",
                b: "hir_match_arm_link_b",
            },
            PingPongBinding {
                input_binding: "hir_match_arm_rank_in",
                output_binding: "hir_match_arm_rank_out",
                a: "hir_match_arm_rank_a",
                b: "hir_match_arm_rank_b",
            },
            PingPongBinding {
                input_binding: "hir_match_payload_owner_in",
                output_binding: "hir_match_payload_owner_out",
                a: "hir_match_payload_owner_a",
                b: "hir_match_payload_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_match_payload_link_in",
                output_binding: "hir_match_payload_link_out",
                a: "hir_match_payload_link_a",
                b: "hir_match_payload_link_b",
            },
            PingPongBinding {
                input_binding: "hir_match_payload_rank_in",
                output_binding: "hir_match_payload_rank_out",
                a: "hir_match_payload_rank_a",
                b: "hir_match_payload_rank_b",
            },
            PingPongBinding {
                input_binding: "hir_match_pattern_parent_in",
                output_binding: "hir_match_pattern_parent_out",
                a: "hir_match_pattern_parent",
                b: "hir_match_pattern_parent_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_match_arm_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_match_arm_scatter",
        &[
            "hir_match_payload_owner_arm",
            "hir_match_payload_match_node",
            "hir_match_payload_ordinal",
        ],
    )?;

    clear(
        graph,
        CANONICAL_MATCH_ARM_CLEAR,
        CompilerPhase::Hir,
        &[
            ("hir_match_arm_family_flag", "hir_match_arm_family_flag"),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
            ("hir_match_arm_raw_to_row", "hir_match_arm_raw_to_row"),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_match_arm_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("arm_owner_match", "hir_match_payload_match_node", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_match_arm_family_flag", None),
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::MatchArm,
        "hir_match_arm_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_match_arm_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_match_arm_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("expr_result_root", "hir_expr_result_root_node", None),
            ("arm_owner_match", "hir_match_payload_match_node", None),
            ("arm_pattern", "hir_match_arm_pattern_node", None),
            ("arm_result", "hir_match_arm_result_node", None),
            ("arm_ordinal", "hir_match_payload_ordinal", None),
            ("raw_to_arm", "hir_match_arm_raw_to_row", None),
            ("payload_start", "hir_match_compact_payload_start", None),
            ("payload_count", "hir_match_compact_payload_count", None),
            ("match_arm_range_words", "hir_match_arm_ranges", None),
            ("match_pattern_to_arm", "hir_match_pattern_to_arm", None),
            ("family_count", "hir_match_arm_table_count", None),
            ("hir_match_arms", "hir_match_arm_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    clear(
        graph,
        CANONICAL_MATCH_PAYLOAD_CLEAR,
        CompilerPhase::Hir,
        &[
            (
                "hir_match_payload_family_flag",
                "hir_match_payload_family_flag",
            ),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_match_payload_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("payload_owner_arm", "hir_match_payload_owner_arm", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_match_payload_family_flag", None),
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::MatchPayload,
        "hir_match_payload_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_match_payload_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_match_payload_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("payload_parent_pattern", "hir_match_pattern_parent", None),
            ("payload_owner_arm", "hir_match_payload_owner_arm", None),
            ("payload_ordinal", "hir_match_payload_ordinal", None),
            ("raw_to_arm", "hir_match_arm_raw_to_row", None),
            ("match_pattern_to_arm", "hir_match_pattern_to_arm", None),
            ("arm_payload_start", "hir_match_compact_payload_start", None),
            ("arm_payload_count", "hir_match_compact_payload_count", None),
            (
                "pattern_payload_count",
                "hir_match_pattern_payload_count",
                None,
            ),
            ("family_count", "hir_match_payload_table_count", None),
            ("hir_match_payloads", "hir_match_payload_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    Ok(())
}

fn register_struct_fields(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::{
        CanonicalConstruct,
        hir::structs::field::rank_step::{A_TO_B, A_TO_B_FINAL, B_TO_A, FINALIZE},
    };

    static_pass(
        graph,
        &passes.hir_struct_fields,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            (
                "hir_struct_field_parent_struct",
                "hir_struct_field_parent_struct",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_field_ordinal",
                "hir_struct_field_ordinal",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_field_type_node",
                "hir_struct_field_type_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_decl_field_start",
                "hir_struct_decl_field_start",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_decl_field_count",
                "hir_struct_decl_field_count",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_lit_head_node",
                "hir_struct_lit_head_node",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_lit_field_start",
                "hir_struct_lit_field_start",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_lit_field_count",
                "hir_struct_lit_field_count",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                "hir_struct_lit_field_parent_lit",
                Some(AccessMode::Write),
            ),
            (
                "hir_struct_lit_field_value_node",
                "hir_struct_lit_field_value_node",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    indirect(graph, "hir_struct_fields", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_struct_field_links,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_struct_field_links",
        &[
            "hir_struct_field_owner_a",
            "hir_struct_field_owner_b",
            "hir_struct_field_link_a",
            "hir_struct_field_link_b",
            "hir_struct_field_rank_a",
            "hir_struct_field_rank_b",
            "hir_struct_lit_field_owner_a",
            "hir_struct_lit_field_owner_b",
            "hir_struct_lit_field_link_a",
            "hir_struct_lit_field_link_b",
            "hir_struct_lit_field_rank_a",
            "hir_struct_lit_field_rank_b",
            "hir_struct_lit_field_previous",
        ],
    )?;
    indirect(graph, "hir_struct_field_links", "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_struct_rank_prefix_local,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_struct_rank_prefix_00_local",
        &[
            "hir_struct_rank_flag",
            "hir_struct_rank_local_prefix",
            "hir_struct_rank_block_sum",
        ],
    )?;

    let levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let scan_aliases = [
        ("block_sum", "hir_struct_rank_block_sum", None),
        ("block_prefix", "hir_struct_rank_block_prefix_a", None),
        ("block_hierarchy", "hir_struct_rank_block_prefix_b", None),
    ];
    reflected(
        graph,
        super::HIR_STRUCT_RANK_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &scan_aliases,
    )?;
    graph.mark_pass_bindings_first_invocation_skips_read(
        super::HIR_STRUCT_RANK_SCAN_UP,
        &["block_prefix", "block_hierarchy"],
    )?;
    graph.repeat_pass_range(
        levels.len() as u32,
        super::HIR_STRUCT_RANK_SCAN_UP,
        super::HIR_STRUCT_RANK_SCAN_UP,
    )?;
    if levels.len() > 1 {
        reflected(
            graph,
            super::HIR_STRUCT_RANK_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &scan_aliases,
        )?;
        graph.repeat_pass_range(
            (levels.len() - 1) as u32,
            super::HIR_STRUCT_RANK_SCAN_DOWN,
            super::HIR_STRUCT_RANK_SCAN_DOWN,
        )?;
    }
    static_pass(
        graph,
        &passes.hir_struct_rank_compact_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "hir_struct_rank_block_prefix",
                "hir_struct_rank_block_prefix_a",
                None,
            ),
            (
                "hir_struct_rank_dispatch_args",
                "hir_struct_rank_dispatch_args",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_struct_rank_compact_scatter",
        &[
            "hir_struct_rank_node",
            "hir_struct_rank_count",
            "hir_struct_rank_dispatch_args",
        ],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_struct_field_rank_step.graph_pass(),
        A_TO_B,
        B_TO_A,
        A_TO_B_FINAL,
        FINALIZE,
        "hir_struct_rank_dispatch_args",
        true,
        crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_struct_rank_node", "hir_struct_rank_node", None),
            ("hir_struct_rank_count", "hir_struct_rank_count", None),
        ],
        &[
            PingPongBinding {
                input_binding: "hir_struct_field_owner_in",
                output_binding: "hir_struct_field_owner_out",
                a: "hir_struct_field_owner_a",
                b: "hir_struct_field_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_struct_field_link_in",
                output_binding: "hir_struct_field_link_out",
                a: "hir_struct_field_link_a",
                b: "hir_struct_field_link_b",
            },
            PingPongBinding {
                input_binding: "hir_struct_field_rank_in",
                output_binding: "hir_struct_field_rank_out",
                a: "hir_struct_field_rank_a",
                b: "hir_struct_field_rank_b",
            },
            PingPongBinding {
                input_binding: "hir_struct_lit_field_owner_in",
                output_binding: "hir_struct_lit_field_owner_out",
                a: "hir_struct_lit_field_owner_a",
                b: "hir_struct_lit_field_owner_b",
            },
            PingPongBinding {
                input_binding: "hir_struct_lit_field_link_in",
                output_binding: "hir_struct_lit_field_link_out",
                a: "hir_struct_lit_field_link_a",
                b: "hir_struct_lit_field_link_b",
            },
            PingPongBinding {
                input_binding: "hir_struct_lit_field_rank_in",
                output_binding: "hir_struct_lit_field_rank_out",
                a: "hir_struct_lit_field_rank_a",
                b: "hir_struct_lit_field_rank_b",
            },
        ],
    )?;
    let clear_name =
        crate::parser::passes::tree::prev::sibling::clear::STRUCT_LITERAL_FIELD_NEXT_CLEAR;
    reflected(
        graph,
        clear_name,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        passes.tree_prev_sibling_clear.graph_pass(),
        &[(
            "prev_sibling",
            "hir_struct_lit_field_next",
            Some(AccessMode::Write),
        )],
    )?;
    indirect(graph, clear_name, "tree_active_dispatch_args")?;
    static_pass(
        graph,
        &passes.hir_struct_field_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("tree_count_status", "partial_parse_status", None)],
    )?;
    indirect(
        graph,
        "hir_struct_field_scatter",
        "tree_active_dispatch_args",
    )?;

    clear(
        graph,
        CANONICAL_FIELD_CLEAR,
        CompilerPhase::Hir,
        &[
            ("hir_field_table_count", "hir_field_table_count"),
            ("hir_field_family_flag", "hir_field_family_flag"),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_field_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("decl_owner", "hir_struct_field_parent_struct", None),
            ("literal_owner", "hir_struct_lit_field_parent_lit", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_field_family_flag", None),
        ],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::Field,
        "hir_field_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_field_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_field_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("alias_to_hir", "hir_canonical_alias_to_dense", None),
            ("decl_owner", "hir_struct_field_parent_struct", None),
            ("decl_ordinal", "hir_struct_field_ordinal", None),
            ("decl_type", "hir_struct_field_type_node", None),
            ("literal_owner", "hir_struct_lit_field_parent_lit", None),
            ("literal_ordinal", "hir_struct_lit_field_rank_a", None),
            ("literal_value", "hir_struct_lit_field_value_node", None),
            ("expr_result_root", "hir_expr_result_root_node", None),
            ("family_count", "hir_field_table_count", None),
            ("hir_fields", "hir_field_rows", None),
            ("field_range_words", "hir_match_arm_ranges", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    register_context_relations(graph, capacity, passes)
}

fn register_context_relations(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    static_pass(
        graph,
        &passes.hir_context_relations_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("hir_stmt_record", "hir_canonical_stmt_record", None),
            (
                "canonical_raw_to_dense",
                "hir_canonical_alias_to_dense",
                None,
            ),
        ],
    )?;
    indirect(
        graph,
        "hir_context_relations_init",
        "hir_semantic_dispatch_args",
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_context_relations_init",
        &[
            "hir_stmt_context_link_a",
            "hir_contextual_stmt_value_a",
            "hir_nearest_stmt_value_a",
            "hir_nearest_block_value_a",
            "hir_nearest_enclosing_control_value_a",
            "hir_nearest_loop_value_a",
            "hir_nearest_fn_value_a",
            "hir_nearest_array_element_value_a",
        ],
    )?;

    if capacity.tree_capacity
        <= crate::parser::passes::hir::context::relations::step_small::HIR_CONTEXT_RELATIONS_SMALL_CAPACITY
    {
        static_pass(
            graph,
            &passes.hir_context_relations_step_small,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            &[("tree_count_status", "partial_parse_status", None)],
        )?;
        // This cooperative single-workgroup pass performs its A→B and B→A
        // rounds internally. Reflection therefore sees B as read/write even
        // though the first internal round fully initializes it before any
        // read. Record that intra-pass lifetime boundary explicitly.
        graph.mark_pass_bindings_initialize(
            "hir_context_relations_step_small",
            &[
                "hir_stmt_context_link_b",
                "hir_contextual_stmt_value_b",
                "hir_nearest_stmt_value_b",
                "hir_nearest_block_value_b",
                "hir_nearest_enclosing_control_value_b",
                "hir_nearest_loop_value_b",
                "hir_nearest_fn_value_b",
                "hir_nearest_array_element_value_b",
            ],
        )?;
    } else {
        use crate::parser::passes::hir::context::relations::step::{
            A_TO_B,
            A_TO_B_FINAL,
            B_TO_A,
            FINALIZE,
        };
        register_ping_pong_walk(
            graph,
            passes.hir_context_relations_step.graph_pass(),
            A_TO_B,
            B_TO_A,
            A_TO_B_FINAL,
            FINALIZE,
            "hir_semantic_dispatch_args",
            true,
            crate::parser::passes::hir::bounded_walk_step_capacity(capacity.tree_capacity),
            &[
                ("tree_count_status", "partial_parse_status", None),
                ("hir_semantic_count", "hir_semantic_count", None),
            ],
            &[
                PingPongBinding { input_binding: "hir_stmt_context_link_in", output_binding: "hir_stmt_context_link_out", a: "hir_stmt_context_link_a", b: "hir_stmt_context_link_b" },
                PingPongBinding { input_binding: "hir_contextual_stmt_value_in", output_binding: "hir_contextual_stmt_value_out", a: "hir_contextual_stmt_value_a", b: "hir_contextual_stmt_value_b" },
                PingPongBinding { input_binding: "hir_nearest_stmt_value_in", output_binding: "hir_nearest_stmt_value_out", a: "hir_nearest_stmt_value_a", b: "hir_nearest_stmt_value_b" },
                PingPongBinding { input_binding: "hir_nearest_block_value_in", output_binding: "hir_nearest_block_value_out", a: "hir_nearest_block_value_a", b: "hir_nearest_block_value_b" },
                PingPongBinding { input_binding: "hir_nearest_enclosing_control_value_in", output_binding: "hir_nearest_enclosing_control_value_out", a: "hir_nearest_enclosing_control_value_a", b: "hir_nearest_enclosing_control_value_b" },
                PingPongBinding { input_binding: "hir_nearest_loop_value_in", output_binding: "hir_nearest_loop_value_out", a: "hir_nearest_loop_value_a", b: "hir_nearest_loop_value_b" },
                PingPongBinding { input_binding: "hir_nearest_fn_value_in", output_binding: "hir_nearest_fn_value_out", a: "hir_nearest_fn_value_a", b: "hir_nearest_fn_value_b" },
                PingPongBinding { input_binding: "hir_nearest_array_element_value_in", output_binding: "hir_nearest_array_element_value_out", a: "hir_nearest_array_element_value_a", b: "hir_nearest_array_element_value_b" },
            ],
        )?;
    }

    static_pass(
        graph,
        &passes.hir_context_relations_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            (
                "canonical_alias_to_dense",
                "hir_canonical_alias_to_dense",
                None,
            ),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_context_relations_scatter",
        &["hir_canonical_context_stmt"],
    )?;
    indirect(
        graph,
        "hir_context_relations_scatter",
        "hir_semantic_dispatch_args",
    )?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_PREDICATES != 0 {
        static_pass(
            graph,
            &passes.hir_method_fields,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            &[("tree_count_status", "partial_parse_status", None)],
        )?;
        indirect(graph, "hir_method_fields", "hir_semantic_dispatch_args")?;
    }
    static_pass(
        graph,
        &passes.hir_stmt_scope,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("hir_stmt_record", "hir_canonical_stmt_record", None),
        ],
    )?;
    register_canonical_materialization(graph, capacity, passes)
}

fn register_canonical_materialization(
    graph: &mut CompilerGraphBuilder,
    capacity: ParserGraphCapacity,
    passes: &ParserPasses,
) -> Result<(), String> {
    use crate::parser::passes::{
        CanonicalConstruct,
        hir::{
            canonical::expr_forest::root_step::{
                A_TO_B as EXPR_A_TO_B,
                A_TO_B_FINAL as EXPR_A_TO_B_FINAL,
                B_TO_A as EXPR_B_TO_A,
                FINALIZE as EXPR_FINALIZE,
                bounded_parent_walk_steps,
            },
            semantic::parent::step::{CANONICAL_RELATIONS, canonical_relation_step_capacity},
        },
    };

    clear(
        graph,
        CANONICAL_PARAMETER_CLEAR,
        CompilerPhase::Hir,
        &[("hir_param_table_count", "hir_param_table_count")],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_param_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("family_flag", "hir_param_family_flag", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_param_mark", &["family_flag"])?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::Parameter,
        "hir_param_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_param_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_param_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("family_count", "hir_param_table_count", None),
            ("hir_params", "hir_param_rows", None),
            ("param_ranges", "hir_param_ranges", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;

    clear(
        graph,
        CANONICAL_TYPE_ARGUMENT_CLEAR,
        CompilerPhase::Hir,
        &[("hir_type_arg_table_count", "hir_type_arg_table_count")],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_type_arg_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("hir_type_arg_owner", "hir_type_arg_owner_a", None),
            ("hir_type_arg_rank", "hir_type_arg_rank_a", None),
            ("family_flag", "hir_type_arg_family_flag", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_type_arg_mark", &["family_flag"])?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::TypeArgument,
        "hir_type_arg_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_type_arg_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_type_arg_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("hir_type_arg_owner", "hir_type_arg_owner_a", None),
            ("hir_type_arg_rank", "hir_type_arg_rank_a", None),
            ("family_count", "hir_type_arg_table_count", None),
            ("hir_type_args", "hir_type_arg_rows", None),
            ("type_arg_ranges", "hir_type_arg_ranges", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_relations_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("raw_to_item", "hir_canonical_raw_to_dense", None),
            ("canonical_flag", "hir_semantic_flag", None),
            (
                "canonical_prefix_before_raw",
                "hir_canonical_prefix_before_raw",
                None,
            ),
            ("relation_link_a", "hir_semantic_parent_link_a", None),
            ("canonical_parent_a", "hir_semantic_parent_value_a", None),
            ("generic_owner_a", "hir_type_arg_rank_a", None),
            ("predicate_subject_a", "hir_variant_payload_rank_a", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_relations_init",
        &["relation_link_a", "canonical_parent_a"],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_tree_relations.graph_triple_pass(),
        CANONICAL_RELATIONS.a_to_b,
        CANONICAL_RELATIONS.b_to_a,
        CANONICAL_RELATIONS.a_to_b_final,
        CANONICAL_RELATIONS.finalize,
        "tree_active_dispatch_args",
        true,
        canonical_relation_step_capacity(capacity.tree_capacity),
        &[("tree_count_status", "partial_parse_status", None)],
        &[
            PingPongBinding {
                input_binding: "relation_link_in",
                output_binding: "relation_link_out",
                a: "hir_semantic_parent_link_a",
                b: "hir_semantic_parent_link_b",
            },
            PingPongBinding {
                input_binding: "first_value_in",
                output_binding: "first_value_out",
                a: "hir_semantic_parent_value_a",
                b: "hir_semantic_parent_value_b",
            },
            PingPongBinding {
                input_binding: "second_value_in",
                output_binding: "second_value_out",
                a: "hir_type_arg_rank_a",
                b: "hir_type_arg_rank_b",
            },
            PingPongBinding {
                input_binding: "third_value_in",
                output_binding: "third_value_out",
                a: "hir_variant_payload_rank_a",
                b: "hir_variant_payload_rank_b",
            },
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_core,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            (
                "canonical_prefix_before_raw",
                "hir_canonical_prefix_before_raw",
                None,
            ),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("canonical_raw_to_dense", "hir_canonical_raw_to_dense", None),
            (
                "canonical_alias_to_dense",
                "hir_canonical_alias_to_dense",
                None,
            ),
            ("parent_value", "hir_semantic_parent_value_a", None),
            (
                "hir_method_impl_receiver_type",
                "hir_method_impl_receiver_type_node",
                None,
            ),
            ("hir_stmt_record", "hir_canonical_stmt_record", None),
            ("hir_expr_record", "hir_canonical_expr_record", None),
            ("hir_field_ranges", "hir_match_arm_ranges", None),
            ("hir_core", "hir_core", Some(AccessMode::Write)),
            ("hir_links", "hir_links", Some(AccessMode::Write)),
            ("hir_payload", "hir_payload", Some(AccessMode::Write)),
            (
                "hir_canonical_semantic_facts",
                "hir_canonical_semantic_facts",
                Some(AccessMode::Write),
            ),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_nav,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[("canonical_count", "hir_canonical_count", None)],
    )?;
    clear(
        graph,
        CANONICAL_EXPR_FOREST_CLEAR,
        CompilerPhase::Hir,
        &[
            (
                "hir_canonical_expr_parent_encoded",
                "hir_canonical_expr_parent_encoded",
            ),
            (
                "hir_canonical_expr_forest_status",
                "hir_canonical_expr_forest_status",
            ),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_expr_forest_edges,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("call_arg_count", "hir_call_arg_table_count", None),
            ("call_args", "hir_call_args", None),
            (
                "expr_parent_encoded",
                "hir_canonical_expr_parent_encoded",
                None,
            ),
            (
                "expr_forest_status",
                "hir_canonical_expr_forest_status",
                None,
            ),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_expr_forest_root_init,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            (
                "expr_parent_encoded",
                "hir_canonical_expr_parent_encoded",
                None,
            ),
            ("expr_parent", "hir_canonical_expr_parent", None),
            ("expr_root", "hir_canonical_expr_root", None),
        ],
    )?;
    register_ping_pong_walk(
        graph,
        passes.hir_canonical_expr_forest_root_step.graph_pass(),
        EXPR_A_TO_B,
        EXPR_B_TO_A,
        EXPR_A_TO_B_FINAL,
        EXPR_FINALIZE,
        "tree_active_dispatch_args",
        false,
        bounded_parent_walk_steps(capacity.token_capacity),
        &[("canonical_count", "hir_canonical_count", None)],
        &[PingPongBinding {
            input_binding: "expr_root_in",
            output_binding: "expr_root_out",
            a: "hir_canonical_expr_root",
            b: "hir_canonical_expr_root_scratch",
        }],
    )?;

    clear(
        graph,
        CANONICAL_GENERIC_PARAMETER_CLEAR,
        CompilerPhase::Hir,
        &[
            (
                "hir_generic_param_table_count",
                "hir_generic_param_table_count",
            ),
            ("hir_canonical_anchor_owner", "hir_canonical_anchor_owner"),
        ],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_generic_param_candidate_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_generic_param_finalize,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("owner_value", "hir_type_arg_rank_a", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("family_flag", "hir_generic_param_family_flag", None),
            ("generic_param_ranges", "hir_generic_param_ranges", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_generic_param_finalize",
        &["family_flag", "generic_param_ranges"],
    )?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::GenericParameter,
        "hir_generic_param_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_generic_param_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_generic_param_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            (
                "candidate_raw_by_anchor",
                "hir_canonical_anchor_owner",
                None,
            ),
            ("owner_value", "hir_type_arg_rank_a", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("family_count", "hir_generic_param_table_count", None),
            ("hir_generic_params", "hir_generic_param_rows", None),
            ("generic_param_ranges", "hir_generic_param_ranges", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;

    clear(
        graph,
        CANONICAL_PATH_SEGMENT_CLEAR,
        CompilerPhase::Hir,
        &[(
            "hir_path_segment_table_count",
            "hir_path_segment_table_count",
        )],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_path_segment_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("segment_count_by_owner", "hir_path_segment_count", None),
            ("owner_local_prefix", "hir_semantic_local_prefix", None),
            ("owner_block_sum", "hir_semantic_block_sum", None),
        ],
    )?;
    let path_levels = hierarchical_scan_levels(capacity.tree_node_blocks.max(1));
    let (up, down) = passes.hir_semantic_prefix_blocks.graph_passes();
    let path_scan_aliases = [
        ("block_sum", "hir_semantic_block_sum", None),
        ("block_prefix", "hir_semantic_block_prefix_a", None),
        ("block_hierarchy", "hir_semantic_block_prefix_b", None),
    ];
    reflected(
        graph,
        super::HIR_PATH_SEGMENT_SCAN_UP,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        up,
        &path_scan_aliases,
    )?;
    graph.repeat_pass_range(
        path_levels.len() as u32,
        super::HIR_PATH_SEGMENT_SCAN_UP,
        super::HIR_PATH_SEGMENT_SCAN_UP,
    )?;
    if path_levels.len() > 1 {
        reflected(
            graph,
            super::HIR_PATH_SEGMENT_SCAN_DOWN,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            down,
            &path_scan_aliases,
        )?;
        graph.repeat_pass_range(
            (path_levels.len() - 1) as u32,
            super::HIR_PATH_SEGMENT_SCAN_DOWN,
            super::HIR_PATH_SEGMENT_SCAN_DOWN,
        )?;
    }
    static_pass(
        graph,
        &passes.hir_canonical_path_segment_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("tree_count_status", "partial_parse_status", None),
            ("owner_local_prefix", "hir_semantic_local_prefix", None),
            ("owner_block_prefix", "hir_semantic_block_prefix_a", None),
            ("path_segment_owner", "hir_path_segment_owner_a", None),
            ("path_segment_rank", "hir_path_segment_rank_a", None),
            ("family_count", "hir_path_segment_table_count", None),
            ("path_segments", "hir_path_segment_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    clear(
        graph,
        CANONICAL_PATH_CLEAR,
        CompilerPhase::Hir,
        &[("hir_path_table_count", "hir_path_table_count")],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_path_mark,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("segment_count", "hir_path_segment_table_count", None),
            ("path_segments", "hir_path_segment_rows", None),
            ("family_flag", "hir_path_family_flag", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_path_mark", &["family_flag"])?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::Path,
        "hir_path_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_path_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_path_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            ("segment_table_count", "hir_path_segment_table_count", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("raw_to_item", "hir_canonical_raw_to_dense", None),
            ("canonical_core", "hir_core", None),
            ("segment_count_by_raw_owner", "hir_path_segment_count", None),
            ("family_count", "hir_path_table_count", None),
            ("paths", "hir_path_rows", None),
            ("path_segments", "hir_path_segment_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_string_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("raw_string_count", "hir_string_count", None),
            ("raw_string_node", "hir_string_node", None),
            ("raw_string_data_offset", "hir_string_data_offset", None),
            ("raw_string_decoded_len", "hir_string_decoded_len", None),
            ("hir_strings", "hir_canonical_string_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;

    // The count is an observable compact-HIR output even when the source pack
    // contains no predicates or methods. Clear it after earlier workspace
    // aliases are dead so an absent family publishes zero rather than the
    // previous occupant's last word.
    clear(
        graph,
        CANONICAL_METHOD_CLEAR,
        CompilerPhase::Hir,
        &[("hir_method_table_count", "hir_method_table_count")],
    )?;
    if capacity.parser_feature_flags & crate::lexer::features::PARSER_FEATURE_PREDICATES != 0 {
        static_pass(
            graph,
            &passes.hir_canonical_method_mark,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            &[
                ("canonical_count", "hir_canonical_count", None),
                ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
                ("method_name_token", "hir_method_name_token", None),
                ("family_flag", "hir_method_family_flag", None),
            ],
        )?;
        graph.mark_pass_bindings_initialize("hir_canonical_method_mark", &["family_flag"])?;
        register_canonical_compaction_prefix(
            graph,
            capacity,
            passes,
            CanonicalConstruct::Method,
            "hir_method_family_flag",
        )?;
        static_pass(
            graph,
            &passes.hir_canonical_method_scatter,
            CompilerPhase::Hir,
            ResourceDomain::HirNodes,
            &[
                ("family_flag", "hir_method_family_flag", None),
                ("family_local_prefix", "hir_semantic_local_prefix", None),
                ("family_block_prefix", "hir_semantic_block_prefix_a", None),
                ("canonical_count", "hir_canonical_count", None),
                ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
                ("raw_to_hir", "hir_canonical_alias_to_dense", None),
                ("method_owner", "hir_method_owner_node", None),
                ("method_impl", "hir_method_impl_node", None),
                ("method_name_token", "hir_method_name_token", None),
                (
                    "method_first_param_token",
                    "hir_method_first_param_token",
                    None,
                ),
                ("method_receiver_mode", "hir_method_receiver_mode", None),
                ("method_visibility", "hir_method_visibility", None),
                ("method_signature_flags", "hir_method_signature_flags", None),
                (
                    "method_impl_receiver_type",
                    "hir_method_impl_receiver_type_node",
                    None,
                ),
                ("family_count", "hir_method_table_count", None),
                ("method_cores", "hir_method_core_rows", None),
                ("method_signatures", "hir_method_signature_rows", None),
                ("canonical_status", "hir_canonical_status", None),
            ],
        )?;
    }

    clear(
        graph,
        CANONICAL_PREDICATE_CLEAR,
        CompilerPhase::Hir,
        &[("hir_predicate_table_count", "hir_predicate_table_count")],
    )?;

    static_pass(
        graph,
        &passes.hir_canonical_predicate_finalize,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("hir_to_raw", "hir_canonical_dense_to_raw", None),
            ("type_root_owner", "hir_type_root_owner", None),
            ("subject_anchor", "hir_variant_payload_rank_a", None),
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("family_flag", "hir_method_family_flag", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize("hir_canonical_predicate_finalize", &["family_flag"])?;
    register_canonical_compaction_prefix(
        graph,
        capacity,
        passes,
        CanonicalConstruct::Predicate,
        "hir_method_family_flag",
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_predicate_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("family_flag", "hir_method_family_flag", None),
            ("family_local_prefix", "hir_semantic_local_prefix", None),
            ("family_block_prefix", "hir_semantic_block_prefix_a", None),
            ("canonical_count", "hir_canonical_count", None),
            ("canonical_dense_to_raw", "hir_canonical_dense_to_raw", None),
            ("raw_to_hir", "hir_canonical_alias_to_dense", None),
            ("subject_anchor", "hir_variant_payload_rank_a", None),
            ("owner_value", "hir_type_arg_rank_a", None),
            ("family_count", "hir_predicate_table_count", None),
            ("predicates", "hir_predicate_rows", None),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_validate,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            (
                "canonical_raw_to_dense",
                "hir_canonical_alias_to_dense",
                None,
            ),
            ("hir_params", "hir_param_rows", None),
            ("hir_type_args", "hir_type_arg_rows", None),
            ("hir_generic_params", "hir_generic_param_rows", None),
            ("hir_paths", "hir_path_rows", None),
            ("hir_path_segments", "hir_path_segment_rows", None),
            ("hir_fields", "hir_field_rows", None),
            ("hir_variants", "hir_variant_rows", None),
            (
                "hir_variant_payload_start",
                "hir_variant_compact_payload_start",
                None,
            ),
            (
                "hir_variant_payload_count",
                "hir_variant_compact_payload_count",
                None,
            ),
            ("hir_variant_payloads", "hir_variant_payload_rows", None),
            ("hir_match_arms", "hir_match_arm_rows", None),
            (
                "hir_match_payload_start",
                "hir_match_compact_payload_start",
                None,
            ),
            (
                "hir_match_payload_count",
                "hir_match_compact_payload_count",
                None,
            ),
            ("hir_match_payloads", "hir_match_payload_rows", None),
            (
                "hir_array_element_start",
                "hir_array_compact_element_start",
                None,
            ),
            (
                "hir_array_element_count",
                "hir_array_compact_element_count",
                None,
            ),
            ("hir_array_elements", "hir_array_element_rows", None),
            ("hir_strings", "hir_canonical_string_rows", None),
            ("hir_method_count", "hir_method_table_count", None),
            ("hir_method_cores", "hir_method_core_rows", None),
            ("hir_method_signatures", "hir_method_signature_rows", None),
            ("hir_predicate_count", "hir_predicate_table_count", None),
            ("hir_predicates", "hir_predicate_rows", None),
            ("hir_expr_parent", "hir_canonical_expr_parent", None),
            ("hir_expr_root", "hir_canonical_expr_root", None),
            (
                "hir_expr_forest_status",
                "hir_canonical_expr_forest_status",
                None,
            ),
            (
                "semantic_to_compact_hir",
                "hir_canonical_prefix_before_raw",
                None,
            ),
            (
                "compact_semantic_dense_node",
                "hir_canonical_semantic_dense_node",
                None,
            ),
            ("canonical_status", "hir_canonical_status", None),
        ],
    )?;
    graph.mark_pass_bindings_initialize(
        "hir_canonical_validate",
        &["compact_semantic_dense_node"],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_decl_index_clear,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("decl_by_name_token", "hir_canonical_anchor_owner", None),
        ],
    )?;
    static_pass(
        graph,
        &passes.hir_canonical_decl_index_scatter,
        CompilerPhase::Hir,
        ResourceDomain::HirNodes,
        &[
            ("canonical_count", "hir_canonical_count", None),
            ("decl_by_name_token", "hir_canonical_anchor_owner", None),
        ],
    )?;
    Ok(())
}
