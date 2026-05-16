use anyhow::Result;

use super::{
    GpuParser,
    Ll1AcceptResult,
    ResidentParseResult,
    support::{bool_from_env, read_u32_words},
};
use crate::parser::buffers::ParserBuffers;

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
    hir_token_pos: U32Readback,
    hir_token_end: U32Readback,
    hir_type_form: U32Readback,
    hir_type_value_node: U32Readback,
    hir_type_len_token: U32Readback,
    hir_type_len_value: U32Readback,
    hir_type_file_id: U32Readback,
    hir_item_kind: U32Readback,
    hir_item_name_token: U32Readback,
    hir_item_decl_token: U32Readback,
    hir_item_namespace: U32Readback,
    hir_item_visibility: U32Readback,
    hir_item_path_start: U32Readback,
    hir_item_path_end: U32Readback,
    hir_item_file_id: U32Readback,
    hir_item_import_target_kind: U32Readback,
    hir_variant_parent_enum: U32Readback,
    hir_variant_ordinal: U32Readback,
    hir_variant_payload_start: U32Readback,
    hir_variant_payload_count: U32Readback,
    hir_match_scrutinee_node: U32Readback,
    hir_match_arm_start: U32Readback,
    hir_match_arm_count: U32Readback,
    hir_match_arm_pattern_node: U32Readback,
    hir_match_arm_payload_start: U32Readback,
    hir_match_arm_payload_count: U32Readback,
    hir_match_arm_result_node: U32Readback,
    hir_call_callee_node: U32Readback,
    hir_call_arg_start: U32Readback,
    hir_call_arg_end: U32Readback,
    hir_call_arg_count: U32Readback,
    hir_call_arg_parent_call: U32Readback,
    hir_call_arg_ordinal: U32Readback,
    hir_member_receiver_node: U32Readback,
    hir_member_receiver_token: U32Readback,
    hir_member_name_token: U32Readback,
    hir_struct_field_parent_struct: U32Readback,
    hir_struct_field_ordinal: U32Readback,
    hir_struct_field_type_node: U32Readback,
    hir_struct_decl_field_start: U32Readback,
    hir_struct_decl_field_count: U32Readback,
    hir_struct_lit_head_node: U32Readback,
    hir_struct_lit_field_start: U32Readback,
    hir_struct_lit_field_count: U32Readback,
    hir_struct_lit_field_parent_lit: U32Readback,
    hir_struct_lit_field_value_node: U32Readback,
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
            hir_call_callee_node: rb(
                device,
                "rb.parser.resident_tree.hir_call_callee_node",
                bufs.hir_call_callee_node.byte_size,
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
        self.hir_call_callee_node.copy_from(
            encoder,
            &bufs.hir_call_callee_node,
            bufs.hir_call_callee_node.byte_size as u64,
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
        self.hir_token_pos.map();
        self.hir_token_end.map();
        self.hir_type_form.map();
        self.hir_type_value_node.map();
        self.hir_type_len_token.map();
        self.hir_type_len_value.map();
        self.hir_type_file_id.map();
        self.hir_item_kind.map();
        self.hir_item_name_token.map();
        self.hir_item_decl_token.map();
        self.hir_item_namespace.map();
        self.hir_item_visibility.map();
        self.hir_item_path_start.map();
        self.hir_item_path_end.map();
        self.hir_item_file_id.map();
        self.hir_item_import_target_kind.map();
        self.hir_variant_parent_enum.map();
        self.hir_variant_ordinal.map();
        self.hir_variant_payload_start.map();
        self.hir_variant_payload_count.map();
        self.hir_match_scrutinee_node.map();
        self.hir_match_arm_start.map();
        self.hir_match_arm_count.map();
        self.hir_match_arm_pattern_node.map();
        self.hir_match_arm_payload_start.map();
        self.hir_match_arm_payload_count.map();
        self.hir_match_arm_result_node.map();
        self.hir_call_callee_node.map();
        self.hir_call_arg_start.map();
        self.hir_call_arg_end.map();
        self.hir_call_arg_count.map();
        self.hir_call_arg_parent_call.map();
        self.hir_call_arg_ordinal.map();
        self.hir_member_receiver_node.map();
        self.hir_member_receiver_token.map();
        self.hir_member_name_token.map();
        self.hir_struct_field_parent_struct.map();
        self.hir_struct_field_ordinal.map();
        self.hir_struct_field_type_node.map();
        self.hir_struct_decl_field_start.map();
        self.hir_struct_decl_field_count.map();
        self.hir_struct_lit_head_node.map();
        self.hir_struct_lit_field_start.map();
        self.hir_struct_lit_field_count.map();
        self.hir_struct_lit_field_parent_lit.map();
        self.hir_struct_lit_field_value_node.map();
    }

    fn decode(&self, bufs: &ParserBuffers) -> Result<ResidentParseResult> {
        let ll1_words = self.status.read_words(6)?;
        let emit_len = (ll1_words[5] as usize).min(bufs.ll1_emit.count);

        Ok(ResidentParseResult {
            ll1: Ll1AcceptResult {
                accepted: ll1_words[0] != 0,
                error_pos: ll1_words[1],
                error_code: ll1_words[2],
                detail: ll1_words[3],
                steps: ll1_words[4],
                emit_len: ll1_words[5],
            },
            ll1_emit_stream: self.emit.read_words(emit_len)?,
            ll1_emit_token_pos: self.emit_pos.read_words(emit_len)?,
            node_kind: self.node_kind.read_words(emit_len)?,
            parent: self.parent.read_words(emit_len)?,
            first_child: self.first_child.read_words(emit_len)?,
            next_sibling: self.next_sibling.read_words(emit_len)?,
            subtree_end: self.subtree_end.read_words(emit_len)?,
            hir_kind: self.hir_kind.read_words(emit_len)?,
            hir_token_pos: self.hir_token_pos.read_words(emit_len)?,
            hir_token_end: self.hir_token_end.read_words(emit_len)?,
            hir_type_form: self.hir_type_form.read_words(emit_len)?,
            hir_type_value_node: self.hir_type_value_node.read_words(emit_len)?,
            hir_type_len_token: self.hir_type_len_token.read_words(emit_len)?,
            hir_type_len_value: self.hir_type_len_value.read_words(emit_len)?,
            hir_type_file_id: self.hir_type_file_id.read_words(emit_len)?,
            hir_item_kind: self.hir_item_kind.read_words(emit_len)?,
            hir_item_name_token: self.hir_item_name_token.read_words(emit_len)?,
            hir_item_decl_token: self.hir_item_decl_token.read_words(emit_len)?,
            hir_item_namespace: self.hir_item_namespace.read_words(emit_len)?,
            hir_item_visibility: self.hir_item_visibility.read_words(emit_len)?,
            hir_item_path_start: self.hir_item_path_start.read_words(emit_len)?,
            hir_item_path_end: self.hir_item_path_end.read_words(emit_len)?,
            hir_item_file_id: self.hir_item_file_id.read_words(emit_len)?,
            hir_item_import_target_kind: self.hir_item_import_target_kind.read_words(emit_len)?,
            hir_variant_parent_enum: self.hir_variant_parent_enum.read_words(emit_len)?,
            hir_variant_ordinal: self.hir_variant_ordinal.read_words(emit_len)?,
            hir_variant_payload_start: self.hir_variant_payload_start.read_words(emit_len)?,
            hir_variant_payload_count: self.hir_variant_payload_count.read_words(emit_len)?,
            hir_match_scrutinee_node: self.hir_match_scrutinee_node.read_words(emit_len)?,
            hir_match_arm_start: self.hir_match_arm_start.read_words(emit_len)?,
            hir_match_arm_count: self.hir_match_arm_count.read_words(emit_len)?,
            hir_match_arm_pattern_node: self.hir_match_arm_pattern_node.read_words(emit_len)?,
            hir_match_arm_payload_start: self.hir_match_arm_payload_start.read_words(emit_len)?,
            hir_match_arm_payload_count: self.hir_match_arm_payload_count.read_words(emit_len)?,
            hir_match_arm_result_node: self.hir_match_arm_result_node.read_words(emit_len)?,
            hir_call_callee_node: self.hir_call_callee_node.read_words(emit_len)?,
            hir_call_arg_start: self.hir_call_arg_start.read_words(emit_len)?,
            hir_call_arg_end: self.hir_call_arg_end.read_words(emit_len)?,
            hir_call_arg_count: self.hir_call_arg_count.read_words(emit_len)?,
            hir_call_arg_parent_call: self.hir_call_arg_parent_call.read_words(emit_len)?,
            hir_call_arg_ordinal: self.hir_call_arg_ordinal.read_words(emit_len)?,
            hir_member_receiver_node: self.hir_member_receiver_node.read_words(emit_len)?,
            hir_member_receiver_token: self.hir_member_receiver_token.read_words(emit_len)?,
            hir_member_name_token: self.hir_member_name_token.read_words(emit_len)?,
            hir_struct_field_parent_struct: self
                .hir_struct_field_parent_struct
                .read_words(emit_len)?,
            hir_struct_field_ordinal: self.hir_struct_field_ordinal.read_words(emit_len)?,
            hir_struct_field_type_node: self.hir_struct_field_type_node.read_words(emit_len)?,
            hir_struct_decl_field_start: self.hir_struct_decl_field_start.read_words(emit_len)?,
            hir_struct_decl_field_count: self.hir_struct_decl_field_count.read_words(emit_len)?,
            hir_struct_lit_head_node: self.hir_struct_lit_head_node.read_words(emit_len)?,
            hir_struct_lit_field_start: self.hir_struct_lit_field_start.read_words(emit_len)?,
            hir_struct_lit_field_count: self.hir_struct_lit_field_count.read_words(emit_len)?,
            hir_struct_lit_field_parent_lit: self
                .hir_struct_lit_field_parent_lit
                .read_words(emit_len)?,
            hir_struct_lit_field_value_node: self
                .hir_struct_lit_field_value_node
                .read_words(emit_len)?,
        })
    }
}

