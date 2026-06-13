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
            signature_status::{HIR_METHOD_SIGNATURE_HAS_GENERICS, HIR_METHOD_SIGNATURE_HAS_WHERE},
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
const HIR_PACKED_NODE_ORDINAL_SLOT_COUNT: u32 = 16;
const PROD_BOUND_TYPE_IDENT: u32 = 230;

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
    pub hir_array_lit_first_element: wgpu::Buffer,
    pub hir_array_lit_element_count: wgpu::Buffer,
    pub hir_array_lit_context_stmt_node: wgpu::Buffer,
    pub hir_array_element_parent_lit: wgpu::Buffer,
    pub hir_array_element_ordinal: wgpu::Buffer,
    pub hir_array_element_next: wgpu::Buffer,
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

/// Narrow readback for parser-owned function return-type records.
///
/// This is intentionally smaller than `ParserHirItemReadbacks`: downstream
/// type checking and backends need the function -> return type node edge, not
/// the full parser debug tree.
pub struct ParserHirFunctionReturnReadbacks {
    pub ll1_status: wgpu::Buffer,
    pub hir_kind: wgpu::Buffer,
    pub hir_token_pos: wgpu::Buffer,
    pub hir_token_end: wgpu::Buffer,
    pub hir_node_file_id: wgpu::Buffer,
    pub hir_type_form: wgpu::Buffer,
    pub hir_type_file_id: wgpu::Buffer,
    pub hir_fn_return_type_node: wgpu::Buffer,
    pub hir_method_signature_flags: wgpu::Buffer,
    pub hir_method_name_token: wgpu::Buffer,
    pub hir_item_kind: wgpu::Buffer,
    pub hir_item_name_token: wgpu::Buffer,
    pub hir_item_file_id: wgpu::Buffer,
}

pub struct DecodedParserHirFunctionReturnReadbacks {
    pub ll1_status: [u32; 6],
    pub hir_kind: Vec<u32>,
    pub hir_token_pos: Vec<u32>,
    pub hir_token_end: Vec<u32>,
    pub hir_node_file_id: Vec<u32>,
    pub hir_type_form: Vec<u32>,
    pub hir_type_file_id: Vec<u32>,
    pub hir_fn_return_type_node: Vec<u32>,
    pub hir_method_signature_flags: Vec<u32>,
    pub hir_method_name_token: Vec<u32>,
    pub hir_item_kind: Vec<u32>,
    pub hir_item_name_token: Vec<u32>,
    pub hir_item_file_id: Vec<u32>,
}

impl ParserHirFunctionReturnReadbacks {
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
                "rb.parser.hir_fn_return_records.ll1_status",
                bufs.ll1_status.byte_size as u64,
            ),
            hir_kind: mk(
                "rb.parser.hir_fn_return_records.hir_kind",
                bufs.hir_kind.byte_size as u64,
            ),
            hir_token_pos: mk(
                "rb.parser.hir_fn_return_records.hir_token_pos",
                bufs.hir_token_pos.byte_size as u64,
            ),
            hir_token_end: mk(
                "rb.parser.hir_fn_return_records.hir_token_end",
                bufs.hir_token_end.byte_size as u64,
            ),
            hir_node_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_node_file_id",
                bufs.hir_token_file_id.byte_size as u64,
            ),
            hir_type_form: mk(
                "rb.parser.hir_fn_return_records.hir_type_form",
                bufs.hir_type_form.byte_size as u64,
            ),
            hir_type_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_type_file_id",
                bufs.hir_type_file_id.byte_size as u64,
            ),
            hir_fn_return_type_node: mk(
                "rb.parser.hir_fn_return_records.hir_fn_return_type_node",
                bufs.hir_fn_return_type_node.byte_size as u64,
            ),
            hir_method_signature_flags: mk(
                "rb.parser.hir_fn_return_records.hir_method_signature_flags",
                bufs.hir_method_signature_flags.byte_size as u64,
            ),
            hir_method_name_token: mk(
                "rb.parser.hir_fn_return_records.hir_method_name_token",
                bufs.hir_method_name_token.byte_size as u64,
            ),
            hir_item_kind: mk(
                "rb.parser.hir_fn_return_records.hir_item_kind",
                bufs.hir_item_kind.byte_size as u64,
            ),
            hir_item_name_token: mk(
                "rb.parser.hir_fn_return_records.hir_item_name_token",
                bufs.hir_item_name_token.byte_size as u64,
            ),
            hir_item_file_id: mk(
                "rb.parser.hir_fn_return_records.hir_item_file_id",
                bufs.hir_item_file_id.byte_size as u64,
            ),
        }
    }

    pub fn encode_copies(&self, encoder: &mut wgpu::CommandEncoder, bufs: &ParserBuffers) {
        encoder.copy_buffer_to_buffer(
            &bufs.ll1_status,
            0,
            &self.ll1_status,
            0,
            bufs.ll1_status.byte_size as u64,
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
            &bufs.hir_type_form,
            0,
            &self.hir_type_form,
            0,
            bufs.hir_type_form.byte_size as u64,
        );
        encoder.copy_buffer_to_buffer(
            &bufs.hir_type_file_id,
            0,
            &self.hir_type_file_id,
            0,
            bufs.hir_type_file_id.byte_size as u64,
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
            &bufs.hir_method_name_token,
            0,
            &self.hir_method_name_token,
            0,
            bufs.hir_method_name_token.byte_size as u64,
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
            &bufs.hir_item_file_id,
            0,
            &self.hir_item_file_id,
            0,
            bufs.hir_item_file_id.byte_size as u64,
        );
    }

    pub fn map_and_decode(
        self,
        device: &wgpu::Device,
        bufs: &ParserBuffers,
    ) -> Result<DecodedParserHirFunctionReturnReadbacks> {
        let map = |name: &str, b: &wgpu::Buffer| {
            crate::gpu::passes_core::map_readback_for_progress(
                &b.slice(..),
                &format!("parser.hir_fn_return_readback.{name}"),
            );
        };
        map("ll1_status", &self.ll1_status);
        map("hir_kind", &self.hir_kind);
        map("hir_token_pos", &self.hir_token_pos);
        map("hir_token_end", &self.hir_token_end);
        map("hir_node_file_id", &self.hir_node_file_id);
        map("hir_type_form", &self.hir_type_form);
        map("hir_type_file_id", &self.hir_type_file_id);
        map("hir_fn_return_type_node", &self.hir_fn_return_type_node);
        map(
            "hir_method_signature_flags",
            &self.hir_method_signature_flags,
        );
        map("hir_method_name_token", &self.hir_method_name_token);
        map("hir_item_kind", &self.hir_item_kind);
        map("hir_item_name_token", &self.hir_item_name_token);
        map("hir_item_file_id", &self.hir_item_file_id);

        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "parser.hir_fn_return_readback",
            wgpu::PollType::wait_indefinitely(),
        );

        let ll1_status = read_u32_array::<6>(&self.ll1_status, "ll1_status")?;
        let tree_len = active_tree_readback_len(
            "hir_fn_return_readback.tree",
            bufs.tree_count_uses_status,
            ll1_status[5],
            bufs.total_emit,
            bufs.hir_kind.count,
        )?;

        let decoded = DecodedParserHirFunctionReturnReadbacks {
            ll1_status,
            hir_kind: read_u32_vec(&self.hir_kind, tree_len),
            hir_token_pos: read_u32_vec(&self.hir_token_pos, tree_len),
            hir_token_end: read_u32_vec(&self.hir_token_end, tree_len),
            hir_node_file_id: read_u32_vec(&self.hir_node_file_id, tree_len),
            hir_type_form: read_u32_vec(&self.hir_type_form, tree_len),
            hir_type_file_id: read_u32_vec(&self.hir_type_file_id, tree_len),
            hir_fn_return_type_node: read_u32_vec(&self.hir_fn_return_type_node, tree_len),
            hir_method_signature_flags: read_u32_vec(&self.hir_method_signature_flags, tree_len),
            hir_method_name_token: read_u32_vec(&self.hir_method_name_token, tree_len),
            hir_item_kind: read_u32_vec(&self.hir_item_kind, tree_len),
            hir_item_name_token: read_u32_vec(&self.hir_item_name_token, tree_len),
            hir_item_file_id: read_u32_vec(&self.hir_item_file_id, tree_len),
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
        Ok(decoded)
    }
}

impl ParserHirItemReadbacks {
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
        let packed_hir_call_arg = read_u32_vec(&self.hir_call_arg_parent_call, tree_len);
        let hir_call_arg_parent_call = packed_hir_call_arg
            .iter()
            .copied()
            .map(crate::parser::hir_records::node_ordinal_node)
            .collect();
        let hir_call_arg_ordinal = packed_hir_call_arg
            .iter()
            .copied()
            .map(crate::parser::hir_records::node_ordinal_ordinal)
            .collect();
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
        let hir_variant_payload_count = read_u32_vec(&self.hir_variant_payload_count, tree_len);

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
            hir_variant_parent_enum: read_u32_vec(&self.hir_variant_parent_enum, tree_len),
            hir_variant_ordinal: read_u32_vec(&self.hir_variant_ordinal, tree_len),
            hir_variant_payload_start: read_u32_vec(&self.hir_variant_payload_start, tree_len),
            hir_variant_payload_count,
            hir_variant_payload_node: read_u32_vec(
                &self.hir_variant_payload_node,
                tree_len.saturating_mul(HIR_VARIANT_PAYLOAD_SLOT_STRIDE as usize),
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
            hir_match_scrutinee_node: read_u32_vec(&self.hir_match_scrutinee_node, tree_len),
            hir_match_arm_start: read_u32_vec(&self.hir_match_arm_start, tree_len),
            hir_match_arm_count: read_u32_vec(&self.hir_match_arm_count, tree_len),
            hir_match_arm_next: read_u32_vec(&self.hir_match_arm_next, tree_len),
            hir_match_arm_pattern_node: read_u32_vec(&self.hir_match_arm_pattern_node, tree_len),
            hir_match_arm_payload_start: read_u32_vec(&self.hir_match_arm_payload_start, tree_len),
            hir_match_arm_payload_count: read_u32_vec(&self.hir_match_arm_payload_count, tree_len),
            hir_match_arm_result_node: read_u32_vec(&self.hir_match_arm_result_node, tree_len),
            hir_match_payload_owner_arm: read_u32_vec(&self.hir_match_payload_owner_arm, tree_len),
            hir_match_payload_match_node: read_u32_vec(
                &self.hir_match_payload_match_node,
                tree_len,
            ),
            hir_match_payload_ordinal: read_u32_vec(&self.hir_match_payload_ordinal, tree_len),
            hir_call_callee_node: read_u32_vec(&self.hir_call_callee_node, tree_len),
            hir_call_context_stmt_node: read_u32_vec(&self.hir_call_context_stmt_node, tree_len),
            hir_call_arg_start: read_u32_vec(&self.hir_call_arg_start, tree_len),
            hir_call_arg_end: read_u32_vec(&self.hir_call_arg_end, tree_len),
            hir_call_arg_count: read_u32_vec(&self.hir_call_arg_count, tree_len),
            hir_call_arg_parent_call,
            hir_call_arg_ordinal,
            hir_array_lit_first_element: read_u32_vec(&self.hir_array_lit_first_element, tree_len),
            hir_array_lit_element_count: read_u32_vec(&self.hir_array_lit_element_count, tree_len),
            hir_array_lit_context_stmt_node: read_u32_vec(
                &self.hir_array_lit_context_stmt_node,
                tree_len,
            ),
            hir_array_element_parent_lit: read_u32_vec(
                &self.hir_array_element_parent_lit,
                tree_len,
            ),
            hir_array_element_ordinal: read_u32_vec(&self.hir_array_element_ordinal, tree_len),
            hir_array_element_next: read_u32_vec(&self.hir_array_element_next, tree_len),
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
            hir_struct_field_parent_struct: read_u32_vec(
                &self.hir_struct_field_parent_struct,
                tree_len,
            ),
            hir_struct_field_ordinal: read_u32_vec(&self.hir_struct_field_ordinal, tree_len),
            hir_struct_field_type_node: read_u32_vec(&self.hir_struct_field_type_node, tree_len),
            hir_struct_decl_field_start: read_u32_vec(&self.hir_struct_decl_field_start, tree_len),
            hir_struct_decl_field_count: read_u32_vec(&self.hir_struct_decl_field_count, tree_len),
            hir_struct_lit_head_node: read_u32_vec(&self.hir_struct_lit_head_node, tree_len),
            hir_struct_lit_context_stmt_node: read_u32_vec(
                &self.hir_struct_lit_context_stmt_node,
                tree_len,
            ),
            hir_struct_lit_field_start: read_u32_vec(&self.hir_struct_lit_field_start, tree_len),
            hir_struct_lit_field_count: read_u32_vec(&self.hir_struct_lit_field_count, tree_len),
            hir_struct_lit_field_parent_lit: read_u32_vec(
                &self.hir_struct_lit_field_parent_lit,
                tree_len,
            ),
            hir_struct_lit_field_value_node: read_u32_vec(
                &self.hir_struct_lit_field_value_node,
                tree_len,
            ),
            hir_struct_lit_field_next: read_u32_vec(&self.hir_struct_lit_field_next, tree_len),
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

/// Decoded results from the staging buffers.
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
        let packed_hir_call_arg = decode_tree_vec(&rb.hir_call_arg_parent_call);
        let hir_call_arg_parent_call = packed_hir_call_arg
            .iter()
            .copied()
            .map(crate::parser::hir_records::node_ordinal_node)
            .collect();
        let hir_call_arg_ordinal = packed_hir_call_arg
            .iter()
            .copied()
            .map(crate::parser::hir_records::node_ordinal_ordinal)
            .collect();
        let hir_array_lit_first_element = decode_tree_vec(&rb.hir_array_lit_first_element);
        let hir_array_lit_element_count = decode_tree_vec(&rb.hir_array_lit_element_count);
        let hir_array_element_parent_lit = decode_tree_vec(&rb.hir_array_element_parent_lit);
        let hir_array_element_ordinal = decode_tree_vec(&rb.hir_array_element_ordinal);
        let hir_array_element_next = decode_tree_vec(&rb.hir_array_element_next);
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
        // This readback path decodes the adjacent-pair projected tree. It is a
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

pub fn validate_hir_enum_variant_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    parent_enums: &[u32],
    variant_ordinals: &[u32],
    payload_starts: &[u32],
    payload_counts: &[u32],
    payload_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    let slot_stride = HIR_VARIANT_PAYLOAD_SLOT_STRIDE as usize;
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
        || parent_enums.len() != row_count
        || variant_ordinals.len() != row_count
        || payload_starts.len() != row_count
        || payload_counts.len() != row_count
        || payload_nodes.len() != row_count.saturating_mul(slot_stride)
    {
        return Err(anyhow!(
            "parser HIR enum variant record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant owner row {owner} lacks source-addressable metadata"
            ));
        }
        if !has_non_empty_span(child) || node_file_ids[child] == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} lacks source-addressable metadata"
            ));
        }
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} published a different file id than owner row {owner}"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR enum variant {label} row {child} falls outside owner row {owner} span"
            ));
        }
        Ok(())
    };

    let mut variant_ordinal_keys = Vec::new();
    let mut payload_owner = vec![INVALID; row_count];
    for (row, &parent) in parent_enums.iter().enumerate() {
        let payload_base = row * slot_stride;
        let payload_slots = &payload_nodes[payload_base..payload_base + slot_stride];

        if parent == INVALID {
            if variant_ordinals[row] != INVALID {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published an ordinal without an enum owner"
                ));
            }
            if payload_starts[row] != INVALID
                || payload_counts[row] != 0
                || payload_slots.iter().any(|&payload| payload != INVALID)
            {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload metadata without an enum-variant owner (kind={}, span={}..{}, item_kind={}, payload_start={}, payload_count={}, payload_slots={:?})",
                    kinds[row],
                    token_pos[row],
                    token_end[row],
                    item_kinds[row],
                    payload_starts[row],
                    payload_counts[row],
                    payload_slots
                ));
            }
            continue;
        }

        let parent = parent as usize;
        if parent >= row_count {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published enum owner {parent}, outside {row_count} readback rows"
            ));
        }
        if kinds[parent] != HIR_NODE_ENUM_ITEM || item_kinds[parent] != HIR_ITEM_KIND_ENUM {
            return Err(anyhow!(
                "parser HIR enum variant row {row} points at owner {parent} without an enum item record"
            ));
        }
        if kinds[row] != HIR_NODE_ITEM || item_kinds[row] != HIR_ITEM_KIND_ENUM_VARIANT {
            return Err(anyhow!(
                "parser HIR enum variant row {row} is not backed by a parser-owned enum-variant item record"
            ));
        }
        if item_file_ids[parent] != node_file_ids[parent]
            || item_file_ids[row] != node_file_ids[row]
            || item_file_ids[row] != item_file_ids[parent]
        {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published item/file ids that do not match enum owner {parent}"
            ));
        }
        require_child_source(parent, row, "row")?;

        let ordinal = variant_ordinals[row];
        if ordinal == INVALID {
            return Err(anyhow!(
                "parser HIR enum variant row {row} omitted its source-order ordinal"
            ));
        }
        variant_ordinal_keys.push((parent, ordinal, row));

        let payload_count = payload_counts[row];
        if payload_count > HIR_VARIANT_PAYLOAD_SLOT_STRIDE {
            return Err(anyhow!(
                "parser HIR enum variant row {row} published {payload_count} payloads, exceeding {} flat payload slots",
                HIR_VARIANT_PAYLOAD_SLOT_STRIDE
            ));
        }

        if payload_count == 0 {
            if payload_starts[row] != INVALID
                || payload_slots.iter().any(|&payload| payload != INVALID)
            {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload slots without a payload count"
                ));
            }
            continue;
        }

        let first_payload = payload_slots[0];
        if payload_starts[row] != first_payload {
            return Err(anyhow!(
                "parser HIR enum variant row {row} payload start does not point at ordinal zero"
            ));
        }

        let mut previous_payload: Option<usize> = None;
        for slot in 0..slot_stride {
            let payload = payload_slots[slot];
            if slot >= payload_count as usize {
                if payload != INVALID {
                    return Err(anyhow!(
                        "parser HIR enum variant row {row} retained stale payload slot {slot}"
                    ));
                }
                continue;
            }

            if payload == INVALID || payload as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR enum variant row {row} published payload count {payload_count} without an in-table payload type at ordinal {slot}"
                ));
            }
            let payload = payload as usize;
            if payload_owner[payload] != INVALID {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} appears in multiple variant payload slots"
                ));
            }
            payload_owner[payload] = row as u32;
            if kinds[payload] != HIR_NODE_TYPE || type_forms[payload] == HIR_TYPE_FORM_NONE {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} is not a concrete type record"
                ));
            }
            if type_file_ids[payload] != node_file_ids[payload] {
                return Err(anyhow!(
                    "parser HIR enum variant payload row {payload} type/file id does not match its HIR row"
                ));
            }
            require_child_source(row, payload, "payload")?;
            if let Some(previous) = previous_payload {
                if token_pos[payload] <= token_pos[previous]
                    || token_end[previous] > token_pos[payload]
                {
                    return Err(anyhow!(
                        "parser HIR enum variant row {row} payload slots overlap or are not in source order"
                    ));
                }
            }
            previous_payload = Some(payload);
        }
    }

    variant_ordinal_keys.sort_unstable();
    let mut current_owner = INVALID as usize;
    let mut expected_ordinal = 0u32;
    for (owner, ordinal, row) in variant_ordinal_keys {
        if owner != current_owner {
            current_owner = owner;
            expected_ordinal = 0;
        }
        if ordinal != expected_ordinal {
            return Err(anyhow!(
                "parser HIR enum row {owner} variant ordinals are not contiguous from zero at row {row}"
            ));
        }
        expected_ordinal += 1;
    }

    Ok(())
}

