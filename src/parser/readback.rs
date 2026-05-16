use anyhow::{Result, anyhow};
use wgpu;

use super::buffers::{ActionHeader, ParserBuffers};

/// Staging buffers for parser readbacks.
pub struct ParserReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub ll1_emit: wgpu::Buffer,
    pub ll1_emit_pos: wgpu::Buffer,
    pub ll1_block_seed_len: wgpu::Buffer,
    pub ll1_seed_plan_status: wgpu::Buffer,
    pub ll1_seeded_status: wgpu::Buffer,
    pub ll1_seeded_emit: wgpu::Buffer,
    pub headers: wgpu::Buffer,
    pub sc: wgpu::Buffer,
    pub emit: wgpu::Buffer,
    pub match_idx: wgpu::Buffer,
    pub depths: wgpu::Buffer,
    pub valid: wgpu::Buffer,
    pub node_kind: wgpu::Buffer,
    pub parent: wgpu::Buffer,
    pub first_child: wgpu::Buffer,
    pub next_sibling: wgpu::Buffer,
    pub subtree_end: wgpu::Buffer,
    pub hir_kind: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
    pub hir_type_form: wgpu::Buffer,
    pub hir_type_value_node: wgpu::Buffer,
    pub hir_type_len_token: wgpu::Buffer,
    pub hir_type_len_value: wgpu::Buffer,
    pub hir_type_file_id: wgpu::Buffer,
    pub hir_item_kind: wgpu::Buffer,
    pub hir_item_name_token: wgpu::Buffer,
    pub hir_item_decl_token: wgpu::Buffer,
    pub hir_item_namespace: wgpu::Buffer,
    pub hir_item_visibility: wgpu::Buffer,
    pub hir_item_path_start: wgpu::Buffer,
    pub hir_item_path_end: wgpu::Buffer,
    pub hir_item_file_id: wgpu::Buffer,
    pub hir_item_import_target_kind: wgpu::Buffer,
    pub hir_variant_parent_enum: wgpu::Buffer,
    pub hir_variant_ordinal: wgpu::Buffer,
    pub hir_variant_payload_start: wgpu::Buffer,
    pub hir_variant_payload_count: wgpu::Buffer,
    pub hir_match_scrutinee_node: wgpu::Buffer,
    pub hir_match_arm_start: wgpu::Buffer,
    pub hir_match_arm_count: wgpu::Buffer,
    pub hir_match_arm_pattern_node: wgpu::Buffer,
    pub hir_match_arm_payload_start: wgpu::Buffer,
    pub hir_match_arm_payload_count: wgpu::Buffer,
    pub hir_match_arm_result_node: wgpu::Buffer,
    pub hir_call_callee_node: wgpu::Buffer,
    pub hir_call_arg_start: wgpu::Buffer,
    pub hir_call_arg_end: wgpu::Buffer,
    pub hir_call_arg_count: wgpu::Buffer,
    pub hir_call_arg_parent_call: wgpu::Buffer,
    pub hir_call_arg_ordinal: wgpu::Buffer,
    pub hir_member_receiver_node: wgpu::Buffer,
    pub hir_member_receiver_token: wgpu::Buffer,
    pub hir_member_name_token: wgpu::Buffer,
    pub hir_struct_field_parent_struct: wgpu::Buffer,
    pub hir_struct_field_ordinal: wgpu::Buffer,
    pub hir_struct_field_type_node: wgpu::Buffer,
    pub hir_struct_decl_field_start: wgpu::Buffer,
    pub hir_struct_decl_field_count: wgpu::Buffer,
    pub hir_struct_lit_head_node: wgpu::Buffer,
    pub hir_struct_lit_field_start: wgpu::Buffer,
    pub hir_struct_lit_field_count: wgpu::Buffer,
    pub hir_struct_lit_field_parent_lit: wgpu::Buffer,
    pub hir_struct_lit_field_value_node: wgpu::Buffer,
}

