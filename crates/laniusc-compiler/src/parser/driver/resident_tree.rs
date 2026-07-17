use anyhow::Result;

use super::{
    GpuParser,
    Ll1AcceptResult,
    ResidentParseResult,
    support::{bool_from_env, read_u32_words},
};
use crate::parser::{
    buffers::ParserBuffers,
    readback::{
        validate_hir_call_argument_records,
        validate_hir_context_relation_records,
        validate_hir_enum_variant_records,
        validate_hir_expression_result_root_records,
        validate_hir_semantic_tree_records,
        validate_hir_source_address_records,
        validate_hir_statement_records,
        validate_hir_struct_declaration_field_records,
    },
};

struct U32Readback {
    label: &'static str,
    buffer: wgpu::Buffer,
}

impl U32Readback {
    fn create(device: &wgpu::Device, label: &'static str, byte_size: u64) -> Self {
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some(label),
            size: byte_size,
            usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
            mapped_at_creation: false,
        });
        Self { label, buffer }
    }

    fn copy_from(&self, encoder: &mut wgpu::CommandEncoder, source: &wgpu::Buffer, byte_size: u64) {
        encoder.copy_buffer_to_buffer(source, 0, &self.buffer, 0, byte_size);
    }

    fn map(&self) {
        crate::gpu::passes_core::map_readback_for_progress(&self.buffer.slice(..), self.label);
    }

    fn read_words(&self, count: usize) -> Result<Vec<u32>> {
        let mapped = self.buffer.slice(..).get_mapped_range();
        let words = read_u32_words(&mapped, count)?;
        drop(mapped);
        self.buffer.unmap();
        Ok(words)
    }

    fn read_words_padded(&self, count: usize, fill: u32) -> Result<Vec<u32>> {
        let mut words = self.read_words(count)?;
        words.resize(count, fill);
        Ok(words)
    }

    fn read_ranges(&self, count: usize) -> Result<(Vec<u32>, Vec<u32>)> {
        let words = self.read_words(count.saturating_mul(2))?;
        let mut starts = Vec::with_capacity(count);
        let mut counts = Vec::with_capacity(count);
        for range in words.chunks_exact(2) {
            starts.push(range[0]);
            counts.push(range[1]);
        }
        Ok((starts, counts))
    }
}

struct ResidentTreeReadbacks {
    status: U32Readback,
    emit: U32Readback,
    emit_pos: U32Readback,
    node_kind: U32Readback,
    parent: U32Readback,
    first_child: U32Readback,
    next_sibling: U32Readback,
    subtree_end: U32Readback,
    hir_kind: U32Readback,
    hir_semantic_prefix_before_node: U32Readback,
    hir_semantic_dense_node: U32Readback,
    hir_semantic_subtree_end: U32Readback,
    hir_semantic_parent: U32Readback,
    hir_semantic_first_child: U32Readback,
    hir_semantic_next_sibling: U32Readback,
    hir_semantic_depth: U32Readback,
    hir_semantic_child_index: U32Readback,
    hir_token_pos: U32Readback,
    hir_token_end: U32Readback,
    hir_node_file_id: U32Readback,
    hir_type_form: U32Readback,
    hir_type_value_node: U32Readback,
    hir_type_len_token: U32Readback,
    hir_type_len_value: U32Readback,
    hir_type_file_id: U32Readback,
    hir_type_path_leaf_node: U32Readback,
    hir_type_arg_start: U32Readback,
    hir_type_arg_count: U32Readback,
    hir_type_arg_next: U32Readback,
    hir_type_alias_target_node: U32Readback,
    hir_fn_return_type_node: U32Readback,
    hir_method_signature_flags: U32Readback,
    hir_stmt_record: U32Readback,
    hir_stmt_scope_end: U32Readback,
    hir_item_kind: U32Readback,
    hir_item_name_token: U32Readback,
    hir_item_decl_token: U32Readback,
    hir_item_namespace: U32Readback,
    hir_item_visibility: U32Readback,
    hir_item_path_start: U32Readback,
    hir_item_path_end: U32Readback,
    hir_item_path_node: U32Readback,
    hir_item_file_id: U32Readback,
    hir_item_import_target_kind: U32Readback,
    hir_variant_parent_enum: U32Readback,
    hir_variant_ordinal: U32Readback,
    hir_variant_payload_start: U32Readback,
    hir_variant_payload_count: U32Readback,
    hir_variant_payload_node: U32Readback,
    hir_match_scrutinee_node: U32Readback,
    hir_match_arm_start: U32Readback,
    hir_match_arm_count: U32Readback,
    hir_match_arm_next: U32Readback,
    hir_match_arm_pattern_node: U32Readback,
    hir_match_arm_payload_start: U32Readback,
    hir_match_arm_payload_count: U32Readback,
    hir_match_arm_result_node: U32Readback,
    hir_match_payload_owner_arm: U32Readback,
    hir_match_payload_match_node: U32Readback,
    hir_match_payload_ordinal: U32Readback,
    hir_call_callee_node: U32Readback,
    hir_call_callee_path_node: U32Readback,
    hir_call_parent_by_callee: U32Readback,
    hir_call_context_stmt_node: U32Readback,
    hir_call_arg_start: U32Readback,
    hir_call_arg_end: U32Readback,
    hir_call_arg_count: U32Readback,
    hir_call_arg_parent_call: U32Readback,
    hir_call_arg_ordinal: U32Readback,
    hir_array_lit_first_element: U32Readback,
    hir_array_lit_element_count: U32Readback,
    hir_array_lit_context_stmt_node: U32Readback,
    hir_array_element_parent_lit: U32Readback,
    hir_array_element_ordinal: U32Readback,
    hir_array_element_next: U32Readback,
    hir_expr_name_role: U32Readback,
    hir_expr_result_root_node: U32Readback,
    hir_expr_parent_node: U32Readback,
    hir_expr_forest_root_node: U32Readback,
    hir_expr_forest_status: U32Readback,
    hir_member_receiver_node: U32Readback,
    hir_member_receiver_token: U32Readback,
    hir_member_name_token: U32Readback,
    hir_nearest_stmt_node: U32Readback,
    hir_nearest_block_node: U32Readback,
    hir_nearest_enclosing_control_node: U32Readback,
    hir_nearest_loop_node: U32Readback,
    hir_nearest_fn_node: U32Readback,
    hir_nearest_array_element_node: U32Readback,
    hir_struct_field_parent_struct: U32Readback,
    hir_struct_field_ordinal: U32Readback,
    hir_struct_field_type_node: U32Readback,
    hir_struct_decl_field_start: U32Readback,
    hir_struct_decl_field_count: U32Readback,
    hir_struct_lit_head_node: U32Readback,
    hir_struct_lit_context_stmt_node: U32Readback,
    hir_struct_lit_field_start: U32Readback,
    hir_struct_lit_field_count: U32Readback,
    hir_struct_lit_field_parent_lit: U32Readback,
    hir_struct_lit_field_value_node: U32Readback,
    hir_struct_lit_field_next: U32Readback,
    hir_canonical_count: U32Readback,
    hir_canonical_dense_to_raw: U32Readback,
    hir_canonical_raw_to_dense: U32Readback,
    hir_param_ranges: U32Readback,
    hir_type_arg_ranges: U32Readback,
    hir_generic_param_count: U32Readback,
    hir_generic_param_rows: U32Readback,
    hir_generic_param_ranges: U32Readback,
    hir_path_count: U32Readback,
    hir_path_rows: U32Readback,
    hir_path_segment_count: U32Readback,
    hir_path_segment_rows: U32Readback,
    hir_field_count: U32Readback,
    hir_field_rows: U32Readback,
    hir_compact_variant_count: U32Readback,
    hir_compact_variant_rows: U32Readback,
    hir_compact_variant_payload_start: U32Readback,
    hir_compact_variant_payload_count: U32Readback,
    hir_compact_variant_payload_row_count: U32Readback,
    hir_compact_variant_payload_rows: U32Readback,
    hir_compact_match_arm_count: U32Readback,
    hir_compact_match_arm_rows: U32Readback,
    hir_compact_match_payload_start: U32Readback,
    hir_compact_match_payload_count: U32Readback,
    hir_compact_match_payload_row_count: U32Readback,
    hir_compact_match_payload_rows: U32Readback,
    hir_compact_array_element_start: U32Readback,
    hir_compact_array_element_count: U32Readback,
    hir_compact_array_element_row_count: U32Readback,
    hir_compact_array_element_rows: U32Readback,
    hir_compact_string_count: U32Readback,
    hir_compact_string_rows: U32Readback,
    hir_compact_method_count: U32Readback,
    hir_compact_method_cores: U32Readback,
    hir_compact_method_signatures: U32Readback,
    hir_compact_predicate_count: U32Readback,
    hir_compact_predicate_rows: U32Readback,
}