pub fn validate_hir_semantic_tree_records(
    kinds: &[u32],
    parse_subtree_end: &[u32],
    semantic_prefix_before_node: &[u32],
    semantic_dense_node: &[u32],
    semantic_subtree_end: &[u32],
    semantic_parent: &[u32],
    semantic_first_child: &[u32],
    semantic_next_sibling: &[u32],
    semantic_depth: &[u32],
    semantic_child_index: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if parse_subtree_end.len() != row_count
        || semantic_prefix_before_node.len() != row_count
        || semantic_dense_node.len() != row_count
        || semantic_subtree_end.len() != row_count
        || semantic_parent.len() != row_count
        || semantic_first_child.len() != row_count
        || semantic_next_sibling.len() != row_count
        || semantic_depth.len() != row_count
        || semantic_child_index.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR semantic-tree record arrays have inconsistent lengths"
        ));
    }

    let semantic_count = kinds.iter().filter(|&&kind| kind != HIR_NODE_NONE).count();
    let mut expected_prefix = 0usize;
    for (node, &kind) in kinds.iter().enumerate() {
        let published_prefix = semantic_prefix_before_node[node] as usize;
        if published_prefix != expected_prefix {
            return Err(anyhow!(
                "parser HIR semantic-tree node {node} published prefix {published_prefix}, expected {expected_prefix}"
            ));
        }
        if kind == HIR_NODE_NONE {
            continue;
        }
        if expected_prefix >= row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree dense row {expected_prefix} exceeds {row_count} readback rows"
            ));
        }
        let dense_node = semantic_dense_node[expected_prefix];
        if dense_node as usize != node {
            return Err(anyhow!(
                "parser HIR semantic-tree dense row {expected_prefix} points at node {dense_node}, expected {node}"
            ));
        }
        expected_prefix += 1;
    }

    let mut next_child_index_by_parent = vec![0u32; semantic_count];
    let mut root_count = 0usize;
    let mut next_root_child_index = 0u32;
    for row in 0..semantic_count {
        let original_node = semantic_dense_node[row] as usize;
        if original_node >= row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published original node {original_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[original_node] == HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} points at non-semantic original node {original_node}"
            ));
        }
        if semantic_prefix_before_node[original_node] as usize != row {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} disagrees with original node {original_node} prefix {}",
                semantic_prefix_before_node[original_node]
            ));
        }

        let subtree_end = semantic_subtree_end[row] as usize;
        if subtree_end <= row || subtree_end > semantic_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published subtree end {subtree_end}, outside row range"
            ));
        }
        let original_end = parse_subtree_end[original_node] as usize;
        if original_end > row_count {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} original node {original_node} published parse subtree end {original_end}, outside {row_count} readback rows"
            ));
        }
        let expected_subtree_end = if original_end == row_count {
            semantic_count
        } else {
            semantic_prefix_before_node[original_end] as usize
        }
        .max(row + 1);
        if subtree_end != expected_subtree_end {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published subtree end {subtree_end}, expected {expected_subtree_end}"
            ));
        }

        let parent = semantic_parent[row];
        if parent == INVALID {
            root_count += 1;
            if semantic_depth[row] != 0 {
                return Err(anyhow!(
                    "parser HIR semantic-tree root row {row} published depth {}",
                    semantic_depth[row]
                ));
            }
            if semantic_child_index[row] != next_root_child_index {
                return Err(anyhow!(
                    "parser HIR semantic-tree root row {row} published child index {}, expected {next_root_child_index}",
                    semantic_child_index[row]
                ));
            }
            next_root_child_index = next_root_child_index.saturating_add(1);
        } else {
            let parent = parent as usize;
            if parent >= semantic_count {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published parent {parent}, outside {semantic_count} semantic rows"
                ));
            }
            if parent >= row {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published non-preorder parent {parent}"
                ));
            }
            if row >= semantic_subtree_end[parent] as usize {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published parent {parent} whose subtree ends at {}",
                    semantic_subtree_end[parent]
                ));
            }
            let expected_depth = semantic_depth[parent].saturating_add(1);
            if semantic_depth[row] != expected_depth {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published depth {}, expected {expected_depth}",
                    semantic_depth[row]
                ));
            }
            let expected_child_index = next_child_index_by_parent[parent];
            if semantic_child_index[row] != expected_child_index {
                return Err(anyhow!(
                    "parser HIR semantic-tree row {row} published child index {}, expected {expected_child_index}",
                    semantic_child_index[row]
                ));
            }
            next_child_index_by_parent[parent] = expected_child_index.saturating_add(1);
        }

        let expected_first_child =
            if row + 1 < semantic_count && semantic_parent[row + 1] == row as u32 {
                (row + 1) as u32
            } else {
                INVALID
            };
        if semantic_first_child[row] != expected_first_child {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published first child {}, expected {expected_first_child}",
                semantic_first_child[row]
            ));
        }

        let expected_next_sibling = if subtree_end < semantic_count
            && semantic_parent[subtree_end] == semantic_parent[row]
        {
            subtree_end as u32
        } else {
            INVALID
        };
        if semantic_next_sibling[row] != expected_next_sibling {
            return Err(anyhow!(
                "parser HIR semantic-tree row {row} published next sibling {}, expected {expected_next_sibling}",
                semantic_next_sibling[row]
            ));
        }
    }

    if semantic_count > 0 && root_count == 0 {
        return Err(anyhow!(
            "parser HIR semantic-tree published semantic rows without a root"
        ));
    }

    Ok(())
}

pub fn validate_hir_type_argument_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    starts: &[u32],
    counts: &[u32],
    next_args: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || starts.len() != row_count
        || next_args.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type argument record arrays have inconsistent lengths"
        ));
    }

    let total_claimed_args = counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR type argument counts overflowed host usize"))
    })?;
    if total_claimed_args > row_count {
        return Err(anyhow!(
            "parser HIR type argument owner rows claim {total_claimed_args} type argument rows, exceeding {row_count} readback rows"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut argument_owner = vec![INVALID; row_count];
    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if starts[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR type argument owner row {owner} published a first argument without an argument count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} is not a type HIR row"
            ));
        }
        if type_forms[owner] != HIR_TYPE_FORM_PATH {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published generic arguments on a non-path type record"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published generic arguments without a source-addressable owner span"
            ));
        }
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published {count} arguments, exceeding {row_count} readback rows"
            ));
        }

        let start = starts[owner];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type argument owner row {owner} published argument count {count} without an in-table first argument"
            ));
        }

        let mut arg = start as usize;
        let mut previous_arg = None;
        for expected_ordinal in 0..count as usize {
            if arg == owner {
                return Err(anyhow!(
                    "parser HIR type argument owner row {owner} points at itself as an argument"
                ));
            }
            if kinds[arg] != HIR_NODE_TYPE {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} is not a type HIR row"
                ));
            }
            if type_forms[arg] == HIR_TYPE_FORM_NONE {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has no concrete type record"
                ));
            }
            if !has_non_empty_span(arg) {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has no source-addressable argument span"
                ));
            }
            if node_file_ids[arg] != node_file_ids[owner] {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} has a different file id than owner row {owner}"
                ));
            }
            if token_pos[arg] < token_pos[owner] || token_end[arg] > token_end[owner] {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} is outside owner row {owner}'s source span"
                ));
            }
            if let Some(previous_arg) = previous_arg {
                if token_pos[arg] <= token_pos[previous_arg]
                    || token_end[previous_arg] > token_pos[arg]
                {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} published argument row {arg} out of source order"
                    ));
                }
            }
            let previous_owner = argument_owner[arg];
            if previous_owner != INVALID {
                return Err(anyhow!(
                    "parser HIR type argument row {arg} appears in multiple owner chains"
                ));
            }
            argument_owner[arg] = owner as u32;
            previous_arg = Some(arg);

            let next = next_args[arg];
            if expected_ordinal + 1 == count as usize {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} final argument row {arg} did not terminate the argument chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR type argument owner row {owner} argument chain ended before count {count}"
                    ));
                }
                arg = next as usize;
            }
        }
    }

    for (arg, &next) in next_args.iter().enumerate() {
        if next == INVALID {
            continue;
        }
        if next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published next argument {next}, outside {row_count} readback rows"
            ));
        }
        let owner = argument_owner[arg];
        if owner == INVALID {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published a next argument without belonging to an owner chain"
            ));
        }
        if argument_owner[next as usize] != owner {
            return Err(anyhow!(
                "parser HIR type argument row {arg} published a next argument outside its owner chain"
            ));
        }
    }

    Ok(())
}

pub fn validate_hir_parameter_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    owner_fn_nodes: &[u32],
    ordinals: &[u32],
    name_tokens: &[u32],
    record_nodes: &[u32],
    type_nodes: &[u32],
) -> Result<()> {
    let row_count = owner_fn_nodes.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || ordinals.len() != row_count
        || name_tokens.len() != row_count
        || record_nodes.len() != row_count
        || type_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR parameter record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut owner_param_counts = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (param_node, &owner) in owner_fn_nodes.iter().enumerate() {
        if owner == INVALID {
            if ordinals[param_node] != INVALID
                || name_tokens[param_node] != INVALID
                || record_nodes[param_node] != INVALID
                || type_nodes[param_node] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR parameter row {param_node} published parameter metadata without an owner function"
                ));
            }
            if kinds[param_node] == HIR_NODE_PARAM {
                return Err(anyhow!(
                    "parser HIR parameter row {param_node} has a parameter HIR kind but no parser-owned parameter record"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published owner function {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_FN {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at owner {owner} without a function HIR row"
            ));
        }
        if kinds[param_node] != HIR_NODE_PARAM {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published parameter metadata on HIR kind {}",
                kinds[param_node]
            ));
        }
        if record_nodes[param_node] != param_node as u32 {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} did not self-identify its parser-owned record node"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at a function owner without a source-addressable span"
            ));
        }
        if !has_non_empty_span(param_node) || node_file_ids[param_node] == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} lacks a source-addressable parameter span"
            ));
        }
        if node_file_ids[param_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published a different file id than owner function {owner}"
            ));
        }
        if token_pos[param_node] < token_pos[owner] || token_end[param_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} falls outside owner function {owner} span"
            ));
        }

        let name_token = name_tokens[param_node];
        if name_token == INVALID
            || name_token < token_pos[param_node]
            || name_token >= token_end[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published a name token outside its parameter span"
            ));
        }

        let ordinal = ordinals[param_node];
        if ordinal == INVALID {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published no source-order ordinal"
            ));
        }
        owner_param_counts[owner] = owner_param_counts[owner].checked_add(1).ok_or_else(|| {
            anyhow!("parser HIR parameter counts overflowed host validation state")
        })?;
        ordinal_keys.push((owner, ordinal, param_node));

        let type_node = type_nodes[param_node];
        if type_node == INVALID {
            continue;
        }
        if type_node as usize >= row_count || type_node as usize == param_node {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} published no in-table type edge"
            ));
        }
        let type_node = type_node as usize;
        if kinds[type_node] != HIR_NODE_TYPE || type_forms[type_node] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at row {type_node} without a concrete type record"
            ));
        }
        if !has_non_empty_span(type_node) {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} without a non-empty token span"
            ));
        }
        if node_file_ids[type_node] != node_file_ids[param_node]
            || type_file_ids[type_node] != node_file_ids[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} with a different file id"
            ));
        }
        if token_pos[type_node] < token_pos[param_node]
            || token_end[type_node] > token_end[param_node]
        {
            return Err(anyhow!(
                "parser HIR parameter row {param_node} points at type row {type_node} outside its parameter span"
            ));
        }
    }

    ordinal_keys.sort_unstable();
    let mut index = 0usize;
    while index < ordinal_keys.len() {
        let owner = ordinal_keys[index].0;
        let count = owner_param_counts[owner];
        for expected_ordinal in 0..count {
            if index >= ordinal_keys.len() || ordinal_keys[index].0 != owner {
                return Err(anyhow!(
                    "parser HIR function row {owner} parameter ordinal table ended before count {count}"
                ));
            }
            let (key_owner, ordinal, param_node) = ordinal_keys[index];
            debug_assert_eq!(key_owner, owner);
            if ordinal != expected_ordinal {
                return Err(anyhow!(
                    "parser HIR function row {owner} parameter ordinals are not contiguous from zero"
                ));
            }
            if expected_ordinal > 0 {
                let previous_param_node = ordinal_keys[index - 1].2;
                if token_pos[param_node] <= token_pos[previous_param_node]
                    || token_end[previous_param_node] > token_pos[param_node]
                {
                    return Err(anyhow!(
                        "parser HIR function row {owner} parameter rows overlap or are not in source order"
                    ));
                }
            }
            index += 1;
        }
    }

    Ok(())
}