impl ParserReadbacks {
    pub fn create(device: &wgpu::Device, bufs: &ParserBuffers) -> Self {
        // Helper to make a MAP_READ + COPY_DST buffer of given size.
        let mk = |label: &str, size: u64| {
            device.create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size,
                usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
                mapped_at_creation: false,
            })
        };

        let ll1_status = mk("rb.parser.ll1_status", bufs.ll1_status.byte_size as u64);
        let ll1_emit = mk("rb.parser.ll1_emit", bufs.ll1_emit.byte_size as u64);
        let ll1_emit_pos = mk("rb.parser.ll1_emit_pos", bufs.ll1_emit_pos.byte_size as u64);
        let ll1_block_seed_len = mk(
            "rb.parser.ll1_block_seed_len",
            bufs.ll1_block_seed_len.byte_size as u64,
        );
        let ll1_seed_plan_status = mk(
            "rb.parser.ll1_seed_plan_status",
            bufs.ll1_seed_plan_status.byte_size as u64,
        );
        let ll1_seeded_status = mk(
            "rb.parser.ll1_seeded_status",
            bufs.ll1_seeded_status.byte_size as u64,
        );
        let ll1_seeded_emit = mk(
            "rb.parser.ll1_seeded_emit",
            bufs.ll1_seeded_emit.byte_size as u64,
        );
        let headers = mk("rb.parser.out_headers", bufs.out_headers.byte_size as u64);
        let sc_bytes = (bufs.total_sc.max(1) * 4) as u64;
        let emit_bytes = (bufs.total_emit.max(1) * 4) as u64;

        let sc = mk("rb.parser.out_sc", sc_bytes);
        let emit = mk("rb.parser.out_emit", emit_bytes);
        let match_idx = mk("rb.parser.match_for_index", sc_bytes);
        let depths = mk("rb.parser.depths_out", bufs.depths_out.byte_size as u64);
        let valid = mk("rb.parser.valid_out", bufs.valid_out.byte_size as u64);
        let node_kind = mk("rb.parser.node_kind", bufs.node_kind.byte_size as u64);
        let parent = mk("rb.parser.parent", bufs.parent.byte_size as u64);
        let first_child = mk("rb.parser.first_child", bufs.first_child.byte_size as u64);
        let next_sibling = mk("rb.parser.next_sibling", bufs.next_sibling.byte_size as u64);
        let subtree_end = mk("rb.parser.subtree_end", bufs.subtree_end.byte_size as u64);
        let hir_kind = mk("rb.parser.hir_kind", bufs.hir_kind.byte_size as u64);
        let hir_token_pos = mk(
            "rb.parser.hir_token_pos",
            bufs.hir_token_pos.byte_size as u64,
        );
        let hir_token_end = mk(
            "rb.parser.hir_token_end",
            bufs.hir_token_end.byte_size as u64,
        );
        let hir_type_form = mk(
            "rb.parser.hir_type_form",
            bufs.hir_type_form.byte_size as u64,
        );
        let hir_type_value_node = mk(
            "rb.parser.hir_type_value_node",
            bufs.hir_type_value_node.byte_size as u64,
        );
        let hir_type_len_token = mk(
            "rb.parser.hir_type_len_token",
            bufs.hir_type_len_token.byte_size as u64,
        );
        let hir_type_len_value = mk(
            "rb.parser.hir_type_len_value",
            bufs.hir_type_len_value.byte_size as u64,
        );
        let hir_type_file_id = mk(
            "rb.parser.hir_type_file_id",
            bufs.hir_type_file_id.byte_size as u64,
        );
        let hir_item_kind = mk(
            "rb.parser.hir_item_kind",
            bufs.hir_item_kind.byte_size as u64,
        );
        let hir_item_name_token = mk(
            "rb.parser.hir_item_name_token",
            bufs.hir_item_name_token.byte_size as u64,
        );
        let hir_item_decl_token = mk(
            "rb.parser.hir_item_decl_token",
            bufs.hir_item_decl_token.byte_size as u64,
        );
        let hir_item_namespace = mk(
            "rb.parser.hir_item_namespace",
            bufs.hir_item_namespace.byte_size as u64,
        );
        let hir_item_visibility = mk(
            "rb.parser.hir_item_visibility",
            bufs.hir_item_visibility.byte_size as u64,
        );
        let hir_item_path_start = mk(
            "rb.parser.hir_item_path_start",
            bufs.hir_item_path_start.byte_size as u64,
        );
        let hir_item_path_end = mk(
            "rb.parser.hir_item_path_end",
            bufs.hir_item_path_end.byte_size as u64,
        );
        let hir_item_file_id = mk(
            "rb.parser.hir_item_file_id",
            bufs.hir_item_file_id.byte_size as u64,
        );
        let hir_item_import_target_kind = mk(
            "rb.parser.hir_item_import_target_kind",
            bufs.hir_item_import_target_kind.byte_size as u64,
        );
        let hir_variant_parent_enum = mk(
            "rb.parser.hir_variant_parent_enum",
            bufs.hir_variant_parent_enum.byte_size as u64,
        );
        let hir_variant_ordinal = mk(
            "rb.parser.hir_variant_ordinal",
            bufs.hir_variant_ordinal.byte_size as u64,
        );
        let hir_variant_payload_start = mk(
            "rb.parser.hir_variant_payload_start",
            bufs.hir_variant_payload_start.byte_size as u64,
        );
        let hir_variant_payload_count = mk(
            "rb.parser.hir_variant_payload_count",
            bufs.hir_variant_payload_count.byte_size as u64,
        );
        let hir_match_scrutinee_node = mk(
            "rb.parser.hir_match_scrutinee_node",
            bufs.hir_match_scrutinee_node.byte_size as u64,
        );
        let hir_match_arm_start = mk(
            "rb.parser.hir_match_arm_start",
            bufs.hir_match_arm_start.byte_size as u64,
        );
        let hir_match_arm_count = mk(
            "rb.parser.hir_match_arm_count",
            bufs.hir_match_arm_count.byte_size as u64,
        );
        let hir_match_arm_pattern_node = mk(
            "rb.parser.hir_match_arm_pattern_node",
            bufs.hir_match_arm_pattern_node.byte_size as u64,
        );
        let hir_match_arm_payload_start = mk(
            "rb.parser.hir_match_arm_payload_start",
            bufs.hir_match_arm_payload_start.byte_size as u64,
        );
        let hir_match_arm_payload_count = mk(
            "rb.parser.hir_match_arm_payload_count",
            bufs.hir_match_arm_payload_count.byte_size as u64,
        );
        let hir_match_arm_result_node = mk(
            "rb.parser.hir_match_arm_result_node",
            bufs.hir_match_arm_result_node.byte_size as u64,
        );
        let hir_call_callee_node = mk(
            "rb.parser.hir_call_callee_node",
            bufs.hir_call_callee_node.byte_size as u64,
        );
        let hir_call_arg_start = mk(
            "rb.parser.hir_call_arg_start",
            bufs.hir_call_arg_start.byte_size as u64,
        );
        let hir_call_arg_end = mk(
            "rb.parser.hir_call_arg_end",
            bufs.hir_call_arg_end.byte_size as u64,
        );
        let hir_call_arg_count = mk(
            "rb.parser.hir_call_arg_count",
            bufs.hir_call_arg_count.byte_size as u64,
        );
        let hir_call_arg_parent_call = mk(
            "rb.parser.hir_call_arg_parent_call",
            bufs.hir_call_arg_parent_call.byte_size as u64,
        );
        let hir_call_arg_ordinal = mk(
            "rb.parser.hir_call_arg_ordinal",
            bufs.hir_call_arg_ordinal.byte_size as u64,
        );
        let hir_member_receiver_node = mk(
            "rb.parser.hir_member_receiver_node",
            bufs.hir_member_receiver_node.byte_size as u64,
        );
        let hir_member_receiver_token = mk(
            "rb.parser.hir_member_receiver_token",
            bufs.hir_member_receiver_token.byte_size as u64,
        );
        let hir_member_name_token = mk(
            "rb.parser.hir_member_name_token",
            bufs.hir_member_name_token.byte_size as u64,
        );
        let hir_struct_field_parent_struct = mk(
            "rb.parser.hir_struct_field_parent_struct",
            bufs.hir_struct_field_parent_struct.byte_size as u64,
        );
        let hir_struct_field_ordinal = mk(
            "rb.parser.hir_struct_field_ordinal",
            bufs.hir_struct_field_ordinal.byte_size as u64,
        );
        let hir_struct_field_type_node = mk(
            "rb.parser.hir_struct_field_type_node",
            bufs.hir_struct_field_type_node.byte_size as u64,
        );
        let hir_struct_decl_field_start = mk(
            "rb.parser.hir_struct_decl_field_start",
            bufs.hir_struct_decl_field_start.byte_size as u64,
        );
        let hir_struct_decl_field_count = mk(
            "rb.parser.hir_struct_decl_field_count",
            bufs.hir_struct_decl_field_count.byte_size as u64,
        );
        let hir_struct_lit_head_node = mk(
            "rb.parser.hir_struct_lit_head_node",
            bufs.hir_struct_lit_head_node.byte_size as u64,
        );
        let hir_struct_lit_field_start = mk(
            "rb.parser.hir_struct_lit_field_start",
            bufs.hir_struct_lit_field_start.byte_size as u64,
        );
        let hir_struct_lit_field_count = mk(
            "rb.parser.hir_struct_lit_field_count",
            bufs.hir_struct_lit_field_count.byte_size as u64,
        );
        let hir_struct_lit_field_parent_lit = mk(
            "rb.parser.hir_struct_lit_field_parent_lit",
            bufs.hir_struct_lit_field_parent_lit.byte_size as u64,
        );
        let hir_struct_lit_field_value_node = mk(
            "rb.parser.hir_struct_lit_field_value_node",
            bufs.hir_struct_lit_field_value_node.byte_size as u64,
        );

        Self {
            ll1_status,
            ll1_emit,
            ll1_emit_pos,
            ll1_block_seed_len,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            headers,
            sc,
            emit,
            match_idx,
            depths,
            valid,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,
            hir_kind,
            hir_token_pos,
            hir_token_end,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_call_callee_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
        }
    }

    /// Record copy commands from device-local outputs into staging buffers.
    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &self.ll1_status,
            0,
            bufs.ll1_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit,
            0,
            &self.ll1_emit,
            0,
            bufs.ll1_emit.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_emit_pos,
            0,
            &self.ll1_emit_pos,
            0,
            bufs.ll1_emit_pos.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_block_seed_len,
            0,
            &self.ll1_block_seed_len,
            0,
            bufs.ll1_block_seed_len.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seed_plan_status,
            0,
            &self.ll1_seed_plan_status,
            0,
            bufs.ll1_seed_plan_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seeded_status,
            0,
            &self.ll1_seeded_status,
            0,
            bufs.ll1_seeded_status.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_seeded_emit,
            0,
            &self.ll1_seeded_emit,
            0,
            bufs.ll1_seeded_emit.byte_size as u64,
        );

        // out_headers
        encoder.copy_buffer_to_buffer(
            &bufs.out_headers,
            0,
            &self.headers,
            0,
            bufs.out_headers.byte_size as u64,
        );

        // out_sc and match_for_index
        let sc_bytes = (bufs.total_sc.max(1) * 4) as u64;
        encoder.copy_buffer_to_buffer(&bufs.out_sc, 0, &self.sc, 0, sc_bytes);
        encoder.copy_buffer_to_buffer(&bufs.match_for_index, 0, &self.match_idx, 0, sc_bytes);

        // out_emit, node_kind, parent
        let emit_bytes = (bufs.total_emit.max(1) * 4) as u64;
        encoder.copy_buffer_to_buffer(&bufs.out_emit, 0, &self.emit, 0, emit_bytes);
        encoder.copy_buffer_to_buffer(
            &bufs.node_kind,
            0,
            &self.node_kind,
            0,
            bufs.node_kind.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.parent,
            0,
            &self.parent,
            0,
            bufs.parent.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.first_child,
            0,
            &self.first_child,
            0,
            bufs.first_child.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.next_sibling,
            0,
            &self.next_sibling,
            0,
            bufs.next_sibling.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.subtree_end,
            0,
            &self.subtree_end,
            0,
            bufs.subtree_end.byte_size as u64,
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

        // depths_out, valid_out
        encoder.copy_buffer_to_buffer(
            &bufs.depths_out,
            0,
            &self.depths,
            0,
            bufs.depths_out.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.valid_out,
            0,
            &self.valid,
            0,
            bufs.valid_out.byte_size as u64,
        );
    }
}

