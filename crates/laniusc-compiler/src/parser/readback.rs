//! Parser debug/readback buffers and parser-owned HIR validators.

use anyhow::{Result, anyhow};
use wgpu;

use super::{
    buffers::{ActionHeader, ParserBuffers},
    hir_records::INVALID,
    passes::hir::{
        expr::fields::{
            HIR_EXPR_FORM_ADD,
            HIR_EXPR_FORM_AND,
            HIR_EXPR_FORM_BIT_AND,
            HIR_EXPR_FORM_BIT_OR,
            HIR_EXPR_FORM_BIT_XOR,
            HIR_EXPR_FORM_CHAR,
            HIR_EXPR_FORM_DIV,
            HIR_EXPR_FORM_EQ,
            HIR_EXPR_FORM_FALSE,
            HIR_EXPR_FORM_FLOAT,
            HIR_EXPR_FORM_FORWARD,
            HIR_EXPR_FORM_GE,
            HIR_EXPR_FORM_GT,
            HIR_EXPR_FORM_INDEX,
            HIR_EXPR_FORM_INT,
            HIR_EXPR_FORM_LE,
            HIR_EXPR_FORM_LT,
            HIR_EXPR_FORM_MOD,
            HIR_EXPR_FORM_MUL,
            HIR_EXPR_FORM_NAME,
            HIR_EXPR_FORM_NE,
            HIR_EXPR_FORM_NEG,
            HIR_EXPR_FORM_NONE,
            HIR_EXPR_FORM_NOT,
            HIR_EXPR_FORM_OR,
            HIR_EXPR_FORM_RANGE,
            HIR_EXPR_FORM_RANGE_FROM,
            HIR_EXPR_FORM_RANGE_FULL,
            HIR_EXPR_FORM_RANGE_INCLUSIVE,
            HIR_EXPR_FORM_RANGE_TO,
            HIR_EXPR_FORM_RANGE_TO_INCLUSIVE,
            HIR_EXPR_FORM_SHL,
            HIR_EXPR_FORM_SHR,
            HIR_EXPR_FORM_STRING,
            HIR_EXPR_FORM_SUB,
            HIR_EXPR_FORM_TRUE,
        },
        item::fields::{
            HIR_ITEM_IMPORT_TARGET_NONE,
            HIR_ITEM_IMPORT_TARGET_PATH,
            HIR_ITEM_IMPORT_TARGET_STRING,
            HIR_ITEM_KIND_CONST,
            HIR_ITEM_KIND_ENUM,
            HIR_ITEM_KIND_ENUM_VARIANT,
            HIR_ITEM_KIND_EXTERN_FN,
            HIR_ITEM_KIND_FN,
            HIR_ITEM_KIND_IMPORT,
            HIR_ITEM_KIND_MODULE,
            HIR_ITEM_KIND_NONE,
            HIR_ITEM_KIND_STRUCT,
            HIR_ITEM_KIND_TRAIT,
            HIR_ITEM_KIND_TYPE_ALIAS,
            HIR_ITEM_NAMESPACE_MODULE,
            HIR_ITEM_NAMESPACE_NONE,
            HIR_ITEM_NAMESPACE_TYPE,
            HIR_ITEM_NAMESPACE_VALUE,
            HIR_ITEM_VIS_PRIVATE,
            HIR_ITEM_VIS_PUBLIC,
        },
        method::{
            fields::{
                HIR_METHOD_RECEIVER_EXPLICIT,
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_SELF,
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PUBLIC,
            },
            signature_status::{
                HIR_METHOD_SIGNATURE_HAS_GENERICS,
                HIR_METHOD_SIGNATURE_HAS_WHERE,
                HIR_METHOD_SIGNATURE_INHERENT_IMPL,
            },
        },
        nodes::{
            HIR_NODE_ARRAY_EXPR,
            HIR_NODE_ASSIGN_EXPR,
            HIR_NODE_BINARY_EXPR,
            HIR_NODE_BLOCK,
            HIR_NODE_BREAK_STMT,
            HIR_NODE_CALL_EXPR,
            HIR_NODE_CONST_ITEM,
            HIR_NODE_CONTINUE_STMT,
            HIR_NODE_ENUM_ITEM,
            HIR_NODE_EXPR,
            HIR_NODE_FILE,
            HIR_NODE_FN,
            HIR_NODE_FOR_STMT,
            HIR_NODE_IF_STMT,
            HIR_NODE_IMPORT_ITEM,
            HIR_NODE_INDEX_EXPR,
            HIR_NODE_ITEM,
            HIR_NODE_LET_STMT,
            HIR_NODE_LITERAL_EXPR,
            HIR_NODE_MATCH_EXPR,
            HIR_NODE_MEMBER_EXPR,
            HIR_NODE_MODULE_ITEM,
            HIR_NODE_NAME_EXPR,
            HIR_NODE_NONE,
            HIR_NODE_PARAM,
            HIR_NODE_PATH_EXPR,
            HIR_NODE_POSTFIX_EXPR,
            HIR_NODE_RETURN_STMT,
            HIR_NODE_STMT,
            HIR_NODE_STRUCT_ITEM,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            HIR_NODE_TYPE,
            HIR_NODE_TYPE_ALIAS_ITEM,
            HIR_NODE_UNARY_EXPR,
            HIR_NODE_WHILE_STMT,
        },
        stmt_fields::{
            HIR_ASSIGN_OP_BOR,
            HIR_ASSIGN_OP_SET,
            HIR_STMT_RECORD_KIND_ASSIGN,
            HIR_STMT_RECORD_KIND_BREAK,
            HIR_STMT_RECORD_KIND_CONST,
            HIR_STMT_RECORD_KIND_CONTINUE,
            HIR_STMT_RECORD_KIND_FOR,
            HIR_STMT_RECORD_KIND_IF,
            HIR_STMT_RECORD_KIND_LET,
            HIR_STMT_RECORD_KIND_NONE,
            HIR_STMT_RECORD_KIND_RETURN,
            HIR_STMT_RECORD_KIND_WHILE,
        },
        types::fields::{
            HIR_TYPE_FORM_ARRAY,
            HIR_TYPE_FORM_NONE,
            HIR_TYPE_FORM_PATH,
            HIR_TYPE_FORM_REF,
            HIR_TYPE_FORM_SLICE,
        },
    },
};

const HIR_VARIANT_PAYLOAD_SLOT_STRIDE: u32 = 4;
const PROD_BOUND_TYPE_IDENT: u32 = 241;

mod validators;
pub use validators::*;
mod hir_item_readbacks;
pub use hir_item_readbacks::*;

/// Staging buffers for parser readbacks.
pub struct ParserReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub ll1_emit: wgpu::Buffer,
    pub ll1_emit_pos: wgpu::Buffer,
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
    pub hir_semantic_prefix_before_node: wgpu::Buffer,
    pub hir_semantic_dense_node: wgpu::Buffer,
    pub hir_semantic_subtree_end: wgpu::Buffer,
    pub hir_semantic_parent: wgpu::Buffer,
    pub hir_semantic_first_child: wgpu::Buffer,
    pub hir_semantic_next_sibling: wgpu::Buffer,
    pub hir_semantic_depth: wgpu::Buffer,
    pub hir_semantic_child_index: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
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
    pub hir_method_signature_flags: wgpu::Buffer,
    pub hir_stmt_record: wgpu::Buffer,
    pub hir_stmt_scope_end: wgpu::Buffer,
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
    pub hir_call_arg_start: wgpu::Buffer,
    pub hir_call_arg_end: wgpu::Buffer,
    pub hir_call_arg_count: wgpu::Buffer,
    pub hir_call_arg_parent_call: wgpu::Buffer,
    pub hir_call_arg_ordinal: wgpu::Buffer,
    pub hir_array_lit_first_element: wgpu::Buffer,
    pub hir_array_lit_element_count: wgpu::Buffer,
    pub hir_array_element_parent_lit: wgpu::Buffer,
    pub hir_array_element_ordinal: wgpu::Buffer,
    pub hir_array_element_next: wgpu::Buffer,
    pub hir_expr_string_start: wgpu::Buffer,
    pub hir_expr_string_len: wgpu::Buffer,
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
    pub hir_struct_lit_field_next: wgpu::Buffer,
}