#[allow(clippy::too_many_arguments)]
pub fn validate_hir_method_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    param_owner_fn_nodes: &[u32],
    param_ordinals: &[u32],
    param_name_tokens: &[u32],
    param_type_nodes: &[u32],
    method_owner_nodes: &[u32],
    method_impl_nodes: &[u32],
    method_name_tokens: &[u32],
    method_first_param_tokens: &[u32],
    method_receiver_modes: &[u32],
    method_visibilities: &[u32],
    method_signature_flags: &[u32],
    method_impl_receiver_type_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || param_owner_fn_nodes.len() != row_count
        || param_ordinals.len() != row_count
        || param_name_tokens.len() != row_count
        || param_type_nodes.len() != row_count
        || method_owner_nodes.len() != row_count
        || method_impl_nodes.len() != row_count
        || method_name_tokens.len() != row_count
        || method_first_param_tokens.len() != row_count
        || method_receiver_modes.len() != row_count
        || method_visibilities.len() != row_count
        || method_signature_flags.len() != row_count
        || method_impl_receiver_type_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR method record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };
    let valid_receiver_mode = |mode| {
        matches!(
            mode,
            HIR_METHOD_RECEIVER_NONE
                | HIR_METHOD_RECEIVER_SELF
                | HIR_METHOD_RECEIVER_REF_SELF
                | HIR_METHOD_RECEIVER_EXPLICIT
        )
    };
    let valid_visibility =
        |visibility| matches!(visibility, HIR_METHOD_VIS_PRIVATE | HIR_METHOD_VIS_PUBLIC);
    let signature_flag_mask = HIR_METHOD_SIGNATURE_HAS_GENERICS | HIR_METHOD_SIGNATURE_HAS_WHERE;

    let mut impl_file_ids = vec![INVALID; row_count];
    for method_node in 0..row_count {
        let owner_node = method_owner_nodes[method_node];
        let impl_node = method_impl_nodes[method_node];
        if owner_node == INVALID {
            if impl_node != INVALID
                || method_name_tokens[method_node] != INVALID
                || method_first_param_tokens[method_node] != INVALID
                || method_receiver_modes[method_node] != HIR_METHOD_RECEIVER_NONE
                || method_visibilities[method_node] != HIR_METHOD_VIS_PRIVATE
                || method_signature_flags[method_node] != 0
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published method metadata without a declaration owner"
                ));
            }
            continue;
        }

        let owner_node = owner_node as usize;
        if owner_node >= row_count {
            return Err(anyhow!(
                "parser HIR method row {method_node} published owner {owner_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[method_node] != HIR_NODE_FN {
            return Err(anyhow!(
                "parser HIR method row {method_node} published an owner without a function-signature HIR row"
            ));
        }
        if !has_non_empty_span(method_node) || node_file_ids[method_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method row {method_node} published an owner without a source-addressable function row"
            ));
        }
        if !has_non_empty_span(owner_node)
            || node_file_ids[owner_node] == INVALID
            || node_file_ids[owner_node] != node_file_ids[method_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} published owner {owner_node} without a matching source-addressable owner row"
            ));
        }
        if token_pos[method_node] < token_pos[owner_node]
            || token_end[method_node] > token_end[owner_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} falls outside declaration owner span {owner_node}"
            ));
        }

        let impl_method = impl_node != INVALID;
        if impl_method {
            if impl_node as usize != owner_node {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published impl owner {impl_node} that does not match declaration owner {owner_node}"
                ));
            }
            if item_kinds[method_node] != HIR_ITEM_KIND_NONE {
                return Err(anyhow!(
                    "parser HIR impl method row {method_node} published value item metadata"
                ));
            }
            if item_name_tokens[method_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR impl method row {method_node} published a value item name token"
                ));
            }
        } else {
            if item_kinds[owner_node] != HIR_ITEM_KIND_TRAIT {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published non-impl owner {owner_node} without a trait item row"
                ));
            }
            if item_kinds[method_node] != HIR_ITEM_KIND_NONE {
                return Err(anyhow!(
                    "parser HIR trait method row {method_node} should not publish a value item row"
                ));
            }
        }

        let name_token = method_name_tokens[method_node];
        if name_token == INVALID
            || name_token < token_pos[method_node]
            || name_token >= token_end[method_node]
        {
            return Err(anyhow!(
                "parser HIR method row {method_node} published a method name token outside its function span"
            ));
        }
        if name_token <= token_pos[method_node] {
            return Err(anyhow!(
                "parser HIR method row {method_node} published a method name token that does not follow its function declaration token"
            ));
        }

        let receiver_mode = method_receiver_modes[method_node];
        if !valid_receiver_mode(receiver_mode) {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown receiver mode {receiver_mode}"
            ));
        }
        let visibility = method_visibilities[method_node];
        if !valid_visibility(visibility) {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown visibility {visibility}"
            ));
        }
        let flags = method_signature_flags[method_node];
        if flags & !signature_flag_mask != 0 {
            return Err(anyhow!(
                "parser HIR method row {method_node} published unknown signature flags {flags}"
            ));
        }

        let first_param_token = method_first_param_tokens[method_node];
        if first_param_token == INVALID {
            if receiver_mode != HIR_METHOD_RECEIVER_NONE {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published receiver mode {receiver_mode} without a first parameter token"
                ));
            }
        } else {
            if first_param_token < token_pos[method_node]
                || first_param_token >= token_end[method_node]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token outside its function span"
                ));
            }
            if first_param_token <= name_token {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token that does not follow its method name token"
                ));
            }
            let ordinal_zero_param =
                param_owner_fn_nodes
                    .iter()
                    .enumerate()
                    .find_map(|(param_node, &owner)| {
                        (owner as usize == method_node
                            && param_ordinals[param_node] == 0
                            && param_name_tokens[param_node] == first_param_token
                            && kinds[param_node] == HIR_NODE_PARAM)
                            .then_some(param_node)
                    });
            let Some(ordinal_zero_param) = ordinal_zero_param else {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token without an ordinal-zero parameter row"
                ));
            };
            if !has_non_empty_span(ordinal_zero_param)
                || node_file_ids[ordinal_zero_param] == INVALID
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} without a source-addressable parameter span"
                ));
            }
            if node_file_ids[ordinal_zero_param] != node_file_ids[method_node] {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} with a different file id"
                ));
            }
            if token_pos[ordinal_zero_param] < token_pos[method_node]
                || token_end[ordinal_zero_param] > token_end[method_node]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published ordinal-zero parameter row {ordinal_zero_param} outside its function span"
                ));
            }
            if first_param_token < token_pos[ordinal_zero_param]
                || first_param_token >= token_end[ordinal_zero_param]
            {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token outside the ordinal-zero parameter span"
                ));
            }
            if receiver_mode == HIR_METHOD_RECEIVER_NONE {
                return Err(anyhow!(
                    "parser HIR method row {method_node} published a first parameter token without a receiver mode"
                ));
            }
            if receiver_mode == HIR_METHOD_RECEIVER_EXPLICIT {
                let param_type_node = param_type_nodes[ordinal_zero_param];
                if param_type_node == INVALID
                    || param_type_node as usize >= row_count
                    || kinds[param_type_node as usize] != HIR_NODE_TYPE
                {
                    return Err(anyhow!(
                        "parser HIR method row {method_node} published an explicit first parameter without a parser-owned type record"
                    ));
                }
                let param_type_node = param_type_node as usize;
                if !has_non_empty_span(param_type_node)
                    || node_file_ids[param_type_node] != node_file_ids[ordinal_zero_param]
                    || token_pos[param_type_node] < token_pos[ordinal_zero_param]
                    || token_end[param_type_node] > token_end[ordinal_zero_param]
                {
                    return Err(anyhow!(
                        "parser HIR method row {method_node} published explicit first parameter type row {param_type_node} without source-addressed ownership by ordinal-zero parameter row {ordinal_zero_param}"
                    ));
                }
            }
        }

        if impl_method {
            let previous_file_id = impl_file_ids[owner_node];
            if previous_file_id != INVALID && previous_file_id != node_file_ids[method_node] {
                return Err(anyhow!(
                    "parser HIR method impl owner {owner_node} was shared across source-pack files"
                ));
            }
            impl_file_ids[owner_node] = node_file_ids[method_node];
        }
    }

    for (impl_node, &receiver_type_node) in method_impl_receiver_type_nodes.iter().enumerate() {
        if receiver_type_node == INVALID {
            continue;
        }
        if !has_non_empty_span(impl_node) || node_file_ids[impl_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published a receiver type without a source-addressable impl owner row"
            ));
        }
        let receiver_type_node = receiver_type_node as usize;
        if receiver_type_node >= row_count {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type {receiver_type_node}, outside {row_count} readback rows"
            ));
        }
        if kinds[receiver_type_node] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} without a type HIR row"
            ));
        }
        if !has_non_empty_span(receiver_type_node) || node_file_ids[receiver_type_node] == INVALID {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} without a source-addressable type span"
            ));
        }
        if node_file_ids[receiver_type_node] != node_file_ids[impl_node] {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} with a different file id"
            ));
        }
        if token_pos[receiver_type_node] < token_pos[impl_node]
            || token_end[receiver_type_node] > token_end[impl_node]
        {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} outside the impl owner span"
            ));
        }
        let impl_file_id = impl_file_ids[impl_node];
        if impl_file_id != INVALID && node_file_ids[receiver_type_node] != impl_file_id {
            return Err(anyhow!(
                "parser HIR method impl row {impl_node} published receiver type row {receiver_type_node} with a different file id"
            ));
        }
    }

    Ok(())
}

fn is_hir_expression_kind(kind: u32) -> bool {
    matches!(
        kind,
        HIR_NODE_EXPR
            | HIR_NODE_ASSIGN_EXPR
            | HIR_NODE_BINARY_EXPR
            | HIR_NODE_UNARY_EXPR
            | HIR_NODE_POSTFIX_EXPR
            | HIR_NODE_CALL_EXPR
            | HIR_NODE_INDEX_EXPR
            | HIR_NODE_MEMBER_EXPR
            | HIR_NODE_NAME_EXPR
            | HIR_NODE_LITERAL_EXPR
            | HIR_NODE_ARRAY_EXPR
            | HIR_NODE_STRUCT_LITERAL_EXPR
            | HIR_NODE_PATH_EXPR
            | HIR_NODE_MATCH_EXPR
    )
}

fn is_hir_expr_value_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_NAME
            | HIR_EXPR_FORM_INT
            | HIR_EXPR_FORM_TRUE
            | HIR_EXPR_FORM_FALSE
            | HIR_EXPR_FORM_FLOAT
            | HIR_EXPR_FORM_STRING
            | HIR_EXPR_FORM_CHAR
    )
}

fn is_hir_expr_literal_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_INT
            | HIR_EXPR_FORM_TRUE
            | HIR_EXPR_FORM_FALSE
            | HIR_EXPR_FORM_FLOAT
            | HIR_EXPR_FORM_STRING
            | HIR_EXPR_FORM_CHAR
    )
}

fn is_hir_expr_unary_form(form: u32) -> bool {
    matches!(form, HIR_EXPR_FORM_NOT | HIR_EXPR_FORM_NEG)
}

fn is_hir_expr_binary_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_EQ
            | HIR_EXPR_FORM_NE
            | HIR_EXPR_FORM_LT
            | HIR_EXPR_FORM_GT
            | HIR_EXPR_FORM_LE
            | HIR_EXPR_FORM_GE
            | HIR_EXPR_FORM_ADD
            | HIR_EXPR_FORM_SUB
            | HIR_EXPR_FORM_MUL
            | HIR_EXPR_FORM_AND
            | HIR_EXPR_FORM_OR
            | HIR_EXPR_FORM_MOD
            | HIR_EXPR_FORM_DIV
            | HIR_EXPR_FORM_BIT_OR
            | HIR_EXPR_FORM_BIT_XOR
            | HIR_EXPR_FORM_BIT_AND
            | HIR_EXPR_FORM_SHL
            | HIR_EXPR_FORM_SHR
    )
}

fn is_hir_expr_range_form(form: u32) -> bool {
    matches!(
        form,
        HIR_EXPR_FORM_RANGE
            | HIR_EXPR_FORM_RANGE_FROM
            | HIR_EXPR_FORM_RANGE_TO
            | HIR_EXPR_FORM_RANGE_FULL
            | HIR_EXPR_FORM_RANGE_INCLUSIVE
            | HIR_EXPR_FORM_RANGE_TO_INCLUSIVE
    )
}

pub fn validate_hir_expression_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    expr_forms: &[u32],
    left_nodes: &[u32],
    right_nodes: &[u32],
    value_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || expr_forms.len() != row_count
        || left_nodes.len() != row_count
        || right_nodes.len() != row_count
        || value_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR expression record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_expression_owner = |node: usize, label: &str| -> Result<()> {
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} without an expression HIR row"
            ));
        }
        if !has_non_empty_span(node) || node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} without a source-addressable expression row"
            ));
        }
        Ok(())
    };

    let require_empty = |node: usize, label: &str| -> Result<()> {
        if left_nodes[node] != INVALID
            || right_nodes[node] != INVALID
            || value_tokens[node] != INVALID
        {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with non-empty operands"
            ));
        }
        Ok(())
    };

    let require_no_right_or_value = |node: usize, label: &str| -> Result<()> {
        if right_nodes[node] != INVALID || value_tokens[node] != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with non-empty reserved operands"
            ));
        }
        Ok(())
    };

    let require_no_value = |node: usize, label: &str| -> Result<()> {
        if value_tokens[node] != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty value token"
            ));
        }
        Ok(())
    };

    let require_no_left = |node: usize, left: u32, label: &str| -> Result<()> {
        if left != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty left operand"
            ));
        }
        Ok(())
    };

    let require_no_right = |node: usize, right: u32, label: &str| -> Result<()> {
        if right != INVALID {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} with a non-empty right operand"
            ));
        }
        Ok(())
    };

    let require_value_token = |node: usize, token: u32, label: &str| -> Result<()> {
        if token == INVALID || token < token_pos[node] || token >= token_end[node] {
            return Err(anyhow!(
                "parser HIR expression row {node} published {label} value token outside its expression span"
            ));
        }
        Ok(())
    };

    let require_expression_edge = |owner: usize, node: u32, label: &str| -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} without an in-table parser-owned expression row"
            ));
        }
        let node = node as usize;
        if node == owner {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} as a self edge"
            ));
        }
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} with non-expression HIR kind {}",
                kinds[node]
            ));
        }
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} without a non-empty token span"
            ));
        }
        if node_file_ids[owner] == INVALID || node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} with a different file id"
            ));
        }
        if token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} row {node} outside the owner expression span (owner={}..{}, operand={}..{})",
                token_pos[owner],
                token_end[owner],
                token_pos[node],
                token_end[node]
            ));
        }
        Ok(node)
    };

    let require_ordered_expression_pair = |owner: usize,
                                           left: usize,
                                           right: usize,
                                           label: &str|
     -> Result<()> {
        if token_pos[right] <= token_pos[left] || token_end[left] > token_pos[right] {
            return Err(anyhow!(
                "parser HIR expression row {owner} published {label} operands out of source order"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        let form = expr_forms[row];
        match form {
            HIR_EXPR_FORM_NONE => {
                if matches!(kinds[row], HIR_NODE_NAME_EXPR | HIR_NODE_LITERAL_EXPR) {
                    return Err(anyhow!(
                        "parser HIR expression row {row} has expression leaf HIR kind {} but no parser-owned expression record",
                        kinds[row]
                    ));
                }
                require_empty(row, "no expression record")?;
            }
            HIR_EXPR_FORM_FORWARD => {
                require_expression_owner(row, "forward record")?;
                require_expression_edge(row, left_nodes[row], "forward target")?;
                require_no_right_or_value(row, "forward record")?;
            }
            form if is_hir_expr_value_form(form) => {
                require_expression_owner(row, "value record")?;
                if form == HIR_EXPR_FORM_NAME
                    && !matches!(kinds[row], HIR_NODE_NAME_EXPR | HIR_NODE_PATH_EXPR)
                {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published name value form on incompatible HIR kind {}",
                        kinds[row]
                    ));
                }
                if is_hir_expr_literal_form(form) && kinds[row] != HIR_NODE_LITERAL_EXPR {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published literal value form {form} on incompatible HIR kind {}",
                        kinds[row]
                    ));
                }
                if left_nodes[row] != INVALID || right_nodes[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR expression row {row} published value record with non-empty child edges"
                    ));
                }
                require_value_token(row, value_tokens[row], "value record")?;
            }
            form if is_hir_expr_unary_form(form) => {
                require_expression_owner(row, "unary record")?;
                require_expression_edge(row, left_nodes[row], "unary operand")?;
                require_no_right_or_value(row, "unary record")?;
            }
            form if is_hir_expr_binary_form(form) => {
                require_expression_owner(row, "binary record")?;
                let left = require_expression_edge(row, left_nodes[row], "binary left operand")?;
                let right = require_expression_edge(row, right_nodes[row], "binary right operand")?;
                require_ordered_expression_pair(row, left, right, "binary")?;
                require_no_value(row, "binary record")?;
            }
            form if is_hir_expr_range_form(form) => {
                require_expression_owner(row, "range record")?;
                let has_start = matches!(
                    form,
                    HIR_EXPR_FORM_RANGE | HIR_EXPR_FORM_RANGE_FROM | HIR_EXPR_FORM_RANGE_INCLUSIVE
                );
                let has_end = matches!(
                    form,
                    HIR_EXPR_FORM_RANGE
                        | HIR_EXPR_FORM_RANGE_TO
                        | HIR_EXPR_FORM_RANGE_INCLUSIVE
                        | HIR_EXPR_FORM_RANGE_TO_INCLUSIVE
                );
                let left = if has_start {
                    Some(require_expression_edge(
                        row,
                        left_nodes[row],
                        "range start operand",
                    )?)
                } else {
                    require_no_left(row, left_nodes[row], "range record")?;
                    None
                };
                let right = if has_end {
                    Some(require_expression_edge(
                        row,
                        right_nodes[row],
                        "range end operand",
                    )?)
                } else {
                    require_no_right(row, right_nodes[row], "range record")?;
                    None
                };
                if let (Some(left), Some(right)) = (left, right) {
                    require_ordered_expression_pair(row, left, right, "range")?;
                }
                require_no_value(row, "range record")?;
            }
            HIR_EXPR_FORM_INDEX => {
                require_expression_owner(row, "index record")?;
                let base = require_expression_edge(row, left_nodes[row], "index base")?;
                let index = require_expression_edge(row, right_nodes[row], "index expression")?;
                require_ordered_expression_pair(row, base, index, "index")?;
                if token_pos[row] != token_pos[base] {
                    return Err(anyhow!(
                        "parser HIR expression row {row} index span does not start at base row {base}"
                    ));
                }
                require_no_value(row, "index record")?;
            }
            other => {
                return Err(anyhow!(
                    "parser HIR expression row {row} published unknown expression record form {other}"
                ));
            }
        }
    }

    Ok(())
}

pub fn validate_hir_expression_result_root_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    result_roots: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || result_roots.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR expression-result-root arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    for (row, &root) in result_roots.iter().enumerate() {
        if root == INVALID {
            continue;
        }
        if !is_hir_expression_kind(kinds[row]) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published a result root without an expression HIR row"
            ));
        }
        let root = root as usize;
        if root >= row_count {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root}, outside {row_count} readback rows"
            ));
        }
        if !is_hir_expression_kind(kinds[root]) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published non-expression result root {root} with HIR kind {}",
                kinds[root]
            ));
        }
        if !has_non_empty_span(row) || !has_non_empty_span(root) {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} without source-addressable spans"
            ));
        }
        if node_file_ids[row] == INVALID
            || node_file_ids[root] == INVALID
            || node_file_ids[row] != node_file_ids[root]
        {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} with a different file id"
            ));
        }
        if token_pos[root] < token_pos[row] || token_end[root] > token_end[row] {
            return Err(anyhow!(
                "parser HIR expression-result row {row} published result root {root} outside the expression span"
            ));
        }
        if result_roots[root] != root as u32 {
            let next_root = result_roots[root];
            return Err(anyhow!(
                "parser HIR expression-result row {row} published non-canonical result root {root} whose root row points to {next_root}"
            ));
        }
    }

    Ok(())
}

fn is_hir_match_pattern_kind(kind: u32) -> bool {
    matches!(kind, HIR_NODE_NAME_EXPR | HIR_NODE_LITERAL_EXPR)
}

fn expected_statement_record_kind_for_hir_kind(kind: u32) -> Option<u32> {
    match kind {
        HIR_NODE_LET_STMT => Some(HIR_STMT_RECORD_KIND_LET),
        HIR_NODE_RETURN_STMT => Some(HIR_STMT_RECORD_KIND_RETURN),
        HIR_NODE_IF_STMT => Some(HIR_STMT_RECORD_KIND_IF),
        HIR_NODE_CONST_ITEM => Some(HIR_STMT_RECORD_KIND_CONST),
        HIR_NODE_WHILE_STMT => Some(HIR_STMT_RECORD_KIND_WHILE),
        HIR_NODE_FOR_STMT => Some(HIR_STMT_RECORD_KIND_FOR),
        HIR_NODE_BREAK_STMT => Some(HIR_STMT_RECORD_KIND_BREAK),
        HIR_NODE_CONTINUE_STMT => Some(HIR_STMT_RECORD_KIND_CONTINUE),
        _ => None,
    }
}