/// Decoded results from the staging buffers.
pub struct DecodedParserReadbacks {
    pub ll1_status: [u32; 6],
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
    pub ll1_block_seed_len: Vec<u32>,
    pub ll1_seed_plan_status: [u32; 8],
    pub ll1_seeded_status: Vec<u32>,
    pub ll1_seeded_emit: Vec<u32>,
    pub headers: Vec<ActionHeader>,
    pub sc_stream: Vec<u32>,
    pub emit_stream: Vec<u32>,
    pub match_for_index: Vec<u32>,
    pub final_depth: i32,
    pub min_depth: i32,
    pub valid: bool,
    pub node_kind: Vec<u32>,
    pub parent: Vec<u32>,
    pub first_child: Vec<u32>,
    pub next_sibling: Vec<u32>,
    pub subtree_end: Vec<u32>,
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_value_node: Vec<u32>,
    pub hir_type_len_token: Vec<u32>,
    pub hir_type_len_value: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_decl_token: Vec<u32>,
    pub hir_item_namespace: Vec<u32>,
    pub hir_item_visibility: Vec<u32>,
    pub hir_item_path_start: Vec<u32>,
    pub hir_item_path_end: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
    pub hir_item_import_target_kind: Vec<u32>,
    pub hir_variant_parent_enum: Vec<u32>,
    pub hir_variant_ordinal: Vec<u32>,
    pub hir_variant_payload_start: Vec<u32>,
    pub hir_variant_payload_count: Vec<u32>,
    pub hir_match_scrutinee_node: Vec<u32>,
    pub hir_match_arm_start: Vec<u32>,
    pub hir_match_arm_count: Vec<u32>,
    pub hir_match_arm_pattern_node: Vec<u32>,
    pub hir_match_arm_payload_start: Vec<u32>,
    pub hir_match_arm_payload_count: Vec<u32>,
    pub hir_match_arm_result_node: Vec<u32>,
    pub hir_call_callee_node: Vec<u32>,
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_member_receiver_node: Vec<u32>,
    pub hir_member_receiver_token: Vec<u32>,
    pub hir_member_name_token: Vec<u32>,
    pub hir_struct_field_parent_struct: Vec<u32>,
    pub hir_struct_field_ordinal: Vec<u32>,
    pub hir_struct_field_type_node: Vec<u32>,
    pub hir_struct_decl_field_start: Vec<u32>,
    pub hir_struct_decl_field_count: Vec<u32>,
    pub hir_struct_lit_head_node: Vec<u32>,
    pub hir_struct_lit_field_start: Vec<u32>,
    pub hir_struct_lit_field_count: Vec<u32>,
    pub hir_struct_lit_field_parent_lit: Vec<u32>,
    pub hir_struct_lit_field_value_node: Vec<u32>,
}