impl ParserReadbacks {
    /// Creates staging buffers for a full parser debug readback.
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
        let hir_semantic_prefix_before_node = mk(
            "rb.parser.hir_semantic_prefix_before_node",
            bufs.hir_semantic_prefix_before_node.byte_size as u64,
        );
        let hir_semantic_dense_node = mk(
            "rb.parser.hir_semantic_dense_node",
            bufs.hir_semantic_dense_node.byte_size as u64,
        );
        let hir_semantic_subtree_end = mk(
            "rb.parser.hir_semantic_subtree_end",
            bufs.hir_semantic_subtree_end.byte_size as u64,
        );
        let hir_semantic_parent = mk(
            "rb.parser.hir_semantic_parent",
            bufs.hir_semantic_parent.byte_size as u64,
        );
        let hir_semantic_first_child = mk(
            "rb.parser.hir_semantic_first_child",
            bufs.hir_semantic_first_child.byte_size as u64,
        );
        let hir_semantic_next_sibling = mk(
            "rb.parser.hir_semantic_next_sibling",
            bufs.hir_semantic_next_sibling.byte_size as u64,
        );
        let hir_semantic_depth = mk(
            "rb.parser.hir_semantic_depth",
            bufs.hir_semantic_depth.byte_size as u64,
        );
        let hir_semantic_child_index = mk(
            "rb.parser.hir_semantic_child_index",
            bufs.hir_semantic_child_index.byte_size as u64,
        );
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
        let hir_type_path_leaf_node = mk(
            "rb.parser.hir_type_path_leaf_node",
            bufs.hir_type_path_leaf_node.byte_size as u64,
        );
        let hir_type_arg_start = mk(
            "rb.parser.hir_type_arg_start",
            bufs.hir_type_arg_start.byte_size as u64,
        );
        let hir_type_arg_count = mk(
            "rb.parser.hir_type_arg_count",
            bufs.hir_type_arg_count.byte_size as u64,
        );
        let hir_type_arg_next = mk(
            "rb.parser.hir_type_arg_next",
            bufs.hir_type_arg_next.byte_size as u64,
        );
        let hir_type_alias_target_node = mk(
            "rb.parser.hir_type_alias_target_node",
            bufs.hir_type_alias_target_node.byte_size as u64,
        );
        let hir_fn_return_type_node = mk(
            "rb.parser.hir_fn_return_type_node",
            bufs.hir_fn_return_type_node.byte_size as u64,
        );
        let hir_method_signature_flags = mk(
            "rb.parser.hir_method_signature_flags",
            bufs.hir_method_signature_flags.byte_size as u64,
        );
        let hir_stmt_record = mk(
            "rb.parser.hir_stmt_record",
            bufs.hir_stmt_record.byte_size as u64,
        );
        let hir_stmt_scope_end = mk(
            "rb.parser.hir_stmt_scope_end",
            bufs.hir_stmt_scope_end.byte_size as u64,
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
        let hir_item_path_node = mk(
            "rb.parser.hir_item_path_node",
            bufs.hir_item_path_node.byte_size as u64,
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
        let hir_variant_payload_node = mk(
            "rb.parser.hir_variant_payload_node",
            bufs.hir_variant_payload_node.byte_size as u64,
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
        let hir_match_arm_next = mk(
            "rb.parser.hir_match_arm_next",
            bufs.hir_match_arm_next.byte_size as u64,
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
        let hir_match_payload_owner_arm = mk(
            "rb.parser.hir_match_payload_owner_arm",
            bufs.hir_match_payload_owner_arm.byte_size as u64,
        );
        let hir_match_payload_match_node = mk(
            "rb.parser.hir_match_payload_match_node",
            bufs.hir_match_payload_match_node.byte_size as u64,
        );
        let hir_match_payload_ordinal = mk(
            "rb.parser.hir_match_payload_ordinal",
            bufs.hir_match_payload_ordinal.byte_size as u64,
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
        let hir_array_lit_first_element = mk(
            "rb.parser.hir_array_lit_first_element",
            bufs.hir_array_lit_first_element.byte_size as u64,
        );
        let hir_array_lit_element_count = mk(
            "rb.parser.hir_array_lit_element_count",
            bufs.hir_array_lit_element_count.byte_size as u64,
        );
        let hir_array_element_parent_lit = mk(
            "rb.parser.hir_array_element_parent_lit",
            bufs.hir_array_element_parent_lit.byte_size as u64,
        );
        let hir_array_element_ordinal = mk(
            "rb.parser.hir_array_element_ordinal",
            bufs.hir_array_element_ordinal.byte_size as u64,
        );
        let hir_array_element_next = mk(
            "rb.parser.hir_array_element_next",
            bufs.hir_array_element_next.byte_size as u64,
        );
        let hir_expr_string_start = mk(
            "rb.parser.hir_expr_string_start",
            bufs.hir_expr_string_start.byte_size as u64,
        );
        let hir_expr_string_len = mk(
            "rb.parser.hir_expr_string_len",
            bufs.hir_expr_string_len.byte_size as u64,
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
        let hir_struct_lit_field_next = mk(
            "rb.parser.hir_struct_lit_field_next",
            bufs.hir_struct_lit_field_next.byte_size as u64,
        );

        Self {
            ll1_status,
            ll1_emit,
            ll1_emit_pos,
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
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_token_pos,
            hir_token_end,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_method_signature_flags,
            hir_stmt_record,
            hir_stmt_scope_end,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_path_node,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_payload_node,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_call_callee_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_expr_string_start,
            hir_expr_string_len,
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
            hir_struct_lit_field_next,
        }
    }

    /// Record copy commands from device-local outputs into staging buffers.
    /// Encodes copies from parser GPU buffers into the staging readback buffers.
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
            &bufs.hir_semantic_prefix_before_node,
            0,
            &self.hir_semantic_prefix_before_node,
            0,
            bufs.hir_semantic_prefix_before_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_dense_node,
            0,
            &self.hir_semantic_dense_node,
            0,
            bufs.hir_semantic_dense_node.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_semantic_subtree_end,
            0,
            &self.hir_semantic_subtree_end,
            0,
            bufs.hir_semantic_subtree_end.byte_size as u64,
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
            &bufs.hir_method_signature_flags,
            0,
            &self.hir_method_signature_flags,
            0,
            bufs.hir_method_signature_flags.byte_size as u64,
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
        encoder.copy_buffer_to_buffer(
            &bufs.hir_struct_lit_field_next,
            0,
            &self.hir_struct_lit_field_next,
            0,
            bufs.hir_struct_lit_field_next.byte_size as u64,
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
/// Decoded full parser debug readback data.
pub struct DecodedParserReadbacks {
    pub ll1_status: [u32; 6],
    pub ll1_emit_stream: Vec<u32>,
    pub ll1_emit_token_pos: Vec<u32>,
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
    pub hir_semantic_prefix_before_node: Vec<u32>,
    pub hir_semantic_dense_node: Vec<u32>,
    pub hir_semantic_subtree_end: Vec<u32>,
    pub hir_semantic_parent: Vec<u32>,
    pub hir_semantic_first_child: Vec<u32>,
    pub hir_semantic_next_sibling: Vec<u32>,
    pub hir_semantic_depth: Vec<u32>,
    pub hir_semantic_child_index: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
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
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_stmt_record_kind: Vec<u32>,
    pub hir_stmt_record_operand0: Vec<u32>,
    pub hir_stmt_record_operand1: Vec<u32>,
    pub hir_stmt_record_operand2: Vec<u32>,
    pub hir_stmt_scope_end: Vec<u32>,
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
    pub hir_call_arg_start: Vec<u32>,
    pub hir_call_arg_end: Vec<u32>,
    pub hir_call_arg_count: Vec<u32>,
    pub hir_call_arg_parent_call: Vec<u32>,
    pub hir_call_arg_ordinal: Vec<u32>,
    pub hir_array_lit_first_element: Vec<u32>,
    pub hir_array_lit_element_count: Vec<u32>,
    pub hir_array_element_parent_lit: Vec<u32>,
    pub hir_array_element_ordinal: Vec<u32>,
    pub hir_array_element_next: Vec<u32>,
    pub hir_expr_string_start: Vec<u32>,
    pub hir_expr_string_len: Vec<u32>,
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
    pub hir_struct_lit_field_next: Vec<u32>,
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
        map(
            "hir_semantic_prefix_before_node",
            &rb.hir_semantic_prefix_before_node,
        );
        map("hir_semantic_dense_node", &rb.hir_semantic_dense_node);
        map("hir_semantic_subtree_end", &rb.hir_semantic_subtree_end);
        map("hir_semantic_parent", &rb.hir_semantic_parent);
        map("hir_semantic_first_child", &rb.hir_semantic_first_child);
        map("hir_semantic_next_sibling", &rb.hir_semantic_next_sibling);
        map("hir_semantic_depth", &rb.hir_semantic_depth);
        map("hir_semantic_child_index", &rb.hir_semantic_child_index);
        map("hir_token_pos", &rb.hir_token_pos);
        map("hir_token_end", &rb.hir_token_end);
        map("hir_type_form", &rb.hir_type_form);
        map("hir_type_value_node", &rb.hir_type_value_node);
        map("hir_type_len_token", &rb.hir_type_len_token);
        map("hir_type_len_value", &rb.hir_type_len_value);
        map("hir_type_file_id", &rb.hir_type_file_id);
        map("hir_type_path_leaf_node", &rb.hir_type_path_leaf_node);
        map("hir_type_arg_start", &rb.hir_type_arg_start);
        map("hir_type_arg_count", &rb.hir_type_arg_count);
        map("hir_type_arg_next", &rb.hir_type_arg_next);
        map("hir_type_alias_target_node", &rb.hir_type_alias_target_node);
        map("hir_fn_return_type_node", &rb.hir_fn_return_type_node);
        map("hir_method_signature_flags", &rb.hir_method_signature_flags);
        map("hir_stmt_record", &rb.hir_stmt_record);
        map("hir_stmt_scope_end", &rb.hir_stmt_scope_end);
        map("hir_item_kind", &rb.hir_item_kind);
        map("hir_item_name_token", &rb.hir_item_name_token);
        map("hir_item_decl_token", &rb.hir_item_decl_token);
        map("hir_item_namespace", &rb.hir_item_namespace);
        map("hir_item_visibility", &rb.hir_item_visibility);
        map("hir_item_path_start", &rb.hir_item_path_start);
        map("hir_item_path_end", &rb.hir_item_path_end);
        map("hir_item_path_node", &rb.hir_item_path_node);
        map("hir_item_file_id", &rb.hir_item_file_id);
        map(
            "hir_item_import_target_kind",
            &rb.hir_item_import_target_kind,
        );
        map("hir_variant_parent_enum", &rb.hir_variant_parent_enum);
        map("hir_variant_ordinal", &rb.hir_variant_ordinal);
        map("hir_variant_payload_start", &rb.hir_variant_payload_start);
        map("hir_variant_payload_count", &rb.hir_variant_payload_count);
        map("hir_variant_payload_node", &rb.hir_variant_payload_node);
        map("hir_match_scrutinee_node", &rb.hir_match_scrutinee_node);
        map("hir_match_arm_start", &rb.hir_match_arm_start);
        map("hir_match_arm_count", &rb.hir_match_arm_count);
        map("hir_match_arm_next", &rb.hir_match_arm_next);
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
        map(
            "hir_match_payload_owner_arm",
            &rb.hir_match_payload_owner_arm,
        );
        map(
            "hir_match_payload_match_node",
            &rb.hir_match_payload_match_node,
        );
        map("hir_match_payload_ordinal", &rb.hir_match_payload_ordinal);
        map("hir_call_callee_node", &rb.hir_call_callee_node);
        map("hir_call_arg_start", &rb.hir_call_arg_start);
        map("hir_call_arg_end", &rb.hir_call_arg_end);
        map("hir_call_arg_count", &rb.hir_call_arg_count);
        map("hir_call_arg_parent_call", &rb.hir_call_arg_parent_call);
        map("hir_call_arg_ordinal", &rb.hir_call_arg_ordinal);
        map(
            "hir_array_lit_first_element",
            &rb.hir_array_lit_first_element,
        );
        map(
            "hir_array_lit_element_count",
            &rb.hir_array_lit_element_count,
        );
        map(
            "hir_array_element_parent_lit",
            &rb.hir_array_element_parent_lit,
        );
        map("hir_array_element_ordinal", &rb.hir_array_element_ordinal);
        map("hir_array_element_next", &rb.hir_array_element_next);
        map("hir_expr_string_start", &rb.hir_expr_string_start);
        map("hir_expr_string_len", &rb.hir_expr_string_len);
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
        map("hir_struct_lit_field_next", &rb.hir_struct_lit_field_next);

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.readback",
            wgpu::PollType::wait_indefinitely(),
        );

        let ll1_status = read_u32_array::<6>(&rb.ll1_status, "ll1_status")?;
        let ll1_emit_stream = Vec::new();
        let ll1_emit_token_pos = Vec::new();
        let tree_len = active_tree_readback_len(
            "readback.tree",
            bufs.tree_count_uses_status,
            ll1_status[5],
            bufs.total_emit,
            bufs.node_kind.count,
        )?;

        let headers = {
            let data = rb.headers.slice(..).get_mapped_range();
            let count = bufs.n_tokens.saturating_sub(1) as usize;
            let out = decode_action_headers(&data, count)?;
            drop(data);
            rb.headers.unmap();
            out
        };

        let stream_len = bufs.total_sc as usize;
        let emit_len = bufs.total_emit as usize;
        let sc_stream = read_u32_vec(&rb.sc, stream_len);
        let emit_stream = read_u32_vec(&rb.emit, emit_len);
        let match_for_index = read_u32_vec(&rb.match_idx, stream_len);
        let [read_final_depth, read_min_depth] = read_i32_array::<2>(&rb.depths, "depths")?;
        let read_valid = read_u32_array::<1>(&rb.valid, "valid")?[0] != 0;
        let (final_depth, min_depth, valid) = (read_final_depth, read_min_depth, read_valid);

        let node_kind = read_u32_vec(&rb.node_kind, tree_len);
        let parent = read_u32_vec(&rb.parent, tree_len);
        let first_child = read_u32_vec(&rb.first_child, tree_len);
        let next_sibling = read_u32_vec(&rb.next_sibling, tree_len);
        let subtree_end = read_u32_vec(&rb.subtree_end, tree_len);
        let hir_kind = read_u32_vec(&rb.hir_kind, tree_len);
        let hir_semantic_prefix_before_node =
            read_u32_vec(&rb.hir_semantic_prefix_before_node, tree_len);
        let hir_semantic_dense_node = read_u32_vec(&rb.hir_semantic_dense_node, tree_len);
        let hir_semantic_subtree_end = read_u32_vec(&rb.hir_semantic_subtree_end, tree_len);
        let hir_semantic_parent = read_u32_vec(&rb.hir_semantic_parent, tree_len);
        let hir_semantic_first_child = read_u32_vec(&rb.hir_semantic_first_child, tree_len);
        let hir_semantic_next_sibling = read_u32_vec(&rb.hir_semantic_next_sibling, tree_len);
        let hir_semantic_depth = read_u32_vec(&rb.hir_semantic_depth, tree_len);
        let hir_semantic_child_index = read_u32_vec(&rb.hir_semantic_child_index, tree_len);
        let hir_token_pos = read_u32_vec(&rb.hir_token_pos, tree_len);
        let hir_token_end = read_u32_vec(&rb.hir_token_end, tree_len);
        let hir_type_form = read_u32_vec(&rb.hir_type_form, tree_len);
        let hir_type_value_node = read_u32_vec(&rb.hir_type_value_node, tree_len);
        let hir_type_len_token = read_u32_vec(&rb.hir_type_len_token, tree_len);
        let hir_type_len_value = read_u32_vec(&rb.hir_type_len_value, tree_len);
        let hir_type_file_id = read_u32_vec(&rb.hir_type_file_id, tree_len);
        let hir_type_path_leaf_node = read_u32_vec(&rb.hir_type_path_leaf_node, tree_len);
        let hir_type_arg_start = read_u32_vec(&rb.hir_type_arg_start, tree_len);
        let hir_type_arg_count = read_u32_vec(&rb.hir_type_arg_count, tree_len);
        let hir_type_arg_next = read_u32_vec(&rb.hir_type_arg_next, tree_len);
        let hir_type_alias_target_node = read_u32_vec(&rb.hir_type_alias_target_node, tree_len);
        let hir_fn_return_type_node = read_u32_vec(&rb.hir_fn_return_type_node, tree_len);
        let hir_method_signature_flags = read_u32_vec(&rb.hir_method_signature_flags, tree_len);
        let hir_stmt_record_words = read_u32_vec(&rb.hir_stmt_record, tree_len.saturating_mul(4));
        let hir_stmt_scope_end = read_u32_vec(&rb.hir_stmt_scope_end, tree_len);
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
        let hir_item_kind = read_u32_vec(&rb.hir_item_kind, tree_len);
        let hir_item_name_token = read_u32_vec(&rb.hir_item_name_token, tree_len);
        let hir_item_decl_token = read_u32_vec(&rb.hir_item_decl_token, tree_len);
        let hir_item_namespace = read_u32_vec(&rb.hir_item_namespace, tree_len);
        let hir_item_visibility = read_u32_vec(&rb.hir_item_visibility, tree_len);
        let hir_item_path_start = read_u32_vec(&rb.hir_item_path_start, tree_len);
        let hir_item_path_end = read_u32_vec(&rb.hir_item_path_end, tree_len);
        let hir_item_path_node = read_u32_vec(&rb.hir_item_path_node, tree_len);
        let hir_item_file_id = read_u32_vec(&rb.hir_item_file_id, tree_len);
        let hir_item_import_target_kind = read_u32_vec(&rb.hir_item_import_target_kind, tree_len);
        let decode_tree_vec = |buffer: &wgpu::Buffer| read_u32_vec(buffer, tree_len);
        let hir_variant_parent_enum = decode_tree_vec(&rb.hir_variant_parent_enum);
        let hir_variant_ordinal = decode_tree_vec(&rb.hir_variant_ordinal);
        let hir_variant_payload_start = decode_tree_vec(&rb.hir_variant_payload_start);
        let hir_variant_payload_count = decode_tree_vec(&rb.hir_variant_payload_count);
        let hir_variant_payload_node = read_u32_vec(
            &rb.hir_variant_payload_node,
            tree_len.saturating_mul(HIR_VARIANT_PAYLOAD_SLOT_STRIDE as usize),
        );
        let hir_match_scrutinee_node = decode_tree_vec(&rb.hir_match_scrutinee_node);
        let hir_match_arm_start = decode_tree_vec(&rb.hir_match_arm_start);
        let hir_match_arm_count = decode_tree_vec(&rb.hir_match_arm_count);
        let hir_match_arm_next = decode_tree_vec(&rb.hir_match_arm_next);
        let hir_match_arm_pattern_node = decode_tree_vec(&rb.hir_match_arm_pattern_node);
        let hir_match_arm_payload_start = decode_tree_vec(&rb.hir_match_arm_payload_start);
        let hir_match_arm_payload_count = decode_tree_vec(&rb.hir_match_arm_payload_count);
        let hir_match_arm_result_node = decode_tree_vec(&rb.hir_match_arm_result_node);
        let hir_match_payload_owner_arm = decode_tree_vec(&rb.hir_match_payload_owner_arm);
        let hir_match_payload_match_node = decode_tree_vec(&rb.hir_match_payload_match_node);
        let hir_match_payload_ordinal = decode_tree_vec(&rb.hir_match_payload_ordinal);
        let hir_call_callee_node = decode_tree_vec(&rb.hir_call_callee_node);
        let hir_call_arg_start = decode_tree_vec(&rb.hir_call_arg_start);
        let hir_call_arg_end = decode_tree_vec(&rb.hir_call_arg_end);
        let hir_call_arg_count = decode_tree_vec(&rb.hir_call_arg_count);
        let hir_call_arg_parent_call = decode_tree_vec(&rb.hir_call_arg_parent_call);
        let hir_call_arg_ordinal = decode_tree_vec(&rb.hir_call_arg_ordinal);
        let hir_array_lit_first_element = decode_tree_vec(&rb.hir_array_lit_first_element);
        let hir_array_lit_element_count = decode_tree_vec(&rb.hir_array_lit_element_count);
        let hir_array_element_parent_lit = decode_tree_vec(&rb.hir_array_element_parent_lit);
        let hir_array_element_ordinal = decode_tree_vec(&rb.hir_array_element_ordinal);
        let hir_array_element_next = decode_tree_vec(&rb.hir_array_element_next);
        let hir_expr_string_start = decode_tree_vec(&rb.hir_expr_string_start);
        let hir_expr_string_len = decode_tree_vec(&rb.hir_expr_string_len);
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
        let hir_struct_lit_field_next = decode_tree_vec(&rb.hir_struct_lit_field_next);

        let decoded = Self {
            ll1_status,
            ll1_emit_stream,
            ll1_emit_token_pos,
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
            hir_semantic_prefix_before_node,
            hir_semantic_dense_node,
            hir_semantic_subtree_end,
            hir_semantic_parent,
            hir_semantic_first_child,
            hir_semantic_next_sibling,
            hir_semantic_depth,
            hir_semantic_child_index,
            hir_token_pos,
            hir_token_end,
            hir_type_form,
            hir_type_value_node,
            hir_type_len_token,
            hir_type_len_value,
            hir_type_file_id,
            hir_type_path_leaf_node,
            hir_type_arg_start,
            hir_type_arg_count,
            hir_type_arg_next,
            hir_type_alias_target_node,
            hir_fn_return_type_node,
            hir_method_signature_flags,
            hir_stmt_record_kind,
            hir_stmt_record_operand0,
            hir_stmt_record_operand1,
            hir_stmt_record_operand2,
            hir_stmt_scope_end,
            hir_item_kind,
            hir_item_name_token,
            hir_item_decl_token,
            hir_item_namespace,
            hir_item_visibility,
            hir_item_path_start,
            hir_item_path_end,
            hir_item_path_node,
            hir_item_file_id,
            hir_item_import_target_kind,
            hir_variant_parent_enum,
            hir_variant_ordinal,
            hir_variant_payload_start,
            hir_variant_payload_count,
            hir_variant_payload_node,
            hir_match_scrutinee_node,
            hir_match_arm_start,
            hir_match_arm_count,
            hir_match_arm_next,
            hir_match_arm_pattern_node,
            hir_match_arm_payload_start,
            hir_match_arm_payload_count,
            hir_match_arm_result_node,
            hir_match_payload_owner_arm,
            hir_match_payload_match_node,
            hir_match_payload_ordinal,
            hir_call_callee_node,
            hir_call_arg_start,
            hir_call_arg_end,
            hir_call_arg_count,
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_array_lit_first_element,
            hir_array_lit_element_count,
            hir_array_element_parent_lit,
            hir_array_element_ordinal,
            hir_array_element_next,
            hir_expr_string_start,
            hir_expr_string_len,
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
            hir_struct_lit_field_next,
        };
        validate_hir_semantic_tree_records(
            &decoded.hir_kind,
            &decoded.subtree_end,
            &decoded.hir_semantic_prefix_before_node,
            &decoded.hir_semantic_dense_node,
            &decoded.hir_semantic_subtree_end,
            &decoded.hir_semantic_parent,
            &decoded.hir_semantic_first_child,
            &decoded.hir_semantic_next_sibling,
            &decoded.hir_semantic_depth,
            &decoded.hir_semantic_child_index,
        )?;
        // This readback path decodes the adjacent-pair partial-parse tree. It is a
        // structural grammar artifact, not the complete LL(1) semantic tree, so
        // full HIR record validation belongs to the resident parse readback.
        Ok(decoded)
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

fn read_u32_vec_padded(buffer: &wgpu::Buffer, len: usize, fill: u32) -> Vec<u32> {
    let mut out = read_u32_vec(buffer, len);
    out.resize(len, fill);
    out
}

fn active_tree_readback_len(
    label: &str,
    uses_status: bool,
    status_count: u32,
    fallback_count: u32,
    capacity: usize,
) -> Result<usize> {
    let requested = if uses_status {
        status_count as usize
    } else {
        fallback_count as usize
    };
    bounded_readback_len(label, requested, capacity)
}

fn bounded_readback_len(label: &str, requested: usize, capacity: usize) -> Result<usize> {
    if requested > capacity {
        return Err(anyhow!(
            "parser {label} published {requested} rows, exceeding readback capacity {capacity}"
        ));
    }
    Ok(requested)
}

/// Validates enum variant ownership, ordinal, and payload rows.
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

#[cfg(test)]
mod tests {
    use super::{
        super::passes::hir::{nodes::HIR_NODE_NONE, types::fields::HIR_TYPE_FORM_ARRAY},
        *,
    };

    #[test]
    fn live_tree_readback_len_accepts_capacity_bound() {
        assert_eq!(
            active_tree_readback_len("test.tree", true, 4, 99, 4)
                .expect("status count at capacity should decode"),
            4
        );
        assert_eq!(
            active_tree_readback_len("test.tree", false, 99, 3, 4)
                .expect("fallback count inside capacity should decode"),
            3
        );
    }

    #[test]
    fn live_tree_readback_len_rejects_status_past_capacity() {
        let err = active_tree_readback_len("test.tree", true, 5, 0, 4)
            .expect_err("status count past capacity should fail closed");
        assert!(
            err.to_string().contains("exceeding readback capacity"),
            "error should describe the violated live tree readback bound"
        );
    }

    #[test]
    fn type_argument_readback_accepts_contiguous_type_chain() {
        validate_hir_type_argument_records(
            &[0, HIR_NODE_TYPE, HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 10, 12, 16],
            &[1, 20, 13, 17],
            &[0; 4],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, 2, INVALID, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 3, INVALID],
        )
        .expect("contiguous generic type argument records should decode");
    }

    #[test]
    fn type_argument_readback_keeps_nested_arguments_on_immediate_owner_chain() {
        validate_hir_type_argument_records(
            &[
                0,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
            ],
            &[0, 10, 12, 15, 24],
            &[1, 30, 22, 16, 25],
            &[0; 5],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, 2, 3, INVALID, INVALID],
            &[0, 2, 1, 0, 0],
            &[INVALID, INVALID, 4, INVALID, INVALID],
        )
        .expect("nested generic owner records should decode when outer chains list direct args");

        let flattened = validate_hir_type_argument_records(
            &[
                0,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
            ],
            &[0, 10, 12, 15, 24],
            &[1, 30, 22, 16, 25],
            &[0; 5],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, 2, 3, INVALID, INVALID],
            &[0, 3, 1, 0, 0],
            &[INVALID, INVALID, 3, 4, INVALID],
        );
        assert!(
            flattened.is_err(),
            "a nested argument row must not also appear in the outer owner's direct argument chain"
        );
    }

    #[test]
    fn type_argument_readback_rejects_owner_counts_past_rows() {
        let err = validate_hir_type_argument_records(
            &[0, HIR_NODE_TYPE, HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 10, 12, 16],
            &[1, 20, 13, 17],
            &[0; 4],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, 2, 3, INVALID],
            &[0, 2, 3, 0],
            &[INVALID, INVALID, 3, INVALID],
        )
        .expect_err("type argument counts past available rows should fail closed");
        assert!(
            err.to_string().contains("claim 5 type argument rows"),
            "error should describe the violated flat type-argument row bound"
        );
    }

    #[test]
    fn type_argument_readback_rejects_broken_next_chain() {
        let err = validate_hir_type_argument_records(
            &[0, HIR_NODE_TYPE, HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 10, 12, 16],
            &[1, 20, 13, 17],
            &[0; 4],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, 2, INVALID, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, INVALID, INVALID],
        )
        .expect_err("missing type argument next links should fail closed");
        assert!(
            err.to_string().contains("argument chain ended"),
            "error should describe the broken parser-owned type argument chain"
        );
    }

    #[test]
    fn type_argument_readback_rejects_orphan_next_links() {
        let err = validate_hir_type_argument_records(
            &[0, HIR_NODE_TYPE, HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 10, 12, 16],
            &[1, 20, 13, 17],
            &[0; 4],
            &[
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_PATH,
            ],
            &[INVALID, INVALID, INVALID, INVALID],
            &[0, 0, 0, 0],
            &[INVALID, INVALID, 3, INVALID],
        )
        .expect_err("orphan type argument next links should fail closed");
        assert!(
            err.to_string()
                .contains("without belonging to an owner chain"),
            "error should describe orphan parser-owned type argument links"
        );
    }

    #[test]
    fn type_argument_readback_rejects_count_on_non_path_owner() {
        let err = validate_hir_type_argument_records(
            &[0, HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 10, 12],
            &[1, 20, 13],
            &[0; 3],
            &[HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_ARRAY, HIR_TYPE_FORM_PATH],
            &[INVALID, 2, INVALID],
            &[0, 1, 0],
            &[INVALID, INVALID, INVALID],
        )
        .expect_err("generic type argument owners must be path type records");
        assert!(
            err.to_string().contains("non-path type record"),
            "error should describe the parser-owned generic type owner contract"
        );
    }

    #[test]
    fn method_readback_accepts_function_keyed_method_and_impl_receiver_type_rows() {
        validate_hir_method_records(
            &[
                HIR_NODE_NONE,
                HIR_NODE_FN,
                HIR_NODE_PARAM,
                HIR_NODE_TYPE,
                HIR_NODE_FN,
            ],
            &[0, 10, 15, 5, 30],
            &[50, 25, 20, 8, 40],
            &[0; 5],
            &[
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_FN,
            ],
            &[INVALID, INVALID, INVALID, INVALID, 32],
            &[INVALID, 0, INVALID, INVALID, 0],
            &[INVALID, INVALID, 1, INVALID, INVALID],
            &[INVALID, INVALID, 0, INVALID, INVALID],
            &[INVALID, INVALID, 15, INVALID, INVALID],
            &[INVALID; 5],
            &[INVALID, 0, INVALID, INVALID, INVALID],
            &[INVALID, 0, INVALID, INVALID, INVALID],
            &[INVALID, 12, INVALID, INVALID, INVALID],
            &[INVALID, 15, INVALID, INVALID, INVALID],
            &[
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_NONE,
            ],
            &[
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PUBLIC,
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PRIVATE,
            ],
            &[
                0,
                HIR_METHOD_SIGNATURE_HAS_GENERICS | HIR_METHOD_SIGNATURE_HAS_WHERE,
                0,
                0,
                0,
            ],
            &[3, INVALID, INVALID, INVALID, INVALID],
        )
        .expect("method rows and impl receiver type rows should decode");
    }

    #[test]
    fn method_readback_rejects_method_name_at_function_span_start() {
        let err = validate_hir_method_records(
            &[HIR_NODE_NONE, HIR_NODE_FN, HIR_NODE_PARAM],
            &[0, 10, 15],
            &[30, 25, 20],
            &[0; 3],
            &[HIR_ITEM_KIND_NONE; 3],
            &[INVALID; 3],
            &[INVALID, 0, INVALID],
            &[INVALID; 3],
            &[INVALID; 3],
            &[INVALID; 3],
            &[INVALID; 3],
            &[INVALID, 0, INVALID],
            &[INVALID, 0, INVALID],
            &[INVALID, 10, INVALID],
            &[INVALID; 3],
            &[HIR_METHOD_RECEIVER_NONE; 3],
            &[HIR_METHOD_VIS_PRIVATE; 3],
            &[0; 3],
            &[INVALID; 3],
        )
        .expect_err("method names must follow the parser-owned function span start");
        assert!(
            err.to_string().contains("method name token"),
            "error should describe the parser-owned method name-token order contract"
        );
    }

    #[test]
    fn method_readback_rejects_first_param_before_method_name() {
        let err = validate_hir_method_records(
            &[HIR_NODE_NONE, HIR_NODE_FN, HIR_NODE_PARAM],
            &[0, 10, 12],
            &[30, 25, 15],
            &[0; 3],
            &[HIR_ITEM_KIND_NONE; 3],
            &[INVALID; 3],
            &[INVALID, 0, INVALID],
            &[INVALID, INVALID, 1],
            &[INVALID, INVALID, 0],
            &[INVALID, INVALID, 13],
            &[INVALID; 3],
            &[INVALID, 0, INVALID],
            &[INVALID, 0, INVALID],
            &[INVALID, 14, INVALID],
            &[INVALID, 13, INVALID],
            &[
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_NONE,
            ],
            &[HIR_METHOD_VIS_PRIVATE; 3],
            &[0; 3],
            &[INVALID; 3],
        )
        .expect_err("method first-parameter tokens must follow method names");
        assert!(
            err.to_string().contains("first parameter token"),
            "error should describe the parser-owned method parameter token order contract"
        );
    }

    #[test]
    fn method_readback_rejects_impl_method_value_item_name_token() {
        let err = validate_hir_method_records(
            &[HIR_NODE_NONE, HIR_NODE_FN, HIR_NODE_PARAM],
            &[0, 10, 15],
            &[30, 25, 20],
            &[0; 3],
            &[HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_NONE],
            &[INVALID, 12, INVALID],
            &[INVALID, 0, INVALID],
            &[INVALID, INVALID, 1],
            &[INVALID, INVALID, 0],
            &[INVALID, INVALID, 15],
            &[INVALID; 3],
            &[INVALID, 0, INVALID],
            &[INVALID, 0, INVALID],
            &[INVALID, 13, INVALID],
            &[INVALID, 15, INVALID],
            &[
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_NONE,
            ],
            &[
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PUBLIC,
                HIR_METHOD_VIS_PRIVATE,
            ],
            &[0; 3],
            &[INVALID; 3],
        )
        .expect_err("impl methods must not publish value item name tokens");
        assert!(
            err.to_string().contains("value item name token"),
            "error should describe the parser-owned method-only namespace contract"
        );
    }

    #[test]
    fn method_readback_rejects_impl_receiver_type_outside_owner_span() {
        let err = validate_hir_method_records(
            &[HIR_NODE_NONE, HIR_NODE_FN, HIR_NODE_PARAM, HIR_NODE_TYPE],
            &[0, 10, 15, 30],
            &[25, 20, 18, 35],
            &[0; 4],
            &[
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
            ],
            &[INVALID; 4],
            &[INVALID, 0, INVALID, INVALID],
            &[INVALID, INVALID, 1, INVALID],
            &[INVALID, INVALID, 0, INVALID],
            &[INVALID, INVALID, 15, INVALID],
            &[INVALID; 4],
            &[INVALID, 0, INVALID, INVALID],
            &[INVALID, 0, INVALID, INVALID],
            &[INVALID, 12, INVALID, INVALID],
            &[INVALID, 15, INVALID, INVALID],
            &[
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_REF_SELF,
                HIR_METHOD_RECEIVER_NONE,
                HIR_METHOD_RECEIVER_NONE,
            ],
            &[
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PUBLIC,
                HIR_METHOD_VIS_PRIVATE,
                HIR_METHOD_VIS_PRIVATE,
            ],
            &[0; 4],
            &[3, INVALID, INVALID, INVALID],
        )
        .expect_err("impl receiver type rows must stay inside the impl owner span");
        assert!(
            err.to_string().contains("outside the impl owner span"),
            "error should describe the parser-owned impl receiver type span contract"
        );
    }

    #[test]
    fn method_readback_rejects_impl_receiver_type_without_source_addressable_owner() {
        let err = validate_hir_method_records(
            &[HIR_NODE_NONE, HIR_NODE_NONE, HIR_NODE_NONE, HIR_NODE_TYPE],
            &[INVALID, INVALID, INVALID, 10],
            &[INVALID, INVALID, INVALID, 15],
            &[INVALID, INVALID, INVALID, 0],
            &[HIR_ITEM_KIND_NONE; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[INVALID; 4],
            &[HIR_METHOD_RECEIVER_NONE; 4],
            &[HIR_METHOD_VIS_PRIVATE; 4],
            &[0; 4],
            &[3, INVALID, INVALID, INVALID],
        )
        .expect_err("impl receiver type rows require a source-addressable owner");
        assert!(
            err.to_string()
                .contains("without a source-addressable impl owner row"),
            "error should describe the parser-owned impl owner source contract"
        );
    }

    #[test]
    fn type_record_readback_accepts_path_array_and_path_leaf_rows() {
        validate_hir_type_records(
            &[
                HIR_NODE_TYPE,
                HIR_NODE_PATH_EXPR,
                HIR_NODE_NONE,
                HIR_NODE_TYPE,
                HIR_NODE_TYPE,
                HIR_NODE_PATH_EXPR,
                HIR_NODE_NONE,
            ],
            &[0, 0, 2, 4, 5, 5, 6],
            &[3, 3, 3, 9, 7, 7, 7],
            &[0; 7],
            &[
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_ARRAY,
                HIR_TYPE_FORM_PATH,
                HIR_TYPE_FORM_NONE,
                HIR_TYPE_FORM_NONE,
            ],
            &[1, INVALID, INVALID, 4, 5, INVALID, INVALID],
            &[INVALID, INVALID, INVALID, 8, INVALID, INVALID, INVALID],
            &[INVALID; 7],
            &[0, INVALID, INVALID, 0, 0, INVALID, INVALID],
            &[2, 2, INVALID, INVALID, 6, 6, INVALID],
        )
        .expect("path, array, and path-expression leaf records should decode");
    }

    #[test]
    fn type_record_readback_rejects_composite_operand_without_type_record() {
        let err = validate_hir_type_records(
            &[HIR_NODE_TYPE, HIR_NODE_TYPE],
            &[0, 1],
            &[3, 2],
            &[0; 2],
            &[HIR_TYPE_FORM_ARRAY, HIR_TYPE_FORM_NONE],
            &[1, INVALID],
            &[2, INVALID],
            &[INVALID, INVALID],
            &[0; 2],
            &[INVALID, INVALID],
        )
        .expect_err("array/ref/slice operands must already be concrete type records");
        assert!(
            err.to_string().contains("concrete type operand"),
            "error should describe the malformed parser-owned composite operand"
        );
    }

    #[test]
    fn type_record_readback_rejects_path_leaf_outside_path_node() {
        let err = validate_hir_type_records(
            &[HIR_NODE_TYPE, HIR_NODE_PATH_EXPR, HIR_NODE_NONE],
            &[0, 0, 3],
            &[4, 2, 4],
            &[0; 3],
            &[HIR_TYPE_FORM_PATH, HIR_TYPE_FORM_NONE, HIR_TYPE_FORM_NONE],
            &[1, INVALID, INVALID],
            &[INVALID, INVALID, INVALID],
            &[INVALID, INVALID, INVALID],
            &[0; 3],
            &[2, INVALID, INVALID],
        )
        .expect_err("path leaves must stay inside the parser-owned path node");
        assert!(
            err.to_string().contains("outside path node"),
            "error should describe the violated parser-owned path leaf span"
        );
    }

    #[test]
    fn type_record_readback_rejects_type_rows_without_concrete_records() {
        let err = validate_hir_type_records(
            &[HIR_NODE_TYPE],
            &[0],
            &[1],
            &[0],
            &[HIR_TYPE_FORM_NONE],
            &[INVALID],
            &[INVALID],
            &[INVALID],
            &[0],
            &[INVALID],
        )
        .expect_err("accepted HIR type rows must publish concrete records");
        assert!(
            err.to_string().contains("no concrete type record"),
            "error should describe the missing parser-owned type record"
        );
    }

    #[test]
    fn call_argument_readback_accepts_contiguous_owned_ordinals() {
        validate_hir_call_argument_records(
            &[
                HIR_NODE_NAME_EXPR,
                HIR_NODE_CALL_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_EXPR,
            ],
            &[10, 10, 12, 14],
            &[11, 20, 13, 15],
            &[0; 4],
            &[INVALID, 0, INVALID, INVALID],
            &[INVALID, 2, INVALID, INVALID],
            &[INVALID, INVALID, 13, 15],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 1, 1],
            &[INVALID, INVALID, 0, 1],
        )
        .expect("contiguous call argument records should decode");
    }

    #[test]
    fn call_argument_readback_accepts_ordinals_beyond_packed_width() {
        let arg_count = 17usize;
        let row_count = 2 + arg_count;
        let mut kinds = vec![HIR_NODE_EXPR; row_count];
        let mut token_pos = vec![INVALID; row_count];
        let mut token_end = vec![INVALID; row_count];
        let node_file_ids = vec![0; row_count];
        let mut callee_nodes = vec![INVALID; row_count];
        let mut starts = vec![INVALID; row_count];
        let mut arg_ends = vec![INVALID; row_count];
        let mut counts = vec![0; row_count];
        let mut parent_calls = vec![INVALID; row_count];
        let mut ordinals = vec![INVALID; row_count];

        kinds[0] = HIR_NODE_NAME_EXPR;
        kinds[1] = HIR_NODE_CALL_EXPR;
        token_pos[0] = 10;
        token_end[0] = 11;
        token_pos[1] = 10;
        token_end[1] = 80;
        callee_nodes[1] = 0;
        starts[1] = 2;
        counts[1] = arg_count as u32;

        for ordinal in 0..arg_count {
            let node = 2 + ordinal;
            token_pos[node] = 12 + ordinal as u32 * 2;
            token_end[node] = token_pos[node] + 1;
            arg_ends[node] = token_end[node];
            parent_calls[node] = 1;
            ordinals[node] = ordinal as u32;
        }

        validate_hir_call_argument_records(
            &kinds,
            &token_pos,
            &token_end,
            &node_file_ids,
            &callee_nodes,
            &starts,
            &arg_ends,
            &counts,
            &parent_calls,
            &ordinals,
        )
        .expect("call argument readback should accept full u32 ordinals");
    }

    #[test]
    fn call_argument_readback_rejects_incomplete_owner_rows() {
        let err = validate_hir_call_argument_records(
            &[
                HIR_NODE_NAME_EXPR,
                HIR_NODE_CALL_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_EXPR,
            ],
            &[10, 10, 12, 14],
            &[11, 20, 13, 15],
            &[0; 4],
            &[INVALID, 0, INVALID, INVALID],
            &[INVALID, 2, INVALID, INVALID],
            &[INVALID, INVALID, 13, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 1, INVALID],
            &[INVALID, INVALID, 0, INVALID],
        )
        .expect_err("missing owned argument rows should fail closed");
        assert!(
            err.to_string().contains("owned argument rows"),
            "error should describe the missing parser-owned argument record"
        );
    }

    #[test]
    fn call_argument_readback_rejects_orphan_argument_metadata() {
        let err = validate_hir_call_argument_records(
            &[HIR_NODE_NAME_EXPR, HIR_NODE_EXPR],
            &[0, 1],
            &[1, 2],
            &[0; 2],
            &[INVALID, INVALID],
            &[INVALID, INVALID],
            &[INVALID, INVALID],
            &[0, 0],
            &[INVALID, INVALID],
            &[INVALID, 0],
        )
        .expect_err("orphan call argument metadata should fail closed");
        assert!(
            err.to_string().contains("without an owner"),
            "error should describe orphan parser-owned call argument metadata"
        );
    }

    #[test]
    fn array_literal_readback_accepts_contiguous_owned_element_chain() {
        validate_hir_array_literal_records(
            &[0, HIR_NODE_ARRAY_EXPR, HIR_NODE_EXPR, HIR_NODE_EXPR],
            &[INVALID, 10, 12, 20],
            &[INVALID, 30, 13, 21],
            &[INVALID, 0, 0, 0],
            &[INVALID, 2, INVALID, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 1, 1],
            &[INVALID, INVALID, 0, 1],
            &[INVALID, INVALID, 3, INVALID],
        )
        .expect("contiguous array literal element records should decode");
    }

    #[test]
    fn array_literal_readback_rejects_missing_owned_element_rows() {
        let err = validate_hir_array_literal_records(
            &[0, HIR_NODE_ARRAY_EXPR, HIR_NODE_EXPR, HIR_NODE_EXPR],
            &[INVALID, 10, 12, 20],
            &[INVALID, 30, 13, 21],
            &[INVALID, 0, 0, 0],
            &[INVALID, 2, INVALID, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 1, INVALID],
            &[INVALID, INVALID, 0, INVALID],
            &[INVALID, INVALID, INVALID, INVALID],
        )
        .expect_err("missing owned array element rows should fail closed");
        assert!(
            err.to_string().contains("owned element rows"),
            "error should describe the missing parser-owned array element record"
        );
    }

    #[test]
    fn array_literal_readback_rejects_non_contiguous_next_chain() {
        let err = validate_hir_array_literal_records(
            &[0, HIR_NODE_ARRAY_EXPR, HIR_NODE_EXPR, HIR_NODE_EXPR],
            &[INVALID, 10, 12, 20],
            &[INVALID, 30, 13, 21],
            &[INVALID, 0, 0, 0],
            &[INVALID, 2, INVALID, INVALID],
            &[0, 2, 0, 0],
            &[INVALID, INVALID, 1, 1],
            &[INVALID, INVALID, 0, 1],
            &[INVALID, INVALID, INVALID, INVALID],
        )
        .expect_err("broken array element next links should fail closed");
        assert!(
            err.to_string().contains("element chain ended"),
            "error should describe the violated parser-owned element chain"
        );
    }

    fn valid_match_source_addresses() -> ([u32; 9], [u32; 9], [u32; 9]) {
        (
            [0, 1, 3, 10, 4, 11, 7, 14, 5],
            [20, 2, 9, 18, 6, 12, 8, 15, 6],
            [0; 9],
        )
    }

    #[test]
    fn match_readback_accepts_contiguous_arms_and_payload_ordinals() {
        let (token_pos, token_end, file_ids) = valid_match_source_addresses();
        validate_hir_match_records(
            &[
                HIR_NODE_MATCH_EXPR,
                HIR_NODE_EXPR,
                0,
                0,
                HIR_NODE_NAME_EXPR,
                HIR_NODE_LITERAL_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_NAME_EXPR,
            ],
            &token_pos,
            &token_end,
            &file_ids,
            &[
                1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                2, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[2, 0, 0, 0, 0, 0, 0, 0, 0],
            &[
                INVALID, INVALID, 3, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, 4, 5, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, 8, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[0, 0, 1, 0, 0, 0, 0, 0, 0],
            &[
                INVALID, INVALID, 6, 7, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2,
            ],
            &[
                INVALID, INVALID, 0, 0, INVALID, INVALID, INVALID, INVALID, 0,
            ],
            &[
                INVALID, INVALID, 0, 1, INVALID, INVALID, INVALID, INVALID, 0,
            ],
        )
        .expect("contiguous parser-owned match arm and payload records should decode");
    }

    #[test]
    fn match_readback_rejects_payload_match_mismatches() {
        let (token_pos, token_end, file_ids) = valid_match_source_addresses();
        let err = validate_hir_match_records(
            &[
                HIR_NODE_MATCH_EXPR,
                HIR_NODE_EXPR,
                0,
                0,
                HIR_NODE_NAME_EXPR,
                HIR_NODE_LITERAL_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_EXPR,
                HIR_NODE_NAME_EXPR,
            ],
            &token_pos,
            &token_end,
            &file_ids,
            &[
                1, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                2, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[2, 0, 0, 0, 0, 0, 0, 0, 0],
            &[
                INVALID, INVALID, 3, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, 4, 5, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, 8, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[0, 0, 1, 0, 0, 0, 0, 0, 0],
            &[
                INVALID, INVALID, 6, 7, INVALID, INVALID, INVALID, INVALID, INVALID,
            ],
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 2,
            ],
            &[
                INVALID, INVALID, 0, 0, INVALID, INVALID, INVALID, INVALID, 1,
            ],
            &[
                INVALID, INVALID, 0, 1, INVALID, INVALID, INVALID, INVALID, 0,
            ],
        )
        .expect_err("payload rows must point back to the owning match expression");
        assert!(
            err.to_string().contains("belongs to match"),
            "error should describe the violated parser-owned payload back edge"
        );
    }

    #[test]
    fn match_readback_rejects_orphan_arm_metadata() {
        let err = validate_hir_match_records(
            &[
                HIR_NODE_MATCH_EXPR,
                HIR_NODE_EXPR,
                0,
                HIR_NODE_NAME_EXPR,
                0,
                HIR_NODE_EXPR,
            ],
            &[0, 1, 2, 3, 4, 6],
            &[10, 2, 9, 4, 5, 7],
            &[0; 6],
            &[1, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[2, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[1, 0, 0, 0, 0, 0],
            &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[INVALID, INVALID, 3, 4, INVALID, INVALID],
            &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[0, 0, 0, 0, 0, 0],
            &[INVALID, INVALID, 5, 5, INVALID, INVALID],
            &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[INVALID, INVALID, 0, INVALID, INVALID, INVALID],
            &[INVALID, INVALID, 0, INVALID, INVALID, INVALID],
        )
        .expect_err("unowned match arm rows must fail closed");
        assert!(
            err.to_string().contains("without belonging to a match"),
            "error should describe orphan parser-owned match arm metadata"
        );
    }

    #[test]
    fn item_path_readback_accepts_module_and_import_path_nodes() {
        validate_hir_item_path_records(
            &[
                HIR_NODE_MODULE_ITEM,
                HIR_NODE_PATH_EXPR,
                HIR_NODE_IMPORT_ITEM,
                HIR_NODE_PATH_EXPR,
                0,
            ],
            &[0, 1, 4, 5, INVALID],
            &[3, 3, 7, 7, INVALID],
            &[0, 0, 1, 1, INVALID],
            &[
                HIR_ITEM_KIND_MODULE,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_IMPORT,
                HIR_ITEM_KIND_NONE,
                HIR_ITEM_KIND_NONE,
            ],
            &[0, INVALID, 1, INVALID, INVALID],
            &[1, INVALID, 5, INVALID, INVALID],
            &[3, INVALID, 7, INVALID, INVALID],
            &[1, INVALID, 3, INVALID, INVALID],
            &[
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_PATH,
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_NONE,
            ],
        )
        .expect("module/import item path records should decode when anchored by path nodes");
    }

    #[test]
    fn item_path_readback_rejects_unanchored_path_node_spans() {
        let err = validate_hir_item_path_records(
            &[HIR_NODE_MODULE_ITEM, HIR_NODE_PATH_EXPR, 0],
            &[0, 1, INVALID],
            &[3, 2, INVALID],
            &[0, 0, INVALID],
            &[HIR_ITEM_KIND_MODULE, HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_NONE],
            &[0, INVALID, INVALID],
            &[1, INVALID, INVALID],
            &[3, INVALID, INVALID],
            &[1, INVALID, INVALID],
            &[
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_NONE,
                HIR_ITEM_IMPORT_TARGET_NONE,
            ],
        )
        .expect_err("path node spans must exactly anchor module/import path spans");
        assert!(
            err.to_string().contains("does not anchor"),
            "error should describe the violated parser-owned item path anchor"
        );
    }

    #[test]
    fn item_path_readback_rejects_path_records_without_path_owner() {
        let err = validate_hir_item_path_records(
            &[0, HIR_NODE_PATH_EXPR],
            &[0, 1],
            &[1, 2],
            &[0, 0],
            &[HIR_ITEM_KIND_NONE, HIR_ITEM_KIND_NONE],
            &[INVALID, INVALID],
            &[INVALID, 1],
            &[INVALID, 2],
            &[INVALID, 1],
            &[HIR_ITEM_IMPORT_TARGET_NONE, HIR_ITEM_IMPORT_TARGET_NONE],
        )
        .expect_err("non module/import rows must not publish item path records");
        assert!(
            err.to_string()
                .contains("without a module/import path owner"),
            "error should describe orphan parser-owned item path records"
        );
    }
}