pub fn validate_hir_call_argument_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    callee_nodes: &[u32],
    starts: &[u32],
    arg_ends: &[u32],
    counts: &[u32],
    parent_calls: &[u32],
    ordinals: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || callee_nodes.len() != row_count
        || starts.len() != row_count
        || arg_ends.len() != row_count
        || parent_calls.len() != row_count
        || ordinals.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR call argument record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_call_source = |call_node: usize| -> Result<()> {
        if !has_non_empty_span(call_node) {
            return Err(anyhow!(
                "parser HIR call row {call_node} published call metadata without a non-empty token span"
            ));
        }
        if node_file_ids[call_node] == INVALID {
            return Err(anyhow!(
                "parser HIR call row {call_node} published call metadata without a source file id"
            ));
        }
        Ok(())
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        require_call_source(owner)?;
        if !has_non_empty_span(child) {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} without a non-empty token span"
            ));
        }
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} with a different file id"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} published {label} row {child} outside the call expression span"
            ));
        }
        Ok(())
    };

    for (call_node, &callee) in callee_nodes.iter().enumerate() {
        if kinds[call_node] != HIR_NODE_CALL_EXPR {
            if callee != INVALID || starts[call_node] != INVALID || counts[call_node] != 0 {
                return Err(anyhow!(
                    "parser HIR call row {call_node} published call metadata without a call-expression HIR owner"
                ));
            }
            continue;
        }
        require_call_source(call_node)?;

        if callee == INVALID || callee as usize >= row_count {
            return Err(anyhow!(
                "parser HIR call row {call_node} published a call expression without an in-table callee"
            ));
        }
        if callee as usize == call_node {
            return Err(anyhow!(
                "parser HIR call row {call_node} points at itself as the call callee"
            ));
        }
        let callee = callee as usize;
        if !is_hir_expression_kind(kinds[callee]) {
            return Err(anyhow!(
                "parser HIR call row {call_node} published callee row {callee} with non-expression HIR kind {}",
                kinds[callee]
            ));
        }
        require_child_source(call_node, callee, "callee")?;
        if token_pos[call_node] != token_pos[callee] {
            return Err(anyhow!(
                "parser HIR call row {call_node} span does not start at callee row {callee}"
            ));
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    let mut ordinal_masks = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (arg_node, &owner) in parent_calls.iter().enumerate() {
        if owner == INVALID {
            if ordinals[arg_node] != INVALID || arg_ends[arg_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR call argument row {arg_node} published argument metadata without an owner"
                ));
            }
            continue;
        }
        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_CALL_EXPR {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} points at owner {owner} without a call-expression HIR owner"
            ));
        }
        if kinds[arg_node] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} is not an expression HIR row"
            ));
        }
        require_child_source(owner, arg_node, "argument")?;
        if arg_ends[arg_node] == INVALID {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} omitted its parser-owned argument end token"
            ));
        }
        if arg_ends[arg_node] != token_end[arg_node] {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published argument end token {} that does not match its HIR span end {}",
                arg_ends[arg_node],
                token_end[arg_node]
            ));
        }
        if arg_ends[arg_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published argument end token outside owner {owner} call span"
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} points at owner {owner} with zero argument count"
            ));
        }
        if owner_count > HIR_PACKED_NODE_ORDINAL_SLOT_COUNT {
            return Err(anyhow!(
                "parser HIR call row {owner} published {owner_count} arguments, exceeding {} packed ordinal slots",
                HIR_PACKED_NODE_ORDINAL_SLOT_COUNT
            ));
        }

        let ordinal = ordinals[arg_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR call argument row {arg_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }
        let bit = 1u32 << ordinal;
        if ordinal_masks[owner] & bit != 0 {
            return Err(anyhow!(
                "parser HIR call row {owner} published duplicate argument ordinal {ordinal}"
            ));
        }
        ordinal_masks[owner] |= bit;
        actual_counts[owner] += 1;
        ordinal_keys.push((owner, ordinal, arg_node));
    }
    ordinal_keys.sort_unstable_by_key(|&(owner, ordinal, _)| (owner, ordinal));

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if starts[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR call row {owner} published a first argument without an argument count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_CALL_EXPR {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument count {count} without a call-expression HIR owner"
            ));
        }
        if count > HIR_PACKED_NODE_ORDINAL_SLOT_COUNT {
            return Err(anyhow!(
                "parser HIR call row {owner} published {count} arguments, exceeding {} packed ordinal slots",
                HIR_PACKED_NODE_ORDINAL_SLOT_COUNT
            ));
        }

        let start = starts[owner];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument count {count} without an in-table first argument"
            ));
        }
        let start = start as usize;
        if parent_calls[start] as usize != owner || ordinals[start] != 0 {
            return Err(anyhow!(
                "parser HIR call row {owner} first argument row {start} is not ordinal zero for that owner"
            ));
        }
        if token_pos[start] < token_pos[owner] || token_end[start] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR call row {owner} first argument row {start} is outside the call expression span"
            ));
        }
        let callee = callee_nodes[owner] as usize;
        if callee >= row_count {
            return Err(anyhow!(
                "parser HIR call row {owner} published argument metadata without an in-table callee"
            ));
        }
        if token_end[callee] > token_pos[start] {
            return Err(anyhow!(
                "parser HIR call row {owner} published callee row {callee} that does not precede first argument row {start}"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR call row {owner} published count {count} but read back {} owned argument rows",
                actual_counts[owner]
            ));
        }
        let expected_mask = (1u32 << count) - 1u32;
        if ordinal_masks[owner] != expected_mask {
            return Err(anyhow!(
                "parser HIR call row {owner} argument ordinals are not contiguous from zero"
            ));
        }
        let mut previous_arg = start;
        for expected_ordinal in 1..count {
            let next_arg = ordinal_keys
                .binary_search_by_key(&(owner, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR call row {owner} argument ordinals are not contiguous from zero"
                    )
                })?;
            if token_pos[next_arg] <= token_pos[previous_arg]
                || token_end[previous_arg] > token_pos[next_arg]
            {
                return Err(anyhow!(
                    "parser HIR call row {owner} argument rows overlap or are not in source order at row {next_arg}"
                ));
            }
            previous_arg = next_arg;
        }
    }

    Ok(())
}

pub fn validate_hir_array_literal_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    first_elements: &[u32],
    counts: &[u32],
    parent_literals: &[u32],
    ordinals: &[u32],
    next_elements: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || first_elements.len() != row_count
        || parent_literals.len() != row_count
        || ordinals.len() != row_count
        || next_elements.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR array literal record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR array literal {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR array literal {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    for (row, &kind) in kinds.iter().enumerate() {
        if kind == HIR_NODE_ARRAY_EXPR {
            require_span(row, "owner")?;
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    for (element_node, &owner) in parent_literals.iter().enumerate() {
        if owner == INVALID {
            if ordinals[element_node] != INVALID || next_elements[element_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR array element row {element_node} published element metadata without an owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_ARRAY_EXPR {
            return Err(anyhow!(
                "parser HIR array element row {element_node} points at owner {owner} without an array-literal HIR owner"
            ));
        }
        if !is_hir_expression_kind(kinds[element_node]) {
            return Err(anyhow!(
                "parser HIR array element row {element_node} is not an expression HIR row"
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR array element row {element_node} points at owner {owner} with zero element count"
            ));
        }
        require_span(owner, "owner")?;
        require_span(element_node, "element")?;
        if node_file_ids[element_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[element_node] < token_pos[owner] || token_end[element_node] > token_end[owner]
        {
            return Err(anyhow!(
                "parser HIR array element row {element_node} falls outside owner {owner} span"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published {owner_count} elements, exceeding {row_count} readback rows"
            ));
        }

        let ordinal = ordinals[element_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }
        let next = next_elements[element_node];
        if next != INVALID && next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR array element row {element_node} published next element {next}, outside {row_count} readback rows"
            ));
        }
        actual_counts[owner] += 1;
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_elements[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} published first element without an element count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_ARRAY_EXPR {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published element count {count} without an array-literal HIR owner"
            ));
        }
        require_span(owner, "owner")?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published {count} elements, exceeding {row_count} readback rows"
            ));
        }

        let first = first_elements[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published element count {count} without an in-table first element"
            ));
        }
        let first = first as usize;
        if token_pos[first] <= token_pos[owner] {
            return Err(anyhow!(
                "parser HIR array literal row {owner} first element row {first} does not follow the array literal start token"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR array literal row {owner} published count {count} but read back {} owned element rows",
                actual_counts[owner]
            ));
        }

        let mut element = first;
        for expected_ordinal in 0..count {
            if parent_literals[element] as usize != owner {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} element chain row {element} does not point back to that owner"
                ));
            }
            if ordinals[element] != expected_ordinal {
                return Err(anyhow!(
                    "parser HIR array literal row {owner} element chain is not contiguous from zero"
                ));
            }

            let next = next_elements[element];
            if expected_ordinal + 1 == count {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} final element row {element} did not terminate the element chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if parent_literals[next] as usize != owner {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain row {next} does not point back to that owner"
                    ));
                }
                if token_pos[next] <= token_pos[element] || token_end[element] > token_pos[next] {
                    return Err(anyhow!(
                        "parser HIR array literal row {owner} element chain overlaps or is not in source order at row {element}"
                    ));
                }
                element = next;
            }
        }
    }

    Ok(())
}

pub fn validate_hir_member_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    receiver_nodes: &[u32],
    receiver_tokens: &[u32],
    member_name_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || receiver_nodes.len() != row_count
        || receiver_tokens.len() != row_count
        || member_name_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR member record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    for row in 0..row_count {
        let receiver = receiver_nodes[row];
        let receiver_token = receiver_tokens[row];
        let member_token = member_name_tokens[row];

        if kinds[row] != HIR_NODE_MEMBER_EXPR {
            if receiver != INVALID || receiver_token != INVALID || member_token != INVALID {
                return Err(anyhow!(
                    "parser HIR member row {row} published member metadata without a member-expression HIR owner"
                ));
            }
            continue;
        }

        if !has_non_empty_span(row) {
            return Err(anyhow!(
                "parser HIR member row {row} published a member expression without a non-empty token span"
            ));
        }
        if node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR member row {row} published a member expression without a source file id"
            ));
        }
        if receiver == INVALID || receiver as usize >= row_count || receiver as usize == row {
            return Err(anyhow!(
                "parser HIR member row {row} published no in-table receiver expression"
            ));
        }
        let receiver = receiver as usize;
        if !is_hir_expression_kind(kinds[receiver]) {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} has non-expression HIR kind {}",
                kinds[receiver]
            ));
        }
        if !has_non_empty_span(receiver) {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} lacks a non-empty token span"
            ));
        }
        if node_file_ids[receiver] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} has a different file id"
            ));
        }
        if token_pos[receiver] < token_pos[row] || token_end[receiver] > token_end[row] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} is outside the member expression span"
            ));
        }
        if token_pos[row] != token_pos[receiver] {
            return Err(anyhow!(
                "parser HIR member row {row} member expression span does not start at receiver row {receiver}"
            ));
        }
        if receiver_token == INVALID || member_token == INVALID || receiver_token >= member_token {
            return Err(anyhow!(
                "parser HIR member row {row} published unordered receiver/member tokens"
            ));
        }
        if receiver_token < token_pos[receiver] || receiver_token >= token_end[receiver] {
            return Err(anyhow!(
                "parser HIR member row {row} receiver token is outside receiver row {receiver}"
            ));
        }
        if token_end[receiver] >= member_token {
            return Err(anyhow!(
                "parser HIR member row {row} receiver row {receiver} does not leave a member separator before the member-name token (receiver span={}..{}, member token={member_token}, member span={}..{})",
                token_pos[receiver],
                token_end[receiver],
                token_pos[row],
                token_end[row],
            ));
        }
        if member_token < token_pos[row] || member_token >= token_end[row] {
            return Err(anyhow!(
                "parser HIR member row {row} member-name token is outside the member expression span"
            ));
        }
        if token_end[row] != member_token + 1 {
            return Err(anyhow!(
                "parser HIR member row {row} member expression span does not end at the member-name token"
            ));
        }
    }

    Ok(())
}

pub fn validate_hir_match_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    scrutinee_nodes: &[u32],
    arm_starts: &[u32],
    arm_counts: &[u32],
    arm_next: &[u32],
    arm_pattern_nodes: &[u32],
    arm_payload_starts: &[u32],
    arm_payload_counts: &[u32],
    arm_result_nodes: &[u32],
    payload_owner_arms: &[u32],
    payload_match_nodes: &[u32],
    payload_ordinals: &[u32],
) -> Result<()> {
    let row_count = arm_counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || scrutinee_nodes.len() != row_count
        || arm_starts.len() != row_count
        || arm_next.len() != row_count
        || arm_pattern_nodes.len() != row_count
        || arm_payload_starts.len() != row_count
        || arm_payload_counts.len() != row_count
        || arm_result_nodes.len() != row_count
        || payload_owner_arms.len() != row_count
        || payload_match_nodes.len() != row_count
        || payload_ordinals.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR match record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR match {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR match {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    let require_child_source = |owner: usize, child: usize, label: &str| -> Result<()> {
        require_span(owner, "owner")?;
        require_span(child, label)?;
        if node_file_ids[child] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR match {label} row {child} published a different file id than owner row {owner}"
            ));
        }
        if token_pos[child] < token_pos[owner] || token_end[child] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR match {label} row {child} falls outside owner row {owner} span"
            ));
        }
        Ok(())
    };

    let require_source_precedes = |owner: usize,
                                   left: usize,
                                   right: usize,
                                   left_label: &str,
                                   right_label: &str|
     -> Result<()> {
        if token_end[left] > token_pos[right] {
            return Err(anyhow!(
                "parser HIR match row {owner} published {left_label} row {left} that does not precede {right_label} row {right}"
            ));
        }
        Ok(())
    };

    let total_claimed_arms = arm_counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR match arm counts overflowed host usize"))
    })?;
    if total_claimed_arms > row_count {
        return Err(anyhow!(
            "parser HIR match rows claim {total_claimed_arms} arm rows, exceeding {row_count} readback rows"
        ));
    }

    let total_claimed_payloads = arm_payload_counts.iter().try_fold(0usize, |acc, &count| {
        acc.checked_add(count as usize)
            .ok_or_else(|| anyhow!("parser HIR match payload counts overflowed host usize"))
    })?;
    if total_claimed_payloads > row_count {
        return Err(anyhow!(
            "parser HIR match arms claim {total_claimed_payloads} payload rows, exceeding {row_count} readback rows"
        ));
    }

    let mut arm_owner = vec![INVALID; row_count];
    let mut arm_ordinal = vec![INVALID; row_count];
    for (match_node, &count) in arm_counts.iter().enumerate() {
        if count == 0 {
            if kinds[match_node] == HIR_NODE_MATCH_EXPR {
                return Err(anyhow!(
                    "parser HIR match row {match_node} has a match-expression HIR kind but no parser-owned match record"
                ));
            }
            if scrutinee_nodes[match_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR match row {match_node} published a scrutinee without a match-expression HIR owner"
                ));
            }
            if arm_starts[match_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR match row {match_node} published a first arm without an arm count"
                ));
            }
            continue;
        }

        if kinds[match_node] != HIR_NODE_MATCH_EXPR {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without a match-expression HIR owner"
            ));
        }
        require_span(match_node, "expression")?;
        let scrutinee = scrutinee_nodes[match_node];
        if scrutinee == INVALID || scrutinee as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without an in-table scrutinee expression"
            ));
        }
        if kinds[scrutinee as usize] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR match row {match_node} scrutinee row {scrutinee} is not an expression HIR row"
            ));
        }
        require_child_source(match_node, scrutinee as usize, "scrutinee")?;

        let start = arm_starts[match_node];
        if start == INVALID || start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match row {match_node} published arm count {count} without an in-table first arm"
            ));
        }

        let mut arm = start as usize;
        for expected_ordinal in 0..count as usize {
            if arm_owner[arm] != INVALID {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} appears in multiple match arm chains"
                ));
            }
            if kinds[arm] != HIR_NODE_NONE {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} has HIR kind {}, not a parser-owned match arm row",
                    kinds[arm]
                ));
            }
            arm_owner[arm] = match_node as u32;
            arm_ordinal[arm] = expected_ordinal as u32;
            require_child_source(match_node, arm, "arm")?;
            if expected_ordinal == 0 {
                require_source_precedes(
                    match_node,
                    scrutinee as usize,
                    arm,
                    "scrutinee",
                    "first arm",
                )?;
            }

            let pattern_node = arm_pattern_nodes[arm];
            if pattern_node == INVALID || pattern_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published no in-table pattern node"
                ));
            }
            if !is_hir_match_pattern_kind(kinds[pattern_node as usize]) {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} pattern row {pattern_node} has non-pattern HIR kind {}",
                    kinds[pattern_node as usize]
                ));
            }
            require_child_source(arm, pattern_node as usize, "arm pattern")?;
            let result_node = arm_result_nodes[arm];
            if result_node == INVALID || result_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published no in-table result expression"
                ));
            }
            if kinds[result_node as usize] != HIR_NODE_EXPR {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} result row {result_node} is not an expression HIR row"
                ));
            }
            require_child_source(arm, result_node as usize, "arm result")?;
            require_source_precedes(
                arm,
                pattern_node as usize,
                result_node as usize,
                "pattern",
                "result expression",
            )?;

            let next = arm_next[arm];
            if expected_ordinal + 1 == count as usize {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} final arm row {arm} did not terminate the arm chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} arm chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if token_pos[next] <= token_pos[arm] {
                    return Err(anyhow!(
                        "parser HIR match row {match_node} arm chain is not in source order at row {arm}"
                    ));
                }
                require_source_precedes(match_node, arm, next, "arm", "next arm")?;
                arm = next;
            }
        }
    }

    let mut actual_payload_counts = vec![0u32; row_count];
    let mut payload_ordinal_keys = Vec::new();
    for (payload_node, &owner) in payload_owner_arms.iter().enumerate() {
        if owner == INVALID {
            if arm_owner[payload_node] != INVALID {
                if payload_match_nodes[payload_node] != arm_owner[payload_node]
                    || payload_ordinals[payload_node] != arm_ordinal[payload_node]
                {
                    return Err(anyhow!(
                        "parser HIR match arm row {payload_node} published arm rank metadata that disagrees with its match arm chain"
                    ));
                }
            } else if payload_match_nodes[payload_node] != INVALID
                || payload_ordinals[payload_node] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR match payload row {payload_node} published payload metadata without an owner arm"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published owner arm {owner}, outside {row_count} readback rows"
            ));
        }
        let match_node = arm_owner[owner];
        if match_node == INVALID {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} points at arm row {owner} outside any match arm chain"
            ));
        }
        if payload_match_nodes[payload_node] != match_node {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published match {}, but owner arm {owner} belongs to match {match_node}",
                payload_match_nodes[payload_node]
            ));
        }

        let owner_count = arm_payload_counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} points at arm row {owner} with zero payload count"
            ));
        }
        let ordinal = payload_ordinals[payload_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} published ordinal {ordinal}, outside owner arm {owner} count {owner_count}"
            ));
        }
        if !is_hir_match_pattern_kind(kinds[payload_node]) {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} has non-pattern HIR kind {}",
                kinds[payload_node]
            ));
        }
        require_child_source(owner, payload_node, "payload")?;
        let pattern_node = arm_pattern_nodes[owner] as usize;
        if token_pos[payload_node] < token_pos[pattern_node]
            || token_end[payload_node] > token_end[pattern_node]
        {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} falls outside owner arm {owner} pattern row {pattern_node} span"
            ));
        }
        if token_pos[payload_node] <= token_pos[pattern_node] {
            return Err(anyhow!(
                "parser HIR match payload row {payload_node} does not start after owner arm {owner} pattern head row {pattern_node}"
            ));
        }

        actual_payload_counts[owner] += 1;
        payload_ordinal_keys.push((owner, ordinal, payload_node));
    }

    payload_ordinal_keys.sort_unstable_by_key(|&(owner, ordinal, _)| (owner, ordinal));
    for pair in payload_ordinal_keys.windows(2) {
        let (owner, ordinal, payload_node) = pair[0];
        let (next_owner, next_ordinal, _) = pair[1];
        if owner == next_owner && ordinal == next_ordinal {
            return Err(anyhow!(
                "parser HIR match arm row {owner} published duplicate payload ordinal {ordinal} at row {payload_node}"
            ));
        }
    }

    for arm in 0..row_count {
        if arm_owner[arm] == INVALID {
            if arm_pattern_nodes[arm] != INVALID
                || arm_result_nodes[arm] != INVALID
                || arm_next[arm] != INVALID
                || arm_payload_starts[arm] != INVALID
                || arm_payload_counts[arm] != 0
            {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published arm metadata without belonging to a match"
                ));
            }
            continue;
        }

        let payload_count = arm_payload_counts[arm];
        if payload_count == 0 {
            if arm_payload_starts[arm] != INVALID {
                return Err(anyhow!(
                    "parser HIR match arm row {arm} published a first payload without a payload count"
                ));
            }
            continue;
        }

        let payload_start = arm_payload_starts[arm];
        if payload_start == INVALID || payload_start as usize >= row_count {
            return Err(anyhow!(
                "parser HIR match arm row {arm} published payload count {payload_count} without an in-table first payload"
            ));
        }
        if payload_owner_arms[payload_start as usize] as usize != arm
            || payload_ordinals[payload_start as usize] != 0
        {
            return Err(anyhow!(
                "parser HIR match arm row {arm} first payload row {payload_start} is not ordinal zero for that arm"
            ));
        }
        if actual_payload_counts[arm] != payload_count {
            return Err(anyhow!(
                "parser HIR match arm row {arm} published payload count {payload_count} but read back {} owned payload rows",
                actual_payload_counts[arm]
            ));
        }

        let mut previous_payload: Option<usize> = None;
        for expected_ordinal in 0..payload_count {
            let payload = payload_ordinal_keys
                .binary_search_by_key(&(arm, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| payload_ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR match arm row {arm} payload ordinals are not contiguous from zero"
                    )
                })?;
            if let Some(previous_payload) = previous_payload {
                if token_pos[payload] <= token_pos[previous_payload] {
                    return Err(anyhow!(
                        "parser HIR match arm row {arm} payload ordinals are not in source order at row {payload}"
                    ));
                }
                if token_end[previous_payload] > token_pos[payload] {
                    return Err(anyhow!(
                        "parser HIR match arm row {arm} payload rows overlap before row {payload}"
                    ));
                }
            }
            previous_payload = Some(payload);
        }
    }

    Ok(())
}