impl DecodedParserReadbacks {
    /// Map, wait, decode all staging buffers into host vectors.
    pub fn map_and_decode(
        device: &wgpu::Device,
        bufs: &ParserBuffers,
        rb: ParserReadbacks,
    ) -> Result<Self> {
        // Map all
        let map = |name: &str, b: &wgpu::Buffer| {
            crate::gpu::passes_core::map_readback_for_progress(
                &b.slice(..),
                &format!("parser.readback.{name}"),
            );
        };
        map("headers", &rb.headers);
        map("ll1_status", &rb.ll1_status);
        map("ll1_emit", &rb.ll1_emit);
        map("ll1_emit_pos", &rb.ll1_emit_pos);
        map("ll1_block_seed_len", &rb.ll1_block_seed_len);
        map("ll1_seed_plan_status", &rb.ll1_seed_plan_status);
        map("ll1_seeded_status", &rb.ll1_seeded_status);
        map("ll1_seeded_emit", &rb.ll1_seeded_emit);
        map("sc", &rb.sc);
        map("emit", &rb.emit);
        map("match_idx", &rb.match_idx);
        map("depths", &rb.depths);
        map("valid", &rb.valid);
        map("node_kind", &rb.node_kind);
        map("parent", &rb.parent);
        map("first_child", &rb.first_child);
        map("next_sibling", &rb.next_sibling);
        map("subtree_end", &rb.subtree_end);
        map("hir_kind", &rb.hir_kind);
        map("hir_token_pos", &rb.hir_token_pos);
        map("hir_token_end", &rb.hir_token_end);
        map("hir_type_form", &rb.hir_type_form);
        map("hir_type_value_node", &rb.hir_type_value_node);
        map("hir_type_len_token", &rb.hir_type_len_token);
        map("hir_type_len_value", &rb.hir_type_len_value);
        map("hir_type_file_id", &rb.hir_type_file_id);
        map("hir_item_kind", &rb.hir_item_kind);
        map("hir_item_name_token", &rb.hir_item_name_token);
        map("hir_item_decl_token", &rb.hir_item_decl_token);
        map("hir_item_namespace", &rb.hir_item_namespace);
        map("hir_item_visibility", &rb.hir_item_visibility);
        map("hir_item_path_start", &rb.hir_item_path_start);
        map("hir_item_path_end", &rb.hir_item_path_end);
        map("hir_item_file_id", &rb.hir_item_file_id);
        map(
            "hir_item_import_target_kind",
            &rb.hir_item_import_target_kind,
        );
        map("hir_variant_parent_enum", &rb.hir_variant_parent_enum);
        map("hir_variant_ordinal", &rb.hir_variant_ordinal);
        map("hir_variant_payload_start", &rb.hir_variant_payload_start);
        map("hir_variant_payload_count", &rb.hir_variant_payload_count);
        map("hir_match_scrutinee_node", &rb.hir_match_scrutinee_node);
        map("hir_match_arm_start", &rb.hir_match_arm_start);
        map("hir_match_arm_count", &rb.hir_match_arm_count);
        map("hir_match_arm_pattern_node", &rb.hir_match_arm_pattern_node);
        map(
            "hir_match_arm_payload_start",
            &rb.hir_match_arm_payload_start,
        );
        map(
            "hir_match_arm_payload_count",
            &rb.hir_match_arm_payload_count,
        );
        map("hir_match_arm_result_node", &rb.hir_match_arm_result_node);
        map("hir_call_callee_node", &rb.hir_call_callee_node);
        map("hir_call_arg_start", &rb.hir_call_arg_start);
        map("hir_call_arg_end", &rb.hir_call_arg_end);
        map("hir_call_arg_count", &rb.hir_call_arg_count);
        map("hir_call_arg_parent_call", &rb.hir_call_arg_parent_call);
        map("hir_call_arg_ordinal", &rb.hir_call_arg_ordinal);
        map("hir_member_receiver_node", &rb.hir_member_receiver_node);
        map("hir_member_receiver_token", &rb.hir_member_receiver_token);
        map("hir_member_name_token", &rb.hir_member_name_token);
        map(
            "hir_struct_field_parent_struct",
            &rb.hir_struct_field_parent_struct,
        );
        map("hir_struct_field_ordinal", &rb.hir_struct_field_ordinal);
        map("hir_struct_field_type_node", &rb.hir_struct_field_type_node);
        map(
            "hir_struct_decl_field_start",
            &rb.hir_struct_decl_field_start,
        );
        map(
            "hir_struct_decl_field_count",
            &rb.hir_struct_decl_field_count,
        );
        map("hir_struct_lit_head_node", &rb.hir_struct_lit_head_node);
        map("hir_struct_lit_field_start", &rb.hir_struct_lit_field_start);
        map("hir_struct_lit_field_count", &rb.hir_struct_lit_field_count);
        map(
            "hir_struct_lit_field_parent_lit",
            &rb.hir_struct_lit_field_parent_lit,
        );
        map(
            "hir_struct_lit_field_value_node",
            &rb.hir_struct_lit_field_value_node,
        );

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.readback",
            wgpu::PollType::Wait,
        );