impl ResidentTreeReadbacks {
    fn create(device: &wgpu::Device, bufs: &ParserBuffers) -> Self {
        Self {
            status: rb(
                device,
                "rb.parser.resident_tree.status",
                bufs.ll1_status.byte_size,
            ),
            emit: rb(
                device,
                "rb.parser.resident_tree.ll1_emit",
                bufs.ll1_emit.byte_size,
            ),
            emit_pos: rb(
                device,
                "rb.parser.resident_tree.ll1_emit_pos",
                bufs.ll1_emit_pos.byte_size,
            ),
            node_kind: rb(
                device,
                "rb.parser.resident_tree.node_kind",
                bufs.node_kind.byte_size,
            ),
            parent: rb(
                device,
                "rb.parser.resident_tree.parent",
                bufs.parent.byte_size,
            ),
            first_child: rb(
                device,
                "rb.parser.resident_tree.first_child",
                bufs.first_child.byte_size,
            ),
            next_sibling: rb(
                device,
                "rb.parser.resident_tree.next_sibling",
                bufs.next_sibling.byte_size,
            ),
            subtree_end: rb(
                device,
                "rb.parser.resident_tree.subtree_end",
                bufs.subtree_end.byte_size,
            ),
            hir_kind: rb(
                device,
                "rb.parser.resident_tree.hir_kind",
                bufs.hir_kind.byte_size,
            ),
            hir_semantic_prefix_before_node: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_prefix_before_node",
                bufs.hir_semantic_prefix_before_node.byte_size,
            ),
            hir_semantic_dense_node: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_dense_node",
                bufs.hir_semantic_dense_node.byte_size,
            ),
            hir_semantic_subtree_end: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_subtree_end",
                bufs.hir_semantic_subtree_end.byte_size,
            ),
            hir_semantic_parent: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_parent",
                bufs.hir_semantic_parent.byte_size,
            ),
            hir_semantic_first_child: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_first_child",
                bufs.hir_semantic_first_child.byte_size,
            ),
            hir_semantic_next_sibling: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_next_sibling",
                bufs.hir_semantic_next_sibling.byte_size,
            ),
            hir_semantic_depth: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_depth",
                bufs.hir_semantic_depth.byte_size,
            ),
            hir_semantic_child_index: rb(
                device,
                "rb.parser.resident_tree.hir_semantic_child_index",
                bufs.hir_semantic_child_index.byte_size,
            ),
            hir_token_pos: rb(
                device,
                "rb.parser.resident_tree.hir_token_pos",
                bufs.hir_token_pos.byte_size,
            ),
            hir_token_end: rb(
                device,
                "rb.parser.resident_tree.hir_token_end",
                bufs.hir_token_end.byte_size,
            ),
            hir_node_file_id: rb(
                device,
                "rb.parser.resident_tree.hir_node_file_id",
                bufs.hir_token_file_id.byte_size,
            ),
            hir_type_form: rb(
                device,
                "rb.parser.resident_tree.hir_type_form",
                bufs.hir_type_form.byte_size,
            ),
            hir_type_value_node: rb(
                device,
                "rb.parser.resident_tree.hir_type_value_node",
                bufs.hir_type_value_node.byte_size,
            ),
            hir_type_len_token: rb(
                device,
                "rb.parser.resident_tree.hir_type_len_token",
                bufs.hir_type_len_token.byte_size,
            ),
            hir_type_len_value: rb(
                device,
                "rb.parser.resident_tree.hir_type_len_value",
                bufs.hir_type_len_value.byte_size,
            ),
            hir_type_file_id: rb(
                device,
                "rb.parser.resident_tree.hir_type_file_id",
                bufs.hir_type_file_id.byte_size,
            ),
            hir_type_path_leaf_node: rb(
                device,
                "rb.parser.resident_tree.hir_type_path_leaf_node",
                bufs.hir_type_path_leaf_node.byte_size,
            ),
            hir_type_arg_start: rb(
                device,
                "rb.parser.resident_tree.hir_type_arg_start",
                bufs.hir_type_arg_start.byte_size,
            ),
            hir_type_arg_count: rb(
                device,
                "rb.parser.resident_tree.hir_type_arg_count",
                bufs.hir_type_arg_count.byte_size,
            ),
            hir_type_arg_next: rb(
                device,
                "rb.parser.resident_tree.hir_type_arg_next",
                bufs.hir_type_arg_next.byte_size,
            ),
            hir_type_alias_target_node: rb(
                device,
                "rb.parser.resident_tree.hir_type_alias_target_node",
                bufs.hir_type_alias_target_node.byte_size,
            ),
            hir_fn_return_type_node: rb(
                device,
                "rb.parser.resident_tree.hir_fn_return_type_node",
                bufs.hir_fn_return_type_node.byte_size,
            ),
            hir_method_signature_flags: rb(
                device,
                "rb.parser.resident_tree.hir_method_signature_flags",
                bufs.hir_method_signature_flags.byte_size,
            ),
            hir_stmt_record: rb(
                device,
                "rb.parser.resident_tree.hir_stmt_record",
                bufs.hir_stmt_record.byte_size,
            ),
            hir_stmt_scope_end: rb(
                device,
                "rb.parser.resident_tree.hir_stmt_scope_end",
                bufs.hir_stmt_scope_end.byte_size,
            ),
            hir_item_kind: rb(
                device,
                "rb.parser.resident_tree.hir_item_kind",
                bufs.hir_item_kind.byte_size,
            ),
            hir_item_name_token: rb(
                device,
                "rb.parser.resident_tree.hir_item_name_token",
                bufs.hir_item_name_token.byte_size,
            ),
            hir_item_decl_token: rb(
                device,
                "rb.parser.resident_tree.hir_item_decl_token",
                bufs.hir_item_decl_token.byte_size,
            ),
            hir_item_namespace: rb(
                device,
                "rb.parser.resident_tree.hir_item_namespace",
                bufs.hir_item_namespace.byte_size,
            ),
            hir_item_visibility: rb(
                device,
                "rb.parser.resident_tree.hir_item_visibility",
                bufs.hir_item_visibility.byte_size,
            ),
            hir_item_path_start: rb(
                device,
                "rb.parser.resident_tree.hir_item_path_start",
                bufs.hir_item_path_start.byte_size,
            ),
            hir_item_path_end: rb(
                device,
                "rb.parser.resident_tree.hir_item_path_end",
                bufs.hir_item_path_end.byte_size,
            ),
            hir_item_path_node: rb(
                device,
                "rb.parser.resident_tree.hir_item_path_node",
                bufs.hir_item_path_node.byte_size,
            ),
            hir_item_file_id: rb(
                device,
                "rb.parser.resident_tree.hir_item_file_id",
                bufs.hir_item_file_id.byte_size,
            ),
            hir_item_import_target_kind: rb(
                device,
                "rb.parser.resident_tree.hir_item_import_target_kind",
                bufs.hir_item_import_target_kind.byte_size,
            ),
            hir_variant_parent_enum: rb(
                device,
                "rb.parser.resident_tree.hir_variant_parent_enum",
                bufs.hir_variant_parent_enum.byte_size,
            ),
            hir_variant_ordinal: rb(
                device,
                "rb.parser.resident_tree.hir_variant_ordinal",
                bufs.hir_variant_ordinal.byte_size,
            ),
            hir_variant_payload_start: rb(
                device,
                "rb.parser.resident_tree.hir_variant_payload_start",
                bufs.hir_variant_payload_start.byte_size,
            ),
            hir_variant_payload_count: rb(
                device,
                "rb.parser.resident_tree.hir_variant_payload_count",
                bufs.hir_variant_payload_count.byte_size,
            ),
            hir_variant_payload_node: rb(
                device,
                "rb.parser.resident_tree.hir_variant_payload_node",
                bufs.hir_variant_payload_node.byte_size,
            ),
            hir_match_scrutinee_node: rb(
                device,
                "rb.parser.resident_tree.hir_match_scrutinee_node",
                bufs.hir_match_scrutinee_node.byte_size,
            ),
            hir_match_arm_start: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_start",
                bufs.hir_match_arm_start.byte_size,
            ),
            hir_match_arm_count: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_count",
                bufs.hir_match_arm_count.byte_size,
            ),
            hir_match_arm_next: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_next",
                bufs.hir_match_arm_next.byte_size,
            ),
            hir_match_arm_pattern_node: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_pattern_node",
                bufs.hir_match_arm_pattern_node.byte_size,
            ),
            hir_match_arm_payload_start: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_payload_start",
                bufs.hir_match_arm_payload_start.byte_size,
            ),
            hir_match_arm_payload_count: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_payload_count",
                bufs.hir_match_arm_payload_count.byte_size,
            ),
            hir_match_arm_result_node: rb(
                device,
                "rb.parser.resident_tree.hir_match_arm_result_node",
                bufs.hir_match_arm_result_node.byte_size,
            ),
            hir_match_payload_owner_arm: rb(
                device,
                "rb.parser.resident_tree.hir_match_payload_owner_arm",
                bufs.hir_match_payload_owner_arm.byte_size,
            ),
            hir_match_payload_match_node: rb(
                device,
                "rb.parser.resident_tree.hir_match_payload_match_node",
                bufs.hir_match_payload_match_node.byte_size,
            ),
            hir_match_payload_ordinal: rb(
                device,
                "rb.parser.resident_tree.hir_match_payload_ordinal",
                bufs.hir_match_payload_ordinal.byte_size,
            ),
            hir_call_callee_node: rb(
                device,
                "rb.parser.resident_tree.hir_call_callee_node",
                bufs.hir_call_callee_node.byte_size,
            ),
            hir_call_callee_path_node: rb(
                device,
                "rb.parser.resident_tree.hir_call_callee_path_node",
                bufs.hir_call_callee_path_node.byte_size,
            ),
            hir_call_parent_by_callee: rb(
                device,
                "rb.parser.resident_tree.hir_call_parent_by_callee",
                bufs.hir_call_parent_by_callee.byte_size,
            ),
            hir_call_context_stmt_node: rb(
                device,
                "rb.parser.resident_tree.hir_call_context_stmt_node",
                bufs.hir_call_context_stmt_node.byte_size,
            ),
            hir_call_arg_start: rb(
                device,
                "rb.parser.resident_tree.hir_call_arg_start",
                bufs.hir_call_arg_start.byte_size,
            ),
            hir_call_arg_end: rb(
                device,
                "rb.parser.resident_tree.hir_call_arg_end",
                bufs.hir_call_arg_end.byte_size,
            ),
            hir_call_arg_count: rb(
                device,
                "rb.parser.resident_tree.hir_call_arg_count",
                bufs.hir_call_arg_count.byte_size,
            ),
            hir_call_arg_parent_call: rb(
                device,
                "rb.parser.resident_tree.hir_call_arg_parent_call",
                bufs.hir_call_arg_parent_call.byte_size,
            ),
            hir_call_arg_ordinal: rb(
                device,
                "rb.parser.resident_tree.hir_call_arg_ordinal",
                bufs.hir_call_arg_ordinal.byte_size,
            ),
            hir_array_lit_first_element: rb(
                device,
                "rb.parser.resident_tree.hir_array_lit_first_element",
                bufs.hir_array_lit_first_element.byte_size,
            ),
            hir_array_lit_element_count: rb(
                device,
                "rb.parser.resident_tree.hir_array_lit_element_count",
                bufs.hir_array_lit_element_count.byte_size,
            ),
            hir_array_lit_context_stmt_node: rb(
                device,
                "rb.parser.resident_tree.hir_array_lit_context_stmt_node",
                bufs.hir_array_lit_context_stmt_node.byte_size,
            ),
            hir_array_element_parent_lit: rb(
                device,
                "rb.parser.resident_tree.hir_array_element_parent_lit",
                bufs.hir_array_element_parent_lit.byte_size,
            ),
            hir_array_element_ordinal: rb(
                device,
                "rb.parser.resident_tree.hir_array_element_ordinal",
                bufs.hir_array_element_ordinal.byte_size,
            ),
            hir_array_element_next: rb(
                device,
                "rb.parser.resident_tree.hir_array_element_next",
                bufs.hir_array_element_next.byte_size,
            ),
            hir_expr_name_role: rb(
                device,
                "rb.parser.resident_tree.hir_expr_name_role",
                bufs.hir_expr_name_role.byte_size,
            ),
            hir_expr_result_root_node: rb(
                device,
                "rb.parser.resident_tree.hir_expr_result_root_node",
                bufs.hir_expr_result_root_node.byte_size,
            ),
            hir_expr_parent_node: rb(
                device,
                "rb.parser.resident_tree.hir_expr_parent_node",
                bufs.hir_expr_parent_node.byte_size,
            ),
            hir_expr_forest_root_node: rb(
                device,
                "rb.parser.resident_tree.hir_expr_forest_root_node",
                bufs.hir_expr_forest_root_node.byte_size,
            ),
            hir_expr_forest_status: rb(
                device,
                "rb.parser.resident_tree.hir_expr_forest_status",
                bufs.hir_expr_forest_status.byte_size,
            ),
            hir_member_receiver_node: rb(
                device,
                "rb.parser.resident_tree.hir_member_receiver_node",
                bufs.hir_member_receiver_node.byte_size,
            ),
            hir_member_receiver_token: rb(
                device,
                "rb.parser.resident_tree.hir_member_receiver_token",
                bufs.hir_member_receiver_token.byte_size,
            ),
            hir_member_name_token: rb(
                device,
                "rb.parser.resident_tree.hir_member_name_token",
                bufs.hir_member_name_token.byte_size,
            ),
            hir_nearest_stmt_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_stmt_node",
                bufs.hir_nearest_stmt_node.byte_size,
            ),
            hir_nearest_block_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_block_node",
                bufs.hir_nearest_block_node.byte_size,
            ),
            hir_nearest_enclosing_control_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_enclosing_control_node",
                bufs.hir_nearest_enclosing_control_node.byte_size,
            ),
            hir_nearest_loop_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_loop_node",
                bufs.hir_nearest_loop_node.byte_size,
            ),
            hir_nearest_fn_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_fn_node",
                bufs.hir_nearest_fn_node.byte_size,
            ),
            hir_nearest_array_element_node: rb(
                device,
                "rb.parser.resident_tree.hir_nearest_array_element_node",
                bufs.hir_nearest_array_element_node.byte_size,
            ),
            hir_struct_field_parent_struct: rb(
                device,
                "rb.parser.resident_tree.hir_struct_field_parent_struct",
                bufs.hir_struct_field_parent_struct.byte_size,
            ),
            hir_struct_field_ordinal: rb(
                device,
                "rb.parser.resident_tree.hir_struct_field_ordinal",
                bufs.hir_struct_field_ordinal.byte_size,
            ),
            hir_struct_field_type_node: rb(
                device,
                "rb.parser.resident_tree.hir_struct_field_type_node",
                bufs.hir_struct_field_type_node.byte_size,
            ),
            hir_struct_decl_field_start: rb(
                device,
                "rb.parser.resident_tree.hir_struct_decl_field_start",
                bufs.hir_struct_decl_field_start.byte_size,
            ),
            hir_struct_decl_field_count: rb(
                device,
                "rb.parser.resident_tree.hir_struct_decl_field_count",
                bufs.hir_struct_decl_field_count.byte_size,
            ),
            hir_struct_lit_head_node: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_head_node",
                bufs.hir_struct_lit_head_node.byte_size,
            ),
            hir_struct_lit_context_stmt_node: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_context_stmt_node",
                bufs.hir_struct_lit_context_stmt_node.byte_size,
            ),
            hir_struct_lit_field_start: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_field_start",
                bufs.hir_struct_lit_field_start.byte_size,
            ),
            hir_struct_lit_field_count: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_field_count",
                bufs.hir_struct_lit_field_count.byte_size,
            ),
            hir_struct_lit_field_parent_lit: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_field_parent_lit",
                bufs.hir_struct_lit_field_parent_lit.byte_size,
            ),
            hir_struct_lit_field_value_node: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_field_value_node",
                bufs.hir_struct_lit_field_value_node.byte_size,
            ),
            hir_struct_lit_field_next: rb(
                device,
                "rb.parser.resident_tree.hir_struct_lit_field_next",
                bufs.hir_struct_lit_field_next.byte_size,
            ),
            hir_canonical_count: rb(
                device,
                "rb.parser.resident_tree.hir_canonical_count",
                bufs.hir_canonical_count.byte_size,
            ),
            hir_canonical_dense_to_raw: rb(
                device,
                "rb.parser.resident_tree.hir_canonical_dense_to_raw",
                bufs.hir_canonical_dense_to_raw.byte_size,
            ),
            hir_canonical_raw_to_dense: rb(
                device,
                "rb.parser.resident_tree.hir_canonical_raw_to_dense",
                bufs.hir_canonical_raw_to_dense.byte_size,
            ),
            hir_param_ranges: rb(
                device,
                "rb.parser.resident_tree.hir_param_ranges",
                bufs.hir_param_ranges.byte_size,
            ),
            hir_type_arg_ranges: rb(
                device,
                "rb.parser.resident_tree.hir_type_arg_ranges",
                bufs.hir_type_arg_ranges.byte_size,
            ),
            hir_generic_param_count: rb(
                device,
                "rb.parser.resident_tree.hir_generic_param_count",
                bufs.hir_generic_param_table_count.byte_size,
            ),
            hir_generic_param_rows: rb(
                device,
                "rb.parser.resident_tree.hir_generic_param_rows",
                bufs.hir_generic_param_rows.byte_size,
            ),
            hir_generic_param_ranges: rb(
                device,
                "rb.parser.resident_tree.hir_generic_param_ranges",
                bufs.hir_generic_param_ranges.byte_size,
            ),
            hir_path_count: rb(
                device,
                "rb.parser.resident_tree.hir_path_count",
                bufs.hir_path_table_count.byte_size,
            ),
            hir_path_rows: rb(
                device,
                "rb.parser.resident_tree.hir_path_rows",
                bufs.hir_path_rows.byte_size,
            ),
            hir_path_segment_count: rb(
                device,
                "rb.parser.resident_tree.hir_path_segment_count",
                bufs.hir_path_segment_table_count.byte_size,
            ),
            hir_path_segment_rows: rb(
                device,
                "rb.parser.resident_tree.hir_path_segment_rows",
                bufs.hir_path_segment_rows.byte_size,
            ),
            hir_field_count: rb(
                device,
                "rb.parser.resident_tree.hir_field_count",
                bufs.hir_field_table_count.byte_size,
            ),
            hir_field_rows: rb(
                device,
                "rb.parser.resident_tree.hir_field_rows",
                bufs.hir_field_rows.byte_size,
            ),
            hir_compact_variant_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_count",
                bufs.hir_variant_table_count.byte_size,
            ),
            hir_compact_variant_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_rows",
                bufs.hir_variant_rows.byte_size,
            ),
            hir_compact_variant_payload_start: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_payload_start",
                bufs.hir_variant_compact_payload_start.byte_size,
            ),
            hir_compact_variant_payload_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_payload_count",
                bufs.hir_variant_compact_payload_count.byte_size,
            ),
            hir_compact_variant_payload_row_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_payload_row_count",
                bufs.hir_variant_payload_table_count.byte_size,
            ),
            hir_compact_variant_payload_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_variant_payload_rows",
                bufs.hir_variant_payload_rows.byte_size,
            ),
            hir_compact_match_arm_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_arm_count",
                bufs.hir_match_arm_table_count.byte_size,
            ),
            hir_compact_match_arm_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_arm_rows",
                bufs.hir_match_arm_rows.byte_size,
            ),
            hir_compact_match_payload_start: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_payload_start",
                bufs.hir_match_compact_payload_start.byte_size,
            ),
            hir_compact_match_payload_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_payload_count",
                bufs.hir_match_compact_payload_count.byte_size,
            ),
            hir_compact_match_payload_row_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_payload_row_count",
                bufs.hir_match_payload_table_count.byte_size,
            ),
            hir_compact_match_payload_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_match_payload_rows",
                bufs.hir_match_payload_rows.byte_size,
            ),
            hir_compact_array_element_start: rb(
                device,
                "rb.parser.resident_tree.hir_compact_array_element_start",
                bufs.hir_array_compact_element_start.byte_size,
            ),
            hir_compact_array_element_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_array_element_count",
                bufs.hir_array_compact_element_count.byte_size,
            ),
            hir_compact_array_element_row_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_array_element_row_count",
                bufs.hir_array_element_table_count.byte_size,
            ),
            hir_compact_array_element_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_array_element_rows",
                bufs.hir_array_element_rows.byte_size,
            ),
            hir_compact_string_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_string_count",
                bufs.hir_string_count.byte_size,
            ),
            hir_compact_string_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_string_rows",
                bufs.hir_canonical_string_rows.byte_size,
            ),
            hir_compact_method_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_method_count",
                bufs.hir_method_table_count.byte_size,
            ),
            hir_compact_method_cores: rb(
                device,
                "rb.parser.resident_tree.hir_compact_method_cores",
                bufs.hir_method_core_rows.byte_size,
            ),
            hir_compact_method_signatures: rb(
                device,
                "rb.parser.resident_tree.hir_compact_method_signatures",
                bufs.hir_method_signature_rows.byte_size,
            ),
            hir_compact_predicate_count: rb(
                device,
                "rb.parser.resident_tree.hir_compact_predicate_count",
                bufs.hir_predicate_table_count.byte_size,
            ),
            hir_compact_predicate_rows: rb(
                device,
                "rb.parser.resident_tree.hir_compact_predicate_rows",
                bufs.hir_predicate_rows.byte_size,
            ),
        }
    }

    fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        self.status
            .copy_from(encoder, &bufs.ll1_status, bufs.ll1_status.byte_size as u64);
        self.emit
            .copy_from(encoder, &bufs.ll1_emit, bufs.ll1_emit.byte_size as u64);
        self.emit_pos.copy_from(
            encoder,
            &bufs.ll1_emit_pos,
            bufs.ll1_emit_pos.byte_size as u64,
        );
        self.node_kind
            .copy_from(encoder, &bufs.node_kind, bufs.node_kind.byte_size as u64);
        self.parent
            .copy_from(encoder, &bufs.parent, bufs.parent.byte_size as u64);
        self.first_child.copy_from(
            encoder,
            &bufs.first_child,
            bufs.first_child.byte_size as u64,
        );
        self.next_sibling.copy_from(
            encoder,
            &bufs.next_sibling,
            bufs.next_sibling.byte_size as u64,
        );
        self.subtree_end.copy_from(
            encoder,
            &bufs.subtree_end,
            bufs.subtree_end.byte_size as u64,
        );
        self.hir_kind
            .copy_from(encoder, &bufs.hir_kind, bufs.hir_kind.byte_size as u64);
        self.hir_semantic_prefix_before_node.copy_from(
            encoder,
            &bufs.hir_semantic_prefix_before_node,
            bufs.hir_semantic_prefix_before_node.byte_size as u64,
        );
        self.hir_semantic_dense_node.copy_from(
            encoder,
            &bufs.hir_semantic_dense_node,
            bufs.hir_semantic_dense_node.byte_size as u64,
        );
        self.hir_semantic_subtree_end.copy_from(
            encoder,
            &bufs.hir_semantic_subtree_end,
            bufs.hir_semantic_subtree_end.byte_size as u64,
        );
        self.hir_semantic_parent.copy_from(
            encoder,
            &bufs.hir_semantic_parent,
            bufs.hir_semantic_parent.byte_size as u64,
        );
        self.hir_semantic_first_child.copy_from(
            encoder,
            &bufs.hir_semantic_first_child,
            bufs.hir_semantic_first_child.byte_size as u64,
        );
        self.hir_semantic_next_sibling.copy_from(
            encoder,
            &bufs.hir_semantic_next_sibling,
            bufs.hir_semantic_next_sibling.byte_size as u64,
        );
        self.hir_semantic_depth.copy_from(
            encoder,
            &bufs.hir_semantic_depth,
            bufs.hir_semantic_depth.byte_size as u64,
        );
        self.hir_semantic_child_index.copy_from(
            encoder,
            &bufs.hir_semantic_child_index,
            bufs.hir_semantic_child_index.byte_size as u64,
        );
        self.hir_token_pos.copy_from(
            encoder,
            &bufs.hir_token_pos,
            bufs.hir_token_pos.byte_size as u64,
        );
        self.hir_token_end.copy_from(
            encoder,
            &bufs.hir_token_end,
            bufs.hir_token_end.byte_size as u64,
        );
        self.hir_node_file_id.copy_from(
            encoder,
            &bufs.hir_token_file_id,
            bufs.hir_token_file_id.byte_size as u64,
        );
        self.hir_type_form.copy_from(
            encoder,
            &bufs.hir_type_form,
            bufs.hir_type_form.byte_size as u64,
        );
        self.hir_type_value_node.copy_from(
            encoder,
            &bufs.hir_type_value_node,
            bufs.hir_type_value_node.byte_size as u64,
        );
        self.hir_type_len_token.copy_from(
            encoder,
            &bufs.hir_type_len_token,
            bufs.hir_type_len_token.byte_size as u64,
        );
        self.hir_type_len_value.copy_from(
            encoder,
            &bufs.hir_type_len_value,
            bufs.hir_type_len_value.byte_size as u64,
        );
        self.hir_type_file_id.copy_from(
            encoder,
            &bufs.hir_type_file_id,
            bufs.hir_type_file_id.byte_size as u64,
        );
        self.hir_type_path_leaf_node.copy_from(
            encoder,
            &bufs.hir_type_path_leaf_node,
            bufs.hir_type_path_leaf_node.byte_size as u64,
        );
        self.hir_type_arg_start.copy_from(
            encoder,
            &bufs.hir_type_arg_start,
            bufs.hir_type_arg_start.byte_size as u64,
        );
        self.hir_type_arg_count.copy_from(
            encoder,
            &bufs.hir_type_arg_count,
            bufs.hir_type_arg_count.byte_size as u64,
        );
        self.hir_type_arg_next.copy_from(
            encoder,
            &bufs.hir_type_arg_next,
            bufs.hir_type_arg_next.byte_size as u64,
        );
        self.hir_type_alias_target_node.copy_from(
            encoder,
            &bufs.hir_type_alias_target_node,
            bufs.hir_type_alias_target_node.byte_size as u64,
        );
        self.hir_fn_return_type_node.copy_from(
            encoder,
            &bufs.hir_fn_return_type_node,
            bufs.hir_fn_return_type_node.byte_size as u64,
        );
        self.hir_method_signature_flags.copy_from(
            encoder,
            &bufs.hir_method_signature_flags,
            bufs.hir_method_signature_flags.byte_size as u64,
        );
        self.hir_stmt_record.copy_from(
            encoder,
            &bufs.hir_stmt_record,
            bufs.hir_stmt_record.byte_size as u64,
        );
        self.hir_stmt_scope_end.copy_from(
            encoder,
            &bufs.hir_stmt_scope_end,
            bufs.hir_stmt_scope_end.byte_size as u64,
        );
        self.hir_item_kind.copy_from(
            encoder,
            &bufs.hir_item_kind,
            bufs.hir_item_kind.byte_size as u64,
        );
        self.hir_item_name_token.copy_from(
            encoder,
            &bufs.hir_item_name_token,
            bufs.hir_item_name_token.byte_size as u64,
        );
        self.hir_item_decl_token.copy_from(
            encoder,
            &bufs.hir_item_decl_token,
            bufs.hir_item_decl_token.byte_size as u64,
        );
        self.hir_item_namespace.copy_from(
            encoder,
            &bufs.hir_item_namespace,
            bufs.hir_item_namespace.byte_size as u64,
        );
        self.hir_item_visibility.copy_from(
            encoder,
            &bufs.hir_item_visibility,
            bufs.hir_item_visibility.byte_size as u64,
        );
        self.hir_item_path_start.copy_from(
            encoder,
            &bufs.hir_item_path_start,
            bufs.hir_item_path_start.byte_size as u64,
        );
        self.hir_item_path_end.copy_from(
            encoder,
            &bufs.hir_item_path_end,
            bufs.hir_item_path_end.byte_size as u64,
        );
        self.hir_item_path_node.copy_from(
            encoder,
            &bufs.hir_item_path_node,
            bufs.hir_item_path_node.byte_size as u64,
        );
        self.hir_item_file_id.copy_from(
            encoder,
            &bufs.hir_item_file_id,
            bufs.hir_item_file_id.byte_size as u64,
        );
        self.hir_item_import_target_kind.copy_from(
            encoder,
            &bufs.hir_item_import_target_kind,
            bufs.hir_item_import_target_kind.byte_size as u64,
        );
        self.hir_variant_parent_enum.copy_from(
            encoder,
            &bufs.hir_variant_parent_enum,
            bufs.hir_variant_parent_enum.byte_size as u64,
        );
        self.hir_variant_ordinal.copy_from(
            encoder,
            &bufs.hir_variant_ordinal,
            bufs.hir_variant_ordinal.byte_size as u64,
        );
        self.hir_variant_payload_start.copy_from(
            encoder,
            &bufs.hir_variant_payload_start,
            bufs.hir_variant_payload_start.byte_size as u64,
        );
        self.hir_variant_payload_count.copy_from(
            encoder,
            &bufs.hir_variant_payload_count,
            bufs.hir_variant_payload_count.byte_size as u64,
        );
        self.hir_variant_payload_node.copy_from(
            encoder,
            &bufs.hir_variant_payload_node,
            bufs.hir_variant_payload_node.byte_size as u64,
        );
        self.hir_match_scrutinee_node.copy_from(
            encoder,
            &bufs.hir_match_scrutinee_node,
            bufs.hir_match_scrutinee_node.byte_size as u64,
        );
        self.hir_match_arm_start.copy_from(
            encoder,
            &bufs.hir_match_arm_start,
            bufs.hir_match_arm_start.byte_size as u64,
        );
        self.hir_match_arm_count.copy_from(
            encoder,
            &bufs.hir_match_arm_count,
            bufs.hir_match_arm_count.byte_size as u64,
        );
        self.hir_match_arm_next.copy_from(
            encoder,
            &bufs.hir_match_arm_next,
            bufs.hir_match_arm_next.byte_size as u64,
        );
        self.hir_match_arm_pattern_node.copy_from(
            encoder,
            &bufs.hir_match_arm_pattern_node,
            bufs.hir_match_arm_pattern_node.byte_size as u64,
        );
        self.hir_match_arm_payload_start.copy_from(
            encoder,
            &bufs.hir_match_arm_payload_start,
            bufs.hir_match_arm_payload_start.byte_size as u64,
        );
        self.hir_match_arm_payload_count.copy_from(
            encoder,
            &bufs.hir_match_arm_payload_count,
            bufs.hir_match_arm_payload_count.byte_size as u64,
        );
        self.hir_match_arm_result_node.copy_from(
            encoder,
            &bufs.hir_match_arm_result_node,
            bufs.hir_match_arm_result_node.byte_size as u64,
        );
        self.hir_match_payload_owner_arm.copy_from(
            encoder,
            &bufs.hir_match_payload_owner_arm,
            bufs.hir_match_payload_owner_arm.byte_size as u64,
        );
        self.hir_match_payload_match_node.copy_from(
            encoder,
            &bufs.hir_match_payload_match_node,
            bufs.hir_match_payload_match_node.byte_size as u64,
        );
        self.hir_match_payload_ordinal.copy_from(
            encoder,
            &bufs.hir_match_payload_ordinal,
            bufs.hir_match_payload_ordinal.byte_size as u64,
        );
        self.hir_call_callee_node.copy_from(
            encoder,
            &bufs.hir_call_callee_node,
            bufs.hir_call_callee_node.byte_size as u64,
        );
        self.hir_call_callee_path_node.copy_from(
            encoder,
            &bufs.hir_call_callee_path_node,
            bufs.hir_call_callee_path_node.byte_size as u64,
        );
        self.hir_call_parent_by_callee.copy_from(
            encoder,
            &bufs.hir_call_parent_by_callee,
            bufs.hir_call_parent_by_callee.byte_size as u64,
        );
        self.hir_call_context_stmt_node.copy_from(
            encoder,
            &bufs.hir_call_context_stmt_node,
            bufs.hir_call_context_stmt_node.byte_size as u64,
        );
        self.hir_call_arg_start.copy_from(
            encoder,
            &bufs.hir_call_arg_start,
            bufs.hir_call_arg_start.byte_size as u64,
        );
        self.hir_call_arg_end.copy_from(
            encoder,
            &bufs.hir_call_arg_end,
            bufs.hir_call_arg_end.byte_size as u64,
        );
        self.hir_call_arg_count.copy_from(
            encoder,
            &bufs.hir_call_arg_count,
            bufs.hir_call_arg_count.byte_size as u64,
        );
        self.hir_call_arg_parent_call.copy_from(
            encoder,
            &bufs.hir_call_arg_parent_call,
            bufs.hir_call_arg_parent_call.byte_size as u64,
        );
        self.hir_call_arg_ordinal.copy_from(
            encoder,
            &bufs.hir_call_arg_ordinal,
            bufs.hir_call_arg_ordinal.byte_size as u64,
        );
        self.hir_array_lit_first_element.copy_from(
            encoder,
            &bufs.hir_array_lit_first_element,
            bufs.hir_array_lit_first_element.byte_size as u64,
        );
        self.hir_array_lit_element_count.copy_from(
            encoder,
            &bufs.hir_array_lit_element_count,
            bufs.hir_array_lit_element_count.byte_size as u64,
        );
        self.hir_array_lit_context_stmt_node.copy_from(
            encoder,
            &bufs.hir_array_lit_context_stmt_node,
            bufs.hir_array_lit_context_stmt_node.byte_size as u64,
        );
        self.hir_array_element_parent_lit.copy_from(
            encoder,
            &bufs.hir_array_element_parent_lit,
            bufs.hir_array_element_parent_lit.byte_size as u64,
        );
        self.hir_array_element_ordinal.copy_from(
            encoder,
            &bufs.hir_array_element_ordinal,
            bufs.hir_array_element_ordinal.byte_size as u64,
        );
        self.hir_array_element_next.copy_from(
            encoder,
            &bufs.hir_array_element_next,
            bufs.hir_array_element_next.byte_size as u64,
        );
        self.hir_expr_name_role.copy_from(
            encoder,
            &bufs.hir_expr_name_role,
            bufs.hir_expr_name_role.byte_size as u64,
        );
        self.hir_expr_result_root_node.copy_from(
            encoder,
            &bufs.hir_expr_result_root_node,
            bufs.hir_expr_result_root_node.byte_size as u64,
        );
        self.hir_expr_parent_node.copy_from(
            encoder,
            &bufs.hir_expr_parent_node,
            bufs.hir_expr_parent_node.byte_size as u64,
        );
        self.hir_expr_forest_root_node.copy_from(
            encoder,
            &bufs.hir_expr_forest_root_node,
            bufs.hir_expr_forest_root_node.byte_size as u64,
        );
        self.hir_expr_forest_status.copy_from(
            encoder,
            &bufs.hir_expr_forest_status,
            bufs.hir_expr_forest_status.byte_size as u64,
        );
        self.hir_member_receiver_node.copy_from(
            encoder,
            &bufs.hir_member_receiver_node,
            bufs.hir_member_receiver_node.byte_size as u64,
        );
        self.hir_member_receiver_token.copy_from(
            encoder,
            &bufs.hir_member_receiver_token,
            bufs.hir_member_receiver_token.byte_size as u64,
        );
        self.hir_member_name_token.copy_from(
            encoder,
            &bufs.hir_member_name_token,
            bufs.hir_member_name_token.byte_size as u64,
        );
        self.hir_nearest_stmt_node.copy_from(
            encoder,
            &bufs.hir_nearest_stmt_node,
            bufs.hir_nearest_stmt_node.byte_size as u64,
        );
        self.hir_nearest_block_node.copy_from(
            encoder,
            &bufs.hir_nearest_block_node,
            bufs.hir_nearest_block_node.byte_size as u64,
        );
        self.hir_nearest_enclosing_control_node.copy_from(
            encoder,
            &bufs.hir_nearest_enclosing_control_node,
            bufs.hir_nearest_enclosing_control_node.byte_size as u64,
        );
        self.hir_nearest_loop_node.copy_from(
            encoder,
            &bufs.hir_nearest_loop_node,
            bufs.hir_nearest_loop_node.byte_size as u64,
        );
        self.hir_nearest_fn_node.copy_from(
            encoder,
            &bufs.hir_nearest_fn_node,
            bufs.hir_nearest_fn_node.byte_size as u64,
        );
        self.hir_nearest_array_element_node.copy_from(
            encoder,
            &bufs.hir_nearest_array_element_node,
            bufs.hir_nearest_array_element_node.byte_size as u64,
        );
        self.hir_struct_field_parent_struct.copy_from(
            encoder,
            &bufs.hir_struct_field_parent_struct,
            bufs.hir_struct_field_parent_struct.byte_size as u64,
        );
        self.hir_struct_field_ordinal.copy_from(
            encoder,
            &bufs.hir_struct_field_ordinal,
            bufs.hir_struct_field_ordinal.byte_size as u64,
        );
        self.hir_struct_field_type_node.copy_from(
            encoder,
            &bufs.hir_struct_field_type_node,
            bufs.hir_struct_field_type_node.byte_size as u64,
        );
        self.hir_struct_decl_field_start.copy_from(
            encoder,
            &bufs.hir_struct_decl_field_start,
            bufs.hir_struct_decl_field_start.byte_size as u64,
        );
        self.hir_struct_decl_field_count.copy_from(
            encoder,
            &bufs.hir_struct_decl_field_count,
            bufs.hir_struct_decl_field_count.byte_size as u64,
        );
        self.hir_struct_lit_head_node.copy_from(
            encoder,
            &bufs.hir_struct_lit_head_node,
            bufs.hir_struct_lit_head_node.byte_size as u64,
        );
        self.hir_struct_lit_context_stmt_node.copy_from(
            encoder,
            &bufs.hir_struct_lit_context_stmt_node,
            bufs.hir_struct_lit_context_stmt_node.byte_size as u64,
        );
        self.hir_struct_lit_field_start.copy_from(
            encoder,
            &bufs.hir_struct_lit_field_start,
            bufs.hir_struct_lit_field_start.byte_size as u64,
        );
        self.hir_struct_lit_field_count.copy_from(
            encoder,
            &bufs.hir_struct_lit_field_count,
            bufs.hir_struct_lit_field_count.byte_size as u64,
        );
        self.hir_struct_lit_field_parent_lit.copy_from(
            encoder,
            &bufs.hir_struct_lit_field_parent_lit,
            bufs.hir_struct_lit_field_parent_lit.byte_size as u64,
        );
        self.hir_struct_lit_field_value_node.copy_from(
            encoder,
            &bufs.hir_struct_lit_field_value_node,
            bufs.hir_struct_lit_field_value_node.byte_size as u64,
        );
        self.hir_struct_lit_field_next.copy_from(
            encoder,
            &bufs.hir_struct_lit_field_next,
            bufs.hir_struct_lit_field_next.byte_size as u64,
        );
        self.hir_canonical_count.copy_from(
            encoder,
            &bufs.hir_canonical_count,
            bufs.hir_canonical_count.byte_size as u64,
        );
        self.hir_canonical_dense_to_raw.copy_from(
            encoder,
            &bufs.hir_canonical_dense_to_raw,
            bufs.hir_canonical_dense_to_raw.byte_size as u64,
        );
        self.hir_canonical_raw_to_dense.copy_from(
            encoder,
            &bufs.hir_canonical_raw_to_dense,
            bufs.hir_canonical_raw_to_dense.byte_size as u64,
        );
        self.hir_param_ranges.copy_from(
            encoder,
            &bufs.hir_param_ranges,
            bufs.hir_param_ranges.byte_size as u64,
        );
        self.hir_type_arg_ranges.copy_from(
            encoder,
            &bufs.hir_type_arg_ranges,
            bufs.hir_type_arg_ranges.byte_size as u64,
        );
        self.hir_generic_param_count.copy_from(
            encoder,
            &bufs.hir_generic_param_table_count,
            bufs.hir_generic_param_table_count.byte_size as u64,
        );
        self.hir_generic_param_rows.copy_from(
            encoder,
            &bufs.hir_generic_param_rows,
            bufs.hir_generic_param_rows.byte_size as u64,
        );
        self.hir_generic_param_ranges.copy_from(
            encoder,
            &bufs.hir_generic_param_ranges,
            bufs.hir_generic_param_ranges.byte_size as u64,
        );
        self.hir_path_count.copy_from(
            encoder,
            &bufs.hir_path_table_count,
            bufs.hir_path_table_count.byte_size as u64,
        );
        self.hir_path_rows.copy_from(
            encoder,
            &bufs.hir_path_rows,
            bufs.hir_path_rows.byte_size as u64,
        );
        self.hir_path_segment_count.copy_from(
            encoder,
            &bufs.hir_path_segment_table_count,
            bufs.hir_path_segment_table_count.byte_size as u64,
        );
        self.hir_path_segment_rows.copy_from(
            encoder,
            &bufs.hir_path_segment_rows,
            bufs.hir_path_segment_rows.byte_size as u64,
        );
        self.hir_field_count.copy_from(
            encoder,
            &bufs.hir_field_table_count,
            bufs.hir_field_table_count.byte_size as u64,
        );
        self.hir_field_rows.copy_from(
            encoder,
            &bufs.hir_field_rows,
            bufs.hir_field_rows.byte_size as u64,
        );
        self.hir_compact_variant_count.copy_from(
            encoder,
            &bufs.hir_variant_table_count,
            bufs.hir_variant_table_count.byte_size as u64,
        );
        self.hir_compact_variant_rows.copy_from(
            encoder,
            &bufs.hir_variant_rows,
            bufs.hir_variant_rows.byte_size as u64,
        );
        self.hir_compact_variant_payload_start.copy_from(
            encoder,
            &bufs.hir_variant_compact_payload_start,
            bufs.hir_variant_compact_payload_start.byte_size as u64,
        );
        self.hir_compact_variant_payload_count.copy_from(
            encoder,
            &bufs.hir_variant_compact_payload_count,
            bufs.hir_variant_compact_payload_count.byte_size as u64,
        );
        self.hir_compact_variant_payload_row_count.copy_from(
            encoder,
            &bufs.hir_variant_payload_table_count,
            bufs.hir_variant_payload_table_count.byte_size as u64,
        );
        self.hir_compact_variant_payload_rows.copy_from(
            encoder,
            &bufs.hir_variant_payload_rows,
            bufs.hir_variant_payload_rows.byte_size as u64,
        );
        self.hir_compact_match_arm_count.copy_from(
            encoder,
            &bufs.hir_match_arm_table_count,
            bufs.hir_match_arm_table_count.byte_size as u64,
        );
        self.hir_compact_match_arm_rows.copy_from(
            encoder,
            &bufs.hir_match_arm_rows,
            bufs.hir_match_arm_rows.byte_size as u64,
        );
        self.hir_compact_match_payload_start.copy_from(
            encoder,
            &bufs.hir_match_compact_payload_start,
            bufs.hir_match_compact_payload_start.byte_size as u64,
        );
        self.hir_compact_match_payload_count.copy_from(
            encoder,
            &bufs.hir_match_compact_payload_count,
            bufs.hir_match_compact_payload_count.byte_size as u64,
        );
        self.hir_compact_match_payload_row_count.copy_from(
            encoder,
            &bufs.hir_match_payload_table_count,
            bufs.hir_match_payload_table_count.byte_size as u64,
        );
        self.hir_compact_match_payload_rows.copy_from(
            encoder,
            &bufs.hir_match_payload_rows,
            bufs.hir_match_payload_rows.byte_size as u64,
        );
        self.hir_compact_array_element_start.copy_from(
            encoder,
            &bufs.hir_array_compact_element_start,
            bufs.hir_array_compact_element_start.byte_size as u64,
        );
        self.hir_compact_array_element_count.copy_from(
            encoder,
            &bufs.hir_array_compact_element_count,
            bufs.hir_array_compact_element_count.byte_size as u64,
        );
        self.hir_compact_array_element_row_count.copy_from(
            encoder,
            &bufs.hir_array_element_table_count,
            bufs.hir_array_element_table_count.byte_size as u64,
        );
        self.hir_compact_array_element_rows.copy_from(
            encoder,
            &bufs.hir_array_element_rows,
            bufs.hir_array_element_rows.byte_size as u64,
        );
        self.hir_compact_string_count.copy_from(
            encoder,
            &bufs.hir_string_count,
            bufs.hir_string_count.byte_size as u64,
        );
        self.hir_compact_string_rows.copy_from(
            encoder,
            &bufs.hir_canonical_string_rows,
            bufs.hir_canonical_string_rows.byte_size as u64,
        );
        self.hir_compact_method_count.copy_from(
            encoder,
            &bufs.hir_method_table_count,
            bufs.hir_method_table_count.byte_size as u64,
        );
        self.hir_compact_method_cores.copy_from(
            encoder,
            &bufs.hir_method_core_rows,
            bufs.hir_method_core_rows.byte_size as u64,
        );
        self.hir_compact_method_signatures.copy_from(
            encoder,
            &bufs.hir_method_signature_rows,
            bufs.hir_method_signature_rows.byte_size as u64,
        );
        self.hir_compact_predicate_count.copy_from(
            encoder,
            &bufs.hir_predicate_table_count,
            bufs.hir_predicate_table_count.byte_size as u64,
        );
        self.hir_compact_predicate_rows.copy_from(
            encoder,
            &bufs.hir_predicate_rows,
            bufs.hir_predicate_rows.byte_size as u64,
        );
    }

    fn map_all(&self) {
        self.status.map();
        self.emit.map();
        self.emit_pos.map();
        self.node_kind.map();
        self.parent.map();
        self.first_child.map();
        self.next_sibling.map();
        self.subtree_end.map();
        self.hir_kind.map();
        self.hir_semantic_prefix_before_node.map();
        self.hir_semantic_dense_node.map();
        self.hir_semantic_subtree_end.map();
        self.hir_semantic_parent.map();
        self.hir_semantic_first_child.map();
        self.hir_semantic_next_sibling.map();
        self.hir_semantic_depth.map();
        self.hir_semantic_child_index.map();
        self.hir_token_pos.map();
        self.hir_token_end.map();
        self.hir_node_file_id.map();
        self.hir_type_form.map();
        self.hir_type_value_node.map();
        self.hir_type_len_token.map();
        self.hir_type_len_value.map();
        self.hir_type_file_id.map();
        self.hir_type_path_leaf_node.map();
        self.hir_type_arg_start.map();
        self.hir_type_arg_count.map();
        self.hir_type_arg_next.map();
        self.hir_type_alias_target_node.map();
        self.hir_fn_return_type_node.map();
        self.hir_method_signature_flags.map();
        self.hir_stmt_record.map();
        self.hir_stmt_scope_end.map();
        self.hir_item_kind.map();
        self.hir_item_name_token.map();
        self.hir_item_decl_token.map();
        self.hir_item_namespace.map();
        self.hir_item_visibility.map();
        self.hir_item_path_start.map();
        self.hir_item_path_end.map();
        self.hir_item_path_node.map();
        self.hir_item_file_id.map();
        self.hir_item_import_target_kind.map();
        self.hir_variant_parent_enum.map();
        self.hir_variant_ordinal.map();
        self.hir_variant_payload_start.map();
        self.hir_variant_payload_count.map();
        self.hir_variant_payload_node.map();
        self.hir_match_scrutinee_node.map();
        self.hir_match_arm_start.map();
        self.hir_match_arm_count.map();
        self.hir_match_arm_next.map();
        self.hir_match_arm_pattern_node.map();
        self.hir_match_arm_payload_start.map();
        self.hir_match_arm_payload_count.map();
        self.hir_match_arm_result_node.map();
        self.hir_match_payload_owner_arm.map();
        self.hir_match_payload_match_node.map();
        self.hir_match_payload_ordinal.map();
        self.hir_call_callee_node.map();
        self.hir_call_callee_path_node.map();
        self.hir_call_parent_by_callee.map();
        self.hir_call_context_stmt_node.map();
        self.hir_call_arg_start.map();
        self.hir_call_arg_end.map();
        self.hir_call_arg_count.map();
        self.hir_call_arg_parent_call.map();
        self.hir_call_arg_ordinal.map();
        self.hir_array_lit_first_element.map();
        self.hir_array_lit_element_count.map();
        self.hir_array_lit_context_stmt_node.map();
        self.hir_array_element_parent_lit.map();
        self.hir_array_element_ordinal.map();
        self.hir_array_element_next.map();
        self.hir_expr_name_role.map();
        self.hir_expr_result_root_node.map();
        self.hir_expr_parent_node.map();
        self.hir_expr_forest_root_node.map();
        self.hir_expr_forest_status.map();
        self.hir_member_receiver_node.map();
        self.hir_member_receiver_token.map();
        self.hir_member_name_token.map();
        self.hir_nearest_stmt_node.map();
        self.hir_nearest_block_node.map();
        self.hir_nearest_enclosing_control_node.map();
        self.hir_nearest_loop_node.map();
        self.hir_nearest_fn_node.map();
        self.hir_nearest_array_element_node.map();
        self.hir_struct_field_parent_struct.map();
        self.hir_struct_field_ordinal.map();
        self.hir_struct_field_type_node.map();
        self.hir_struct_decl_field_start.map();
        self.hir_struct_decl_field_count.map();
        self.hir_struct_lit_head_node.map();
        self.hir_struct_lit_context_stmt_node.map();
        self.hir_struct_lit_field_start.map();
        self.hir_struct_lit_field_count.map();
        self.hir_struct_lit_field_parent_lit.map();
        self.hir_struct_lit_field_value_node.map();
        self.hir_struct_lit_field_next.map();
        self.hir_canonical_count.map();
        self.hir_canonical_dense_to_raw.map();
        self.hir_canonical_raw_to_dense.map();
        self.hir_param_ranges.map();
        self.hir_type_arg_ranges.map();
        self.hir_generic_param_count.map();
        self.hir_generic_param_rows.map();
        self.hir_generic_param_ranges.map();
        self.hir_path_count.map();
        self.hir_path_rows.map();
        self.hir_path_segment_count.map();
        self.hir_path_segment_rows.map();
        self.hir_field_count.map();
        self.hir_field_rows.map();
        self.hir_compact_variant_count.map();
        self.hir_compact_variant_rows.map();
        self.hir_compact_variant_payload_start.map();
        self.hir_compact_variant_payload_count.map();
        self.hir_compact_variant_payload_row_count.map();
        self.hir_compact_variant_payload_rows.map();
        self.hir_compact_match_arm_count.map();
        self.hir_compact_match_arm_rows.map();
        self.hir_compact_match_payload_start.map();
        self.hir_compact_match_payload_count.map();
        self.hir_compact_match_payload_row_count.map();
        self.hir_compact_match_payload_rows.map();
        self.hir_compact_array_element_start.map();
        self.hir_compact_array_element_count.map();
        self.hir_compact_array_element_row_count.map();
        self.hir_compact_array_element_rows.map();
        self.hir_compact_string_count.map();
        self.hir_compact_string_rows.map();
        self.hir_compact_method_count.map();
        self.hir_compact_method_cores.map();
        self.hir_compact_method_signatures.map();
        self.hir_compact_predicate_count.map();
        self.hir_compact_predicate_rows.map();
    }

    fn decode(&self, bufs: &ParserBuffers) -> Result<ResidentParseResult> {
        let ll1_words = self.status.read_words(6)?;
        let tree_len = if bufs.tree_count_uses_status {
            (ll1_words[5] as usize).min(bufs.node_kind.count)
        } else {
            (bufs.total_emit as usize).min(bufs.node_kind.count)
        };

        let hir_call_arg_parent_call = self.hir_call_arg_parent_call.read_words(tree_len)?;
        let hir_call_arg_ordinal = self.hir_call_arg_ordinal.read_words(tree_len)?;

        let canonical_capacity = bufs.hir_canonical_capacity as usize;
        let (hir_param_range_start, hir_param_range_count) =
            self.hir_param_ranges.read_ranges(canonical_capacity)?;
        let (hir_type_arg_range_start, hir_type_arg_range_count) =
            self.hir_type_arg_ranges.read_ranges(canonical_capacity)?;
        let (hir_generic_param_range_start, hir_generic_param_range_count) = self
            .hir_generic_param_ranges
            .read_ranges(canonical_capacity)?;

        let hir_stmt_record_words = self
            .hir_stmt_record
            .read_words(tree_len.saturating_mul(4))?;
        let mut hir_stmt_record_kind = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand0 = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand1 = Vec::with_capacity(tree_len);
        let mut hir_stmt_record_operand2 = Vec::with_capacity(tree_len);
        for row in 0..tree_len {
            let base = row.saturating_mul(4);
            hir_stmt_record_kind.push(*hir_stmt_record_words.get(base).unwrap_or(&u32::MAX));
            hir_stmt_record_operand0
                .push(*hir_stmt_record_words.get(base + 1).unwrap_or(&u32::MAX));
            hir_stmt_record_operand1
                .push(*hir_stmt_record_words.get(base + 2).unwrap_or(&u32::MAX));
            hir_stmt_record_operand2
                .push(*hir_stmt_record_words.get(base + 3).unwrap_or(&u32::MAX));
        }

        let generic_param_count = self
            .hir_generic_param_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let generic_param_count = generic_param_count.min(bufs.hir_generic_param_rows.count);
        let generic_param_words = self
            .hir_generic_param_rows
            .read_words(generic_param_count.saturating_mul(4))?;
        let mut hir_generic_param_owner = Vec::with_capacity(generic_param_count);
        let mut hir_generic_param_name_token = Vec::with_capacity(generic_param_count);
        let mut hir_generic_param_kind = Vec::with_capacity(generic_param_count);
        let mut hir_generic_param_file_id = Vec::with_capacity(generic_param_count);
        for row in 0..generic_param_count {
            let base = row.saturating_mul(4);
            hir_generic_param_owner.push(generic_param_words[base]);
            hir_generic_param_name_token.push(generic_param_words[base + 1]);
            hir_generic_param_kind.push(generic_param_words[base + 2]);
            hir_generic_param_file_id.push(generic_param_words[base + 3]);
        }

        let path_count = self
            .hir_path_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let path_count = path_count.min(bufs.hir_path_rows.count);
        let path_words = self
            .hir_path_rows
            .read_words(path_count.saturating_mul(4))?;
        let mut hir_path_owner = Vec::with_capacity(path_count);
        let mut hir_path_segment_start = Vec::with_capacity(path_count);
        let mut hir_path_segment_count = Vec::with_capacity(path_count);
        let mut hir_path_kind = Vec::with_capacity(path_count);
        for row in 0..path_count {
            let base = row.saturating_mul(4);
            hir_path_owner.push(path_words[base]);
            hir_path_segment_start.push(path_words[base + 1]);
            hir_path_segment_count.push(path_words[base + 2]);
            hir_path_kind.push(path_words[base + 3]);
        }

        let path_segment_count = self
            .hir_path_segment_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let path_segment_count = path_segment_count.min(bufs.hir_path_segment_rows.count);
        let path_segment_words = self
            .hir_path_segment_rows
            .read_words(path_segment_count.saturating_mul(4))?;
        let mut hir_path_segment_path = Vec::with_capacity(path_segment_count);
        let mut hir_path_segment_name_token = Vec::with_capacity(path_segment_count);
        let mut hir_path_segment_ordinal = Vec::with_capacity(path_segment_count);
        let mut hir_path_segment_file_id = Vec::with_capacity(path_segment_count);
        for row in 0..path_segment_count {
            let base = row.saturating_mul(4);
            hir_path_segment_path.push(path_segment_words[base]);
            hir_path_segment_name_token.push(path_segment_words[base + 1]);
            hir_path_segment_ordinal.push(path_segment_words[base + 2]);
            hir_path_segment_file_id.push(path_segment_words[base + 3]);
        }

        let field_count = self
            .hir_field_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let field_count = field_count.min(bufs.hir_field_rows.count);
        let field_words = self
            .hir_field_rows
            .read_words(field_count.saturating_mul(4))?;
        let mut hir_field_owner = Vec::with_capacity(field_count);
        let mut hir_field_name_token = Vec::with_capacity(field_count);
        let mut hir_field_value = Vec::with_capacity(field_count);
        let mut hir_field_ordinal = Vec::with_capacity(field_count);
        for row in 0..field_count {
            let base = row.saturating_mul(4);
            hir_field_owner.push(field_words[base]);
            hir_field_name_token.push(field_words[base + 1]);
            hir_field_value.push(field_words[base + 2]);
            hir_field_ordinal.push(field_words[base + 3]);
        }

        let compact_variant_count = self
            .hir_compact_variant_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_variant_count = compact_variant_count.min(bufs.hir_variant_rows.count);
        let variant_words = self
            .hir_compact_variant_rows
            .read_words(compact_variant_count.saturating_mul(4))?;
        let mut hir_compact_variant_owner = Vec::with_capacity(compact_variant_count);
        let mut hir_compact_variant_name_token = Vec::with_capacity(compact_variant_count);
        let mut hir_compact_variant_ordinal = Vec::with_capacity(compact_variant_count);
        let mut hir_compact_variant_file_id = Vec::with_capacity(compact_variant_count);
        for row in 0..compact_variant_count {
            let base = row.saturating_mul(4);
            hir_compact_variant_owner.push(variant_words[base]);
            hir_compact_variant_name_token.push(variant_words[base + 1]);
            hir_compact_variant_ordinal.push(variant_words[base + 2]);
            hir_compact_variant_file_id.push(variant_words[base + 3]);
        }
        let hir_compact_variant_payload_start = self
            .hir_compact_variant_payload_start
            .read_words(compact_variant_count)?;
        let hir_compact_variant_payload_count = self
            .hir_compact_variant_payload_count
            .read_words(compact_variant_count)?;

        let compact_payload_count = self
            .hir_compact_variant_payload_row_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_payload_count = compact_payload_count.min(bufs.hir_variant_payload_rows.count);
        let payload_words = self
            .hir_compact_variant_payload_rows
            .read_words(compact_payload_count.saturating_mul(4))?;
        let mut hir_compact_variant_payload_variant = Vec::with_capacity(compact_payload_count);
        let mut hir_compact_variant_payload_type_node = Vec::with_capacity(compact_payload_count);
        let mut hir_compact_variant_payload_ordinal = Vec::with_capacity(compact_payload_count);
        let mut hir_compact_variant_payload_file_id = Vec::with_capacity(compact_payload_count);
        for row in 0..compact_payload_count {
            let base = row.saturating_mul(4);
            hir_compact_variant_payload_variant.push(payload_words[base]);
            hir_compact_variant_payload_type_node.push(payload_words[base + 1]);
            hir_compact_variant_payload_ordinal.push(payload_words[base + 2]);
            hir_compact_variant_payload_file_id.push(payload_words[base + 3]);
        }

        let compact_match_arm_count = self
            .hir_compact_match_arm_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_match_arm_count = compact_match_arm_count.min(bufs.hir_match_arm_rows.count);
        let match_arm_words = self
            .hir_compact_match_arm_rows
            .read_words(compact_match_arm_count.saturating_mul(4))?;
        let mut hir_compact_match_arm_owner = Vec::with_capacity(compact_match_arm_count);
        let mut hir_compact_match_arm_pattern = Vec::with_capacity(compact_match_arm_count);
        let mut hir_compact_match_arm_result = Vec::with_capacity(compact_match_arm_count);
        let mut hir_compact_match_arm_ordinal = Vec::with_capacity(compact_match_arm_count);
        for row in 0..compact_match_arm_count {
            let base = row.saturating_mul(4);
            hir_compact_match_arm_owner.push(match_arm_words[base]);
            hir_compact_match_arm_pattern.push(match_arm_words[base + 1]);
            hir_compact_match_arm_result.push(match_arm_words[base + 2]);
            hir_compact_match_arm_ordinal.push(match_arm_words[base + 3]);
        }
        let hir_compact_match_payload_start = self
            .hir_compact_match_payload_start
            .read_words(compact_match_arm_count)?;
        let hir_compact_match_payload_count = self
            .hir_compact_match_payload_count
            .read_words(compact_match_arm_count)?;

        let compact_match_payload_count = self
            .hir_compact_match_payload_row_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_match_payload_count =
            compact_match_payload_count.min(bufs.hir_match_payload_rows.count);
        let match_payload_words = self
            .hir_compact_match_payload_rows
            .read_words(compact_match_payload_count.saturating_mul(4))?;
        let mut hir_compact_match_payload_arm = Vec::with_capacity(compact_match_payload_count);
        let mut hir_compact_match_payload_pattern = Vec::with_capacity(compact_match_payload_count);
        let mut hir_compact_match_payload_ordinal = Vec::with_capacity(compact_match_payload_count);
        let mut hir_compact_match_payload_file_id = Vec::with_capacity(compact_match_payload_count);
        for row in 0..compact_match_payload_count {
            let base = row.saturating_mul(4);
            hir_compact_match_payload_arm.push(match_payload_words[base]);
            hir_compact_match_payload_pattern.push(match_payload_words[base + 1]);
            hir_compact_match_payload_ordinal.push(match_payload_words[base + 2]);
            hir_compact_match_payload_file_id.push(match_payload_words[base + 3]);
        }

        let compact_array_capacity = bufs.hir_canonical_capacity as usize;
        let hir_compact_array_element_start = self
            .hir_compact_array_element_start
            .read_words(compact_array_capacity)?;
        let hir_compact_array_element_count = self
            .hir_compact_array_element_count
            .read_words(compact_array_capacity)?;
        let compact_array_element_count = self
            .hir_compact_array_element_row_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_array_element_count =
            compact_array_element_count.min(bufs.hir_array_element_rows.count);
        let array_element_words = self
            .hir_compact_array_element_rows
            .read_words(compact_array_element_count.saturating_mul(4))?;
        let mut hir_compact_array_element_array = Vec::with_capacity(compact_array_element_count);
        let mut hir_compact_array_element_value = Vec::with_capacity(compact_array_element_count);
        let mut hir_compact_array_element_ordinal = Vec::with_capacity(compact_array_element_count);
        let mut hir_compact_array_element_file_id = Vec::with_capacity(compact_array_element_count);
        for row in 0..compact_array_element_count {
            let base = row.saturating_mul(4);
            hir_compact_array_element_array.push(array_element_words[base]);
            hir_compact_array_element_value.push(array_element_words[base + 1]);
            hir_compact_array_element_ordinal.push(array_element_words[base + 2]);
            hir_compact_array_element_file_id.push(array_element_words[base + 3]);
        }
        let compact_string_count = self
            .hir_compact_string_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_string_count = compact_string_count.min(bufs.hir_canonical_string_rows.count);
        let compact_string_words = self
            .hir_compact_string_rows
            .read_words(compact_string_count.saturating_mul(4))?;
        let mut hir_compact_string_node = Vec::with_capacity(compact_string_count);
        let mut hir_compact_string_data_offset = Vec::with_capacity(compact_string_count);
        let mut hir_compact_string_decoded_len = Vec::with_capacity(compact_string_count);
        let mut hir_compact_string_file_id = Vec::with_capacity(compact_string_count);
        for row in 0..compact_string_count {
            let base = row.saturating_mul(4);
            hir_compact_string_node.push(compact_string_words[base]);
            hir_compact_string_data_offset.push(compact_string_words[base + 1]);
            hir_compact_string_decoded_len.push(compact_string_words[base + 2]);
            hir_compact_string_file_id.push(compact_string_words[base + 3]);
        }
        let compact_method_count = self
            .hir_compact_method_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_method_count = compact_method_count.min(bufs.hir_method_core_rows.count);
        let method_core_words = self
            .hir_compact_method_cores
            .read_words(compact_method_count.saturating_mul(4))?;
        let method_signature_words = self
            .hir_compact_method_signatures
            .read_words(compact_method_count.saturating_mul(4))?;
        let mut hir_compact_method_node = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_owner = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_impl_node = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_name_token = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_first_param_token = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_impl_receiver_type = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_receiver_mode = Vec::with_capacity(compact_method_count);
        let mut hir_compact_method_metadata = Vec::with_capacity(compact_method_count);
        for row in 0..compact_method_count {
            let base = row.saturating_mul(4);
            hir_compact_method_node.push(method_core_words[base]);
            hir_compact_method_owner.push(method_core_words[base + 1]);
            hir_compact_method_impl_node.push(method_core_words[base + 2]);
            hir_compact_method_name_token.push(method_core_words[base + 3]);
            hir_compact_method_first_param_token.push(method_signature_words[base]);
            hir_compact_method_impl_receiver_type.push(method_signature_words[base + 1]);
            hir_compact_method_receiver_mode.push(method_signature_words[base + 2]);
            hir_compact_method_metadata.push(method_signature_words[base + 3]);
        }
        let compact_predicate_count = self
            .hir_compact_predicate_count
            .read_words(1)?
            .first()
            .copied()
            .unwrap_or(0) as usize;
        let compact_predicate_count = compact_predicate_count.min(bufs.hir_predicate_rows.count);
        let predicate_words = self
            .hir_compact_predicate_rows
            .read_words(compact_predicate_count.saturating_mul(4))?;
        let mut hir_compact_predicate_owner = Vec::with_capacity(compact_predicate_count);
        let mut hir_compact_predicate_subject = Vec::with_capacity(compact_predicate_count);
        let mut hir_compact_predicate_bound = Vec::with_capacity(compact_predicate_count);
        let mut hir_compact_predicate_metadata = Vec::with_capacity(compact_predicate_count);
        for row in 0..compact_predicate_count {
            let base = row.saturating_mul(4);
            hir_compact_predicate_owner.push(predicate_words[base]);
            hir_compact_predicate_subject.push(predicate_words[base + 1]);
            hir_compact_predicate_bound.push(predicate_words[base + 2]);
            hir_compact_predicate_metadata.push(predicate_words[base + 3]);
        }

        let result = ResidentParseResult {
            ll1: Ll1AcceptResult {
                accepted: ll1_words[0] != 0,
                error_pos: ll1_words[1],
                error_code: ll1_words[2],
                detail: ll1_words[3],
                steps: ll1_words[4],
                emit_len: ll1_words[5],
            },
            ll1_emit_stream: Vec::new(),
            ll1_emit_token_pos: Vec::new(),
            node_kind: self.node_kind.read_words(tree_len)?,
            parent: self.parent.read_words(tree_len)?,
            first_child: self.first_child.read_words(tree_len)?,
            next_sibling: self.next_sibling.read_words(tree_len)?,
            subtree_end: self.subtree_end.read_words(tree_len)?,
            hir_kind: self.hir_kind.read_words(tree_len)?,
            hir_semantic_prefix_before_node: self
                .hir_semantic_prefix_before_node
                .read_words(tree_len)?,
            hir_semantic_dense_node: self.hir_semantic_dense_node.read_words(tree_len)?,
            hir_semantic_subtree_end: self.hir_semantic_subtree_end.read_words(tree_len)?,
            hir_semantic_parent: self.hir_semantic_parent.read_words(tree_len)?,
            hir_semantic_first_child: self.hir_semantic_first_child.read_words(tree_len)?,
            hir_semantic_next_sibling: self.hir_semantic_next_sibling.read_words(tree_len)?,
            hir_semantic_depth: self.hir_semantic_depth.read_words(tree_len)?,
            hir_semantic_child_index: self.hir_semantic_child_index.read_words(tree_len)?,
            hir_token_pos: self.hir_token_pos.read_words(tree_len)?,
            hir_token_end: self.hir_token_end.read_words(tree_len)?,
            hir_node_file_id: self.hir_node_file_id.read_words(tree_len)?,
            hir_type_form: self.hir_type_form.read_words(tree_len)?,
            hir_type_value_node: self.hir_type_value_node.read_words(tree_len)?,
            hir_type_len_token: self.hir_type_len_token.read_words(tree_len)?,
            hir_type_len_value: self.hir_type_len_value.read_words(tree_len)?,
            hir_type_file_id: self.hir_type_file_id.read_words(tree_len)?,
            hir_type_path_leaf_node: self.hir_type_path_leaf_node.read_words(tree_len)?,
            hir_type_arg_start: self.hir_type_arg_start.read_words(tree_len)?,
            hir_type_arg_count: self.hir_type_arg_count.read_words(tree_len)?,
            hir_type_arg_next: self.hir_type_arg_next.read_words(tree_len)?,
            hir_type_alias_target_node: self.hir_type_alias_target_node.read_words(tree_len)?,
            hir_fn_return_type_node: self.hir_fn_return_type_node.read_words(tree_len)?,
            hir_method_signature_flags: self.hir_method_signature_flags.read_words(tree_len)?,
            hir_stmt_record_kind,
            hir_stmt_record_operand0,
            hir_stmt_record_operand1,
            hir_stmt_record_operand2,
            hir_stmt_scope_end: self.hir_stmt_scope_end.read_words(tree_len)?,
            hir_item_kind: self.hir_item_kind.read_words(tree_len)?,
            hir_item_name_token: self.hir_item_name_token.read_words(tree_len)?,
            hir_item_decl_token: self.hir_item_decl_token.read_words(tree_len)?,
            hir_item_namespace: self.hir_item_namespace.read_words(tree_len)?,
            hir_item_visibility: self.hir_item_visibility.read_words(tree_len)?,
            hir_item_path_start: self.hir_item_path_start.read_words(tree_len)?,
            hir_item_path_end: self.hir_item_path_end.read_words(tree_len)?,
            hir_item_path_node: self.hir_item_path_node.read_words(tree_len)?,
            hir_item_file_id: self.hir_item_file_id.read_words(tree_len)?,
            hir_item_import_target_kind: self.hir_item_import_target_kind.read_words(tree_len)?,
            hir_variant_parent_enum: self
                .hir_variant_parent_enum
                .read_words_padded(tree_len, u32::MAX)?,
            hir_variant_ordinal: self
                .hir_variant_ordinal
                .read_words_padded(tree_len, u32::MAX)?,
            hir_variant_payload_start: self
                .hir_variant_payload_start
                .read_words_padded(tree_len, u32::MAX)?,
            hir_variant_payload_count: self
                .hir_variant_payload_count
                .read_words_padded(tree_len, 0)?,
            hir_variant_payload_node: self
                .hir_variant_payload_node
                .read_words_padded(tree_len.saturating_mul(4), u32::MAX)?,
            hir_match_scrutinee_node: self
                .hir_match_scrutinee_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_arm_start: self
                .hir_match_arm_start
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_arm_count: self.hir_match_arm_count.read_words_padded(tree_len, 0)?,
            hir_match_arm_next: self
                .hir_match_arm_next
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_arm_pattern_node: self
                .hir_match_arm_pattern_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_arm_payload_start: self
                .hir_match_arm_payload_start
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_arm_payload_count: self
                .hir_match_arm_payload_count
                .read_words_padded(tree_len, 0)?,
            hir_match_arm_result_node: self
                .hir_match_arm_result_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_payload_owner_arm: self
                .hir_match_payload_owner_arm
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_payload_match_node: self
                .hir_match_payload_match_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_match_payload_ordinal: self
                .hir_match_payload_ordinal
                .read_words_padded(tree_len, u32::MAX)?,
            hir_call_callee_node: self.hir_call_callee_node.read_words(tree_len)?,
            hir_call_callee_path_node: self.hir_call_callee_path_node.read_words(tree_len)?,
            hir_call_parent_by_callee: self.hir_call_parent_by_callee.read_words(tree_len)?,
            hir_call_context_stmt_node: self.hir_call_context_stmt_node.read_words(tree_len)?,
            hir_call_arg_start: self.hir_call_arg_start.read_words(tree_len)?,
            hir_call_arg_end: self.hir_call_arg_end.read_words(tree_len)?,
            hir_call_arg_count: self.hir_call_arg_count.read_words(tree_len)?,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_array_lit_first_element: self
                .hir_array_lit_first_element
                .read_words_padded(tree_len, u32::MAX)?,
            hir_array_lit_element_count: self
                .hir_array_lit_element_count
                .read_words_padded(tree_len, 0)?,
            hir_array_lit_context_stmt_node: self
                .hir_array_lit_context_stmt_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_array_element_parent_lit: self
                .hir_array_element_parent_lit
                .read_words_padded(tree_len, u32::MAX)?,
            hir_array_element_ordinal: self
                .hir_array_element_ordinal
                .read_words_padded(tree_len, u32::MAX)?,
            hir_array_element_next: self
                .hir_array_element_next
                .read_words_padded(tree_len, u32::MAX)?,
            hir_expr_name_role: self.hir_expr_name_role.read_words(tree_len)?,
            hir_expr_result_root_node: self.hir_expr_result_root_node.read_words(tree_len)?,
            hir_expr_parent_node: self.hir_expr_parent_node.read_words(tree_len)?,
            hir_expr_forest_root_node: self.hir_expr_forest_root_node.read_words(tree_len)?,
            hir_expr_forest_status: self
                .hir_expr_forest_status
                .read_words(1)?
                .first()
                .copied()
                .unwrap_or(u32::MAX),
            hir_member_receiver_node: self.hir_member_receiver_node.read_words(tree_len)?,
            hir_member_receiver_token: self.hir_member_receiver_token.read_words(tree_len)?,
            hir_member_name_token: self.hir_member_name_token.read_words(tree_len)?,
            hir_nearest_stmt_node: self.hir_nearest_stmt_node.read_words(tree_len)?,
            hir_nearest_block_node: self.hir_nearest_block_node.read_words(tree_len)?,
            hir_nearest_enclosing_control_node: self
                .hir_nearest_enclosing_control_node
                .read_words(tree_len)?,
            hir_nearest_loop_node: self.hir_nearest_loop_node.read_words(tree_len)?,
            hir_nearest_fn_node: self.hir_nearest_fn_node.read_words(tree_len)?,
            hir_nearest_array_element_node: self
                .hir_nearest_array_element_node
                .read_words(tree_len)?,
            hir_struct_field_parent_struct: self
                .hir_struct_field_parent_struct
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_field_ordinal: self
                .hir_struct_field_ordinal
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_field_type_node: self
                .hir_struct_field_type_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_decl_field_start: self
                .hir_struct_decl_field_start
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_decl_field_count: self
                .hir_struct_decl_field_count
                .read_words_padded(tree_len, 0)?,
            hir_struct_lit_head_node: self
                .hir_struct_lit_head_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_lit_context_stmt_node: self
                .hir_struct_lit_context_stmt_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_lit_field_start: self
                .hir_struct_lit_field_start
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_lit_field_count: self
                .hir_struct_lit_field_count
                .read_words_padded(tree_len, 0)?,
            hir_struct_lit_field_parent_lit: self
                .hir_struct_lit_field_parent_lit
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_lit_field_value_node: self
                .hir_struct_lit_field_value_node
                .read_words_padded(tree_len, u32::MAX)?,
            hir_struct_lit_field_next: self
                .hir_struct_lit_field_next
                .read_words_padded(tree_len, u32::MAX)?,
            hir_canonical_count: self
                .hir_canonical_count
                .read_words(1)?
                .first()
                .copied()
                .unwrap_or(0),
            hir_canonical_dense_to_raw: self
                .hir_canonical_dense_to_raw
                .read_words(compact_array_capacity)?,
            hir_canonical_raw_to_dense: self.hir_canonical_raw_to_dense.read_words(tree_len)?,
            hir_param_range_start,
            hir_param_range_count,
            hir_type_arg_range_start,
            hir_type_arg_range_count,
            hir_generic_param_owner,
            hir_generic_param_name_token,
            hir_generic_param_kind,
            hir_generic_param_file_id,
            hir_generic_param_range_start,
            hir_generic_param_range_count,
            hir_path_owner,
            hir_path_segment_start,
            hir_path_segment_count,
            hir_path_kind,
            hir_path_segment_path,
            hir_path_segment_name_token,
            hir_path_segment_ordinal,
            hir_path_segment_file_id,
            hir_field_owner,
            hir_field_name_token,
            hir_field_value,
            hir_field_ordinal,
            hir_compact_variant_owner,
            hir_compact_variant_name_token,
            hir_compact_variant_ordinal,
            hir_compact_variant_file_id,
            hir_compact_variant_payload_start,
            hir_compact_variant_payload_count,
            hir_compact_variant_payload_variant,
            hir_compact_variant_payload_type_node,
            hir_compact_variant_payload_ordinal,
            hir_compact_variant_payload_file_id,
            hir_compact_match_arm_owner,
            hir_compact_match_arm_pattern,
            hir_compact_match_arm_result,
            hir_compact_match_arm_ordinal,
            hir_compact_match_payload_start,
            hir_compact_match_payload_count,
            hir_compact_match_payload_arm,
            hir_compact_match_payload_pattern,
            hir_compact_match_payload_ordinal,
            hir_compact_match_payload_file_id,
            hir_compact_array_element_start,
            hir_compact_array_element_count,
            hir_compact_array_element_array,
            hir_compact_array_element_value,
            hir_compact_array_element_ordinal,
            hir_compact_array_element_file_id,
            hir_compact_string_node,
            hir_compact_string_data_offset,
            hir_compact_string_decoded_len,
            hir_compact_string_file_id,
            hir_compact_method_node,
            hir_compact_method_owner,
            hir_compact_method_impl_node,
            hir_compact_method_name_token,
            hir_compact_method_first_param_token,
            hir_compact_method_impl_receiver_type,
            hir_compact_method_receiver_mode,
            hir_compact_method_metadata,
            hir_compact_predicate_owner,
            hir_compact_predicate_subject,
            hir_compact_predicate_bound,
            hir_compact_predicate_metadata,
        };
        validate_hir_source_address_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_type_form,
            &result.hir_type_file_id,
            &result.hir_item_kind,
            &result.hir_item_file_id,
        )?;
        validate_hir_semantic_tree_records(
            &result.hir_kind,
            &result.subtree_end,
            &result.hir_semantic_prefix_before_node,
            &result.hir_semantic_dense_node,
            &result.hir_semantic_subtree_end,
            &result.hir_semantic_parent,
            &result.hir_semantic_first_child,
            &result.hir_semantic_next_sibling,
            &result.hir_semantic_depth,
            &result.hir_semantic_child_index,
        )?;
        validate_hir_statement_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_stmt_record_kind,
            &result.hir_stmt_record_operand0,
            &result.hir_stmt_record_operand1,
            &result.hir_stmt_record_operand2,
            &result.hir_stmt_scope_end,
        )?;
        validate_hir_context_relation_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_stmt_record_kind,
            &result.hir_nearest_stmt_node,
            &result.hir_nearest_block_node,
            &result.hir_nearest_enclosing_control_node,
            &result.hir_nearest_loop_node,
            &result.hir_nearest_fn_node,
            &result.hir_call_context_stmt_node,
            &result.hir_array_lit_context_stmt_node,
            &result.hir_struct_lit_context_stmt_node,
        )?;
        validate_hir_expression_result_root_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_expr_result_root_node,
        )?;
        validate_hir_call_argument_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_call_callee_node,
            &result.hir_call_arg_start,
            &result.hir_call_arg_end,
            &result.hir_call_arg_count,
            &result.hir_call_arg_parent_call,
            &result.hir_call_arg_ordinal,
        )?;
        validate_hir_enum_variant_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_type_form,
            &result.hir_type_file_id,
            &result.hir_item_kind,
            &result.hir_item_file_id,
            &result.hir_variant_parent_enum,
            &result.hir_variant_ordinal,
            &result.hir_variant_payload_start,
            &result.hir_variant_payload_count,
            &result.hir_variant_payload_node,
        )?;
        validate_hir_struct_declaration_field_records(
            &result.hir_kind,
            &result.hir_token_pos,
            &result.hir_token_end,
            &result.hir_node_file_id,
            &result.hir_type_form,
            &result.hir_type_file_id,
            &result.hir_item_kind,
            &result.hir_item_file_id,
            &result.hir_struct_field_parent_struct,
            &result.hir_struct_field_ordinal,
            &result.hir_struct_field_type_node,
            &result.hir_struct_decl_field_start,
            &result.hir_struct_decl_field_count,
        )?;
        Ok(result)
    }
}

impl GpuParser {
    /// Submits a resident tree encoder, maps readbacks, and assembles the parse result.
    pub(super) fn finish_resident_tree_readback(
        &self,
        mut encoder: wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<ResidentParseResult> {
        let readbacks = ResidentTreeReadbacks::create(&self.device, bufs);
        readbacks.encode_copies(&mut encoder, bufs);

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        crate::gpu::passes_core::submit_with_optional_validation(
            &self.device,
            &self.queue,
            "parser.resident-tree",
            encoder.finish(),
            use_scopes,
            "resident parser tree batch",
        );

        readbacks.map_all();
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "parser.resident-tree",
            wgpu::PollType::wait_indefinitely(),
        );
        readbacks.decode(bufs)
    }
}

fn rb(device: &wgpu::Device, label: &'static str, byte_size: usize) -> U32Readback {
    U32Readback::create(device, label, byte_size as u64)
}