pub fn validate_hir_statement_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    stmt_kinds: &[u32],
    operand0: &[u32],
    operand1: &[u32],
    operand2: &[u32],
    stmt_scope_end: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || stmt_kinds.len() != row_count
        || operand0.len() != row_count
        || operand1.len() != row_count
        || operand2.len() != row_count
        || stmt_scope_end.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR statement record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} without a non-empty token span"
            ));
        }
        Ok(())
    };

    let require_statement_kind = |node: usize, expected: u32, label: &str| -> Result<()> {
        if kinds[node] != expected {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} on HIR kind {}, expected {expected}",
                kinds[node]
            ));
        }
        Ok(())
    };

    let require_empty_operands = |node: usize, label: &str| -> Result<()> {
        if operand0[node] != INVALID || operand1[node] != INVALID || operand2[node] != INVALID {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} with non-empty operands ({}, {}, {}) on HIR kind {} span {}..{}",
                operand0[node],
                operand1[node],
                operand2[node],
                kinds[node],
                token_pos[node],
                token_end[node],
            ));
        }
        Ok(())
    };

    let require_token_inside = |owner: usize, token: u32, label: &str| -> Result<()> {
        require_span(owner, label)?;
        if token == INVALID || token < token_pos[owner] || token >= token_end[owner] {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} token outside its statement span"
            ));
        }
        Ok(())
    };

    let require_empty_scope_end = |node: usize, label: &str| -> Result<()> {
        if stmt_scope_end[node] != INVALID {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} with a declaration scope end"
            ));
        }
        Ok(())
    };

    let require_scope_end_after_owner = |node: usize, label: &str| -> Result<()> {
        require_span(node, label)?;
        let end = stmt_scope_end[node];
        if end == INVALID || end < token_end[node] {
            return Err(anyhow!(
                "parser HIR statement row {node} published {label} without a parser-owned declaration scope end after its statement span"
            ));
        }
        Ok(())
    };

    let require_node_edge = |owner: usize,
                             node: u32,
                             allowed_kinds: &[u32],
                             require_inside_owner: bool,
                             label: &str|
     -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} node {node} without an in-table parser-owned node (rows={row_count}, owner kind={}, span={}..{}, operands=({}, {}, {}))",
                kinds[owner],
                token_pos[owner],
                token_end[owner],
                operand0[owner],
                operand1[owner],
                operand2[owner]
            ));
        }
        let node = node as usize;
        require_span(owner, label)?;
        require_span(node, label)?;
        if node_file_ids[owner] == INVALID || node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with a different file id"
            ));
        }
        if require_inside_owner
            && (token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner])
        {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} outside its statement span"
            ));
        }
        if !allowed_kinds.is_empty() && !allowed_kinds.contains(&kinds[node]) {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with HIR kind {}",
                kinds[node]
            ));
        }
        Ok(node)
    };

    let require_expression_edge = |owner: usize, node: u32, label: &str| -> Result<usize> {
        let node = require_node_edge(owner, node, &[], true, label)?;
        if !is_hir_expression_kind(kinds[node]) {
            return Err(anyhow!(
                "parser HIR statement row {owner} published {label} row {node} with non-expression HIR kind {}",
                kinds[node]
            ));
        }
        Ok(node)
    };

    for row in 0..row_count {
        if stmt_kinds[row] != HIR_STMT_RECORD_KIND_NONE {
            require_span(row, "statement record")?;
            if node_file_ids[row] == INVALID {
                return Err(anyhow!(
                    "parser HIR statement row {row} published a statement record without a node file id"
                ));
            }
        } else if let Some(expected_kind) = expected_statement_record_kind_for_hir_kind(kinds[row])
        {
            return Err(anyhow!(
                "parser HIR statement row {row} has concrete HIR statement kind {} but no parser-owned statement record kind {expected_kind}",
                kinds[row]
            ));
        }

        match stmt_kinds[row] {
            HIR_STMT_RECORD_KIND_NONE => {
                require_empty_operands(row, "no statement record")?;
                require_empty_scope_end(row, "no statement record")?;
            }
            HIR_STMT_RECORD_KIND_LET => {
                require_statement_kind(row, HIR_NODE_LET_STMT, "let record")?;
                require_token_inside(row, operand0[row], "let declaration")?;
                require_scope_end_after_owner(row, "let declaration")?;
                if operand1[row] != INVALID {
                    require_expression_edge(row, operand1[row], "let initializer")?;
                }
                if operand2[row] != INVALID {
                    require_node_edge(
                        row,
                        operand2[row],
                        &[HIR_NODE_TYPE],
                        true,
                        "let declared type",
                    )?;
                }
            }
            HIR_STMT_RECORD_KIND_RETURN => {
                require_statement_kind(row, HIR_NODE_RETURN_STMT, "return record")?;
                require_empty_scope_end(row, "return record")?;
                if operand1[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published return record with a non-empty reserved operand"
                    ));
                }
                if operand0[row] == INVALID {
                    if operand2[row] != INVALID {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published a return value token without a return expression"
                        ));
                    }
                } else {
                    let return_expression =
                        require_expression_edge(row, operand0[row], "return expression")?;
                    require_token_inside(row, operand2[row], "return value")?;
                    if operand2[row] < token_pos[return_expression]
                        || operand2[row] >= token_end[return_expression]
                    {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published return value token outside its return expression span"
                        ));
                    }
                }
            }
            HIR_STMT_RECORD_KIND_IF => {
                require_statement_kind(row, HIR_NODE_IF_STMT, "if record")?;
                require_empty_scope_end(row, "if record")?;
                let condition = require_expression_edge(row, operand0[row], "if condition")?;
                let then_block =
                    require_node_edge(row, operand1[row], &[HIR_NODE_BLOCK], false, "if then arm")?;
                if token_end[condition] > token_pos[then_block] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published if condition row {condition} that overlaps the then block"
                    ));
                }
                if operand2[row] != INVALID {
                    let else_block = require_node_edge(
                        row,
                        operand2[row],
                        &[HIR_NODE_BLOCK],
                        false,
                        "if else block",
                    )?;
                    if else_block == then_block {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published the same block row for if then and else arms"
                        ));
                    }
                    if token_pos[else_block] < token_end[then_block] {
                        return Err(anyhow!(
                            "parser HIR statement row {row} published if else block before the then arm ended"
                        ));
                    }
                }
            }
            HIR_STMT_RECORD_KIND_CONST => {
                require_statement_kind(row, HIR_NODE_CONST_ITEM, "const record")?;
                require_token_inside(row, operand0[row], "const declaration")?;
                require_expression_edge(row, operand1[row], "const value")?;
                require_node_edge(
                    row,
                    operand2[row],
                    &[HIR_NODE_TYPE],
                    true,
                    "const declared type",
                )?;
                if stmt_scope_end[row] != INVALID {
                    require_scope_end_after_owner(row, "const declaration")?;
                }
            }
            HIR_STMT_RECORD_KIND_ASSIGN => {
                require_statement_kind(row, HIR_NODE_STMT, "assignment record")?;
                require_empty_scope_end(row, "assignment record")?;
                let target = require_expression_edge(row, operand0[row], "assignment target")?;
                let rhs = require_expression_edge(row, operand1[row], "assignment rhs")?;
                if token_end[target] > token_pos[rhs] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published assignment target row {target} that overlaps or follows rhs row {rhs}"
                    ));
                }
                let op = operand2[row];
                if !(HIR_ASSIGN_OP_SET..=HIR_ASSIGN_OP_BOR).contains(&op) {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published assignment operator {op} outside the supported operator range"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_WHILE => {
                require_statement_kind(row, HIR_NODE_WHILE_STMT, "while record")?;
                require_empty_scope_end(row, "while record")?;
                let condition = require_expression_edge(row, operand0[row], "while condition")?;
                let body =
                    require_node_edge(row, operand1[row], &[HIR_NODE_BLOCK], false, "while body")?;
                if token_end[condition] > token_pos[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published while condition row {condition} that overlaps the body block"
                    ));
                }
                if operand2[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published while record with a non-empty reserved operand"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_FOR => {
                require_statement_kind(row, HIR_NODE_FOR_STMT, "for record")?;
                require_token_inside(row, operand0[row], "for binding")?;
                let iterable =
                    require_expression_edge(row, operand1[row], "for iterable expression")?;
                let body =
                    require_node_edge(row, operand2[row], &[HIR_NODE_BLOCK], false, "for body")?;
                require_scope_end_after_owner(row, "for binding")?;
                if stmt_scope_end[row] != token_end[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published for declaration scope end that does not match the body block end"
                    ));
                }
                if token_end[iterable] > token_pos[body] {
                    return Err(anyhow!(
                        "parser HIR statement row {row} published for iterable expression row {iterable} after the body block started"
                    ));
                }
            }
            HIR_STMT_RECORD_KIND_BREAK => {
                require_statement_kind(row, HIR_NODE_BREAK_STMT, "break record")?;
                require_span(row, "break record")?;
                require_empty_operands(row, "break record")?;
                require_empty_scope_end(row, "break record")?;
            }
            HIR_STMT_RECORD_KIND_CONTINUE => {
                require_statement_kind(row, HIR_NODE_CONTINUE_STMT, "continue record")?;
                require_span(row, "continue record")?;
                require_empty_operands(row, "continue record")?;
                require_empty_scope_end(row, "continue record")?;
            }
            other => {
                return Err(anyhow!(
                    "parser HIR statement row {row} published unknown statement record kind {other}"
                ));
            }
        }
    }

    Ok(())
}

pub fn validate_hir_const_item_statement_records(
    kinds: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    stmt_kinds: &[u32],
    stmt_decl_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || stmt_kinds.len() != row_count
        || stmt_decl_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR const item/statement record arrays have inconsistent lengths"
        ));
    }

    for row in 0..row_count {
        let has_const_item = item_kinds[row] == HIR_ITEM_KIND_CONST;
        let has_const_stmt = stmt_kinds[row] == HIR_STMT_RECORD_KIND_CONST;

        if has_const_item {
            if kinds[row] != HIR_NODE_CONST_ITEM {
                return Err(anyhow!(
                    "parser HIR const item row {row} published item metadata on HIR kind {}",
                    kinds[row]
                ));
            }
            if !has_const_stmt {
                return Err(anyhow!(
                    "parser HIR const item row {row} published const item metadata without a const statement record"
                ));
            }
        }

        if has_const_stmt {
            if kinds[row] != HIR_NODE_CONST_ITEM {
                return Err(anyhow!(
                    "parser HIR const statement row {row} published const statement metadata on HIR kind {}",
                    kinds[row]
                ));
            }
            if !has_const_item {
                return Err(anyhow!(
                    "parser HIR const statement row {row} published a const statement record without const item metadata"
                ));
            }
            if item_name_tokens[row] == INVALID || stmt_decl_tokens[row] != item_name_tokens[row] {
                return Err(anyhow!(
                    "parser HIR const statement row {row} declaration token does not match its item name token"
                ));
            }
        }
    }

    Ok(())
}