        let ll1_status = read_u32_array::<6>(&rb.ll1_status, "ll1_status")?;
        let ll1_emit_stream = read_u32_vec(
            &rb.ll1_emit,
            (ll1_status[5] as usize).min(bufs.ll1_emit.count),
        );
        let ll1_emit_token_pos = read_u32_vec(
            &rb.ll1_emit_pos,
            (ll1_status[5] as usize).min(bufs.ll1_emit_pos.count),
        );
        let ll1_block_seed_len =
            read_u32_vec(&rb.ll1_block_seed_len, bufs.ll1_block_seed_len.count);
        let ll1_seed_plan_status =
            read_u32_array::<8>(&rb.ll1_seed_plan_status, "ll1_seed_plan_status")?;
        let ll1_seeded_status = read_u32_vec(&rb.ll1_seeded_status, bufs.ll1_seeded_status.count);
        let ll1_seeded_emit = read_u32_vec(&rb.ll1_seeded_emit, bufs.ll1_seeded_emit.count);
        let tree_len = if bufs.tree_count_uses_status {
            (ll1_status[5] as usize).min(bufs.node_kind.count)
        } else {
            (bufs.total_emit as usize).min(bufs.node_kind.count)
        };

        let headers = {
            let data = rb.headers.slice(..).get_mapped_range();
            let count = (bufs.n_tokens.saturating_sub(1)) as usize;
            let out = decode_action_headers(&data, count)?;
            drop(data);
            rb.headers.unmap();
            out
        };