impl GpuParser {
    pub(super) fn finish_resident_tree_readback(
        &self,
        mut encoder: wgpu::CommandEncoder,
        bufs: &ParserBuffers,
    ) -> Result<ResidentParseResult> {
        let readbacks = ResidentTreeReadbacks::create(&self.device, bufs);
        readbacks.encode_copies(&mut encoder, bufs);

        let use_scopes = bool_from_env("LANIUS_VALIDATION_SCOPES", false);
        if use_scopes {
            self.device.push_error_scope(wgpu::ErrorFilter::Validation);
        }
        crate::gpu::passes_core::submit_with_progress(
            &self.queue,
            "parser.resident-tree",
            encoder.finish(),
        );
        if use_scopes {
            if let Some(err) = pollster::block_on(self.device.pop_error_scope()) {
                eprintln!(
                    "[wgpu submit] validation while submitting resident parser tree batch: {err:#?}"
                );
            }
        }

        readbacks.map_all();
        crate::gpu::passes_core::wait_for_map_progress(
            &self.device,
            "parser.resident-tree",
            wgpu::PollType::Wait,
        );
        readbacks.decode(bufs)
    }
}

fn rb(device: &wgpu::Device, label: &'static str, byte_size: usize) -> U32Readback {
    U32Readback::create(device, label, byte_size as u64)
}