pub fn validate_hir_context_relation_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    stmt_record_kinds: &[u32],
    nearest_stmt_nodes: &[u32],
    nearest_block_nodes: &[u32],
    nearest_control_nodes: &[u32],
    nearest_loop_nodes: &[u32],
    nearest_fn_nodes: &[u32],
    call_context_stmt_nodes: &[u32],
    array_lit_context_stmt_nodes: &[u32],
    struct_lit_context_stmt_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || stmt_record_kinds.len() != row_count
        || nearest_stmt_nodes.len() != row_count
        || nearest_block_nodes.len() != row_count
        || nearest_control_nodes.len() != row_count
        || nearest_loop_nodes.len() != row_count
        || nearest_fn_nodes.len() != row_count
        || call_context_stmt_nodes.len() != row_count
        || array_lit_context_stmt_nodes.len() != row_count
        || struct_lit_context_stmt_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR context-relation record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let has_statement_record = |node: usize| {
        if kinds[node] == HIR_NODE_STMT {
            return stmt_record_kinds[node] == HIR_STMT_RECORD_KIND_ASSIGN
                || (stmt_record_kinds[node] == HIR_STMT_RECORD_KIND_NONE
                    && nearest_block_nodes[node] != INVALID);
        }
        match expected_statement_record_kind_for_hir_kind(kinds[node]) {
            Some(expected) => stmt_record_kinds[node] == expected,
            None => false,
        }
    };

    let require_relation = |row: usize, related: u32, label: &str| -> Result<Option<usize>> {
        if related == INVALID {
            return Ok(None);
        }
        let related = related as usize;
        if related >= row_count {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related}, outside {row_count} readback rows"
            ));
        }
        if !has_non_empty_span(row) || !has_non_empty_span(related) {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} without source-addressable spans"
            ));
        }
        if node_file_ids[row] == INVALID
            || node_file_ids[related] == INVALID
            || node_file_ids[row] != node_file_ids[related]
        {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} with a different file id"
            ));
        }
        if token_pos[related] > token_pos[row] || token_end[row] > token_end[related] {
            return Err(anyhow!(
                "parser HIR context row {row} published {label} relation {related} outside the related node span"
            ));
        }
        Ok(Some(related))
    };

    let relation_contains = |outer: usize, inner: usize| -> bool {
        has_non_empty_span(outer)
            && has_non_empty_span(inner)
            && node_file_ids[outer] != INVALID
            && node_file_ids[outer] == node_file_ids[inner]
            && token_pos[outer] <= token_pos[inner]
            && token_end[inner] <= token_end[outer]
    };

    let require_context_contains = |row: usize,
                                    outer: Option<usize>,
                                    inner: Option<usize>,
                                    outer_label: &str,
                                    inner_label: &str|
     -> Result<()> {
        let (Some(outer), Some(inner)) = (outer, inner) else {
            return Ok(());
        };
        if !relation_contains(outer, inner) {
            return Err(anyhow!(
                "parser HIR context row {row} published {outer_label} relation {outer} that does not contain {inner_label} relation {inner}"
            ));
        }
        Ok(())
    };

    let require_context_peer_relation = |row: usize,
                                         context: usize,
                                         row_relation_value: u32,
                                         context_relation_value: u32,
                                         relation_label: &str,
                                         context_label: &str|
     -> Result<()> {
        let context_relation = require_relation(context, context_relation_value, relation_label)?;
        let row_relation = require_relation(row, row_relation_value, relation_label)?;
        match (row_relation, context_relation) {
            (None, None) => {}
            (None, Some(context_relation)) => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} without matching {relation_label} relation {context_relation}"
                ));
            }
            (Some(row_relation), None) => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} with extra {relation_label} relation {row_relation} that the context row omitted"
                ));
            }
            (Some(row_relation), Some(context_relation)) if row_relation != context_relation => {
                return Err(anyhow!(
                    "parser HIR context row {row} published {context_label} relation {context} with {relation_label} relation {row_relation} that disagrees with context {relation_label} relation {context_relation}"
                ));
            }
            (Some(_), Some(_)) => {}
        }
        Ok(())
    };

    for row in 0..row_count {
        let nearest_statement =
            require_relation(row, nearest_stmt_nodes[row], "nearest statement")?;
        if let Some(stmt) = nearest_statement {
            if !has_statement_record(stmt) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest statement relation {stmt} is not backed by a parser-owned statement record (stmt_hir_kind={}, stmt_record_kind={}, stmt_nearest_block={})",
                    kinds[stmt],
                    stmt_record_kinds[stmt],
                    nearest_block_nodes[stmt]
                ));
            }
        }
        if has_statement_record(row) {
            match nearest_statement {
                Some(stmt) if stmt == row => {}
                Some(stmt) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} statement row published nearest statement relation {stmt} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} statement row omitted its nearest statement self relation"
                    ));
                }
            }
        }

        let nearest_block = require_relation(row, nearest_block_nodes[row], "nearest block")?;
        if let Some(block) = nearest_block {
            if kinds[block] != HIR_NODE_BLOCK {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest block relation {block} has HIR kind {}",
                    kinds[block]
                ));
            }
        }
        if kinds[row] == HIR_NODE_BLOCK {
            match nearest_block {
                Some(block) if block == row => {}
                Some(block) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} block row published nearest block relation {block} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} block row omitted its nearest block self relation"
                    ));
                }
            }
        }
        if has_statement_record(row) && kinds[row] != HIR_NODE_CONST_ITEM && nearest_block.is_none()
        {
            return Err(anyhow!(
                "parser HIR context row {row} statement row omitted its nearest block relation (kind={}, span={}..{})",
                kinds[row],
                token_pos[row],
                token_end[row]
            ));
        }

        let nearest_control =
            require_relation(row, nearest_control_nodes[row], "nearest enclosing control")?;
        if let Some(control) = nearest_control {
            if control == row {
                return Err(anyhow!(
                    "parser HIR context row {row} published itself as nearest enclosing control"
                ));
            }
            if !matches!(
                kinds[control],
                HIR_NODE_IF_STMT | HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT | HIR_NODE_MATCH_EXPR
            ) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest enclosing control relation {control} has HIR kind {}",
                    kinds[control]
                ));
            }
            if expected_statement_record_kind_for_hir_kind(kinds[control]).is_some()
                && !has_statement_record(control)
            {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest enclosing control relation {control} is not backed by a parser-owned control statement record"
                ));
            }
        }

        let nearest_loop = require_relation(row, nearest_loop_nodes[row], "nearest loop")?;
        if let Some(loop_node) = nearest_loop {
            if !matches!(kinds[loop_node], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest loop relation {loop_node} has HIR kind {}",
                    kinds[loop_node]
                ));
            }
            if !has_statement_record(loop_node) {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest loop relation {loop_node} is not backed by a parser-owned loop statement record"
                ));
            }
        }
        if matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
            match nearest_loop {
                Some(loop_node) if loop_node == row => {}
                Some(loop_node) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} loop row published nearest loop relation {loop_node} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} loop row omitted its nearest loop self relation"
                    ));
                }
            }
        }
        if let Some(control) = nearest_control {
            if matches!(kinds[control], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT) {
                let loop_row_owns_itself =
                    matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT)
                        && nearest_loop == Some(row)
                        && relation_contains(control, row);
                if !loop_row_owns_itself {
                    match nearest_loop {
                        Some(loop_node) if loop_node == control => {}
                        Some(loop_node) => {
                            return Err(anyhow!(
                                "parser HIR context row {row} nearest loop relation {loop_node} disagrees with loop enclosing control {control}"
                            ));
                        }
                        None => {
                            return Err(anyhow!(
                                "parser HIR context row {row} omitted nearest loop relation for loop enclosing control {control}"
                            ));
                        }
                    }
                }
            }
        }
        if matches!(kinds[row], HIR_NODE_BREAK_STMT | HIR_NODE_CONTINUE_STMT)
            || matches!(
                stmt_record_kinds[row],
                HIR_STMT_RECORD_KIND_BREAK | HIR_STMT_RECORD_KIND_CONTINUE
            )
        {
            if nearest_loop.is_none() {
                return Err(anyhow!(
                    "parser HIR context row {row} loop-control statement omitted its nearest loop relation"
                ));
            }
        }
        let nearest_function = require_relation(row, nearest_fn_nodes[row], "nearest function")?;
        if let Some(function) = nearest_function {
            if kinds[function] != HIR_NODE_FN {
                return Err(anyhow!(
                    "parser HIR context row {row} nearest function relation {function} has HIR kind {}",
                    kinds[function]
                ));
            }
        }
        if kinds[row] == HIR_NODE_FN {
            match nearest_function {
                Some(function) if function == row => {}
                Some(function) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} function row published nearest function relation {function} instead of itself"
                    ));
                }
                None => {
                    return Err(anyhow!(
                        "parser HIR context row {row} function row omitted its nearest function self relation"
                    ));
                }
            }
        }
        if kinds[row] == HIR_NODE_RETURN_STMT
            || stmt_record_kinds[row] == HIR_STMT_RECORD_KIND_RETURN
        {
            if nearest_function.is_none() {
                return Err(anyhow!(
                    "parser HIR context row {row} return statement omitted its nearest function relation (kind={}, span={}..{}, nearest_stmt={:?}, nearest_block={:?}, nearest_control={:?}, nearest_loop={:?}, raw_nearest_fn={})",
                    kinds[row],
                    token_pos[row],
                    token_end[row],
                    nearest_statement,
                    nearest_block,
                    nearest_control,
                    nearest_loop,
                    nearest_fn_nodes[row]
                ));
            }
        }

        if matches!(kinds[row], HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT)
            && nearest_loop == Some(row)
        {
            if let Some(control) = nearest_control
                && !relation_contains(control, row)
            {
                return Err(anyhow!(
                    "parser HIR context row {row} loop statement is outside nearest enclosing control relation {control}"
                ));
            }
        } else {
            require_context_contains(
                row,
                nearest_loop,
                nearest_control,
                "nearest loop",
                "nearest enclosing control",
            )?;
        }
        require_context_contains(
            row,
            nearest_function,
            nearest_statement,
            "nearest function",
            "nearest statement",
        )?;
        require_context_contains(
            row,
            nearest_function,
            nearest_block,
            "nearest function",
            "nearest block",
        )?;
        if kinds[row] != HIR_NODE_BLOCK {
            require_context_contains(
                row,
                nearest_block,
                nearest_statement,
                "nearest block",
                "nearest statement",
            )?;
        }
        require_context_contains(
            row,
            nearest_function,
            nearest_control,
            "nearest function",
            "nearest enclosing control",
        )?;
        require_context_contains(
            row,
            nearest_function,
            nearest_loop,
            "nearest function",
            "nearest loop",
        )?;
    }

    for (contexts, owner_kind, label) in [
        (
            call_context_stmt_nodes,
            HIR_NODE_CALL_EXPR,
            "call contextual statement",
        ),
        (
            array_lit_context_stmt_nodes,
            HIR_NODE_ARRAY_EXPR,
            "array literal contextual statement",
        ),
        (
            struct_lit_context_stmt_nodes,
            HIR_NODE_STRUCT_LITERAL_EXPR,
            "struct literal contextual statement",
        ),
    ] {
        for (row, &context) in contexts.iter().enumerate() {
            if kinds[row] != owner_kind {
                if context != INVALID {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} without the matching owner HIR kind"
                    ));
                }
                continue;
            }

            let Some(context) = require_relation(row, context, label)? else {
                if let Some(nearest_stmt) =
                    require_relation(row, nearest_stmt_nodes[row], "nearest statement")?
                {
                    return Err(anyhow!(
                        "parser HIR context row {row} omitted {label} relation even though nearest statement {nearest_stmt} is available"
                    ));
                }
                continue;
            };
            if !has_statement_record(context) {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} without a parser-owned statement relation"
                ));
            }
            let Some(nearest_stmt) =
                require_relation(row, nearest_stmt_nodes[row], "nearest statement")?
            else {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} without a parser-owned nearest statement relation"
                ));
            };
            if nearest_stmt != context {
                return Err(anyhow!(
                    "parser HIR context row {row} published {label} relation {context} that disagrees with nearest statement {nearest_stmt}"
                ));
            }
            require_context_peer_relation(
                row,
                context,
                nearest_block_nodes[row],
                nearest_block_nodes[context],
                "nearest block",
                label,
            )?;
            require_context_peer_relation(
                row,
                context,
                nearest_fn_nodes[row],
                nearest_fn_nodes[context],
                "nearest function",
                label,
            )?;
            require_context_peer_relation(
                row,
                context,
                nearest_loop_nodes[row],
                nearest_loop_nodes[context],
                "nearest loop",
                label,
            )?;
            let row_control =
                require_relation(row, nearest_control_nodes[row], "nearest enclosing control")?;
            let context_control = require_relation(
                context,
                nearest_control_nodes[context],
                "nearest enclosing control",
            )?;
            let context_is_control = matches!(
                kinds[context],
                HIR_NODE_IF_STMT | HIR_NODE_WHILE_STMT | HIR_NODE_FOR_STMT | HIR_NODE_MATCH_EXPR
            );
            match (row_control, context_control) {
                (Some(row_control), _) if context_is_control && row_control == context => {}
                (Some(row_control), _) if relation_contains(context, row_control) => {}
                (None, None) => {}
                (None, Some(context_control)) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} without matching nearest enclosing control relation {context_control}"
                    ));
                }
                (Some(row_control), None) => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} with extra nearest enclosing control relation {row_control} that the context row omitted"
                    ));
                }
                (Some(row_control), Some(context_control)) if row_control != context_control => {
                    return Err(anyhow!(
                        "parser HIR context row {row} published {label} relation {context} with nearest enclosing control relation {row_control} that disagrees with context nearest enclosing control relation {context_control}"
                    ));
                }
                (Some(_), Some(_)) => {}
            }
        }
    }

    Ok(())
}

fn is_known_hir_kind(kind: u32) -> bool {
    matches!(
        kind,
        HIR_NODE_NONE
            | HIR_NODE_FILE
            | HIR_NODE_ITEM
            | HIR_NODE_FN
            | HIR_NODE_PARAM
            | HIR_NODE_TYPE
            | HIR_NODE_BLOCK
            | HIR_NODE_STMT
            | HIR_NODE_LET_STMT
            | HIR_NODE_RETURN_STMT
            | HIR_NODE_IF_STMT
            | HIR_NODE_WHILE_STMT
            | HIR_NODE_BREAK_STMT
            | HIR_NODE_CONTINUE_STMT
            | HIR_NODE_EXPR
            | HIR_NODE_ASSIGN_EXPR
            | HIR_NODE_BINARY_EXPR
            | HIR_NODE_UNARY_EXPR
            | HIR_NODE_POSTFIX_EXPR
            | HIR_NODE_CALL_EXPR
            | HIR_NODE_INDEX_EXPR
            | HIR_NODE_MEMBER_EXPR
            | HIR_NODE_NAME_EXPR
            | HIR_NODE_LITERAL_EXPR
            | HIR_NODE_ARRAY_EXPR
            | HIR_NODE_CONST_ITEM
            | HIR_NODE_ENUM_ITEM
            | HIR_NODE_STRUCT_ITEM
            | HIR_NODE_STRUCT_LITERAL_EXPR
            | HIR_NODE_TYPE_ALIAS_ITEM
            | HIR_NODE_FOR_STMT
            | HIR_NODE_MODULE_ITEM
            | HIR_NODE_IMPORT_ITEM
            | HIR_NODE_PATH_EXPR
            | HIR_NODE_MATCH_EXPR
    )
}

fn is_known_hir_type_form(form: u32) -> bool {
    matches!(
        form,
        HIR_TYPE_FORM_NONE
            | HIR_TYPE_FORM_PATH
            | HIR_TYPE_FORM_ARRAY
            | HIR_TYPE_FORM_SLICE
            | HIR_TYPE_FORM_REF
    )
}

fn expected_hir_kind_for_item_kind(item_kind: u32) -> Result<Option<u32>> {
    match item_kind {
        HIR_ITEM_KIND_NONE => Ok(None),
        HIR_ITEM_KIND_MODULE => Ok(Some(HIR_NODE_MODULE_ITEM)),
        HIR_ITEM_KIND_IMPORT => Ok(Some(HIR_NODE_IMPORT_ITEM)),
        HIR_ITEM_KIND_CONST => Ok(Some(HIR_NODE_CONST_ITEM)),
        HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN => Ok(Some(HIR_NODE_FN)),
        HIR_ITEM_KIND_STRUCT => Ok(Some(HIR_NODE_STRUCT_ITEM)),
        HIR_ITEM_KIND_ENUM => Ok(Some(HIR_NODE_ENUM_ITEM)),
        HIR_ITEM_KIND_TYPE_ALIAS => Ok(Some(HIR_NODE_TYPE_ALIAS_ITEM)),
        HIR_ITEM_KIND_ENUM_VARIANT | HIR_ITEM_KIND_TRAIT => Ok(Some(HIR_NODE_ITEM)),
        other => Err(anyhow!("unknown item kind {other}")),
    }
}

fn expected_namespace_for_item_kind(item_kind: u32) -> Result<Option<u32>> {
    match item_kind {
        HIR_ITEM_KIND_NONE => Ok(Some(HIR_ITEM_NAMESPACE_NONE)),
        HIR_ITEM_KIND_MODULE | HIR_ITEM_KIND_IMPORT => Ok(Some(HIR_ITEM_NAMESPACE_MODULE)),
        HIR_ITEM_KIND_CONST
        | HIR_ITEM_KIND_FN
        | HIR_ITEM_KIND_EXTERN_FN
        | HIR_ITEM_KIND_ENUM_VARIANT => Ok(Some(HIR_ITEM_NAMESPACE_VALUE)),
        HIR_ITEM_KIND_STRUCT
        | HIR_ITEM_KIND_ENUM
        | HIR_ITEM_KIND_TYPE_ALIAS
        | HIR_ITEM_KIND_TRAIT => Ok(Some(HIR_ITEM_NAMESPACE_TYPE)),
        other => Err(anyhow!("unknown item kind {other}")),
    }
}

fn item_kind_requires_name_token(item_kind: u32) -> bool {
    matches!(
        item_kind,
        HIR_ITEM_KIND_CONST
            | HIR_ITEM_KIND_FN
            | HIR_ITEM_KIND_EXTERN_FN
            | HIR_ITEM_KIND_STRUCT
            | HIR_ITEM_KIND_ENUM
            | HIR_ITEM_KIND_TYPE_ALIAS
            | HIR_ITEM_KIND_ENUM_VARIANT
            | HIR_ITEM_KIND_TRAIT
    )
}

fn is_known_item_visibility(visibility: u32) -> bool {
    matches!(visibility, HIR_ITEM_VIS_PRIVATE | HIR_ITEM_VIS_PUBLIC)
}