        let sc_stream = read_u32_vec(&rb.sc, bufs.total_sc as usize);
        let emit_stream = read_u32_vec(&rb.emit, bufs.total_emit as usize);
        let match_for_index = read_u32_vec(&rb.match_idx, bufs.total_sc as usize);
        let [final_depth, min_depth] = read_i32_array::<2>(&rb.depths, "depths")?;
        let valid = read_u32_array::<1>(&rb.valid, "valid")?[0] != 0;

        let node_kind = read_u32_vec(&rb.node_kind, tree_len);
        let parent = read_u32_vec(&rb.parent, tree_len);
        let first_child = read_u32_vec(&rb.first_child, tree_len);
        let next_sibling = read_u32_vec(&rb.next_sibling, tree_len);
        let subtree_end = read_u32_vec(&rb.subtree_end, tree_len);
        let hir_kind = read_u32_vec(&rb.hir_kind, tree_len);
        let hir_token_pos = read_u32_vec(&rb.hir_token_pos, tree_len);
        let hir_token_end = read_u32_vec(&rb.hir_token_end, tree_len);
        let hir_type_form = read_u32_vec(&rb.hir_type_form, tree_len);
        let hir_type_value_node = read_u32_vec(&rb.hir_type_value_node, tree_len);
        let hir_type_len_token = read_u32_vec(&rb.hir_type_len_token, tree_len);
        let hir_type_len_value = read_u32_vec(&rb.hir_type_len_value, tree_len);
        let hir_type_file_id = read_u32_vec(&rb.hir_type_file_id, tree_len);
        let hir_item_kind = read_u32_vec(&rb.hir_item_kind, tree_len);
        let hir_item_name_token = read_u32_vec(&rb.hir_item_name_token, tree_len);
        let hir_item_decl_token = read_u32_vec(&rb.hir_item_decl_token, tree_len);
        let hir_item_namespace = read_u32_vec(&rb.hir_item_namespace, tree_len);
        let hir_item_visibility = read_u32_vec(&rb.hir_item_visibility, tree_len);
        let hir_item_path_start = read_u32_vec(&rb.hir_item_path_start, tree_len);
        let hir_item_path_end = read_u32_vec(&rb.hir_item_path_end, tree_len);
        let hir_item_file_id = read_u32_vec(&rb.hir_item_file_id, tree_len);
        let hir_item_import_target_kind = read_u32_vec(&rb.hir_item_import_target_kind, tree_len);
        let decode_tree_vec = |buffer: &wgpu::Buffer| read_u32_vec(buffer, tree_len);
        let hir_variant_parent_enum = decode_tree_vec(&rb.hir_variant_parent_enum);
        let hir_variant_ordinal = decode_tree_vec(&rb.hir_variant_ordinal);
        let hir_variant_payload_start = decode_tree_vec(&rb.hir_variant_payload_start);
        let hir_variant_payload_count = decode_tree_vec(&rb.hir_variant_payload_count);
        let hir_match_scrutinee_node = decode_tree_vec(&rb.hir_match_scrutinee_node);
        let hir_match_arm_start = decode_tree_vec(&rb.hir_match_arm_start);
        let hir_match_arm_count = decode_tree_vec(&rb.hir_match_arm_count);
        let hir_match_arm_pattern_node = decode_tree_vec(&rb.hir_match_arm_pattern_node);
        let hir_match_arm_payload_start = decode_tree_vec(&rb.hir_match_arm_payload_start);
        let hir_match_arm_payload_count = decode_tree_vec(&rb.hir_match_arm_payload_count);
        let hir_match_arm_result_node = decode_tree_vec(&rb.hir_match_arm_result_node);
        let hir_call_callee_node = decode_tree_vec(&rb.hir_call_callee_node);
        let hir_call_arg_start = decode_tree_vec(&rb.hir_call_arg_start);
        let hir_call_arg_end = decode_tree_vec(&rb.hir_call_arg_end);
        let hir_call_arg_count = decode_tree_vec(&rb.hir_call_arg_count);
        let hir_call_arg_parent_call = decode_tree_vec(&rb.hir_call_arg_parent_call);
        let hir_call_arg_ordinal = decode_tree_vec(&rb.hir_call_arg_ordinal);
        let hir_member_receiver_node = decode_tree_vec(&rb.hir_member_receiver_node);
        let hir_member_receiver_token = decode_tree_vec(&rb.hir_member_receiver_token);
        let hir_member_name_token = decode_tree_vec(&rb.hir_member_name_token);
        let hir_struct_field_parent_struct = decode_tree_vec(&rb.hir_struct_field_parent_struct);
        let hir_struct_field_ordinal = decode_tree_vec(&rb.hir_struct_field_ordinal);
        let hir_struct_field_type_node = decode_tree_vec(&rb.hir_struct_field_type_node);
        let hir_struct_decl_field_start = decode_tree_vec(&rb.hir_struct_decl_field_start);
        let hir_struct_decl_field_count = decode_tree_vec(&rb.hir_struct_decl_field_count);
        let hir_struct_lit_head_node = decode_tree_vec(&rb.hir_struct_lit_head_node);
        let hir_struct_lit_field_start = decode_tree_vec(&rb.hir_struct_lit_field_start);
        let hir_struct_lit_field_count = decode_tree_vec(&rb.hir_struct_lit_field_count);
        let hir_struct_lit_field_parent_lit = decode_tree_vec(&rb.hir_struct_lit_field_parent_lit);
        let hir_struct_lit_field_value_node = decode_tree_vec(&rb.hir_struct_lit_field_value_node);

