use super::*;

mod function_return_readbacks;
pub use function_return_readbacks::*;

/// Narrow readback for parser-owned HIR item/type/type-alias/parameter/method/variant/member/stmt/match/call/array/struct record contracts.
///
/// Production resident parser buffers intentionally reuse some debug-only
/// navigation arrays. This helper copies only durable item/type/type-alias/parameter/method/variant/member/stmt/match/call/array/struct,
/// span, and file-id records so source-pack contract tests can exercise the
/// production buffer layout.
pub struct ParserHirItemReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub node_kind: wgpu::Buffer,
    pub hir_kind: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
    pub hir_node_file_id: wgpu::Buffer,
    pub hir_semantic_dense_node: wgpu::Buffer,
    pub hir_semantic_parent: wgpu::Buffer,
    pub hir_semantic_first_child: wgpu::Buffer,
    pub hir_semantic_next_sibling: wgpu::Buffer,
    pub hir_semantic_depth: wgpu::Buffer,
    pub hir_semantic_child_index: wgpu::Buffer,
    pub hir_type_form: wgpu::Buffer,
    pub hir_type_value_node: wgpu::Buffer,
    pub hir_type_len_token: wgpu::Buffer,
    pub hir_type_len_value: wgpu::Buffer,
    pub hir_type_file_id: wgpu::Buffer,
    pub hir_type_path_leaf_node: wgpu::Buffer,
    pub hir_type_arg_start: wgpu::Buffer,
    pub hir_type_arg_count: wgpu::Buffer,
    pub hir_type_arg_next: wgpu::Buffer,
    pub hir_type_alias_target_node: wgpu::Buffer,
    pub hir_fn_return_type_node: wgpu::Buffer,
    pub hir_item_kind: wgpu::Buffer,
    pub hir_item_name_token: wgpu::Buffer,
    pub hir_item_decl_token: wgpu::Buffer,
    pub hir_item_namespace: wgpu::Buffer,
    pub hir_item_visibility: wgpu::Buffer,
    pub hir_item_path_start: wgpu::Buffer,
    pub hir_item_path_end: wgpu::Buffer,
    pub hir_item_path_node: wgpu::Buffer,
    pub hir_item_file_id: wgpu::Buffer,
    pub hir_item_import_target_kind: wgpu::Buffer,
    pub hir_variant_parent_enum: wgpu::Buffer,
    pub hir_variant_ordinal: wgpu::Buffer,
    pub hir_variant_payload_start: wgpu::Buffer,
    pub hir_variant_payload_count: wgpu::Buffer,
    pub hir_variant_payload_node: wgpu::Buffer,
    pub hir_param_record: wgpu::Buffer,
    pub hir_param_type_node: wgpu::Buffer,
    pub hir_method_owner_node: wgpu::Buffer,
    pub hir_method_impl_node: wgpu::Buffer,
    pub hir_method_name_token: wgpu::Buffer,
    pub hir_method_first_param_token: wgpu::Buffer,
    pub hir_method_receiver_mode: wgpu::Buffer,
    pub hir_method_visibility: wgpu::Buffer,
    pub hir_method_signature_flags: wgpu::Buffer,
    pub hir_method_impl_receiver_type_node: wgpu::Buffer,
    pub hir_expr_record: wgpu::Buffer,
    pub hir_match_scrutinee_node: wgpu::Buffer,
    pub hir_match_arm_start: wgpu::Buffer,
    pub hir_match_arm_count: wgpu::Buffer,
    pub hir_match_arm_next: wgpu::Buffer,
    pub hir_match_arm_pattern_node: wgpu::Buffer,
    pub hir_match_arm_payload_start: wgpu::Buffer,
    pub hir_match_arm_payload_count: wgpu::Buffer,
    pub hir_match_arm_result_node: wgpu::Buffer,
    pub hir_match_payload_owner_arm: wgpu::Buffer,
    pub hir_match_payload_match_node: wgpu::Buffer,
    pub hir_match_payload_ordinal: wgpu::Buffer,
    pub hir_call_callee_node: wgpu::Buffer,
    pub hir_call_context_stmt_node: wgpu::Buffer,
    pub hir_call_arg_start: wgpu::Buffer,
    pub hir_call_arg_end: wgpu::Buffer,
    pub hir_call_arg_count: wgpu::Buffer,
    pub hir_call_arg_parent_call: wgpu::Buffer,
    pub hir_call_arg_ordinal: wgpu::Buffer,
    pub hir_array_lit_first_element: wgpu::Buffer,
    pub hir_array_lit_element_count: wgpu::Buffer,
    pub hir_array_lit_context_stmt_node: wgpu::Buffer,
    pub hir_array_element_parent_lit: wgpu::Buffer,
    pub hir_array_element_ordinal: wgpu::Buffer,
    pub hir_array_element_next: wgpu::Buffer,
    pub hir_expr_string_start: wgpu::Buffer,
    pub hir_expr_string_len: wgpu::Buffer,
    pub hir_member_receiver_node: wgpu::Buffer,
    pub hir_member_receiver_token: wgpu::Buffer,
    pub hir_member_name_token: wgpu::Buffer,
    pub hir_stmt_record: wgpu::Buffer,
    pub hir_stmt_scope_end: wgpu::Buffer,
    pub hir_nearest_stmt_node: wgpu::Buffer,
    pub hir_nearest_block_node: wgpu::Buffer,
    pub hir_nearest_enclosing_control_node: wgpu::Buffer,
    pub hir_nearest_loop_node: wgpu::Buffer,
    pub hir_nearest_fn_node: wgpu::Buffer,
    pub hir_struct_field_parent_struct: wgpu::Buffer,
    pub hir_struct_field_ordinal: wgpu::Buffer,
    pub hir_struct_field_type_node: wgpu::Buffer,
    pub hir_struct_decl_field_start: wgpu::Buffer,
    pub hir_struct_decl_field_count: wgpu::Buffer,
    pub hir_struct_lit_head_node: wgpu::Buffer,
    pub hir_struct_lit_context_stmt_node: wgpu::Buffer,
    pub hir_struct_lit_field_start: wgpu::Buffer,
    pub hir_struct_lit_field_count: wgpu::Buffer,
    pub hir_struct_lit_field_parent_lit: wgpu::Buffer,
    pub hir_struct_lit_field_value_node: wgpu::Buffer,
    pub hir_struct_lit_field_next: wgpu::Buffer,
}

/// Decoded parser-owned HIR item/type/member/call/aggregate readback data.
pub struct DecodedParserHirItemReadbacks {
    pub ll1_status: [u32; 6],
    pub node_kind: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_node_file_id: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_type_path_leaf_node: Vec<u32>,
    pub hir_type_arg_start: Vec<u32>,
    pub hir_type_arg_count: Vec<u32>,
    pub hir_type_arg_next: Vec<u32>,
    pub hir_type_alias_target_node: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_path_node: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_variant_payload_node: Vec<u32>,
    pub hir_param_owner_fn_node: Vec<u32>,
    pub hir_param_ordinal: Vec<u32>,
    pub hir_param_name_token: Vec<u32>,
    pub hir_param_record_node: Vec<u32>,
    pub hir_param_type_node: Vec<u32>,
    pub hir_method_owner_node: Vec<u32>,
    pub hir_method_impl_node: Vec<u32>,
    pub hir_method_name_token: Vec<u32>,
    pub hir_method_first_param_token: Vec<u32>,
    pub hir_method_receiver_mode: Vec<u32>,
    pub hir_method_visibility: Vec<u32>,
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_method_impl_receiver_type_node: Vec<u32>,
    pub hir_expr_record_form: Vec<u32>,
    pub hir_expr_record_left: Vec<u32>,
    pub hir_expr_record_right: Vec<u32>,
    pub hir_expr_record_value_token: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_next: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_match_payload_owner_arm: Vec<u32>,
    pub hir_match_payload_match_node: Vec<u32>,
    pub hir_match_payload_ordinal: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_context_stmt_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_lit_context_stmt_node: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_expr_string_start: Vec<u32>,
    pub hir_expr_string_len: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_stmt_record_kind: Vec<u32>,
    pub hir_stmt_record_operand0: Vec<u32>,
    pub hir_stmt_record_operand1: Vec<u32>,
    pub hir_stmt_record_operand2: Vec<u32>,
    pub hir_stmt_scope_end: Vec<u32>,
    pub hir_nearest_stmt_node: Vec<u32>,
    pub hir_nearest_block_node: Vec<u32>,
    pub hir_nearest_enclosing_control_node: Vec<u32>,
    pub hir_nearest_loop_node: Vec<u32>,
    pub hir_nearest_fn_node: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_context_stmt_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
    pub hir_struct_lit_field_next: Vec<u32>,
}