pub fn validate_hir_source_address_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR source address record arrays have inconsistent lengths"
        ));
    }

    let mut previous_public_record: Option<(usize, u32, u32, u32)> = None;
    for row in 0..row_count {
        if !is_known_hir_kind(kinds[row]) {
            return Err(anyhow!(
                "parser HIR source address row {row} published unknown HIR node kind {}",
                kinds[row]
            ));
        }
        if !is_known_hir_type_form(type_forms[row]) {
            return Err(anyhow!(
                "parser HIR source address row {row} published unknown type form {}",
                type_forms[row]
            ));
        }

        let expected_item_node_kind = expected_hir_kind_for_item_kind(item_kinds[row])
            .map_err(|err| anyhow!("parser HIR source address row {row} published {err}"))?;
        let has_item_record = expected_item_node_kind.is_some();
        let has_type_record = type_forms[row] != HIR_TYPE_FORM_NONE;
        let has_hir_record = kinds[row] != HIR_NODE_NONE;
        if has_hir_record
            && (token_pos[row] == INVALID
                || token_end[row] == INVALID
                || token_pos[row] >= token_end[row])
        {
            return Err(anyhow!(
                "parser HIR source address row {row} published HIR kind {} without a non-empty token span",
                kinds[row]
            ));
        }
        if has_hir_record && node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR source address row {row} published HIR kind {} without a node file id",
                kinds[row]
            ));
        }
        if !has_item_record && !has_type_record {
            continue;
        }

        if has_item_record && item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item row {row} published file id {} but node file id is {}",
                item_file_ids[row],
                node_file_ids[row]
            ));
        }
        if let Some(expected_node_kind) = expected_item_node_kind {
            if kinds[row] != expected_node_kind {
                return Err(anyhow!(
                    "parser HIR item row {row} published item kind {} on HIR kind {}, expected {expected_node_kind}",
                    item_kinds[row],
                    kinds[row]
                ));
            }
        }

        if has_type_record {
            if kinds[row] != HIR_NODE_TYPE {
                return Err(anyhow!(
                    "parser HIR type row {row} published type form {} without a type HIR node",
                    type_forms[row]
                ));
            }
            if type_file_ids[row] != node_file_ids[row] {
                return Err(anyhow!(
                    "parser HIR type row {row} published file id {} but node file id is {}",
                    type_file_ids[row],
                    node_file_ids[row]
                ));
            }
        }

        let current_key = (node_file_ids[row], token_pos[row], token_end[row]);
        if let Some((previous_row, previous_file_id, previous_token_pos, previous_token_end)) =
            previous_public_record
        {
            if current_key < (previous_file_id, previous_token_pos, previous_token_end) {
                return Err(anyhow!(
                    "parser HIR source address row {row} is out of flat source order after row {previous_row}: ({}, {}, {}) before ({previous_file_id}, {previous_token_pos}, {previous_token_end})",
                    node_file_ids[row],
                    token_pos[row],
                    token_end[row]
                ));
            }
        }
        previous_public_record = Some((row, node_file_ids[row], token_pos[row], token_end[row]));
    }

    Ok(())
}

pub fn validate_hir_item_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_namespaces: &[u32],
    item_visibilities: &[u32],
    item_file_ids: &[u32],
) -> Result<()> {
    let row_count = item_kinds.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_name_tokens.len() != row_count
        || item_namespaces.len() != row_count
        || item_visibilities.len() != row_count
        || item_file_ids.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR item record arrays have inconsistent lengths"
        ));
    }

    for row in 0..row_count {
        let item_kind = item_kinds[row];
        let expected_namespace = expected_namespace_for_item_kind(item_kind)
            .map_err(|err| anyhow!("parser HIR item row {row} published {err}"))?;
        if !is_known_item_visibility(item_visibilities[row]) {
            return Err(anyhow!(
                "parser HIR item row {row} published unknown item visibility {}",
                item_visibilities[row]
            ));
        }

        let Some(expected_node_kind) = expected_hir_kind_for_item_kind(item_kind)
            .map_err(|err| anyhow!("parser HIR item row {row} published {err}"))?
        else {
            if item_namespaces[row] != HIR_ITEM_NAMESPACE_NONE {
                return Err(anyhow!(
                    "parser HIR non-item row {row} published item namespace {}",
                    item_namespaces[row]
                ));
            }
            if item_name_tokens[row] != INVALID {
                return Err(anyhow!(
                    "parser HIR non-item row {row} retained item name metadata"
                ));
            }
            if item_file_ids[row] != INVALID && item_file_ids[row] != node_file_ids[row] {
                return Err(anyhow!(
                    "parser HIR non-item row {row} published file id {} but node file id is {}",
                    item_file_ids[row],
                    node_file_ids[row]
                ));
            }
            continue;
        };

        if kinds[row] != expected_node_kind {
            return Err(anyhow!(
                "parser HIR item row {row} published item kind {item_kind} on HIR kind {}, expected {expected_node_kind}",
                kinds[row]
            ));
        }
        if item_namespaces[row] != expected_namespace.unwrap_or(HIR_ITEM_NAMESPACE_NONE) {
            return Err(anyhow!(
                "parser HIR item row {row} published namespace {} for item kind {item_kind}",
                item_namespaces[row]
            ));
        }
        if token_pos[row] == INVALID
            || token_end[row] == INVALID
            || token_pos[row] >= token_end[row]
            || node_file_ids[row] == INVALID
        {
            return Err(anyhow!(
                "parser HIR item row {row} published item kind {item_kind} without source-addressable ownership"
            ));
        }
        if item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item row {row} published file id {} but node file id is {}",
                item_file_ids[row],
                node_file_ids[row]
            ));
        }

        let name_token = item_name_tokens[row];
        if item_kind_requires_name_token(item_kind) {
            if name_token == INVALID || name_token < token_pos[row] || name_token >= token_end[row]
            {
                return Err(anyhow!(
                    "parser HIR item row {row} published item kind {item_kind} without an in-span name token"
                ));
            }
            if matches!(item_kind, HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN)
                && name_token <= token_pos[row]
            {
                return Err(anyhow!(
                    "parser HIR function item row {row} published a name token that does not follow its declaration token"
                ));
            }
        } else if name_token != INVALID {
            return Err(anyhow!(
                "parser HIR item row {row} published a name token for path-owned item kind {item_kind}"
            ));
        }
    }

    Ok(())
}

pub fn validate_hir_type_alias_target_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    target_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || target_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type-alias target record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let mut target_owners = vec![INVALID; row_count];
    for row in 0..row_count {
        let is_type_alias = item_kinds[row] == HIR_ITEM_KIND_TYPE_ALIAS;
        let target = target_nodes[row];

        if !is_type_alias {
            if kinds[row] == HIR_NODE_TYPE_ALIAS_ITEM {
                return Err(anyhow!(
                    "parser HIR type-alias row {row} has no parser-owned type-alias item metadata"
                ));
            }
            if target != INVALID {
                return Err(anyhow!(
                    "parser HIR row {row} published a type-alias target without type-alias item metadata"
                ));
            }
            continue;
        }

        if kinds[row] != HIR_NODE_TYPE_ALIAS_ITEM {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published item metadata on HIR kind {}",
                kinds[row]
            ));
        }
        if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published item metadata without a source-addressable alias span"
            ));
        }
        if item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} has inconsistent item and node file ids"
            ));
        }

        let name_token = item_name_tokens[row];
        if name_token == INVALID || name_token < token_pos[row] || name_token >= token_end[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published a name token outside its alias span"
            ));
        }

        if target == INVALID || target as usize >= row_count || target as usize == row {
            return Err(anyhow!(
                "parser HIR type-alias row {row} published no in-table target type row"
            ));
        }
        let target = target as usize;
        if kinds[target] != HIR_NODE_TYPE || type_forms[target] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} is not a concrete type record"
            ));
        }
        if !has_non_empty_span(target) {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} lacks a non-empty token span"
            ));
        }
        if node_file_ids[target] != node_file_ids[row]
            || type_file_ids[target] != node_file_ids[row]
        {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} has a different file id"
            ));
        }
        if token_pos[target] < token_pos[row] || token_end[target] > token_end[row] {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} falls outside the alias span"
            ));
        }
        if token_pos[target] <= name_token {
            return Err(anyhow!(
                "parser HIR type-alias row {row} target row {target} does not follow the alias name token"
            ));
        }

        let previous_owner = target_owners[target];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR type-alias row {row} shares target row {target} with alias row {previous_owner}"
            ));
        }
        target_owners[target] = row as u32;
    }

    Ok(())
}

pub fn validate_hir_type_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_value_nodes: &[u32],
    type_len_tokens: &[u32],
    type_len_values: &[u32],
    type_file_ids: &[u32],
    type_path_leaf_nodes: &[u32],
) -> Result<()> {
    let node_kinds = vec![INVALID; kinds.len()];
    validate_hir_type_records_with_node_kinds(
        &node_kinds,
        kinds,
        token_pos,
        token_end,
        node_file_ids,
        type_forms,
        type_value_nodes,
        type_len_tokens,
        type_len_values,
        type_file_ids,
        type_path_leaf_nodes,
    )
}

pub fn validate_hir_type_records_with_node_kinds(
    node_kinds: &[u32],
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_value_nodes: &[u32],
    type_len_tokens: &[u32],
    type_len_values: &[u32],
    type_file_ids: &[u32],
    type_path_leaf_nodes: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if node_kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_value_nodes.len() != row_count
        || type_len_tokens.len() != row_count
        || type_len_values.len() != row_count
        || type_file_ids.len() != row_count
        || type_path_leaf_nodes.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR type record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_type_owner = |owner: usize, label: &str| -> Result<()> {
        if kinds[owner] != HIR_NODE_TYPE {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} on HIR kind {}",
                kinds[owner]
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} without a source-addressable type row"
            ));
        }
        if type_file_ids[owner] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published file id {} but node file id is {}",
                type_file_ids[owner],
                node_file_ids[owner]
            ));
        }
        Ok(())
    };

    let require_parser_node_inside_owner = |owner: usize,
                                            node: u32,
                                            label: &str|
     -> Result<usize> {
        if node == INVALID || node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} without an in-table parser-owned row"
            ));
        }
        let node = node as usize;
        if node == owner {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} as a self edge"
            ));
        }
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} without a non-empty token span"
            ));
        }
        if node_file_ids[node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} with a different file id"
            ));
        }
        if token_pos[node] < token_pos[owner] || token_end[node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR type row {owner} published {label} row {node} outside the owner type span"
            ));
        }
        Ok(node)
    };

    let require_path_leaf = |owner: usize, path_node: usize| -> Result<usize> {
        let leaf = type_path_leaf_nodes[owner];
        if leaf == INVALID || leaf as usize >= row_count {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published no in-table parser-owned path leaf"
            ));
        }
        let leaf = leaf as usize;
        if !has_non_empty_span(leaf) {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} without a non-empty token span"
            ));
        }
        if kinds[leaf] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} on concrete HIR kind {} instead of a parser path-segment row",
                kinds[leaf]
            ));
        }
        if node_file_ids[leaf] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} with a different file id"
            ));
        }
        if token_pos[leaf] < token_pos[path_node] || token_end[leaf] > token_end[path_node] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} outside path node {path_node}"
            ));
        }
        if token_end[leaf] != token_end[path_node] {
            return Err(anyhow!(
                "parser HIR path/type row {owner} published path leaf row {leaf} that is not the terminal segment of path node {path_node}"
            ));
        }
        Ok(leaf)
    };

    let require_no_len = |row: usize, label: &str| -> Result<()> {
        if type_len_tokens[row] != INVALID || type_len_values[row] != INVALID {
            return Err(anyhow!(
                "parser HIR type row {row} published {label} with array length metadata"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        if kinds[row] == HIR_NODE_PATH_EXPR {
            if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
                return Err(anyhow!(
                    "parser HIR path row {row} published a path leaf without a source-addressable path row"
                ));
            }
            require_path_leaf(row, row)?;
        } else if type_path_leaf_nodes[row] != INVALID
            && type_forms[row] != HIR_TYPE_FORM_PATH
            && node_kinds[row] != PROD_BOUND_TYPE_IDENT
        {
            return Err(anyhow!(
                "parser HIR row {row} published a path leaf without a path HIR/type owner"
            ));
        }

        match type_forms[row] {
            HIR_TYPE_FORM_NONE => {
                if kinds[row] == HIR_NODE_TYPE {
                    return Err(anyhow!(
                        "parser HIR type row {row} has a type HIR kind but no concrete type record"
                    ));
                }
                if type_value_nodes[row] != INVALID
                    || type_len_tokens[row] != INVALID
                    || type_len_values[row] != INVALID
                {
                    return Err(anyhow!(
                        "parser HIR row {row} published type metadata without a concrete type record"
                    ));
                }
            }
            HIR_TYPE_FORM_PATH => {
                require_type_owner(row, "path type record")?;
                let path_node =
                    require_parser_node_inside_owner(row, type_value_nodes[row], "path node")?;
                if kinds[path_node] != HIR_NODE_PATH_EXPR {
                    return Err(anyhow!(
                        "parser HIR type row {row} published path type record without a parser-owned path node record"
                    ));
                }
                if token_pos[path_node] != token_pos[row] {
                    return Err(anyhow!(
                        "parser HIR type row {row} path type span does not start at parser-owned path node {path_node}"
                    ));
                }
                let path_leaf = require_path_leaf(row, path_node)?;
                let path_node_leaf = require_path_leaf(path_node, path_node)?;
                if path_leaf != path_node_leaf {
                    return Err(anyhow!(
                        "parser HIR type row {row} published path leaf row {path_leaf} different from parser-owned path node {path_node} leaf row {path_node_leaf}"
                    ));
                }
                require_no_len(row, "path type record")?;
            }
            HIR_TYPE_FORM_ARRAY | HIR_TYPE_FORM_SLICE | HIR_TYPE_FORM_REF => {
                let label = match type_forms[row] {
                    HIR_TYPE_FORM_ARRAY => "array type record",
                    HIR_TYPE_FORM_SLICE => "slice type record",
                    _ => "reference type record",
                };
                require_type_owner(row, label)?;
                let operand =
                    require_parser_node_inside_owner(row, type_value_nodes[row], "operand type")?;
                if kinds[operand] != HIR_NODE_TYPE || type_forms[operand] == HIR_TYPE_FORM_NONE {
                    return Err(anyhow!(
                        "parser HIR type row {row} published operand row {operand} without a concrete type operand"
                    ));
                }
                if type_path_leaf_nodes[row] != INVALID {
                    return Err(anyhow!(
                        "parser HIR type row {row} published {label} with path leaf metadata"
                    ));
                }
                if type_forms[row] == HIR_TYPE_FORM_ARRAY {
                    let len_token = type_len_tokens[row];
                    if len_token == INVALID
                        || len_token < token_pos[row]
                        || len_token >= token_end[row]
                    {
                        return Err(anyhow!(
                            "parser HIR type row {row} published array type record without an in-span length token"
                        ));
                    }
                } else {
                    require_no_len(row, label)?;
                }
            }
            other => {
                return Err(anyhow!(
                    "parser HIR type row {row} published unknown type record form {other}"
                ));
            }
        }
    }

    Ok(())
}

fn is_hir_function_item_kind(kind: u32) -> bool {
    matches!(kind, HIR_ITEM_KIND_FN | HIR_ITEM_KIND_EXTERN_FN)
}

fn is_hir_function_return_owner(kind: u32, item_kind: u32) -> bool {
    kind == HIR_NODE_FN && (item_kind == HIR_ITEM_KIND_NONE || is_hir_function_item_kind(item_kind))
}

pub fn validate_hir_function_return_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    return_type_nodes: &[u32],
    item_kinds: &[u32],
    item_name_tokens: &[u32],
    item_file_ids: &[u32],
    method_signature_flags: &[u32],
    method_name_tokens: &[u32],
) -> Result<()> {
    let row_count = kinds.len();
    if token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || return_type_nodes.len() != row_count
        || item_kinds.len() != row_count
        || item_name_tokens.len() != row_count
        || item_file_ids.len() != row_count
        || method_signature_flags.len() != row_count
        || method_name_tokens.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR function return record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let signature_flag_mask = HIR_METHOD_SIGNATURE_HAS_GENERICS | HIR_METHOD_SIGNATURE_HAS_WHERE;
    for row in 0..row_count {
        let flags = method_signature_flags[row];
        if flags == 0 {
            continue;
        }
        if flags & !signature_flag_mask != 0 {
            return Err(anyhow!(
                "parser HIR function return row {row} published unknown method signature flags {flags}"
            ));
        }
        if kinds[row] != HIR_NODE_FN || item_kinds[row] != HIR_ITEM_KIND_NONE {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without a parser-owned method row"
            ));
        }
        if !has_non_empty_span(row) || node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without a source-addressable method row"
            ));
        }
        let method_name_token = method_name_tokens[row];
        if method_name_token == INVALID
            || method_name_token < token_pos[row]
            || method_name_token >= token_end[row]
        {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags without an in-span parser-owned method name token"
            ));
        }
        if method_name_token <= token_pos[row] {
            return Err(anyhow!(
                "parser HIR function return row {row} published method signature flags with a method name token that does not follow the function span start"
            ));
        }
    }

    let mut return_type_owner = vec![INVALID; row_count];
    for owner in 0..row_count {
        let return_type_node = return_type_nodes[owner];
        if return_type_node == INVALID {
            continue;
        }

        if !is_hir_function_return_owner(kinds[owner], item_kinds[owner]) {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a return type without a function or method owner"
            ));
        }
        if !has_non_empty_span(owner) || node_file_ids[owner] == INVALID {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a return type without a source-addressable function owner"
            ));
        }
        if is_hir_function_item_kind(item_kinds[owner])
            && item_file_ids[owner] != node_file_ids[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} has inconsistent owner item and node file ids"
            ));
        }
        let (owner_name_token, owner_name_label) = if is_hir_function_item_kind(item_kinds[owner]) {
            let name_token = item_name_tokens[owner];
            if name_token == INVALID
                || name_token < token_pos[owner]
                || name_token >= token_end[owner]
            {
                return Err(anyhow!(
                    "parser HIR function return row {owner} published a return type without a source-addressable function name token"
                ));
            }
            (name_token, "function")
        } else {
            let name_token = method_name_tokens[owner];
            if name_token == INVALID
                || name_token < token_pos[owner]
                || name_token >= token_end[owner]
            {
                return Err(anyhow!(
                    "parser HIR function return row {owner} published a return type without a source-addressable method name token"
                ));
            }
            (name_token, "method")
        };
        if owner_name_token <= token_pos[owner] {
            return Err(anyhow!(
                "parser HIR function return row {owner} published a {owner_name_label} name token that does not follow the function span start"
            ));
        }

        if return_type_node as usize >= row_count || return_type_node as usize == owner {
            return Err(anyhow!(
                "parser HIR function return row {owner} published no in-table return type node"
            ));
        }
        let return_type_node = return_type_node as usize;
        let previous_owner = return_type_owner[return_type_node];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR function return row {owner} shares return type row {return_type_node} with owner row {previous_owner}"
            ));
        }
        return_type_owner[return_type_node] = owner as u32;
        if kinds[return_type_node] != HIR_NODE_TYPE
            || type_forms[return_type_node] == HIR_TYPE_FORM_NONE
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at row {return_type_node} without a concrete type record"
            ));
        }
        if !has_non_empty_span(return_type_node) {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} without a non-empty token span"
            ));
        }
        if node_file_ids[return_type_node] != node_file_ids[owner]
            || type_file_ids[return_type_node] != node_file_ids[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} with a different file id"
            ));
        }
        if token_pos[return_type_node] < token_pos[owner]
            || token_end[return_type_node] > token_end[owner]
        {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} outside the function span"
            ));
        }
        if token_pos[return_type_node] <= owner_name_token {
            return Err(anyhow!(
                "parser HIR function return row {owner} points at return type row {return_type_node} that does not follow the {owner_name_label} name token"
            ));
        }
    }

    Ok(())
}