        Ok(Self {
            ll1_status,
            ll1_emit_stream,
            ll1_emit_token_pos,
            ll1_block_seed_len,
            ll1_seed_plan_status,
            ll1_seeded_status,
            ll1_seeded_emit,
            headers,
            sc_stream,
            emit_stream,
            match_for_index,
            final_depth,
            min_depth,
            valid,
            node_kind,
            parent,
            first_child,
            next_sibling,
            subtree_end,
            hir_kind,
            hir_token_pos,
            hir_token_end,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_call_callee_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_member_receiver_node,
            hir_member_receiver_token,
            hir_member_name_token,
            hir_struct_field_parent_struct,
            hir_struct_field_ordinal,
            hir_struct_field_type_node,
            hir_struct_decl_field_start,
            hir_struct_decl_field_count,
            hir_struct_lit_head_node,
            hir_struct_lit_field_start,
            hir_struct_lit_field_count,
            hir_struct_lit_field_parent_lit,
            hir_struct_lit_field_value_node,
        })
    }
}

fn read_u32_array<const N: usize>(buffer: &wgpu::Buffer, label: &str) -> Result<[u32; N]> {
    let data = buffer.slice(..).get_mapped_range();
    let decoded = crate::gpu::readback::read_u32_words(&data, label);
    drop(data);
    buffer.unmap();
    decoded
}