impl ParserHirItemReadbacks {
    /// Creates staging buffers for parser-owned HIR item and aggregate readback.
    pub fn create(device: &wgpu::Device, bufs: &ParserBuffers) -> Self {
        let mk = |label: &str, size: u64| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        };

        Self {
            ll1_status: mk(
                "rb.parser.hir_item_records.ll1_status",
                bufs.ll1_status.byte_size as u64,
            ),
            node_kind: mk(
                "rb.parser.hir_item_records.node_kind",
                bufs.node_kind.byte_size as u64,
            ),
            hir_kind: mk(
                "rb.parser.hir_item_records.hir_kind",
                bufs.hir_kind.byte_size as u64,
            ),
            hir_token_pos: mk(
                "rb.parser.hir_item_records.hir_token_pos",
                bufs.hir_token_pos.byte_size as u64,
            ),
            hir_token_end: mk(
                "rb.parser.hir_item_records.hir_token_end",
                bufs.hir_token_end.byte_size as u64,
            ),
            hir_node_file_id: mk(
                "rb.parser.hir_item_records.hir_node_file_id",
                bufs.hir_token_file_id.byte_size as u64,
            ),
            hir_semantic_dense_node: mk(
                "rb.parser.hir_item_records.hir_semantic_dense_node",
                bufs.hir_semantic_dense_node.byte_size as u64,
            ),
            hir_semantic_parent: mk(
                "rb.parser.hir_item_records.hir_semantic_parent",
                bufs.hir_semantic_parent.byte_size as u64,
            ),
            hir_semantic_first_child: mk(
                "rb.parser.hir_item_records.hir_semantic_first_child",
                bufs.hir_semantic_first_child.byte_size as u64,
            ),
            hir_semantic_next_sibling: mk(
                "rb.parser.hir_item_records.hir_semantic_next_sibling",
                bufs.hir_semantic_next_sibling.byte_size as u64,
            ),
            hir_semantic_depth: mk(
                "rb.parser.hir_item_records.hir_semantic_depth",
                bufs.hir_semantic_depth.byte_size as u64,
            ),
            hir_semantic_child_index: mk(
                "rb.parser.hir_item_records.hir_semantic_child_index",
                bufs.hir_semantic_child_index.byte_size as u64,
            ),
            hir_type_form: mk(
                "rb.parser.hir_item_records.hir_type_form",
                bufs.hir_type_form.byte_size as u64,
            ),
            hir_type_value_node: mk(
                "rb.parser.hir_item_records.hir_type_value_node",
                bufs.hir_type_value_node.byte_size as u64,
            ),
            hir_type_len_token: mk(
                "rb.parser.hir_item_records.hir_type_len_token",
                bufs.hir_type_len_token.byte_size as u64,
            ),
            hir_type_len_value: mk(
                "rb.parser.hir_item_records.hir_type_len_value",
                bufs.hir_type_len_value.byte_size as u64,
            ),
            hir_type_file_id: mk(
                "rb.parser.hir_item_records.hir_type_file_id",
                bufs.hir_type_file_id.byte_size as u64,
            ),
            hir_type_path_leaf_node: mk(
                "rb.parser.hir_item_records.hir_type_path_leaf_node",
                bufs.hir_type_path_leaf_node.byte_size as u64,
            ),
            hir_type_arg_start: mk(
                "rb.parser.hir_item_records.hir_type_arg_start",
                bufs.hir_type_arg_start.byte_size as u64,
            ),
            hir_type_arg_count: mk(
                "rb.parser.hir_item_records.hir_type_arg_count",
                bufs.hir_type_arg_count.byte_size as u64,
            ),
            hir_type_arg_next: mk(
                "rb.parser.hir_item_records.hir_type_arg_next",
                bufs.hir_type_arg_next.byte_size as u64,
            ),
            hir_type_alias_target_node: mk(
                "rb.parser.hir_item_records.hir_type_alias_target_node",
                bufs.hir_type_alias_target_node.byte_size as u64,
            ),
            hir_fn_return_type_node: mk(
                "rb.parser.hir_item_records.hir_fn_return_type_node",
                bufs.hir_fn_return_type_node.byte_size as u64,
            ),
            hir_item_kind: mk(
                "rb.parser.hir_item_records.hir_item_kind",
                bufs.hir_item_kind.byte_size as u64,
            ),
            hir_item_name_token: mk(
                "rb.parser.hir_item_records.hir_item_name_token",
                bufs.hir_item_name_token.byte_size as u64,
            ),
            hir_item_decl_token: mk(
                "rb.parser.hir_item_records.hir_item_decl_token",
                bufs.hir_item_decl_token.byte_size as u64,
            ),
            hir_item_namespace: mk(
                "rb.parser.hir_item_records.hir_item_namespace",
                bufs.hir_item_namespace.byte_size as u64,
            ),
            hir_item_visibility: mk(
                "rb.parser.hir_item_records.hir_item_visibility",
                bufs.hir_item_visibility.byte_size as u64,
            ),
            hir_item_path_start: mk(
                "rb.parser.hir_item_records.hir_item_path_start",
                bufs.hir_item_path_start.byte_size as u64,
            ),
            hir_item_path_end: mk(
                "rb.parser.hir_item_records.hir_item_path_end",
                bufs.hir_item_path_end.byte_size as u64,
            ),
            hir_item_path_node: mk(
                "rb.parser.hir_item_records.hir_item_path_node",
                bufs.hir_item_path_node.byte_size as u64,
            ),
            hir_item_file_id: mk(
                "rb.parser.hir_item_records.hir_item_file_id",
                bufs.hir_item_file_id.byte_size as u64,
            ),
            hir_item_import_target_kind: mk(
                "rb.parser.hir_item_records.hir_item_import_target_kind",
                bufs.hir_item_import_target_kind.byte_size as u64,
            ),
            hir_variant_parent_enum: mk(
                "rb.parser.hir_item_records.hir_variant_parent_enum",
                bufs.hir_variant_parent_enum.byte_size as u64,
            ),
            hir_variant_ordinal: mk(
                "rb.parser.hir_item_records.hir_variant_ordinal",
                bufs.hir_variant_ordinal.byte_size as u64,
            ),
            hir_variant_payload_start: mk(
                "rb.parser.hir_item_records.hir_variant_payload_start",
                bufs.hir_variant_payload_start.byte_size as u64,
            ),
            hir_variant_payload_count: mk(
                "rb.parser.hir_item_records.hir_variant_payload_count",
                bufs.hir_variant_payload_count.byte_size as u64,
            ),
            hir_variant_payload_node: mk(
                "rb.parser.hir_item_records.hir_variant_payload_node",
                bufs.hir_variant_payload_node.byte_size as u64,
            ),
            hir_param_record: mk(
                "rb.parser.hir_item_records.hir_param_record",
                bufs.hir_param_record.byte_size as u64,
            ),
            hir_param_type_node: mk(
                "rb.parser.hir_item_records.hir_param_type_node",
                bufs.hir_param_type_node.byte_size as u64,
            ),
            hir_method_owner_node: mk(
                "rb.parser.hir_item_records.hir_method_owner_node",
                bufs.hir_method_owner_node.byte_size as u64,
            ),
            hir_method_impl_node: mk(
                "rb.parser.hir_item_records.hir_method_impl_node",
                bufs.hir_method_impl_node.byte_size as u64,
            ),
            hir_method_name_token: mk(
                "rb.parser.hir_item_records.hir_method_name_token",
                bufs.hir_method_name_token.byte_size as u64,
            ),
            hir_method_first_param_token: mk(
                "rb.parser.hir_item_records.hir_method_first_param_token",
                bufs.hir_method_first_param_token.byte_size as u64,
            ),
            hir_method_receiver_mode: mk(
                "rb.parser.hir_item_records.hir_method_receiver_mode",
                bufs.hir_method_receiver_mode.byte_size as u64,
            ),
            hir_method_visibility: mk(
                "rb.parser.hir_item_records.hir_method_visibility",
                bufs.hir_method_visibility.byte_size as u64,
            ),
            hir_method_signature_flags: mk(
                "rb.parser.hir_item_records.hir_method_signature_flags",
                bufs.hir_method_signature_flags.byte_size as u64,
            ),
            hir_method_impl_receiver_type_node: mk(
                "rb.parser.hir_item_records.hir_method_impl_receiver_type_node",
                bufs.hir_method_impl_receiver_type_node.byte_size as u64,
            ),
            hir_expr_record: mk(
                "rb.parser.hir_item_records.hir_expr_record",
                bufs.hir_expr_record.byte_size as u64,
            ),
            hir_match_scrutinee_node: mk(
                "rb.parser.hir_item_records.hir_match_scrutinee_node",
                bufs.hir_match_scrutinee_node.byte_size as u64,
            ),
            hir_match_arm_start: mk(
                "rb.parser.hir_item_records.hir_match_arm_start",
                bufs.hir_match_arm_start.byte_size as u64,
            ),
            hir_match_arm_count: mk(
                "rb.parser.hir_item_records.hir_match_arm_count",
                bufs.hir_match_arm_count.byte_size as u64,
            ),
            hir_match_arm_next: mk(
                "rb.parser.hir_item_records.hir_match_arm_next",
                bufs.hir_match_arm_next.byte_size as u64,
            ),
            hir_match_arm_pattern_node: mk(
                "rb.parser.hir_item_records.hir_match_arm_pattern_node",
                bufs.hir_match_arm_pattern_node.byte_size as u64,
            ),
            hir_match_arm_payload_start: mk(
                "rb.parser.hir_item_records.hir_match_arm_payload_start",
                bufs.hir_match_arm_payload_start.byte_size as u64,
            ),
            hir_match_arm_payload_count: mk(
                "rb.parser.hir_item_records.hir_match_arm_payload_count",
                bufs.hir_match_arm_payload_count.byte_size as u64,
            ),
            hir_match_arm_result_node: mk(
                "rb.parser.hir_item_records.hir_match_arm_result_node",
                bufs.hir_match_arm_result_node.byte_size as u64,
            ),
            hir_match_payload_owner_arm: mk(
                "rb.parser.hir_item_records.hir_match_payload_owner_arm",
                bufs.hir_match_payload_owner_arm.byte_size as u64,
            ),
            hir_match_payload_match_node: mk(
                "rb.parser.hir_item_records.hir_match_payload_match_node",
                bufs.hir_match_payload_match_node.byte_size as u64,
            ),
            hir_match_payload_ordinal: mk(
                "rb.parser.hir_item_records.hir_match_payload_ordinal",
                bufs.hir_match_payload_ordinal.byte_size as u64,
            ),
            hir_call_callee_node: mk(
                "rb.parser.hir_item_records.hir_call_callee_node",
                bufs.hir_call_callee_node.byte_size as u64,
            ),
            hir_call_context_stmt_node: mk(
                "rb.parser.hir_item_records.hir_call_context_stmt_node",
                bufs.hir_call_context_stmt_node.byte_size as u64,
            ),
            hir_call_arg_start: mk(
                "rb.parser.hir_item_records.hir_call_arg_start",
                bufs.hir_call_arg_start.byte_size as u64,
            ),
            hir_call_arg_end: mk(
                "rb.parser.hir_item_records.hir_call_arg_end",
                bufs.hir_call_arg_end.byte_size as u64,
            ),
            hir_call_arg_count: mk(
                "rb.parser.hir_item_records.hir_call_arg_count",
                bufs.hir_call_arg_count.byte_size as u64,
            ),
            hir_call_arg_parent_call: mk(
                "rb.parser.hir_item_records.hir_call_arg_parent_call",
                bufs.hir_call_arg_parent_call.byte_size as u64,
            ),
            hir_call_arg_ordinal: mk(
                "rb.parser.hir_item_records.hir_call_arg_ordinal",
                bufs.hir_call_arg_ordinal.byte_size as u64,
            ),
            hir_array_lit_first_element: mk(
                "rb.parser.hir_item_records.hir_array_lit_first_element",
                bufs.hir_array_lit_first_element.byte_size as u64,
            ),
            hir_array_lit_element_count: mk(
                "rb.parser.hir_item_records.hir_array_lit_element_count",
                bufs.hir_array_lit_element_count.byte_size as u64,
            ),
            hir_array_lit_context_stmt_node: mk(
                "rb.parser.hir_item_records.hir_array_lit_context_stmt_node",
                bufs.hir_array_lit_context_stmt_node.byte_size as u64,
            ),
            hir_array_element_parent_lit: mk(
                "rb.parser.hir_item_records.hir_array_element_parent_lit",
                bufs.hir_array_element_parent_lit.byte_size as u64,
            ),
            hir_array_element_ordinal: mk(
                "rb.parser.hir_item_records.hir_array_element_ordinal",
                bufs.hir_array_element_ordinal.byte_size as u64,
            ),
            hir_array_element_next: mk(
                "rb.parser.hir_item_records.hir_array_element_next",
                bufs.hir_array_element_next.byte_size as u64,
            ),
            hir_expr_string_start: mk(
                "rb.parser.hir_item_records.hir_expr_string_start",
                bufs.hir_expr_string_start.byte_size as u64,
            ),
            hir_expr_string_len: mk(
                "rb.parser.hir_item_records.hir_expr_string_len",
                bufs.hir_expr_string_len.byte_size as u64,
            ),
            hir_member_receiver_node: mk(
                "rb.parser.hir_item_records.hir_member_receiver_node",
                bufs.hir_member_receiver_node.byte_size as u64,
            ),
            hir_member_receiver_token: mk(
                "rb.parser.hir_item_records.hir_member_receiver_token",
                bufs.hir_member_receiver_token.byte_size as u64,
            ),
            hir_member_name_token: mk(
                "rb.parser.hir_item_records.hir_member_name_token",
                bufs.hir_member_name_token.byte_size as u64,
            ),
            hir_stmt_record: mk(
                "rb.parser.hir_item_records.hir_stmt_record",
                bufs.hir_stmt_record.byte_size as u64,
            ),
            hir_stmt_scope_end: mk(
                "rb.parser.hir_item_records.hir_stmt_scope_end",
                bufs.hir_stmt_scope_end.byte_size as u64,
            ),
            hir_nearest_stmt_node: mk(
                "rb.parser.hir_item_records.hir_nearest_stmt_node",
                bufs.hir_nearest_stmt_node.byte_size as u64,
            ),
            hir_nearest_block_node: mk(
                "rb.parser.hir_item_records.hir_nearest_block_node",
                bufs.hir_nearest_block_node.byte_size as u64,
            ),
            hir_nearest_enclosing_control_node: mk(
                "rb.parser.hir_item_records.hir_nearest_enclosing_control_node",
                bufs.hir_nearest_enclosing_control_node.byte_size as u64,
            ),
            hir_nearest_loop_node: mk(
                "rb.parser.hir_item_records.hir_nearest_loop_node",
                bufs.hir_nearest_loop_node.byte_size as u64,
            ),
            hir_nearest_fn_node: mk(
                "rb.parser.hir_item_records.hir_nearest_fn_node",
                bufs.hir_nearest_fn_node.byte_size as u64,
            ),
            hir_struct_field_parent_struct: mk(
                "rb.parser.hir_item_records.hir_struct_field_parent_struct",
                bufs.hir_struct_field_parent_struct.byte_size as u64,
            ),
            hir_struct_field_ordinal: mk(
                "rb.parser.hir_item_records.hir_struct_field_ordinal",
                bufs.hir_struct_field_ordinal.byte_size as u64,
            ),
            hir_struct_field_type_node: mk(
                "rb.parser.hir_item_records.hir_struct_field_type_node",
                bufs.hir_struct_field_type_node.byte_size as u64,
            ),
            hir_struct_decl_field_start: mk(
                "rb.parser.hir_item_records.hir_struct_decl_field_start",
                bufs.hir_struct_decl_field_start.byte_size as u64,
            ),
            hir_struct_decl_field_count: mk(
                "rb.parser.hir_item_records.hir_struct_decl_field_count",
                bufs.hir_struct_decl_field_count.byte_size as u64,
            ),
            hir_struct_lit_head_node: mk(
                "rb.parser.hir_item_records.hir_struct_lit_head_node",
                bufs.hir_struct_lit_head_node.byte_size as u64,
            ),
            hir_struct_lit_context_stmt_node: mk(
                "rb.parser.hir_item_records.hir_struct_lit_context_stmt_node",
                bufs.hir_struct_lit_context_stmt_node.byte_size as u64,
            ),
            hir_struct_lit_field_start: mk(
                "rb.parser.hir_item_records.hir_struct_lit_field_start",
                bufs.hir_struct_lit_field_start.byte_size as u64,
            ),
            hir_struct_lit_field_count: mk(
                "rb.parser.hir_item_records.hir_struct_lit_field_count",
                bufs.hir_struct_lit_field_count.byte_size as u64,
            ),
            hir_struct_lit_field_parent_lit: mk(
                "rb.parser.hir_item_records.hir_struct_lit_field_parent_lit",
                bufs.hir_struct_lit_field_parent_lit.byte_size as u64,
            ),
            hir_struct_lit_field_value_node: mk(
                "rb.parser.hir_item_records.hir_struct_lit_field_value_node",
                bufs.hir_struct_lit_field_value_node.byte_size as u64,
            ),
            hir_struct_lit_field_next: mk(
                "rb.parser.hir_item_records.hir_struct_lit_field_next",
                bufs.hir_struct_lit_field_next.byte_size as u64,
            ),
        }
    }

    /// Encodes copies for parser-owned HIR item and aggregate readback.
    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &self.ll1_status,
            0,
            bufs.ll1_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.node_kind,
            0,
            &self.node_kind,
            0,
            bufs.node_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_kind,
            0,
            &self.hir_kind,
            0,
            bufs.hir_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_pos,
            0,
            &self.hir_token_pos,
            0,
            bufs.hir_token_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_end,
            0,
            &self.hir_token_end,
            0,
            bufs.hir_token_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_token_file_id,
            0,
            &self.hir_node_file_id,
            0,
            bufs.hir_token_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_dense_node,
            0,
            &self.hir_semantic_dense_node,
            0,
            bufs.hir_semantic_dense_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_parent,
            0,
            &self.hir_semantic_parent,
            0,
            bufs.hir_semantic_parent.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_first_child,
            0,
            &self.hir_semantic_first_child,
            0,
            bufs.hir_semantic_first_child.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_next_sibling,
            0,
            &self.hir_semantic_next_sibling,
            0,
            bufs.hir_semantic_next_sibling.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_depth,
            0,
            &self.hir_semantic_depth,
            0,
            bufs.hir_semantic_depth.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_child_index,
            0,
            &self.hir_semantic_child_index,
            0,
            bufs.hir_semantic_child_index.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_form,
            0,
            &self.hir_type_form,
            0,
            bufs.hir_type_form.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_value_node,
            0,
            &self.hir_type_value_node,
            0,
            bufs.hir_type_value_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_len_token,
            0,
            &self.hir_type_len_token,
            0,
            bufs.hir_type_len_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_len_value,
            0,
            &self.hir_type_len_value,
            0,
            bufs.hir_type_len_value.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_file_id,
            0,
            &self.hir_type_file_id,
            0,
            bufs.hir_type_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_path_leaf_node,
            0,
            &self.hir_type_path_leaf_node,
            0,
            bufs.hir_type_path_leaf_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_arg_start,
            0,
            &self.hir_type_arg_start,
            0,
            bufs.hir_type_arg_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_arg_count,
            0,
            &self.hir_type_arg_count,
            0,
            bufs.hir_type_arg_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_arg_next,
            0,
            &self.hir_type_arg_next,
            0,
            bufs.hir_type_arg_next.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_alias_target_node,
            0,
            &self.hir_type_alias_target_node,
            0,
            bufs.hir_type_alias_target_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_fn_return_type_node,
            0,
            &self.hir_fn_return_type_node,
            0,
            bufs.hir_fn_return_type_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_kind,
            0,
            &self.hir_item_kind,
            0,
            bufs.hir_item_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_name_token,
            0,
            &self.hir_item_name_token,
            0,
            bufs.hir_item_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_decl_token,
            0,
            &self.hir_item_decl_token,
            0,
            bufs.hir_item_decl_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_namespace,
            0,
            &self.hir_item_namespace,
            0,
            bufs.hir_item_namespace.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_visibility,
            0,
            &self.hir_item_visibility,
            0,
            bufs.hir_item_visibility.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_path_start,
            0,
            &self.hir_item_path_start,
            0,
            bufs.hir_item_path_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_path_end,
            0,
            &self.hir_item_path_end,
            0,
            bufs.hir_item_path_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_path_node,
            0,
            &self.hir_item_path_node,
            0,
            bufs.hir_item_path_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_file_id,
            0,
            &self.hir_item_file_id,
            0,
            bufs.hir_item_file_id.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_item_import_target_kind,
            0,
            &self.hir_item_import_target_kind,
            0,
            bufs.hir_item_import_target_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_parent_enum,
            0,
            &self.hir_variant_parent_enum,
            0,
            bufs.hir_variant_parent_enum.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_ordinal,
            0,
            &self.hir_variant_ordinal,
            0,
            bufs.hir_variant_ordinal.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_payload_start,
            0,
            &self.hir_variant_payload_start,
            0,
            bufs.hir_variant_payload_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_payload_count,
            0,
            &self.hir_variant_payload_count,
            0,
            bufs.hir_variant_payload_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_variant_payload_node,
            0,
            &self.hir_variant_payload_node,
            0,
            bufs.hir_variant_payload_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_param_record,
            0,
            &self.hir_param_record,
            0,
            bufs.hir_param_record.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_param_type_node,
            0,
            &self.hir_param_type_node,
            0,
            bufs.hir_param_type_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_owner_node,
            0,
            &self.hir_method_owner_node,
            0,
            bufs.hir_method_owner_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_impl_node,
            0,
            &self.hir_method_impl_node,
            0,
            bufs.hir_method_impl_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_name_token,
            0,
            &self.hir_method_name_token,
            0,
            bufs.hir_method_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_first_param_token,
            0,
            &self.hir_method_first_param_token,
            0,
            bufs.hir_method_first_param_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_receiver_mode,
            0,
            &self.hir_method_receiver_mode,
            0,
            bufs.hir_method_receiver_mode.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_visibility,
            0,
            &self.hir_method_visibility,
            0,
            bufs.hir_method_visibility.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_signature_flags,
            0,
            &self.hir_method_signature_flags,
            0,
            bufs.hir_method_signature_flags.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_method_impl_receiver_type_node,
            0,
            &self.hir_method_impl_receiver_type_node,
            0,
            bufs.hir_method_impl_receiver_type_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_expr_record,
            0,
            &self.hir_expr_record,
            0,
            bufs.hir_expr_record.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_scrutinee_node,
            0,
            &self.hir_match_scrutinee_node,
            0,
            bufs.hir_match_scrutinee_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_start,
            0,
            &self.hir_match_arm_start,
            0,
            bufs.hir_match_arm_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_count,
            0,
            &self.hir_match_arm_count,
            0,
            bufs.hir_match_arm_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_next,
            0,
            &self.hir_match_arm_next,
            0,
            bufs.hir_match_arm_next.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_pattern_node,
            0,
            &self.hir_match_arm_pattern_node,
            0,
            bufs.hir_match_arm_pattern_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_payload_start,
            0,
            &self.hir_match_arm_payload_start,
            0,
            bufs.hir_match_arm_payload_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_payload_count,
            0,
            &self.hir_match_arm_payload_count,
            0,
            bufs.hir_match_arm_payload_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_arm_result_node,
            0,
            &self.hir_match_arm_result_node,
            0,
            bufs.hir_match_arm_result_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_payload_owner_arm,
            0,
            &self.hir_match_payload_owner_arm,
            0,
            bufs.hir_match_payload_owner_arm.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_payload_match_node,
            0,
            &self.hir_match_payload_match_node,
            0,
            bufs.hir_match_payload_match_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_match_payload_ordinal,
            0,
            &self.hir_match_payload_ordinal,
            0,
            bufs.hir_match_payload_ordinal.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_callee_node,
            0,
            &self.hir_call_callee_node,
            0,
            bufs.hir_call_callee_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_arg_start,
            0,
            &self.hir_call_arg_start,
            0,
            bufs.hir_call_arg_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_arg_end,
            0,
            &self.hir_call_arg_end,
            0,
            bufs.hir_call_arg_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_arg_count,
            0,
            &self.hir_call_arg_count,
            0,
            bufs.hir_call_arg_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_arg_parent_call,
            0,
            &self.hir_call_arg_parent_call,
            0,
            bufs.hir_call_arg_parent_call.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_arg_ordinal,
            0,
            &self.hir_call_arg_ordinal,
            0,
            bufs.hir_call_arg_ordinal.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_lit_first_element,
            0,
            &self.hir_array_lit_first_element,
            0,
            bufs.hir_array_lit_first_element.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_lit_element_count,
            0,
            &self.hir_array_lit_element_count,
            0,
            bufs.hir_array_lit_element_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_element_parent_lit,
            0,
            &self.hir_array_element_parent_lit,
            0,
            bufs.hir_array_element_parent_lit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_element_ordinal,
            0,
            &self.hir_array_element_ordinal,
            0,
            bufs.hir_array_element_ordinal.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_element_next,
            0,
            &self.hir_array_element_next,
            0,
            bufs.hir_array_element_next.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_expr_string_start,
            0,
            &self.hir_expr_string_start,
            0,
            bufs.hir_expr_string_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_expr_string_len,
            0,
            &self.hir_expr_string_len,
            0,
            bufs.hir_expr_string_len.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_member_receiver_node,
            0,
            &self.hir_member_receiver_node,
            0,
            bufs.hir_member_receiver_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_member_receiver_token,
            0,
            &self.hir_member_receiver_token,
            0,
            bufs.hir_member_receiver_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_member_name_token,
            0,
            &self.hir_member_name_token,
            0,
            bufs.hir_member_name_token.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_stmt_record,
            0,
            &self.hir_stmt_record,
            0,
            bufs.hir_stmt_record.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_stmt_scope_end,
            0,
            &self.hir_stmt_scope_end,
            0,
            bufs.hir_stmt_scope_end.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_nearest_stmt_node,
            0,
            &self.hir_nearest_stmt_node,
            0,
            bufs.hir_nearest_stmt_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_nearest_block_node,
            0,
            &self.hir_nearest_block_node,
            0,
            bufs.hir_nearest_block_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_nearest_enclosing_control_node,
            0,
            &self.hir_nearest_enclosing_control_node,
            0,
            bufs.hir_nearest_enclosing_control_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_nearest_loop_node,
            0,
            &self.hir_nearest_loop_node,
            0,
            bufs.hir_nearest_loop_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_nearest_fn_node,
            0,
            &self.hir_nearest_fn_node,
            0,
            bufs.hir_nearest_fn_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_call_context_stmt_node,
            0,
            &self.hir_call_context_stmt_node,
            0,
            bufs.hir_call_context_stmt_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_array_lit_context_stmt_node,
            0,
            &self.hir_array_lit_context_stmt_node,
            0,
            bufs.hir_array_lit_context_stmt_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_field_parent_struct,
            0,
            &self.hir_struct_field_parent_struct,
            0,
            bufs.hir_struct_field_parent_struct.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_field_ordinal,
            0,
            &self.hir_struct_field_ordinal,
            0,
            bufs.hir_struct_field_ordinal.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_field_type_node,
            0,
            &self.hir_struct_field_type_node,
            0,
            bufs.hir_struct_field_type_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_decl_field_start,
            0,
            &self.hir_struct_decl_field_start,
            0,
            bufs.hir_struct_decl_field_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_decl_field_count,
            0,
            &self.hir_struct_decl_field_count,
            0,
            bufs.hir_struct_decl_field_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_head_node,
            0,
            &self.hir_struct_lit_head_node,
            0,
            bufs.hir_struct_lit_head_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_context_stmt_node,
            0,
            &self.hir_struct_lit_context_stmt_node,
            0,
            bufs.hir_struct_lit_context_stmt_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_start,
            0,
            &self.hir_struct_lit_field_start,
            0,
            bufs.hir_struct_lit_field_start.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_count,
            0,
            &self.hir_struct_lit_field_count,
            0,
            bufs.hir_struct_lit_field_count.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_parent_lit,
            0,
            &self.hir_struct_lit_field_parent_lit,
            0,
            bufs.hir_struct_lit_field_parent_lit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_value_node,
            0,
            &self.hir_struct_lit_field_value_node,
            0,
            bufs.hir_struct_lit_field_value_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_next,
            0,
            &self.hir_struct_lit_field_next,
            0,
            bufs.hir_struct_lit_field_next.byte_size as u64,
        );
    }

    /// Maps and decodes parser-owned HIR item and aggregate readback data.
    pub fn map_and_decode(
        self,
        device: &wgpu::Device,
        bufs: &ParserBuffers,
    ) -> Result<DecodedParserHirItemReadbacks> {
        let map = |name: &str, b: &wgpu::Buffer| {
            crate::gpu::passes_core::map_readback_for_progress(
                &b.slice(..),
                &format!("parser.hir_item_readback.{name}"),
            );
        };
        map("ll1_status", &self.ll1_status);
        map("node_kind", &self.node_kind);
        map("hir_kind", &self.hir_kind);
        map("hir_token_pos", &self.hir_token_pos);
        map("hir_token_end", &self.hir_token_end);
        map("hir_node_file_id", &self.hir_node_file_id);
        map("hir_semantic_dense_node", &self.hir_semantic_dense_node);
        map("hir_semantic_parent", &self.hir_semantic_parent);
        map("hir_semantic_first_child", &self.hir_semantic_first_child);
        map("hir_semantic_next_sibling", &self.hir_semantic_next_sibling);
        map("hir_semantic_depth", &self.hir_semantic_depth);
        map("hir_semantic_child_index", &self.hir_semantic_child_index);
        map("hir_type_form", &self.hir_type_form);
        map("hir_type_value_node", &self.hir_type_value_node);
        map("hir_type_len_token", &self.hir_type_len_token);
        map("hir_type_len_value", &self.hir_type_len_value);
        map("hir_type_file_id", &self.hir_type_file_id);
        map("hir_type_path_leaf_node", &self.hir_type_path_leaf_node);
        map("hir_type_arg_start", &self.hir_type_arg_start);
        map("hir_type_arg_count", &self.hir_type_arg_count);
        map("hir_type_arg_next", &self.hir_type_arg_next);
        map(
            "hir_type_alias_target_node",
            &self.hir_type_alias_target_node,
        );
        map("hir_fn_return_type_node", &self.hir_fn_return_type_node);
        map("hir_item_kind", &self.hir_item_kind);
        map("hir_item_name_token", &self.hir_item_name_token);
        map("hir_item_decl_token", &self.hir_item_decl_token);
        map("hir_item_namespace", &self.hir_item_namespace);
        map("hir_item_visibility", &self.hir_item_visibility);
        map("hir_item_path_start", &self.hir_item_path_start);
        map("hir_item_path_end", &self.hir_item_path_end);
        map("hir_item_path_node", &self.hir_item_path_node);
        map("hir_item_file_id", &self.hir_item_file_id);
        map(
            "hir_item_import_target_kind",
            &self.hir_item_import_target_kind,
        );
        map("hir_variant_parent_enum", &self.hir_variant_parent_enum);
        map("hir_variant_ordinal", &self.hir_variant_ordinal);
        map("hir_variant_payload_start", &self.hir_variant_payload_start);
        map("hir_variant_payload_count", &self.hir_variant_payload_count);
        map("hir_variant_payload_node", &self.hir_variant_payload_node);
        map("hir_param_record", &self.hir_param_record);
        map("hir_param_type_node", &self.hir_param_type_node);
        map("hir_method_owner_node", &self.hir_method_owner_node);
        map("hir_method_impl_node", &self.hir_method_impl_node);
        map("hir_method_name_token", &self.hir_method_name_token);
        map(
            "hir_method_first_param_token",
            &self.hir_method_first_param_token,
        );
        map("hir_method_receiver_mode", &self.hir_method_receiver_mode);
        map("hir_method_visibility", &self.hir_method_visibility);
        map(
            "hir_method_signature_flags",
            &self.hir_method_signature_flags,
        );
        map(
            "hir_method_impl_receiver_type_node",
            &self.hir_method_impl_receiver_type_node,
        );
        map("hir_expr_record", &self.hir_expr_record);
        map("hir_match_scrutinee_node", &self.hir_match_scrutinee_node);
        map("hir_match_arm_start", &self.hir_match_arm_start);
        map("hir_match_arm_count", &self.hir_match_arm_count);
        map("hir_match_arm_next", &self.hir_match_arm_next);
        map(
            "hir_match_arm_pattern_node",
            &self.hir_match_arm_pattern_node,
        );
        map(
            "hir_match_arm_payload_start",
            &self.hir_match_arm_payload_start,
        );
        map(
            "hir_match_arm_payload_count",
            &self.hir_match_arm_payload_count,
        );
        map("hir_match_arm_result_node", &self.hir_match_arm_result_node);
        map(
            "hir_match_payload_owner_arm",
            &self.hir_match_payload_owner_arm,
        );
        map(
            "hir_match_payload_match_node",
            &self.hir_match_payload_match_node,
        );
        map("hir_match_payload_ordinal", &self.hir_match_payload_ordinal);
        map("hir_call_callee_node", &self.hir_call_callee_node);
        map(
            "hir_call_context_stmt_node",
            &self.hir_call_context_stmt_node,
        );
        map("hir_call_arg_start", &self.hir_call_arg_start);
        map("hir_call_arg_end", &self.hir_call_arg_end);
        map("hir_call_arg_count", &self.hir_call_arg_count);
        map("hir_call_arg_parent_call", &self.hir_call_arg_parent_call);
        map("hir_call_arg_ordinal", &self.hir_call_arg_ordinal);
        map(
            "hir_array_lit_first_element",
            &self.hir_array_lit_first_element,
        );
        map(
            "hir_array_lit_element_count",
            &self.hir_array_lit_element_count,
        );
        map(
            "hir_array_lit_context_stmt_node",
            &self.hir_array_lit_context_stmt_node,
        );
        map(
            "hir_array_element_parent_lit",
            &self.hir_array_element_parent_lit,
        );
        map("hir_array_element_ordinal", &self.hir_array_element_ordinal);
        map("hir_array_element_next", &self.hir_array_element_next);
        map("hir_expr_string_start", &self.hir_expr_string_start);
        map("hir_expr_string_len", &self.hir_expr_string_len);
        map("hir_member_receiver_node", &self.hir_member_receiver_node);
        map("hir_member_receiver_token", &self.hir_member_receiver_token);
        map("hir_member_name_token", &self.hir_member_name_token);
        map("hir_stmt_record", &self.hir_stmt_record);
        map("hir_stmt_scope_end", &self.hir_stmt_scope_end);
        map("hir_nearest_stmt_node", &self.hir_nearest_stmt_node);
        map("hir_nearest_block_node", &self.hir_nearest_block_node);
        map(
            "hir_nearest_enclosing_control_node",
            &self.hir_nearest_enclosing_control_node,
        );
        map("hir_nearest_loop_node", &self.hir_nearest_loop_node);
        map("hir_nearest_fn_node", &self.hir_nearest_fn_node);
        map(
            "hir_struct_field_parent_struct",
            &self.hir_struct_field_parent_struct,
        );
        map("hir_struct_field_ordinal", &self.hir_struct_field_ordinal);
        map(
            "hir_struct_field_type_node",
            &self.hir_struct_field_type_node,
        );
        map(
            "hir_struct_decl_field_start",
            &self.hir_struct_decl_field_start,
        );
        map(
            "hir_struct_decl_field_count",
            &self.hir_struct_decl_field_count,
        );
        map("hir_struct_lit_head_node", &self.hir_struct_lit_head_node);
        map(
            "hir_struct_lit_context_stmt_node",
            &self.hir_struct_lit_context_stmt_node,
        );
        map(
            "hir_struct_lit_field_start",
            &self.hir_struct_lit_field_start,
        );
        map(
            "hir_struct_lit_field_count",
            &self.hir_struct_lit_field_count,
        );
        map(
            "hir_struct_lit_field_parent_lit",
            &self.hir_struct_lit_field_parent_lit,
        );
        map(
            "hir_struct_lit_field_value_node",
            &self.hir_struct_lit_field_value_node,
        );
        map("hir_struct_lit_field_next", &self.hir_struct_lit_field_next);

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.hir_item_readback",
            wgpu::PollType::wait_indefinitely(),
        );

        let ll1_status = read_u32_array::<6>(&self.ll1_status, "ll1_status")?;
        let tree_len = active_tree_readback_len(
            "hir_item_readback.tree",
            bufs.tree_count_uses_status,
            ll1_status[5],
            bufs.total_emit,
            bufs.hir_kind.count,
        )?;
        let hir_param_record_words =
            read_u32_vec(&self.hir_param_record, tree_len.saturating_mul(4));
        let mut hir_param_owner_fn_node = Vec::with_capacity(tree_len);
        let mut hir_param_ordinal = Vec::with_capacity(tree_len);
        let mut hir_param_name_token = Vec::with_capacity(tree_len);
        let mut hir_param_record_node = Vec::with_capacity(tree_len);
        for node in 0..tree_len {
            let base = node * 4;
            hir_param_owner_fn_node.push(*hir_param_record_words.get(base).unwrap_or(&u32::MAX));
            hir_param_ordinal.push(*hir_param_record_words.get(base + 1).unwrap_or(&u32::MAX));
            hir_param_name_token.push(*hir_param_record_words.get(base + 2).unwrap_or(&u32::MAX));
            hir_param_record_node.push(*hir_param_record_words.get(base + 3).unwrap_or(&u32::MAX));
        }
        let hir_expr_record_words = read_u32_vec(&self.hir_expr_record, tree_len.saturating_mul(4));
        let mut hir_expr_record_form = Vec::with_capacity(tree_len);
        let mut hir_expr_record_left = Vec::with_capacity(tree_len);
        let mut hir_expr_record_right = Vec::with_capacity(tree_len);
        let mut hir_expr_record_value_token = Vec::with_capacity(tree_len);
        for node in 0..tree_len {
            let base = node * 4;
            hir_expr_record_form.push(*hir_expr_record_words.get(base).unwrap_or(&u32::MAX));
            hir_expr_record_left.push(*hir_expr_record_words.get(base + 1).unwrap_or(&u32::MAX));
            hir_expr_record_right.push(*hir_expr_record_words.get(base + 2).unwrap_or(&u32::MAX));
            hir_expr_record_value_token
                .push(*hir_expr_record_words.get(base + 3).unwrap_or(&u32::MAX));
        }
        let hir_call_arg_parent_call = read_u32_vec(&self.hir_call_arg_parent_call, tree_len);
        let hir_call_arg_ordinal = read_u32_vec(&self.hir_call_arg_ordinal, tree_len);
        let hir_stmt_record_words = read_u32_vec(&self.hir_stmt_record, tree_len.saturating_mul(4));
        let mut hir_stmt_record_kind = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand0 = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand1 = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand2 = Vec::with_capacity(tree_len);
        for node in 0..tree_len {
            let base = node * 4;
            hir_stmt_record_kind.push(*hir_stmt_record_words.get(base).unwrap_or(&u32::MAX));
            hir_stmt_record_operand0
                .push(*hir_stmt_record_words.get(base + 1).unwrap_or(&u32::MAX));
            hir_stmt_record_operand1
                .push(*hir_stmt_record_words.get(base + 2).unwrap_or(&u32::MAX));
            hir_stmt_record_operand2
                .push(*hir_stmt_record_words.get(base + 3).unwrap_or(&u32::MAX));
        }
        let hir_variant_payload_count =
            read_u32_vec_padded(&self.hir_variant_payload_count, tree_len, 0);

        let decoded = DecodedParserHirItemReadbacks {
            ll1_status,
            node_kind: read_u32_vec(&self.node_kind, tree_len),
            hir_kind: read_u32_vec(&self.hir_kind, tree_len),
            hir_token_pos: read_u32_vec(&self.hir_token_pos, tree_len),
            hir_token_end: read_u32_vec(&self.hir_token_end, tree_len),
            hir_node_file_id: read_u32_vec(&self.hir_node_file_id, tree_len),
            hir_semantic_dense_node: read_u32_vec(&self.hir_semantic_dense_node, tree_len),
            hir_semantic_parent: read_u32_vec(&self.hir_semantic_parent, tree_len),
            hir_semantic_first_child: read_u32_vec(&self.hir_semantic_first_child, tree_len),
            hir_semantic_next_sibling: read_u32_vec(&self.hir_semantic_next_sibling, tree_len),
            hir_semantic_depth: read_u32_vec(&self.hir_semantic_depth, tree_len),
            hir_semantic_child_index: read_u32_vec(&self.hir_semantic_child_index, tree_len),
            hir_type_form: read_u32_vec(&self.hir_type_form, tree_len),
            hir_type_value_node: read_u32_vec(&self.hir_type_value_node, tree_len),
            hir_type_len_token: read_u32_vec(&self.hir_type_len_token, tree_len),
            hir_type_len_value: read_u32_vec(&self.hir_type_len_value, tree_len),
            hir_type_file_id: read_u32_vec(&self.hir_type_file_id, tree_len),
            hir_type_path_leaf_node: read_u32_vec(&self.hir_type_path_leaf_node, tree_len),
            hir_type_arg_start: read_u32_vec(&self.hir_type_arg_start, tree_len),
            hir_type_arg_count: read_u32_vec(&self.hir_type_arg_count, tree_len),
            hir_type_arg_next: read_u32_vec(&self.hir_type_arg_next, tree_len),
            hir_type_alias_target_node: read_u32_vec(&self.hir_type_alias_target_node, tree_len),
            hir_fn_return_type_node: read_u32_vec(&self.hir_fn_return_type_node, tree_len),
            hir_item_kind: read_u32_vec(&self.hir_item_kind, tree_len),
            hir_item_name_token: read_u32_vec(&self.hir_item_name_token, tree_len),
            hir_item_decl_token: read_u32_vec(&self.hir_item_decl_token, tree_len),
            hir_item_namespace: read_u32_vec(&self.hir_item_namespace, tree_len),
            hir_item_visibility: read_u32_vec(&self.hir_item_visibility, tree_len),
            hir_item_path_start: read_u32_vec(&self.hir_item_path_start, tree_len),
            hir_item_path_end: read_u32_vec(&self.hir_item_path_end, tree_len),
            hir_item_path_node: read_u32_vec(&self.hir_item_path_node, tree_len),
            hir_item_file_id: read_u32_vec(&self.hir_item_file_id, tree_len),
            hir_item_import_target_kind: read_u32_vec(&self.hir_item_import_target_kind, tree_len),
            hir_variant_parent_enum: read_u32_vec_padded(
                &self.hir_variant_parent_enum,
                tree_len,
                u32::MAX,
            ),
            hir_variant_ordinal: read_u32_vec_padded(&self.hir_variant_ordinal, tree_len, u32::MAX),
            hir_variant_payload_start: read_u32_vec_padded(
                &self.hir_variant_payload_start,
                tree_len,
                u32::MAX,
            ),
            hir_variant_payload_count,
            hir_variant_payload_node: read_u32_vec_padded(
                &self.hir_variant_payload_node,
                tree_len.saturating_mul(HIR_VARIANT_PAYLOAD_SLOT_STRIDE as usize),
                u32::MAX,
            ),
            hir_param_owner_fn_node,
            hir_param_ordinal,
            hir_param_name_token,
            hir_param_record_node,
            hir_param_type_node: read_u32_vec(&self.hir_param_type_node, tree_len),
            hir_method_owner_node: read_u32_vec(&self.hir_method_owner_node, tree_len),
            hir_method_impl_node: read_u32_vec(&self.hir_method_impl_node, tree_len),
            hir_method_name_token: read_u32_vec(&self.hir_method_name_token, tree_len),
            hir_method_first_param_token: read_u32_vec(
                &self.hir_method_first_param_token,
                tree_len,
            ),
            hir_method_receiver_mode: read_u32_vec(&self.hir_method_receiver_mode, tree_len),
            hir_method_visibility: read_u32_vec(&self.hir_method_visibility, tree_len),
            hir_method_signature_flags: read_u32_vec(&self.hir_method_signature_flags, tree_len),
            hir_method_impl_receiver_type_node: read_u32_vec(
                &self.hir_method_impl_receiver_type_node,
                tree_len,
            ),
            hir_expr_record_form,
            hir_expr_record_left,
            hir_expr_record_right,
            hir_expr_record_value_token,
            hir_match_scrutinee_node: read_u32_vec_padded(
                &self.hir_match_scrutinee_node,
                tree_len,
                u32::MAX,
            ),
            hir_match_arm_start: read_u32_vec_padded(&self.hir_match_arm_start, tree_len, u32::MAX),
            hir_match_arm_count: read_u32_vec_padded(&self.hir_match_arm_count, tree_len, 0),
            hir_match_arm_next: read_u32_vec_padded(&self.hir_match_arm_next, tree_len, u32::MAX),
            hir_match_arm_pattern_node: read_u32_vec_padded(
                &self.hir_match_arm_pattern_node,
                tree_len,
                u32::MAX,
            ),
            hir_match_arm_payload_start: read_u32_vec_padded(
                &self.hir_match_arm_payload_start,
                tree_len,
                u32::MAX,
            ),
            hir_match_arm_payload_count: read_u32_vec_padded(
                &self.hir_match_arm_payload_count,
                tree_len,
                0,
            ),
            hir_match_arm_result_node: read_u32_vec_padded(
                &self.hir_match_arm_result_node,
                tree_len,
                u32::MAX,
            ),
            hir_match_payload_owner_arm: read_u32_vec_padded(
                &self.hir_match_payload_owner_arm,
                tree_len,
                u32::MAX,
            ),
            hir_match_payload_match_node: read_u32_vec_padded(
                &self.hir_match_payload_match_node,
                tree_len,
                u32::MAX,
            ),
            hir_match_payload_ordinal: read_u32_vec_padded(
                &self.hir_match_payload_ordinal,
                tree_len,
                u32::MAX,
            ),
            hir_call_callee_node: read_u32_vec(&self.hir_call_callee_node, tree_len),
            hir_call_context_stmt_node: read_u32_vec(&self.hir_call_context_stmt_node, tree_len),
            hir_call_arg_start: read_u32_vec(&self.hir_call_arg_start, tree_len),
            hir_call_arg_end: read_u32_vec(&self.hir_call_arg_end, tree_len),
            hir_call_arg_count: read_u32_vec(&self.hir_call_arg_count, tree_len),
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_array_lit_first_element: read_u32_vec_padded(
                &self.hir_array_lit_first_element,
                tree_len,
                u32::MAX,
            ),
            hir_array_lit_element_count: read_u32_vec_padded(
                &self.hir_array_lit_element_count,
                tree_len,
                0,
            ),
            hir_array_lit_context_stmt_node: read_u32_vec_padded(
                &self.hir_array_lit_context_stmt_node,
                tree_len,
                u32::MAX,
            ),
            hir_array_element_parent_lit: read_u32_vec_padded(
                &self.hir_array_element_parent_lit,
                tree_len,
                u32::MAX,
            ),
            hir_array_element_ordinal: read_u32_vec_padded(
                &self.hir_array_element_ordinal,
                tree_len,
                u32::MAX,
            ),
            hir_array_element_next: read_u32_vec_padded(
                &self.hir_array_element_next,
                tree_len,
                u32::MAX,
            ),
            hir_expr_string_start: read_u32_vec(&self.hir_expr_string_start, tree_len),
            hir_expr_string_len: read_u32_vec(&self.hir_expr_string_len, tree_len),
            hir_member_receiver_node: read_u32_vec(&self.hir_member_receiver_node, tree_len),
            hir_member_receiver_token: read_u32_vec(&self.hir_member_receiver_token, tree_len),
            hir_member_name_token: read_u32_vec(&self.hir_member_name_token, tree_len),
            hir_stmt_record_kind,
            hir_stmt_record_operand0,
            hir_stmt_record_operand1,
            hir_stmt_record_operand2,
            hir_stmt_scope_end: read_u32_vec(&self.hir_stmt_scope_end, tree_len),
            hir_nearest_stmt_node: read_u32_vec(&self.hir_nearest_stmt_node, tree_len),
            hir_nearest_block_node: read_u32_vec(&self.hir_nearest_block_node, tree_len),
            hir_nearest_enclosing_control_node: read_u32_vec(
                &self.hir_nearest_enclosing_control_node,
                tree_len,
            ),
            hir_nearest_loop_node: read_u32_vec(&self.hir_nearest_loop_node, tree_len),
            hir_nearest_fn_node: read_u32_vec(&self.hir_nearest_fn_node, tree_len),
            hir_struct_field_parent_struct: read_u32_vec_padded(
                &self.hir_struct_field_parent_struct,
                tree_len,
                u32::MAX,
            ),
            hir_struct_field_ordinal: read_u32_vec_padded(
                &self.hir_struct_field_ordinal,
                tree_len,
                u32::MAX,
            ),
            hir_struct_field_type_node: read_u32_vec_padded(
                &self.hir_struct_field_type_node,
                tree_len,
                u32::MAX,
            ),
            hir_struct_decl_field_start: read_u32_vec_padded(
                &self.hir_struct_decl_field_start,
                tree_len,
                u32::MAX,
            ),
            hir_struct_decl_field_count: read_u32_vec_padded(
                &self.hir_struct_decl_field_count,
                tree_len,
                0,
            ),
            hir_struct_lit_head_node: read_u32_vec_padded(
                &self.hir_struct_lit_head_node,
                tree_len,
                u32::MAX,
            ),
            hir_struct_lit_context_stmt_node: read_u32_vec_padded(
                &self.hir_struct_lit_context_stmt_node,
                tree_len,
                u32::MAX,
            ),
            hir_struct_lit_field_start: read_u32_vec_padded(
                &self.hir_struct_lit_field_start,
                tree_len,
                u32::MAX,
            ),
            hir_struct_lit_field_count: read_u32_vec_padded(
                &self.hir_struct_lit_field_count,
                tree_len,
                0,
            ),
            hir_struct_lit_field_parent_lit: read_u32_vec_padded(
                &self.hir_struct_lit_field_parent_lit,
                tree_len,
                u32::MAX,
            ),
            hir_struct_lit_field_value_node: read_u32_vec_padded(
                &self.hir_struct_lit_field_value_node,
                tree_len,
                u32::MAX,
            ),
            hir_struct_lit_field_next: read_u32_vec_padded(
                &self.hir_struct_lit_field_next,
                tree_len,
                u32::MAX,
            ),
        };
        validate_hir_source_address_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_file_id,
        )?;
        validate_hir_type_records_with_node_kinds(
            &decoded.node_kind,
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_value_node,
            &decoded.hir_type_len_token,
            &decoded.hir_type_len_value,
            &decoded.hir_type_file_id,
            &decoded.hir_type_path_leaf_node,
        )?;
        validate_hir_type_alias_target_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_item_file_id,
            &decoded.hir_type_alias_target_node,
        )?;
        validate_hir_item_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_item_namespace,
            &decoded.hir_item_visibility,
            &decoded.hir_item_file_id,
        )?;
        validate_hir_enum_variant_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_file_id,
            &decoded.hir_variant_parent_enum,
            &decoded.hir_variant_ordinal,
            &decoded.hir_variant_payload_start,
            &decoded.hir_variant_payload_count,
            &decoded.hir_variant_payload_node,
        )?;
        validate_hir_parameter_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_param_owner_fn_node,
            &decoded.hir_param_ordinal,
            &decoded.hir_param_name_token,
            &decoded.hir_param_record_node,
            &decoded.hir_param_type_node,
        )?;
        validate_hir_method_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_item_file_id,
            &decoded.hir_param_owner_fn_node,
            &decoded.hir_param_ordinal,
            &decoded.hir_param_name_token,
            &decoded.hir_param_type_node,
            &decoded.hir_method_owner_node,
            &decoded.hir_method_impl_node,
            &decoded.hir_method_name_token,
            &decoded.hir_method_first_param_token,
            &decoded.hir_method_receiver_mode,
            &decoded.hir_method_visibility,
            &decoded.hir_method_signature_flags,
            &decoded.hir_method_impl_receiver_type_node,
        )?;
        validate_hir_type_argument_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_arg_start,
            &decoded.hir_type_arg_count,
            &decoded.hir_type_arg_next,
        )?;
        validate_hir_call_argument_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_call_callee_node,
            &decoded.hir_call_arg_start,
            &decoded.hir_call_arg_end,
            &decoded.hir_call_arg_count,
            &decoded.hir_call_arg_parent_call,
            &decoded.hir_call_arg_ordinal,
        )?;
        validate_hir_array_literal_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_array_lit_first_element,
            &decoded.hir_array_lit_element_count,
            &decoded.hir_array_element_parent_lit,
            &decoded.hir_array_element_ordinal,
            &decoded.hir_array_element_next,
        )?;
        validate_hir_expression_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_expr_record_form,
            &decoded.hir_expr_record_left,
            &decoded.hir_expr_record_right,
            &decoded.hir_expr_record_value_token,
        )?;
        validate_hir_member_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_member_receiver_node,
            &decoded.hir_member_receiver_token,
            &decoded.hir_member_name_token,
        )?;
        validate_hir_match_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_match_scrutinee_node,
            &decoded.hir_match_arm_start,
            &decoded.hir_match_arm_count,
            &decoded.hir_match_arm_next,
            &decoded.hir_match_arm_pattern_node,
            &decoded.hir_match_arm_payload_start,
            &decoded.hir_match_arm_payload_count,
            &decoded.hir_match_arm_result_node,
            &decoded.hir_match_payload_owner_arm,
            &decoded.hir_match_payload_match_node,
            &decoded.hir_match_payload_ordinal,
        )?;
        validate_hir_statement_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_stmt_record_kind,
            &decoded.hir_stmt_record_operand0,
            &decoded.hir_stmt_record_operand1,
            &decoded.hir_stmt_record_operand2,
            &decoded.hir_stmt_scope_end,
        )?;
        validate_hir_const_item_statement_records(
            &decoded.hir_kind,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_stmt_record_kind,
            &decoded.hir_stmt_record_operand0,
        )?;
        validate_hir_context_relation_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_stmt_record_kind,
            &decoded.hir_nearest_stmt_node,
            &decoded.hir_nearest_block_node,
            &decoded.hir_nearest_enclosing_control_node,
            &decoded.hir_nearest_loop_node,
            &decoded.hir_nearest_fn_node,
            &decoded.hir_call_context_stmt_node,
            &decoded.hir_array_lit_context_stmt_node,
            &decoded.hir_struct_lit_context_stmt_node,
        )?;
        validate_hir_struct_literal_field_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_struct_lit_head_node,
            &decoded.hir_struct_lit_field_start,
            &decoded.hir_struct_lit_field_count,
            &decoded.hir_struct_lit_field_parent_lit,
            &decoded.hir_struct_lit_field_value_node,
            &decoded.hir_struct_lit_field_next,
        )?;
        validate_hir_struct_declaration_field_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_file_id,
            &decoded.hir_struct_field_parent_struct,
            &decoded.hir_struct_field_ordinal,
            &decoded.hir_struct_field_type_node,
            &decoded.hir_struct_decl_field_start,
            &decoded.hir_struct_decl_field_count,
        )?;
        validate_hir_function_return_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_type_form,
            &decoded.hir_type_file_id,
            &decoded.hir_fn_return_type_node,
            &decoded.hir_item_kind,
            &decoded.hir_item_name_token,
            &decoded.hir_item_file_id,
            &decoded.hir_method_signature_flags,
            &decoded.hir_method_name_token,
        )?;
        validate_hir_item_path_records(
            &decoded.hir_kind,
            &decoded.hir_token_pos,
            &decoded.hir_token_end,
            &decoded.hir_node_file_id,
            &decoded.hir_item_kind,
            &decoded.hir_item_file_id,
            &decoded.hir_item_path_start,
            &decoded.hir_item_path_end,
            &decoded.hir_item_path_node,
            &decoded.hir_item_import_target_kind,
        )?;
        Ok(decoded)
    }
}