pub fn validate_hir_struct_declaration_field_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    type_forms: &[u32],
    type_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    parent_structs: &[u32],
    ordinals: &[u32],
    type_nodes: &[u32],
    first_fields: &[u32],
    counts: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || type_forms.len() != row_count
        || type_file_ids.len() != row_count
        || item_kinds.len() != row_count
        || item_file_ids.len() != row_count
        || parent_structs.len() != row_count
        || ordinals.len() != row_count
        || type_nodes.len() != row_count
        || first_fields.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR struct declaration field record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR struct declaration {label} row {node} lacks a non-empty token span"
            ));
        }
        if node_file_ids[node] == INVALID {
            return Err(anyhow!(
                "parser HIR struct declaration {label} row {node} lacks a source file id"
            ));
        }
        Ok(())
    };

    let require_struct_owner = |owner: usize| -> Result<()> {
        if kinds[owner] != HIR_NODE_STRUCT_ITEM || item_kinds[owner] != HIR_ITEM_KIND_STRUCT {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} is not backed by a parser-owned struct item record"
            ));
        }
        require_span(owner, "owner")?;
        if item_file_ids[owner] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} has inconsistent item and node file ids"
            ));
        }
        Ok(())
    };

    let mut actual_counts = vec![0u32; row_count];
    let mut ordinal_keys = Vec::new();
    for (field_node, &owner) in parent_structs.iter().enumerate() {
        if owner == INVALID {
            if ordinals[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct field row {field_node} published a field ordinal without a struct owner"
                ));
            }
            if type_nodes[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct field row {field_node} published a field type edge without a struct owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        require_struct_owner(owner)?;
        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} points at owner {owner} with zero field count"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published {owner_count} fields, exceeding {row_count} readback rows"
            ));
        }

        if kinds[field_node] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} has HIR kind {}, not a parser-owned struct declaration field record",
                kinds[field_node]
            ));
        }
        require_span(field_node, "field")?;
        if node_file_ids[field_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[field_node] < token_pos[owner] || token_end[field_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} falls outside owner {owner} span"
            ));
        }

        let ordinal = ordinals[field_node];
        if ordinal >= owner_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published ordinal {ordinal}, outside owner {owner} count {owner_count}"
            ));
        }

        let type_node = type_nodes[field_node];
        if type_node == INVALID || type_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} published no in-table type node"
            ));
        }
        let type_node = type_node as usize;
        if kinds[type_node] != HIR_NODE_TYPE || type_forms[type_node] == HIR_TYPE_FORM_NONE {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} is not a concrete type record"
            ));
        }
        require_span(type_node, "field type")?;
        if node_file_ids[type_node] != node_file_ids[field_node]
            || type_file_ids[type_node] != node_file_ids[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} has a different file id"
            ));
        }
        if token_pos[type_node] < token_pos[field_node]
            || token_end[type_node] > token_end[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} falls outside the field span"
            ));
        }
        if token_pos[type_node] <= token_pos[field_node] {
            return Err(anyhow!(
                "parser HIR struct field row {field_node} type row {type_node} does not follow the field name token"
            ));
        }

        actual_counts[owner] += 1;
        ordinal_keys.push((owner, ordinal, field_node));
    }

    ordinal_keys.sort_unstable();
    for pair in ordinal_keys.windows(2) {
        let (owner, ordinal, first_row) = pair[0];
        let (next_owner, next_ordinal, _) = pair[1];
        if owner == next_owner && ordinal == next_ordinal {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published duplicate field ordinal {ordinal} at row {first_row}"
            ));
        }
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_fields[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct declaration row {owner} published first field without a field count"
                ));
            }
            continue;
        }
        require_struct_owner(owner)?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published {count} fields, exceeding {row_count} readback rows"
            ));
        }

        let first = first_fields[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published field count {count} without an in-table first field"
            ));
        }
        let first = first as usize;
        if parent_structs[first] as usize != owner || ordinals[first] != 0 {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} first field row {first} is not ordinal zero for that owner"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR struct declaration row {owner} published count {count} but read back {} owned field rows",
                actual_counts[owner]
            ));
        }

        let mut previous_field: Option<usize> = None;
        for expected_ordinal in 0..count {
            let field = ordinal_keys
                .binary_search_by_key(&(owner, expected_ordinal), |&(owner, ordinal, _)| {
                    (owner, ordinal)
                })
                .ok()
                .map(|index| ordinal_keys[index].2)
                .ok_or_else(|| {
                    anyhow!(
                        "parser HIR struct declaration row {owner} field ordinals are not contiguous from zero"
                    )
                })?;
            if let Some(previous) = previous_field {
                if token_pos[field] <= token_pos[previous] || token_end[previous] > token_pos[field]
                {
                    return Err(anyhow!(
                        "parser HIR struct declaration row {owner} fields overlap or are not in source order at row {field}"
                    ));
                }
            }
            previous_field = Some(field);
        }
    }

    Ok(())
}

pub fn validate_hir_struct_literal_field_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    head_nodes: &[u32],
    first_fields: &[u32],
    counts: &[u32],
    parent_literals: &[u32],
    value_nodes: &[u32],
    next_fields: &[u32],
) -> Result<()> {
    let row_count = counts.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || head_nodes.len() != row_count
        || first_fields.len() != row_count
        || parent_literals.len() != row_count
        || value_nodes.len() != row_count
        || next_fields.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR struct literal field record arrays have inconsistent lengths"
        ));
    }

    let has_non_empty_span = |node: usize| {
        token_pos[node] != INVALID
            && token_end[node] != INVALID
            && token_pos[node] < token_end[node]
    };

    let require_span = |node: usize, label: &str| -> Result<()> {
        if !has_non_empty_span(node) {
            return Err(anyhow!(
                "parser HIR struct literal {label} row {node} lacks a non-empty token span"
            ));
        }
        Ok(())
    };

    for row in 0..row_count {
        let head = head_nodes[row];
        if kinds[row] != HIR_NODE_STRUCT_LITERAL_EXPR {
            if head != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal row {row} published a head node without a struct-literal HIR owner"
                ));
            }
            continue;
        }

        require_span(row, "owner")?;
        if node_file_ids[row] == INVALID {
            return Err(anyhow!(
                "parser HIR struct literal row {row} published a head node without a node file id"
            ));
        }
        if head == INVALID || head as usize >= row_count || head as usize == row {
            return Err(anyhow!(
                "parser HIR struct literal row {row} published no in-table head path node"
            ));
        }

        let head = head as usize;
        require_span(head, "head")?;
        if node_file_ids[head] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} published a different file id"
            ));
        }
        if token_pos[head] < token_pos[row] || token_end[head] > token_end[row] {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} falls outside owner row {row} span"
            ));
        }
        if !matches!(kinds[head], HIR_NODE_PATH_EXPR | HIR_NODE_NAME_EXPR) {
            return Err(anyhow!(
                "parser HIR struct literal row {row} head row {head} has non-path/name HIR kind {}",
                kinds[head]
            ));
        }
    }

    let mut actual_counts = vec![0u32; row_count];
    for (field_node, &owner) in parent_literals.iter().enumerate() {
        if owner == INVALID {
            if next_fields[field_node] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal field row {field_node} published next field without an owner"
                ));
            }
            let value_node = value_nodes[field_node];
            if value_node != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal field row {field_node} published value node without an owner"
                ));
            }
            continue;
        }

        let owner = owner as usize;
        if owner >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published owner {owner}, outside {row_count} readback rows"
            ));
        }
        if kinds[owner] != HIR_NODE_STRUCT_LITERAL_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} points at owner {owner} that is not a struct-literal HIR row"
            ));
        }
        if kinds[field_node] != HIR_NODE_NONE {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} has HIR kind {}, not a parser-owned struct-literal field record",
                kinds[field_node]
            ));
        }

        let owner_count = counts[owner];
        if owner_count == 0 {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} points at owner {owner} with zero field count"
            ));
        }
        require_span(owner, "owner")?;
        require_span(field_node, "field")?;
        if node_file_ids[owner] == INVALID || node_file_ids[field_node] != node_file_ids[owner] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published a different file id than owner {owner}"
            ));
        }
        if token_pos[field_node] < token_pos[owner] || token_end[field_node] > token_end[owner] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} falls outside owner {owner} span"
            ));
        }
        if owner_count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published {owner_count} fields, exceeding {row_count} readback rows"
            ));
        }

        let value_node = value_nodes[field_node];
        if value_node == INVALID || value_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published a field without an in-table value expression"
            ));
        }
        if kinds[value_node as usize] != HIR_NODE_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} is not an expression HIR row"
            ));
        }
        let value_node = value_node as usize;
        require_span(value_node, "field value")?;
        if node_file_ids[value_node] != node_file_ids[field_node] {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} published a different file id"
            ));
        }
        if token_pos[value_node] < token_pos[field_node]
            || token_end[value_node] > token_end[field_node]
        {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} value row {value_node} falls outside the field span"
            ));
        }

        let next = next_fields[field_node];
        if next != INVALID && next as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal field row {field_node} published next field {next}, outside {row_count} readback rows"
            ));
        }
        actual_counts[owner] += 1;
    }

    for (owner, &count) in counts.iter().enumerate() {
        if count == 0 {
            if first_fields[owner] != INVALID {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} published first field without a field count"
                ));
            }
            continue;
        }
        if kinds[owner] != HIR_NODE_STRUCT_LITERAL_EXPR {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without a struct-literal HIR owner"
            ));
        }
        require_span(owner, "owner")?;
        if count as usize > row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published {count} fields, exceeding {row_count} readback rows"
            ));
        }

        let first = first_fields[owner];
        if first == INVALID || first as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without an in-table first field"
            ));
        }
        let first = first as usize;
        let head = head_nodes[owner];
        if head == INVALID || head as usize >= row_count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published field count {count} without an in-table head path node"
            ));
        }
        let head = head as usize;
        if token_end[head] > token_pos[first] {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} head row {head} does not precede first field row {first}"
            ));
        }
        if actual_counts[owner] != count {
            return Err(anyhow!(
                "parser HIR struct literal row {owner} published count {count} but read back {} owned field rows",
                actual_counts[owner]
            ));
        }

        let mut field = first;
        for expected_position in 0..count {
            if parent_literals[field] as usize != owner {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} field chain row {field} does not point back to that owner"
                ));
            }
            let value_node = value_nodes[field];
            if value_node == INVALID || value_node as usize >= row_count {
                return Err(anyhow!(
                    "parser HIR struct literal row {owner} field chain row {field} has no in-table value expression"
                ));
            }

            let next = next_fields[field];
            if expected_position + 1 == count {
                if next != INVALID {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} final field row {field} did not terminate the field chain"
                    ));
                }
            } else {
                if next == INVALID || next as usize >= row_count {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain ended before count {count}"
                    ));
                }
                let next = next as usize;
                if parent_literals[next] as usize != owner {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain row {next} does not point back to that owner"
                    ));
                }
                if token_pos[next] <= token_pos[field] || token_end[field] > token_pos[next] {
                    return Err(anyhow!(
                        "parser HIR struct literal row {owner} field chain rows overlap or are not in source order at row {field}"
                    ));
                }
                field = next;
            }
        }
    }

    Ok(())
}

pub fn validate_hir_item_path_records(
    kinds: &[u32],
    token_pos: &[u32],
    token_end: &[u32],
    node_file_ids: &[u32],
    item_kinds: &[u32],
    item_file_ids: &[u32],
    path_starts: &[u32],
    path_ends: &[u32],
    path_nodes: &[u32],
    import_target_kinds: &[u32],
) -> Result<()> {
    let row_count = item_kinds.len();
    if kinds.len() != row_count
        || token_pos.len() != row_count
        || token_end.len() != row_count
        || node_file_ids.len() != row_count
        || item_file_ids.len() != row_count
        || path_starts.len() != row_count
        || path_ends.len() != row_count
        || path_nodes.len() != row_count
        || import_target_kinds.len() != row_count
    {
        return Err(anyhow!(
            "parser HIR item path record arrays have inconsistent lengths"
        ));
    }

    let mut path_node_owners = vec![INVALID; row_count];
    for row in 0..row_count {
        let item_kind = item_kinds[row];
        let import_target_kind = import_target_kinds[row];
        if item_kind != HIR_ITEM_KIND_IMPORT {
            if import_target_kind != HIR_ITEM_IMPORT_TARGET_NONE {
                return Err(anyhow!(
                    "parser HIR item row {row} published import-target metadata for non-import item kind {item_kind}"
                ));
            }
        } else {
            match import_target_kind {
                HIR_ITEM_IMPORT_TARGET_PATH => {}
                HIR_ITEM_IMPORT_TARGET_NONE => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published no import target record"
                    ));
                }
                HIR_ITEM_IMPORT_TARGET_STRING => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published unsupported string import target without a parser-owned path record"
                    ));
                }
                other => {
                    return Err(anyhow!(
                        "parser HIR import item row {row} published unknown import target kind {other}"
                    ));
                }
            }
        }

        let expects_path = item_kind == HIR_ITEM_KIND_MODULE
            || (item_kind == HIR_ITEM_KIND_IMPORT
                && import_target_kind == HIR_ITEM_IMPORT_TARGET_PATH);
        if !expects_path {
            if path_starts[row] != INVALID
                || path_ends[row] != INVALID
                || path_nodes[row] != INVALID
            {
                return Err(anyhow!(
                    "parser HIR item row {row} published a path record without a module/import path owner"
                ));
            }
            continue;
        }
        let expected_owner_kind = if item_kind == HIR_ITEM_KIND_MODULE {
            HIR_NODE_MODULE_ITEM
        } else {
            HIR_NODE_IMPORT_ITEM
        };
        if kinds[row] != expected_owner_kind {
            return Err(anyhow!(
                "parser HIR item path row {row} published item kind {item_kind} on HIR kind {}, expected path owner kind {expected_owner_kind}",
                kinds[row]
            ));
        }

        if token_pos[row] == INVALID
            || token_end[row] == INVALID
            || token_pos[row] >= token_end[row]
        {
            return Err(anyhow!(
                "parser HIR item path row {row} published a path owner without a non-empty item span"
            ));
        }
        if node_file_ids[row] == INVALID || item_file_ids[row] != node_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item path row {row} has inconsistent item and node file ids"
            ));
        }

        let path_start = path_starts[row];
        let path_end = path_ends[row];
        if path_start == INVALID
            || path_end == INVALID
            || path_start >= path_end
            || path_start <= token_pos[row]
            || path_end > token_end[row]
        {
            return Err(anyhow!(
                "parser HIR item path row {row} published a path span outside its item span"
            ));
        }

        let path_node = path_nodes[row];
        if path_node == INVALID || path_node as usize >= row_count {
            return Err(anyhow!(
                "parser HIR item path row {row} published no in-table path node"
            ));
        }
        let path_node = path_node as usize;
        if kinds[path_node] != HIR_NODE_PATH_EXPR {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} is not a path HIR row"
            ));
        }
        if node_file_ids[path_node] != item_file_ids[row] {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} has a different file id"
            ));
        }
        if token_pos[path_node] != path_start || token_end[path_node] != path_end {
            return Err(anyhow!(
                "parser HIR item path row {row} path node {path_node} does not anchor the published path span"
            ));
        }
        let previous_owner = path_node_owners[path_node];
        if previous_owner != INVALID {
            return Err(anyhow!(
                "parser HIR item path row {row} shares path node {path_node} with item path row {previous_owner}"
            ));
        }
        path_node_owners[path_node] = row as u32;
    }

    Ok(())
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
            &[HIR_NODE_TYPE, 0, 0],
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
    fn call_argument_readback_rejects_packed_ordinal_overflow() {
        let err = validate_hir_call_argument_records(
            &[HIR_NODE_NAME_EXPR, HIR_NODE_CALL_EXPR, HIR_NODE_EXPR],
            &[10, 10, 12],
            &[11, 20, 13],
            &[0; 3],
            &[INVALID, 0, INVALID],
            &[INVALID, 2, INVALID],
            &[INVALID, INVALID, 13],
            &[0, HIR_PACKED_NODE_ORDINAL_SLOT_COUNT + 1, 0],
            &[INVALID, INVALID, 1],
            &[INVALID, INVALID, 0],
        )
        .expect_err("call argument counts past the packed ordinal width should fail closed");
        assert!(
            err.to_string().contains("packed ordinal slots"),
            "error should describe the violated packed-record bound"
        );
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
            [20, 2, 9, 18, 5, 12, 8, 15, 6],
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
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 0,
            ],
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 0,
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
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 1,
            ],
            &[
                INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, INVALID, 0,
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
            &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
            &[INVALID, INVALID, INVALID, INVALID, INVALID, INVALID],
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