fn read_i32_array<const N: usize>(buffer: &wgpu::Buffer, label: &str) -> Result<[i32; N]> {
    let data = buffer.slice(..).get_mapped_range();
    let decoded = crate::gpu::readback::read_i32_words(&data, label);
    drop(data);
    buffer.unmap();
    decoded
}

fn read_u32_vec(buffer: &wgpu::Buffer, len: usize) -> Vec<u32> {
    let data = buffer.slice(..).get_mapped_range();
    let mut out = Vec::with_capacity(len);
    for chunk in data.chunks_exact(4).take(len) {
        out.push(u32::from_le_bytes(
            chunk.try_into().expect("u32 chunk size mismatch"),
        ));
    }
    drop(data);
    buffer.unmap();
    out
}

fn decode_action_headers(bytes: &[u8], count: usize) -> Result<Vec<ActionHeader>> {
    let stride = core::mem::size_of::<ActionHeader>();
    if bytes.len() < stride * count {
        return Err(anyhow!("out_headers readback too small"));
    }
    let mut out = Vec::with_capacity(count);
    for i in 0..count {
        let off = i * stride;
        let push_len = u32::from_le_bytes(bytes[off + 0..off + 4].try_into().unwrap());
        let emit_len = u32::from_le_bytes(bytes[off + 4..off + 8].try_into().unwrap());
        let pop_tag = u32::from_le_bytes(bytes[off + 8..off + 12].try_into().unwrap());
        let pop_count = u32::from_le_bytes(bytes[off + 12..off + 16].try_into().unwrap());
        out.push(ActionHeader {
            push_len,
            emit_len,
            pop_tag,
            pop_count,
        });
    }
    Ok(out)
}
