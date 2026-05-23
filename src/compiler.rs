use std::{fs, path::Path, sync::OnceLock};

use futures_intrusive::sync::Mutex;

use crate::{
    codegen::{wasm, x86},
    gpu::{
        device::{self, GpuDevice},
        timer::GpuTimer,
    },
    lexer::{
        buffers::GpuBuffers as LexerBuffers,
        driver::{GpuLexer, ResidentLexerParserInputs},
    },
    parser::{
        buffers::ParserBuffers,
        driver::{GpuParser, Ll1AcceptResult},
        tables::PrecomputedParseTables,
    },
    type_checker as gpu_type_checker,
};

#[derive(Debug)]
pub enum CompileError {
    GpuFrontend(String),
    GpuSyntax(String),
    GpuTypeCheck(String),
    GpuCodegen(String),
}

impl std::fmt::Display for CompileError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            CompileError::GpuFrontend(err) => write!(f, "GPU frontend error: {err}"),
            CompileError::GpuSyntax(err) => write!(f, "GPU syntax error: {err}"),
            CompileError::GpuTypeCheck(err) => write!(f, "GPU type check error: {err}"),
            CompileError::GpuCodegen(err) => write!(f, "GPU codegen error: {err}"),
        }
    }
}

impl std::error::Error for CompileError {}

pub struct GpuParseBenchmarkResult {
    pub ll1: Ll1AcceptResult,
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub semantic_hir_count: u32,
}

pub struct GpuLiveCapacityEstimateResult {
    pub token_count: u32,
    pub parser_tree_capacity: u32,
    pub parser_emit_len: u32,
    pub semantic_hir_count: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct GpuCompilerBackends {
    pub wasm: bool,
    pub x86: bool,
}

impl GpuCompilerBackends {
    pub const fn all() -> Self {
        Self {
            wasm: true,
            x86: true,
        }
    }

    pub const fn frontend_only() -> Self {
        Self {
            wasm: false,
            x86: false,
        }
    }

    pub const fn wasm_only() -> Self {
        Self {
            wasm: true,
            x86: false,
        }
    }

    pub const fn x86_only() -> Self {
        Self {
            wasm: false,
            x86: true,
        }
    }
}

pub struct GpuCompiler<'gpu> {
    gpu: &'gpu GpuDevice,
    lexer: GpuLexer,
    parser: GpuParser,
    parse_tables: PrecomputedParseTables,
    type_checker: gpu_type_checker::GpuTypeChecker,
    resident_pipeline_lock: Mutex<()>,
    wasm_generator: Result<Box<wasm::GpuWasmCodeGenerator>, String>,
    x86_generator: Result<Box<x86::GpuX86CodeGenerator>, String>,
}

struct OwnedX86ParserBuffers {
    ll1_status: wgpu::Buffer,
    tree_active_dispatch_args: wgpu::Buffer,
    hir_kind: wgpu::Buffer,
    parent: wgpu::Buffer,
    first_child: wgpu::Buffer,
    next_sibling: wgpu::Buffer,
    subtree_end: wgpu::Buffer,
    hir_item_kind: wgpu::Buffer,
    hir_item_decl_token: wgpu::Buffer,
    hir_item_name_token: wgpu::Buffer,
    hir_item_namespace: wgpu::Buffer,
    hir_item_visibility: wgpu::Buffer,
    hir_item_path_start: wgpu::Buffer,
    hir_token_pos: wgpu::Buffer,
    hir_type_form: wgpu::Buffer,
    hir_type_value_node: wgpu::Buffer,
    hir_type_len_token: wgpu::Buffer,
    hir_type_len_value: wgpu::Buffer,
    hir_type_path_leaf_node: wgpu::Buffer,
    hir_type_path_leaf_link_a: wgpu::Buffer,
    hir_type_path_leaf_link_b: wgpu::Buffer,
    hir_type_arg_start: wgpu::Buffer,
    hir_type_arg_count: wgpu::Buffer,
    hir_type_arg_next: wgpu::Buffer,
    hir_type_arg_rank_a: wgpu::Buffer,
    hir_type_alias_target_node: wgpu::Buffer,
    hir_fn_return_type_node: wgpu::Buffer,
    hir_semantic_dense_node: wgpu::Buffer,
    hir_param_record: wgpu::Buffer,
    hir_stmt_record: wgpu::Buffer,
    hir_expr_record: wgpu::Buffer,
    hir_expr_int_value: wgpu::Buffer,
    hir_member_receiver_node: wgpu::Buffer,
    hir_member_name_token: wgpu::Buffer,
    hir_call_callee_node: wgpu::Buffer,
    hir_call_arg_start: wgpu::Buffer,
    hir_call_arg_end: wgpu::Buffer,
    hir_call_arg_count: wgpu::Buffer,
    hir_call_arg_parent_call: wgpu::Buffer,
    hir_call_arg_ordinal: wgpu::Buffer,
    hir_array_lit_first_element: wgpu::Buffer,
    hir_array_lit_element_count: wgpu::Buffer,
    hir_array_element_parent_lit: wgpu::Buffer,
    hir_array_element_ordinal: wgpu::Buffer,
    hir_array_element_next: wgpu::Buffer,
    hir_array_element_previous: wgpu::Buffer,
    hir_variant_parent_enum: wgpu::Buffer,
    hir_variant_ordinal: wgpu::Buffer,
    hir_variant_payload_count: wgpu::Buffer,
    hir_variant_payload_owner_a: wgpu::Buffer,
    hir_variant_payload_owner_b: wgpu::Buffer,
    hir_match_scrutinee_node: wgpu::Buffer,
    hir_match_arm_start: wgpu::Buffer,
    hir_match_arm_count: wgpu::Buffer,
    hir_match_arm_next: wgpu::Buffer,
    hir_match_arm_pattern_node: wgpu::Buffer,
    hir_match_arm_payload_start: wgpu::Buffer,
    hir_match_arm_payload_count: wgpu::Buffer,
    hir_match_arm_result_node: wgpu::Buffer,
    hir_struct_decl_field_count: wgpu::Buffer,
    hir_struct_lit_field_parent_lit: wgpu::Buffer,
    hir_struct_lit_field_start: wgpu::Buffer,
    hir_struct_lit_field_count: wgpu::Buffer,
    hir_struct_lit_field_value_node: wgpu::Buffer,
    hir_struct_lit_field_next: wgpu::Buffer,
}

struct OwnedLexerParserInputBuffers {
    source_len: u32,
    in_bytes: wgpu::Buffer,
    tokens_out: wgpu::Buffer,
    token_count: wgpu::Buffer,
    token_file_id: wgpu::Buffer,
}

impl OwnedLexerParserInputBuffers {
    fn from_lexer_buffers(bufs: &LexerBuffers) -> Self {
        Self {
            source_len: bufs.n,
            in_bytes: bufs.in_bytes.buffer.clone(),
            tokens_out: bufs.tokens_out.buffer.clone(),
            token_count: bufs.token_count.buffer.clone(),
            token_file_id: bufs.token_file_id.buffer.clone(),
        }
    }
}

impl OwnedX86ParserBuffers {
    fn from_parser_buffers(bufs: &ParserBuffers) -> Self {
        Self {
            ll1_status: bufs.ll1_status.buffer.clone(),
            tree_active_dispatch_args: bufs.tree_active_dispatch_args.buffer.clone(),
            hir_kind: bufs.hir_kind.buffer.clone(),
            parent: bufs.parent.buffer.clone(),
            first_child: bufs.first_child.buffer.clone(),
            next_sibling: bufs.next_sibling.buffer.clone(),
            subtree_end: bufs.subtree_end.buffer.clone(),
            hir_item_kind: bufs.hir_item_kind.buffer.clone(),
            hir_item_decl_token: bufs.hir_item_decl_token.buffer.clone(),
            hir_item_name_token: bufs.hir_item_name_token.buffer.clone(),
            hir_item_namespace: bufs.hir_item_namespace.buffer.clone(),
            hir_item_visibility: bufs.hir_item_visibility.buffer.clone(),
            hir_item_path_start: bufs.hir_item_path_start.buffer.clone(),
            hir_token_pos: bufs.hir_token_pos.buffer.clone(),
            hir_type_form: bufs.hir_type_form.buffer.clone(),
            hir_type_value_node: bufs.hir_type_value_node.buffer.clone(),
            hir_type_len_token: bufs.hir_type_len_token.buffer.clone(),
            hir_type_len_value: bufs.hir_type_len_value.buffer.clone(),
            hir_type_path_leaf_node: bufs.hir_type_path_leaf_node.buffer.clone(),
            hir_type_path_leaf_link_a: bufs.hir_type_path_leaf_link_a.buffer.clone(),
            hir_type_path_leaf_link_b: bufs.hir_type_path_leaf_link_b.buffer.clone(),
            hir_type_arg_start: bufs.hir_type_arg_start.buffer.clone(),
            hir_type_arg_count: bufs.hir_type_arg_count.buffer.clone(),
            hir_type_arg_next: bufs.hir_type_arg_next.buffer.clone(),
            hir_type_arg_rank_a: bufs.hir_type_arg_rank_a.buffer.clone(),
            hir_type_alias_target_node: bufs.hir_type_alias_target_node.buffer.clone(),
            hir_fn_return_type_node: bufs.hir_fn_return_type_node.buffer.clone(),
            hir_semantic_dense_node: bufs.hir_semantic_dense_node.buffer.clone(),
            hir_param_record: bufs.hir_param_record.buffer.clone(),
            hir_stmt_record: bufs.hir_stmt_record.buffer.clone(),
            hir_expr_record: bufs.hir_expr_record.buffer.clone(),
            hir_expr_int_value: bufs.hir_expr_int_value.buffer.clone(),
            hir_member_receiver_node: bufs.hir_member_receiver_node.buffer.clone(),
            hir_member_name_token: bufs.hir_member_name_token.buffer.clone(),
            hir_call_callee_node: bufs.hir_call_callee_node.buffer.clone(),
            hir_call_arg_start: bufs.hir_call_arg_start.buffer.clone(),
            hir_call_arg_end: bufs.hir_call_arg_end.buffer.clone(),
            hir_call_arg_count: bufs.hir_call_arg_count.buffer.clone(),
            hir_call_arg_parent_call: bufs.hir_call_arg_parent_call.buffer.clone(),
            hir_call_arg_ordinal: bufs.hir_call_arg_ordinal.buffer.clone(),
            hir_array_lit_first_element: bufs.hir_array_lit_first_element.buffer.clone(),
            hir_array_lit_element_count: bufs.hir_array_lit_element_count.buffer.clone(),
            hir_array_element_parent_lit: bufs.hir_array_element_parent_lit.buffer.clone(),
            hir_array_element_ordinal: bufs.hir_array_element_ordinal.buffer.clone(),
            hir_array_element_next: bufs.hir_array_element_next.buffer.clone(),
            hir_array_element_previous: bufs.hir_array_element_previous.buffer.clone(),
            hir_variant_parent_enum: bufs.hir_variant_parent_enum.buffer.clone(),
            hir_variant_ordinal: bufs.hir_variant_ordinal.buffer.clone(),
            hir_variant_payload_count: bufs.hir_variant_payload_count.buffer.clone(),
            hir_variant_payload_owner_a: bufs.hir_variant_payload_owner_a.buffer.clone(),
            hir_variant_payload_owner_b: bufs.hir_variant_payload_owner_b.buffer.clone(),
            hir_match_scrutinee_node: bufs.hir_match_scrutinee_node.buffer.clone(),
            hir_match_arm_start: bufs.hir_match_arm_start.buffer.clone(),
            hir_match_arm_count: bufs.hir_match_arm_count.buffer.clone(),
            hir_match_arm_next: bufs.hir_match_arm_next.buffer.clone(),
            hir_match_arm_pattern_node: bufs.hir_match_arm_pattern_node.buffer.clone(),
            hir_match_arm_payload_start: bufs.hir_match_arm_payload_start.buffer.clone(),
            hir_match_arm_payload_count: bufs.hir_match_arm_payload_count.buffer.clone(),
            hir_match_arm_result_node: bufs.hir_match_arm_result_node.buffer.clone(),
            hir_struct_decl_field_count: bufs.hir_struct_decl_field_count.buffer.clone(),
            hir_struct_lit_field_parent_lit: bufs.hir_struct_lit_field_parent_lit.buffer.clone(),
            hir_struct_lit_field_start: bufs.hir_struct_lit_field_start.buffer.clone(),
            hir_struct_lit_field_count: bufs.hir_struct_lit_field_count.buffer.clone(),
            hir_struct_lit_field_value_node: bufs.hir_struct_lit_field_value_node.buffer.clone(),
            hir_struct_lit_field_next: bufs.hir_struct_lit_field_next.buffer.clone(),
        }
    }
}

#[allow(dead_code)]
struct OwnedTypecheckParserBuffers {
    ll1_status: wgpu::Buffer,
    node_kind: wgpu::Buffer,
    parent: wgpu::Buffer,
    first_child: wgpu::Buffer,
    next_sibling: wgpu::Buffer,
    subtree_end: wgpu::Buffer,
    hir_kind: wgpu::Buffer,
    hir_token_pos: wgpu::Buffer,
    hir_token_end: wgpu::Buffer,
    hir_token_file_id: wgpu::Buffer,
    hir_semantic_count: wgpu::Buffer,
    hir_semantic_dense_node: wgpu::Buffer,
    hir_semantic_parent: wgpu::Buffer,
    hir_semantic_prefix_before_node: wgpu::Buffer,
    hir_type_form: wgpu::Buffer,
    hir_type_value_node: wgpu::Buffer,
    hir_type_len_token: wgpu::Buffer,
    hir_type_len_value: wgpu::Buffer,
    hir_type_path_leaf_node: wgpu::Buffer,
    hir_type_path_leaf_value_a: wgpu::Buffer,
    hir_type_arg_start: wgpu::Buffer,
    hir_type_arg_count: wgpu::Buffer,
    hir_type_arg_next: wgpu::Buffer,
    hir_type_arg_rank_b: wgpu::Buffer,
    hir_type_arg_previous: wgpu::Buffer,
    hir_type_alias_target_node: wgpu::Buffer,
    hir_type_alias_owner_link_a: wgpu::Buffer,
    hir_type_alias_owner_link_b: wgpu::Buffer,
    hir_type_alias_owner_value_a: wgpu::Buffer,
    hir_type_alias_owner_value_b: wgpu::Buffer,
    hir_fn_return_type_node: wgpu::Buffer,
    hir_fn_signature_owner_link_b: wgpu::Buffer,
    hir_fn_signature_function_owner_a: wgpu::Buffer,
    hir_fn_signature_function_owner_b: wgpu::Buffer,
    hir_item_kind: wgpu::Buffer,
    hir_item_name_token: wgpu::Buffer,
    hir_item_namespace: wgpu::Buffer,
    hir_item_visibility: wgpu::Buffer,
    hir_item_path_start: wgpu::Buffer,
    hir_item_path_end: wgpu::Buffer,
    hir_item_file_id: wgpu::Buffer,
    hir_item_import_target_kind: wgpu::Buffer,
    hir_param_record: wgpu::Buffer,
    hir_stmt_record: wgpu::Buffer,
    hir_expr_record: wgpu::Buffer,
    hir_expr_int_value: wgpu::Buffer,
    hir_member_receiver_node: wgpu::Buffer,
    hir_member_receiver_token: wgpu::Buffer,
    hir_member_name_token: wgpu::Buffer,
    hir_call_callee_node: wgpu::Buffer,
    hir_call_arg_start: wgpu::Buffer,
    hir_call_arg_end: wgpu::Buffer,
    hir_call_arg_count: wgpu::Buffer,
    hir_call_arg_parent_call: wgpu::Buffer,
    hir_call_arg_ordinal: wgpu::Buffer,
    hir_call_arg_owner_a: wgpu::Buffer,
    hir_call_arg_owner_b: wgpu::Buffer,
    hir_call_arg_link_a: wgpu::Buffer,
    hir_call_arg_link_b: wgpu::Buffer,
    hir_call_arg_rank_a: wgpu::Buffer,
    hir_call_arg_rank_b: wgpu::Buffer,
    hir_array_lit_first_element: wgpu::Buffer,
    hir_array_lit_element_count: wgpu::Buffer,
    hir_array_element_next: wgpu::Buffer,
    hir_array_element_previous: wgpu::Buffer,
    hir_variant_parent_enum: wgpu::Buffer,
    hir_variant_payload_start: wgpu::Buffer,
    hir_variant_payload_count: wgpu::Buffer,
    hir_variant_rank_a: wgpu::Buffer,
    hir_variant_payload_owner_a: wgpu::Buffer,
    hir_variant_payload_owner_b: wgpu::Buffer,
    hir_variant_payload_link_a: wgpu::Buffer,
    hir_variant_payload_link_b: wgpu::Buffer,
    hir_variant_payload_rank_a: wgpu::Buffer,
    hir_variant_payload_rank_b: wgpu::Buffer,
    hir_match_scrutinee_node: wgpu::Buffer,
    hir_match_arm_start: wgpu::Buffer,
    hir_match_arm_count: wgpu::Buffer,
    hir_match_arm_next: wgpu::Buffer,
    hir_match_arm_pattern_node: wgpu::Buffer,
    hir_match_arm_payload_start: wgpu::Buffer,
    hir_match_arm_payload_count: wgpu::Buffer,
    hir_match_arm_result_node: wgpu::Buffer,
    hir_match_arm_previous: wgpu::Buffer,
    hir_match_payload_owner_arm: wgpu::Buffer,
    hir_match_payload_match_node: wgpu::Buffer,
    hir_match_payload_ordinal: wgpu::Buffer,
    hir_match_rank_node: wgpu::Buffer,
    hir_match_rank_local_prefix: wgpu::Buffer,
    hir_struct_field_parent_struct: wgpu::Buffer,
    hir_struct_field_ordinal: wgpu::Buffer,
    hir_struct_field_type_node: wgpu::Buffer,
    hir_struct_decl_field_start: wgpu::Buffer,
    hir_struct_decl_field_count: wgpu::Buffer,
    hir_struct_lit_head_node: wgpu::Buffer,
    hir_struct_lit_field_start: wgpu::Buffer,
    hir_struct_lit_field_count: wgpu::Buffer,
    hir_struct_lit_field_parent_lit: wgpu::Buffer,
    hir_struct_lit_field_value_node: wgpu::Buffer,
    hir_list_rank_flag: wgpu::Buffer,
    hir_list_rank_node: wgpu::Buffer,
    hir_list_rank_local_prefix: wgpu::Buffer,
    default_token_file_id: wgpu::Buffer,
    out_headers: wgpu::Buffer,
    semantic_token_kinds: wgpu::Buffer,
    token_brace_semantic_kind: wgpu::Buffer,
    token_bracket_semantic_kind: wgpu::Buffer,
    token_statement_context_kind: wgpu::Buffer,
    token_brace_match_depth: wgpu::Buffer,
    token_depth_brace_inblock: wgpu::Buffer,
    token_depth_bracket_inblock: wgpu::Buffer,
    tree_prefix: wgpu::Buffer,
    sc_offsets: wgpu::Buffer,
    emit_offsets: wgpu::Buffer,
    pack_sc_prefix_a: wgpu::Buffer,
    pack_sc_prefix_b: wgpu::Buffer,
    pack_emit_prefix_a: wgpu::Buffer,
    pack_emit_prefix_b: wgpu::Buffer,
    match_for_index: wgpu::Buffer,
}

impl OwnedTypecheckParserBuffers {
    fn from_parser_buffers(bufs: &ParserBuffers) -> Self {
        Self {
            ll1_status: bufs.ll1_status.buffer.clone(),
            node_kind: bufs.node_kind.buffer.clone(),
            parent: bufs.parent.buffer.clone(),
            first_child: bufs.first_child.buffer.clone(),
            next_sibling: bufs.next_sibling.buffer.clone(),
            subtree_end: bufs.subtree_end.buffer.clone(),
            hir_kind: bufs.hir_kind.buffer.clone(),
            hir_token_pos: bufs.hir_token_pos.buffer.clone(),
            hir_token_end: bufs.hir_token_end.buffer.clone(),
            hir_token_file_id: bufs.hir_token_file_id.buffer.clone(),
            hir_semantic_count: bufs.hir_semantic_count.buffer.clone(),
            hir_semantic_dense_node: bufs.hir_semantic_dense_node.buffer.clone(),
            hir_semantic_parent: bufs.hir_semantic_parent.buffer.clone(),
            hir_semantic_prefix_before_node: bufs.hir_semantic_prefix_before_node.buffer.clone(),
            hir_type_form: bufs.hir_type_form.buffer.clone(),
            hir_type_value_node: bufs.hir_type_value_node.buffer.clone(),
            hir_type_len_token: bufs.hir_type_len_token.buffer.clone(),
            hir_type_len_value: bufs.hir_type_len_value.buffer.clone(),
            hir_type_path_leaf_node: bufs.hir_type_path_leaf_node.buffer.clone(),
            hir_type_path_leaf_value_a: bufs.hir_type_path_leaf_value_a.buffer.clone(),
            hir_type_arg_start: bufs.hir_type_arg_start.buffer.clone(),
            hir_type_arg_count: bufs.hir_type_arg_count.buffer.clone(),
            hir_type_arg_next: bufs.hir_type_arg_next.buffer.clone(),
            hir_type_arg_rank_b: bufs.hir_type_arg_rank_b.buffer.clone(),
            hir_type_arg_previous: bufs.hir_type_arg_previous.buffer.clone(),
            hir_type_alias_target_node: bufs.hir_type_alias_target_node.buffer.clone(),
            hir_type_alias_owner_link_a: bufs.hir_type_alias_owner_link_a.buffer.clone(),
            hir_type_alias_owner_link_b: bufs.hir_type_alias_owner_link_b.buffer.clone(),
            hir_type_alias_owner_value_a: bufs.hir_type_alias_owner_value_a.buffer.clone(),
            hir_type_alias_owner_value_b: bufs.hir_type_alias_owner_value_b.buffer.clone(),
            hir_fn_return_type_node: bufs.hir_fn_return_type_node.buffer.clone(),
            hir_fn_signature_owner_link_b: bufs.hir_fn_signature_owner_link_b.buffer.clone(),
            hir_fn_signature_function_owner_a: bufs
                .hir_fn_signature_function_owner_a
                .buffer
                .clone(),
            hir_fn_signature_function_owner_b: bufs
                .hir_fn_signature_function_owner_b
                .buffer
                .clone(),
            hir_item_kind: bufs.hir_item_kind.buffer.clone(),
            hir_item_name_token: bufs.hir_item_name_token.buffer.clone(),
            hir_item_namespace: bufs.hir_item_namespace.buffer.clone(),
            hir_item_visibility: bufs.hir_item_visibility.buffer.clone(),
            hir_item_path_start: bufs.hir_item_path_start.buffer.clone(),
            hir_item_path_end: bufs.hir_item_path_end.buffer.clone(),
            hir_item_file_id: bufs.hir_item_file_id.buffer.clone(),
            hir_item_import_target_kind: bufs.hir_item_import_target_kind.buffer.clone(),
            hir_param_record: bufs.hir_param_record.buffer.clone(),
            hir_stmt_record: bufs.hir_stmt_record.buffer.clone(),
            hir_expr_record: bufs.hir_expr_record.buffer.clone(),
            hir_expr_int_value: bufs.hir_expr_int_value.buffer.clone(),
            hir_member_receiver_node: bufs.hir_member_receiver_node.buffer.clone(),
            hir_member_receiver_token: bufs.hir_member_receiver_token.buffer.clone(),
            hir_member_name_token: bufs.hir_member_name_token.buffer.clone(),
            hir_call_callee_node: bufs.hir_call_callee_node.buffer.clone(),
            hir_call_arg_start: bufs.hir_call_arg_start.buffer.clone(),
            hir_call_arg_end: bufs.hir_call_arg_end.buffer.clone(),
            hir_call_arg_count: bufs.hir_call_arg_count.buffer.clone(),
            hir_call_arg_parent_call: bufs.hir_call_arg_parent_call.buffer.clone(),
            hir_call_arg_ordinal: bufs.hir_call_arg_ordinal.buffer.clone(),
            hir_call_arg_owner_a: bufs.hir_call_arg_owner_a.buffer.clone(),
            hir_call_arg_owner_b: bufs.hir_call_arg_owner_b.buffer.clone(),
            hir_call_arg_link_a: bufs.hir_call_arg_link_a.buffer.clone(),
            hir_call_arg_link_b: bufs.hir_call_arg_link_b.buffer.clone(),
            hir_call_arg_rank_a: bufs.hir_call_arg_rank_a.buffer.clone(),
            hir_call_arg_rank_b: bufs.hir_call_arg_rank_b.buffer.clone(),
            hir_array_lit_first_element: bufs.hir_array_lit_first_element.buffer.clone(),
            hir_array_lit_element_count: bufs.hir_array_lit_element_count.buffer.clone(),
            hir_array_element_next: bufs.hir_array_element_next.buffer.clone(),
            hir_array_element_previous: bufs.hir_array_element_previous.buffer.clone(),
            hir_variant_parent_enum: bufs.hir_variant_parent_enum.buffer.clone(),
            hir_variant_payload_start: bufs.hir_variant_payload_start.buffer.clone(),
            hir_variant_payload_count: bufs.hir_variant_payload_count.buffer.clone(),
            hir_variant_rank_a: bufs.hir_variant_rank_a.buffer.clone(),
            hir_variant_payload_owner_a: bufs.hir_variant_payload_owner_a.buffer.clone(),
            hir_variant_payload_owner_b: bufs.hir_variant_payload_owner_b.buffer.clone(),
            hir_variant_payload_link_a: bufs.hir_variant_payload_link_a.buffer.clone(),
            hir_variant_payload_link_b: bufs.hir_variant_payload_link_b.buffer.clone(),
            hir_variant_payload_rank_a: bufs.hir_variant_payload_rank_a.buffer.clone(),
            hir_variant_payload_rank_b: bufs.hir_variant_payload_rank_b.buffer.clone(),
            hir_match_scrutinee_node: bufs.hir_match_scrutinee_node.buffer.clone(),
            hir_match_arm_start: bufs.hir_match_arm_start.buffer.clone(),
            hir_match_arm_count: bufs.hir_match_arm_count.buffer.clone(),
            hir_match_arm_next: bufs.hir_match_arm_next.buffer.clone(),
            hir_match_arm_pattern_node: bufs.hir_match_arm_pattern_node.buffer.clone(),
            hir_match_arm_payload_start: bufs.hir_match_arm_payload_start.buffer.clone(),
            hir_match_arm_payload_count: bufs.hir_match_arm_payload_count.buffer.clone(),
            hir_match_arm_result_node: bufs.hir_match_arm_result_node.buffer.clone(),
            hir_match_arm_previous: bufs.hir_match_arm_previous.buffer.clone(),
            hir_match_payload_owner_arm: bufs.hir_match_payload_owner_arm.buffer.clone(),
            hir_match_payload_match_node: bufs.hir_match_payload_match_node.buffer.clone(),
            hir_match_payload_ordinal: bufs.hir_match_payload_ordinal.buffer.clone(),
            hir_match_rank_node: bufs.hir_match_rank_node.buffer.clone(),
            hir_match_rank_local_prefix: bufs.hir_match_rank_local_prefix.buffer.clone(),
            hir_struct_field_parent_struct: bufs.hir_struct_field_parent_struct.buffer.clone(),
            hir_struct_field_ordinal: bufs.hir_struct_field_ordinal.buffer.clone(),
            hir_struct_field_type_node: bufs.hir_struct_field_type_node.buffer.clone(),
            hir_struct_decl_field_start: bufs.hir_struct_decl_field_start.buffer.clone(),
            hir_struct_decl_field_count: bufs.hir_struct_decl_field_count.buffer.clone(),
            hir_struct_lit_head_node: bufs.hir_struct_lit_head_node.buffer.clone(),
            hir_struct_lit_field_start: bufs.hir_struct_lit_field_start.buffer.clone(),
            hir_struct_lit_field_count: bufs.hir_struct_lit_field_count.buffer.clone(),
            hir_struct_lit_field_parent_lit: bufs.hir_struct_lit_field_parent_lit.buffer.clone(),
            hir_struct_lit_field_value_node: bufs.hir_struct_lit_field_value_node.buffer.clone(),
            hir_list_rank_flag: bufs.hir_list_rank_flag.buffer.clone(),
            hir_list_rank_node: bufs.hir_list_rank_node.buffer.clone(),
            hir_list_rank_local_prefix: bufs.hir_list_rank_local_prefix.buffer.clone(),
            default_token_file_id: bufs.default_token_file_id.buffer.clone(),
            out_headers: bufs.out_headers.buffer.clone(),
            semantic_token_kinds: bufs.semantic_token_kinds.buffer.clone(),
            token_brace_semantic_kind: bufs.token_brace_semantic_kind.buffer.clone(),
            token_bracket_semantic_kind: bufs.token_bracket_semantic_kind.buffer.clone(),
            token_statement_context_kind: bufs.token_statement_context_kind.buffer.clone(),
            token_brace_match_depth: bufs.token_brace_match_depth.buffer.clone(),
            token_depth_brace_inblock: bufs.token_depth_brace_inblock.buffer.clone(),
            token_depth_bracket_inblock: bufs.token_depth_bracket_inblock.buffer.clone(),
            tree_prefix: bufs.tree_prefix.buffer.clone(),
            sc_offsets: bufs.sc_offsets.buffer.clone(),
            emit_offsets: bufs.emit_offsets.buffer.clone(),
            pack_sc_prefix_a: bufs.pack_sc_prefix_a.buffer.clone(),
            pack_sc_prefix_b: bufs.pack_sc_prefix_b.buffer.clone(),
            pack_emit_prefix_a: bufs.pack_emit_prefix_a.buffer.clone(),
            pack_emit_prefix_b: bufs.pack_emit_prefix_b.buffer.clone(),
            match_for_index: bufs.match_for_index.buffer.clone(),
        }
    }

    fn hir_item_buffers(&self) -> gpu_type_checker::GpuTypeCheckHirItemBuffers<'_> {
        gpu_type_checker::GpuTypeCheckHirItemBuffers {
            node_kind: &self.node_kind,
            parent: &self.parent,
            first_child: &self.first_child,
            next_sibling: &self.next_sibling,
            subtree_end: &self.subtree_end,
            kind: &self.hir_item_kind,
            name_token: &self.hir_item_name_token,
            type_form: &self.hir_type_form,
            type_value_node: &self.hir_type_value_node,
            type_len_token: &self.hir_type_len_token,
            type_len_value: &self.hir_type_len_value,
            type_path_leaf_node: &self.hir_type_path_leaf_node,
            type_arg_start: &self.hir_type_arg_start,
            type_arg_count: &self.hir_type_arg_count,
            type_arg_next: &self.hir_type_arg_next,
            type_alias_target_node: &self.hir_type_alias_target_node,
            fn_return_type_node: &self.hir_fn_return_type_node,
            param_record: &self.hir_param_record,
            expr_record: &self.hir_expr_record,
            expr_int_value: &self.hir_expr_int_value,
            member_receiver_node: &self.hir_member_receiver_node,
            member_receiver_token: &self.hir_member_receiver_token,
            member_name_token: &self.hir_member_name_token,
            stmt_record: &self.hir_stmt_record,
            array_lit_first_element: &self.hir_array_lit_first_element,
            array_lit_element_count: &self.hir_array_lit_element_count,
            array_element_next: &self.hir_array_element_next,
            namespace: &self.hir_item_namespace,
            visibility: &self.hir_item_visibility,
            path_start: &self.hir_item_path_start,
            path_end: &self.hir_item_path_end,
            file_id: &self.hir_item_file_id,
            import_target_kind: &self.hir_item_import_target_kind,
            call_callee_node: &self.hir_call_callee_node,
            call_arg_start: &self.hir_call_arg_start,
            call_arg_end: &self.hir_call_arg_end,
            call_arg_count: &self.hir_call_arg_count,
            call_arg_parent_call: &self.hir_call_arg_parent_call,
            call_arg_ordinal: &self.hir_call_arg_ordinal,
            variant_parent_enum: &self.hir_variant_parent_enum,
            variant_payload_start: &self.hir_variant_payload_start,
            variant_payload_count: &self.hir_variant_payload_count,
            match_scrutinee_node: &self.hir_match_scrutinee_node,
            match_arm_start: &self.hir_match_arm_start,
            match_arm_count: &self.hir_match_arm_count,
            match_arm_next: &self.hir_match_arm_next,
            match_arm_pattern_node: &self.hir_match_arm_pattern_node,
            match_arm_payload_start: &self.hir_match_arm_payload_start,
            match_arm_payload_count: &self.hir_match_arm_payload_count,
            match_arm_result_node: &self.hir_match_arm_result_node,
            match_payload_owner_arm: &self.hir_match_payload_owner_arm,
            match_payload_match_node: &self.hir_match_payload_match_node,
            match_payload_ordinal: &self.hir_match_payload_ordinal,
            struct_field_parent_struct: &self.hir_struct_field_parent_struct,
            struct_field_ordinal: &self.hir_struct_field_ordinal,
            struct_field_type_node: &self.hir_struct_field_type_node,
            struct_decl_field_start: &self.hir_struct_decl_field_start,
            struct_decl_field_count: &self.hir_struct_decl_field_count,
            struct_lit_head_node: &self.hir_struct_lit_head_node,
            struct_lit_field_start: &self.hir_struct_lit_field_start,
            struct_lit_field_count: &self.hir_struct_lit_field_count,
            struct_lit_field_parent_lit: &self.hir_struct_lit_field_parent_lit,
            struct_lit_field_value_node: &self.hir_struct_lit_field_value_node,
            semantic_dense_node: &self.hir_semantic_dense_node,
            semantic_count: &self.hir_semantic_count,
        }
    }
}

impl GpuCompiler<'static> {
    pub async fn new() -> Result<Self, CompileError> {
        Self::new_with_device(device::global()).await
    }
}

impl<'gpu> GpuCompiler<'gpu> {
    pub async fn new_with_device(gpu: &'gpu GpuDevice) -> Result<Self, CompileError> {
        Self::new_with_device_and_backends(gpu, GpuCompilerBackends::all()).await
    }

    pub async fn new_with_device_and_backends(
        gpu: &'gpu GpuDevice,
        backends: GpuCompilerBackends,
    ) -> Result<Self, CompileError> {
        let mut host_timer = CompilerHostTimer::new("compiler.init");
        host_timer.pipeline_cache_size(gpu, "start");
        let lexer = GpuLexer::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU lexer: {err}")))?;
        host_timer.stamp("lexer");
        host_timer.pipeline_cache_size(gpu, "after_lexer");
        let parser = GpuParser::new_with_device(gpu)
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("initialize GPU parser: {err}")))?;
        host_timer.stamp("parser");
        host_timer.pipeline_cache_size(gpu, "after_parser");
        let parse_tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .map_err(|err| {
                    CompileError::GpuFrontend(format!("load GPU parse tables: {err}"))
                })?;
        host_timer.stamp("parse_tables");
        let type_checker =
            gpu_type_checker::GpuTypeChecker::new_with_device(gpu).map_err(|err| {
                CompileError::GpuFrontend(format!("initialize GPU type checker: {err}"))
            })?;
        host_timer.stamp("type_checker");
        host_timer.pipeline_cache_size(gpu, "after_type_checker");
        let wasm_generator = if backends.wasm {
            let generator = wasm::GpuWasmCodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU WASM code generator failed; WASM compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("wasm_generator");
            host_timer.pipeline_cache_size(gpu, "after_wasm_generator");
            generator
        } else {
            host_timer.stamp("wasm_generator.skipped");
            Err("GPU WASM code generator was not initialized for this compiler".into())
        };
        let x86_generator = if backends.x86 {
            let generator = x86::GpuX86CodeGenerator::new_with_device(gpu)
                .map(Box::new)
                .map_err(|err| err.to_string());
            if let Err(err) = &generator {
                log::warn!(
                    "preinitializing GPU x86 code generator failed; x86 compilation will report this error when used: {err}"
                );
            }
            host_timer.stamp("x86_generator");
            host_timer.pipeline_cache_size(gpu, "after_x86_generator");
            generator
        } else {
            host_timer.stamp("x86_generator.skipped");
            Err("GPU x86 code generator was not initialized for this compiler".into())
        };
        Ok(Self {
            gpu,
            lexer,
            parser,
            parse_tables,
            type_checker,
            resident_pipeline_lock: Mutex::new((), false),
            wasm_generator,
            x86_generator,
        })
    }

    pub fn gpu(&self) -> &'gpu GpuDevice {
        self.gpu
    }

    pub async fn type_check_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        self.type_check_expanded_source(&src).await
    }

    pub async fn benchmark_lex_source(&self, src: &str) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens(
                &src,
                |_device, _queue, _bufs, _encoder, _timer| Ok::<_, CompileError>(()),
                |_device, _queue, _bufs, ()| Ok::<_, CompileError>(()),
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex benchmark: {err}")))?
    }

    pub async fn benchmark_live_capacity_estimate(
        &self,
        src: &str,
    ) -> Result<GpuLiveCapacityEstimateResult, CompileError> {
        let parse = self.benchmark_parse_source(src).await?;
        Ok(GpuLiveCapacityEstimateResult {
            token_count: parse.token_count,
            parser_tree_capacity: parse.parser_tree_capacity,
            parser_emit_len: parse.ll1.emit_len,
            semantic_hir_count: parse.semantic_hir_count,
        })
    }

    pub async fn benchmark_parse_source(
        &self,
        src: &str,
    ) -> Result<GpuParseBenchmarkResult, CompileError> {
        let src = prepare_source_for_gpu_type_check(src)?;
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_parser_inputs_after_count_releasing_lexer(
                &src,
                |_, _, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (parser_check, parse_result) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.source_len,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_count = parse_result?;
                    Ok((
                        parser_check,
                        semantic_count,
                        token_count,
                        parser_tree_capacity,
                    ))
                },
                |_,
                 _,
                 _bufs: &ResidentLexerParserInputs,
                 (parser_check, semantic_count, token_count, parser_tree_capacity)| {
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    Ok(GpuParseBenchmarkResult {
                        ll1,
                        token_count,
                        parser_tree_capacity,
                        semantic_hir_count,
                    })
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("parse benchmark: {err}")))?
    }

    pub async fn type_check_source_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<(), CompileError> {
        let src = prepare_source_for_gpu_type_check_from_path(path)?;
        self.type_check_expanded_source(&src).await
    }

    pub async fn type_check_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        self.type_check_explicit_source_pack(sources).await
    }

    async fn type_check_expanded_source(&self, src: &str) -> Result<(), CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok(type_check)
                },
                |device, _queue, _bufs, type_check| {
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    async fn type_check_explicit_source_pack<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<(), CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.typecheck.source_pack.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, parser_recorded) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |_parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                Ok::<_, CompileError>(())
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    parser_recorded?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.typecheck.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok(type_check)
                },
                |device, _queue, type_check| {
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_to_wasm_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_wasm(&src).await
    }

    pub async fn compile_source_pack_to_wasm<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("source_pack.compile.start");
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("source_pack.lex.recorded");
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("source_pack.parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("source_pack.typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    field_parent_struct: &parse_bufs
                                                        .hir_struct_field_parent_struct,
                                                    field_ordinal: &parse_bufs
                                                        .hir_struct_field_ordinal,
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("source_pack.wasm.recorded");
                                Ok::<_, CompileError>((recorded, wasm_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.parser.typecheck.recorded");
                    let (type_check, wasm_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check))
                },
                |device, queue, (parser_check, type_check, wasm_check)| {
                    trace_wasm_compile("source_pack.finish.parser.start");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("source_pack.finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_explicit_source_pack_paths_to_wasm<SP, UP>(
        &self,
        stdlib_paths: &[SP],
        user_paths: &[UP],
    ) -> Result<Vec<u8>, CompileError>
    where
        SP: AsRef<Path>,
        UP: AsRef<Path>,
    {
        let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
        self.compile_source_pack_to_wasm(&sources).await
    }

    async fn compile_expanded_source_to_wasm(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        trace_wasm_compile("compile.start");
        self.lexer
            .with_recorded_resident_tokens_after_count(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    trace_wasm_compile("lex.recorded");
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let (parser_check, type_check) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut timer,
                            |parse_bufs, encoder, timer| {
                                trace_wasm_compile("parser.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                let hir_status = &parse_bufs.ll1_status;
                                let recorded = self
                                    .type_checker
                                    .record_resident_token_buffer_with_hir_items_on_gpu(
                                        device,
                                        queue,
                                        encoder,
                                        bufs.n,
                                        bufs.source_file_start.count as u32,
                                        token_capacity,
                                        &bufs.tokens_out,
                                        &bufs.token_count,
                                        &bufs.token_file_id,
                                        &bufs.in_bytes,
                                        parse_bufs.tree_capacity,
                                        &parse_bufs.hir_kind,
                                        &parse_bufs.hir_token_pos,
                                        &parse_bufs.hir_token_end,
                                        &parse_bufs.hir_token_file_id,
                                        hir_status,
                                        gpu_type_checker::GpuTypeCheckHirItemBuffers {
                                            node_kind: &parse_bufs.node_kind,
                                            parent: &parse_bufs.parent,
                                            first_child: &parse_bufs.first_child,
                                            next_sibling: &parse_bufs.next_sibling,
                                            subtree_end: &parse_bufs.subtree_end,
                                            kind: &parse_bufs.hir_item_kind,
                                            name_token: &parse_bufs.hir_item_name_token,
                                            type_form: &parse_bufs.hir_type_form,
                                            type_value_node: &parse_bufs.hir_type_value_node,
                                            type_len_token: &parse_bufs.hir_type_len_token,
                                            type_len_value: &parse_bufs.hir_type_len_value,
                                            type_path_leaf_node: &parse_bufs
                                                .hir_type_path_leaf_node,
                                            type_arg_start: &parse_bufs.hir_type_arg_start,
                                            type_arg_count: &parse_bufs.hir_type_arg_count,
                                            type_arg_next: &parse_bufs.hir_type_arg_next,
                                            type_alias_target_node: &parse_bufs
                                                .hir_type_alias_target_node,
                                            fn_return_type_node: &parse_bufs
                                                .hir_fn_return_type_node,
                                            param_record: &parse_bufs.hir_param_record,
                                            expr_record: &parse_bufs.hir_expr_record,
                                            expr_int_value: &parse_bufs.hir_expr_int_value,
                                            member_receiver_node: &parse_bufs
                                                .hir_member_receiver_node,
                                            member_receiver_token: &parse_bufs
                                                .hir_member_receiver_token,
                                            member_name_token: &parse_bufs.hir_member_name_token,
                                            stmt_record: &parse_bufs.hir_stmt_record,
                                            array_lit_first_element: &parse_bufs
                                                .hir_array_lit_first_element,
                                            array_lit_element_count: &parse_bufs
                                                .hir_array_lit_element_count,
                                            array_element_next: &parse_bufs.hir_array_element_next,
                                            namespace: &parse_bufs.hir_item_namespace,
                                            visibility: &parse_bufs.hir_item_visibility,
                                            path_start: &parse_bufs.hir_item_path_start,
                                            path_end: &parse_bufs.hir_item_path_end,
                                            file_id: &parse_bufs.hir_item_file_id,
                                            import_target_kind: &parse_bufs
                                                .hir_item_import_target_kind,
                                            call_callee_node: &parse_bufs.hir_call_callee_node,
                                            call_arg_start: &parse_bufs.hir_call_arg_start,
                                            call_arg_end: &parse_bufs.hir_call_arg_end,
                                            call_arg_count: &parse_bufs.hir_call_arg_count,
                                            call_arg_parent_call: &parse_bufs
                                                .hir_call_arg_parent_call,
                                            call_arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                            variant_parent_enum: &parse_bufs
                                                .hir_variant_parent_enum,
                                            variant_payload_start: &parse_bufs
                                                .hir_variant_payload_start,
                                            variant_payload_count: &parse_bufs
                                                .hir_variant_payload_count,
                                            match_scrutinee_node: &parse_bufs
                                                .hir_match_scrutinee_node,
                                            match_arm_start: &parse_bufs.hir_match_arm_start,
                                            match_arm_count: &parse_bufs.hir_match_arm_count,
                                            match_arm_next: &parse_bufs.hir_match_arm_next,
                                            match_arm_pattern_node: &parse_bufs
                                                .hir_match_arm_pattern_node,
                                            match_arm_payload_start: &parse_bufs
                                                .hir_match_arm_payload_start,
                                            match_arm_payload_count: &parse_bufs
                                                .hir_match_arm_payload_count,
                                            match_arm_result_node: &parse_bufs
                                                .hir_match_arm_result_node,
                                            match_payload_owner_arm: &parse_bufs
                                                .hir_match_payload_owner_arm,
                                            match_payload_match_node: &parse_bufs
                                                .hir_match_payload_match_node,
                                            match_payload_ordinal: &parse_bufs
                                                .hir_match_payload_ordinal,
                                            struct_field_parent_struct: &parse_bufs
                                                .hir_struct_field_parent_struct,
                                            struct_field_ordinal: &parse_bufs
                                                .hir_struct_field_ordinal,
                                            struct_field_type_node: &parse_bufs
                                                .hir_struct_field_type_node,
                                            struct_decl_field_start: &parse_bufs
                                                .hir_struct_decl_field_start,
                                            struct_decl_field_count: &parse_bufs
                                                .hir_struct_decl_field_count,
                                            struct_lit_head_node: &parse_bufs
                                                .hir_struct_lit_head_node,
                                            struct_lit_field_start: &parse_bufs
                                                .hir_struct_lit_field_start,
                                            struct_lit_field_count: &parse_bufs
                                                .hir_struct_lit_field_count,
                                            struct_lit_field_parent_lit: &parse_bufs
                                                .hir_struct_lit_field_parent_lit,
                                            struct_lit_field_value_node: &parse_bufs
                                                .hir_struct_lit_field_value_node,
                                            semantic_dense_node: &parse_bufs
                                                .hir_semantic_dense_node,
                                            semantic_count: &parse_bufs.hir_semantic_count,
                                        },
                                        timer.as_deref_mut(),
                                    )
                                    .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                                trace_wasm_compile("typecheck.recorded");
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "typecheck.done");
                                }
                                let wasm_check = self
                                    .type_checker
                                    .with_codegen_buffers(|codegen| {
                                        self.wasm_generator()?
                                            .record_wasm_from_gpu_token_buffer(
                                                device,
                                                queue,
                                                encoder,
                                                bufs.n,
                                                token_capacity,
                                                &bufs.tokens_out,
                                                &bufs.token_count,
                                                &bufs.in_bytes,
                                                parse_bufs.tree_capacity,
                                                &parse_bufs.node_kind,
                                                &parse_bufs.parent,
                                                &parse_bufs.first_child,
                                                &parse_bufs.next_sibling,
                                                &parse_bufs.hir_kind,
                                                &parse_bufs.hir_token_pos,
                                                &parse_bufs.hir_token_end,
                                                hir_status,
                                                codegen.visible_decl,
                                                codegen.visible_type,
                                                codegen.name_id_by_token,
                                                wasm::GpuWasmStructMetadataBuffers {
                                                    field_parent_struct: &parse_bufs
                                                        .hir_struct_field_parent_struct,
                                                    field_ordinal: &parse_bufs
                                                        .hir_struct_field_ordinal,
                                                    lit_field_parent_lit: &parse_bufs
                                                        .hir_struct_lit_field_parent_lit,
                                                },
                                                wasm::GpuWasmEnumMatchMetadataBuffers {
                                                    variant_ordinal: &parse_bufs
                                                        .hir_variant_ordinal,
                                                    match_scrutinee_node: &parse_bufs
                                                        .hir_match_scrutinee_node,
                                                    match_arm_start: &parse_bufs
                                                        .hir_match_arm_start,
                                                    match_arm_count: &parse_bufs
                                                        .hir_match_arm_count,
                                                    match_arm_pattern_node: &parse_bufs
                                                        .hir_match_arm_pattern_node,
                                                    match_arm_payload_start: &parse_bufs
                                                        .hir_match_arm_payload_start,
                                                    match_arm_payload_count: &parse_bufs
                                                        .hir_match_arm_payload_count,
                                                    match_arm_result_node: &parse_bufs
                                                        .hir_match_arm_result_node,
                                                },
                                                wasm::GpuWasmCallMetadataBuffers {
                                                    callee_node: &parse_bufs.hir_call_callee_node,
                                                    arg_start: &parse_bufs.hir_call_arg_start,
                                                    arg_parent_call: &parse_bufs
                                                        .hir_call_arg_parent_call,
                                                    arg_end: &parse_bufs.hir_call_arg_end,
                                                    arg_count: &parse_bufs.hir_call_arg_count,
                                                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                                                },
                                                wasm::GpuWasmExprMetadataBuffers {
                                                    record: &parse_bufs.hir_expr_record,
                                                    int_value: &parse_bufs.hir_expr_int_value,
                                                    stmt_record: &parse_bufs.hir_stmt_record,
                                                },
                                                &parse_bufs.hir_param_record,
                                                codegen.type_expr_ref_tag,
                                                codegen.type_expr_ref_payload,
                                                codegen.module_value_path_call_head,
                                                codegen.module_value_path_call_open,
                                                codegen.module_value_path_const_head,
                                                codegen.module_value_path_const_end,
                                                codegen.call_fn_index,
                                                codegen.call_intrinsic_tag,
                                                codegen.fn_entrypoint_tag,
                                                codegen.call_return_type,
                                                codegen.call_return_type_token,
                                                codegen.call_param_count,
                                                codegen.call_param_type,
                                                codegen.method_decl_receiver_ref_tag,
                                                codegen.method_decl_receiver_ref_payload,
                                                codegen.method_decl_param_offset,
                                                codegen.method_decl_receiver_mode,
                                                codegen.method_call_receiver_ref_tag,
                                                codegen.method_call_receiver_ref_payload,
                                                codegen.type_instance_decl_token,
                                                codegen.type_instance_arg_start,
                                                codegen.type_instance_arg_count,
                                                codegen.type_instance_arg_ref_tag,
                                                codegen.type_instance_arg_ref_payload,
                                                codegen.fn_return_ref_tag,
                                                codegen.fn_return_ref_payload,
                                                codegen.member_result_ref_tag,
                                                codegen.member_result_ref_payload,
                                                codegen.struct_init_field_expected_ref_tag,
                                                codegen.struct_init_field_expected_ref_payload,
                                            )
                                            .map_err(|err| {
                                                CompileError::GpuCodegen(err.to_string())
                                            })
                                    })
                                    .ok_or_else(|| {
                                        CompileError::GpuCodegen(
                                            "GPU type metadata buffers missing".into(),
                                        )
                                    })??;
                                trace_wasm_compile("wasm.recorded");
                                Ok::<_, CompileError>((recorded, wasm_check))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("parser.typecheck.recorded");
                    let (type_check, wasm_check) = type_check?;
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "wasm.codegen.done");
                    }
                    Ok((parser_check, type_check, wasm_check))
                },
                |device, queue, _bufs, (parser_check, type_check, wasm_check)| {
                    trace_wasm_compile("finish.parser.start");
                    self.parser
                        .finish_recorded_resident_ll1_hir_check(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    trace_wasm_compile("finish.typecheck.start");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    trace_wasm_compile("finish.wasm.start");
                    self.wasm_generator()?
                        .finish_recorded_wasm(device, queue, &wasm_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }

    fn wasm_generator(&self) -> Result<&wasm::GpuWasmCodeGenerator, CompileError> {
        trace_wasm_compile("wasm.generator");
        self.wasm_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU WASM code generator: {err}"))
        })
    }

    fn x86_generator(&self) -> Result<&x86::GpuX86CodeGenerator, CompileError> {
        self.x86_generator.as_deref().map_err(|err| {
            CompileError::GpuCodegen(format!("initialize GPU x86 code generator: {err}"))
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn record_x86_from_parse_buffers_with_codegen(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        x86_hir_node_count: u32,
        x86_inst_hir_node_count: u32,
        parse_bufs: &OwnedX86ParserBuffers,
        codegen: gpu_type_checker::GpuX86CodegenBuffers<'_>,
        feature_summary: x86::X86FeatureSummary,
        mut timer: Option<&mut GpuTimer>,
    ) -> Result<x86::RecordedX86Codegen, CompileError> {
        let hir_status = &parse_bufs.ll1_status;
        let external_scratch = Self::x86_external_scratch_from_frontend_and_codegen_buffers(
            parse_bufs,
            codegen,
            token_capacity,
            feature_summary,
        );
        self.x86_generator()?
            .record_x86_elf_from_gpu_hir(
                device,
                queue,
                encoder,
                source_len,
                token_capacity,
                x86_hir_node_count,
                x86_inst_hir_node_count,
                hir_status,
                &parse_bufs.tree_active_dispatch_args,
                &parse_bufs.hir_kind,
                &parse_bufs.parent,
                &parse_bufs.first_child,
                &parse_bufs.next_sibling,
                &parse_bufs.subtree_end,
                x86::GpuX86FunctionMetadataBuffers {
                    node_decl_token: &parse_bufs.hir_item_decl_token,
                    node_name_token: &parse_bufs.hir_item_name_token,
                    hir_token_pos: &parse_bufs.hir_token_pos,
                    fn_return_type_node: &parse_bufs.hir_fn_return_type_node,
                    param_record: &parse_bufs.hir_param_record,
                    enclosing_fn: codegen.enclosing_fn,
                    method_decl_param_offset: codegen.method_decl_param_offset,
                    method_decl_receiver_ref_tag: codegen.method_decl_receiver_ref_tag,
                    method_decl_receiver_ref_payload: codegen.method_decl_receiver_ref_payload,
                },
                x86::GpuX86ExprMetadataBuffers {
                    record: &parse_bufs.hir_expr_record,
                    int_value: &parse_bufs.hir_expr_int_value,
                    stmt_record: &parse_bufs.hir_stmt_record,
                    type_form: &parse_bufs.hir_type_form,
                    type_len_value: &parse_bufs.hir_type_len_value,
                },
                x86::GpuX86CallMetadataBuffers {
                    callee_node: &parse_bufs.hir_call_callee_node,
                    arg_start: &parse_bufs.hir_call_arg_start,
                    arg_end: &parse_bufs.hir_call_arg_end,
                    arg_count: &parse_bufs.hir_call_arg_count,
                    arg_parent_call: &parse_bufs.hir_call_arg_parent_call,
                    arg_ordinal: &parse_bufs.hir_call_arg_ordinal,
                    member_receiver_node: &parse_bufs.hir_member_receiver_node,
                    member_name_token: &parse_bufs.hir_member_name_token,
                    call_fn_index: codegen.call_fn_index,
                    call_intrinsic_tag: codegen.call_intrinsic_tag,
                    call_return_type: codegen.call_return_type,
                    call_return_type_token: codegen.call_return_type_token,
                    call_param_type: codegen.call_param_type,
                },
                x86::GpuX86ArrayMetadataBuffers {
                    lit_first_element: &parse_bufs.hir_array_lit_first_element,
                    lit_element_count: &parse_bufs.hir_array_lit_element_count,
                    element_parent_lit: &parse_bufs.hir_array_element_parent_lit,
                    element_ordinal: &parse_bufs.hir_array_element_ordinal,
                    element_next: &parse_bufs.hir_array_element_next,
                },
                x86::GpuX86EnumMetadataBuffers {
                    item_decl_token: &parse_bufs.hir_item_decl_token,
                    variant_parent_enum: &parse_bufs.hir_variant_parent_enum,
                    variant_ordinal: &parse_bufs.hir_variant_ordinal,
                    variant_payload_count: &parse_bufs.hir_variant_payload_count,
                    match_scrutinee_node: &parse_bufs.hir_match_scrutinee_node,
                    match_arm_start: &parse_bufs.hir_match_arm_start,
                    match_arm_count: &parse_bufs.hir_match_arm_count,
                    match_arm_next: &parse_bufs.hir_match_arm_next,
                    match_arm_pattern_node: &parse_bufs.hir_match_arm_pattern_node,
                    match_arm_payload_start: &parse_bufs.hir_match_arm_payload_start,
                    match_arm_payload_count: &parse_bufs.hir_match_arm_payload_count,
                    match_arm_result_node: &parse_bufs.hir_match_arm_result_node,
                    hir_token_pos: &parse_bufs.hir_token_pos,
                    path_count_out: codegen.path_count_out,
                    path_id_by_owner_hir: codegen.path_id_by_owner_hir,
                    resolved_value_decl: codegen.resolved_value_decl,
                    resolved_value_status: codegen.resolved_value_status,
                    decl_count_out: codegen.decl_count_out,
                    decl_kind: codegen.decl_kind,
                    decl_name_token: codegen.decl_name_token,
                    decl_id_by_name_token: codegen.decl_id_by_name_token,
                    decl_hir_node: codegen.decl_hir_node,
                    decl_parent_type_decl: codegen.decl_parent_type_decl,
                },
                x86::GpuX86StructMetadataBuffers {
                    item_name_token: &parse_bufs.hir_item_name_token,
                    decl_hir_node: codegen.decl_hir_node,
                    struct_decl_field_count: &parse_bufs.hir_struct_decl_field_count,
                    struct_lit_field_parent_lit: &parse_bufs.hir_struct_lit_field_parent_lit,
                    struct_lit_field_start: &parse_bufs.hir_struct_lit_field_start,
                    struct_lit_field_count: &parse_bufs.hir_struct_lit_field_count,
                    struct_lit_field_value_node: &parse_bufs.hir_struct_lit_field_value_node,
                    struct_lit_field_next: &parse_bufs.hir_struct_lit_field_next,
                    member_result_field_ordinal: codegen.member_result_field_ordinal,
                    struct_init_field_ordinal: codegen.struct_init_field_ordinal,
                    struct_init_field_ordinal_by_node: codegen.struct_init_field_ordinal_by_node,
                },
                x86::GpuX86TypeMetadataBuffers {
                    decl_type_ref_tag: codegen.decl_type_ref_tag,
                    decl_type_ref_payload: codegen.decl_type_ref_payload,
                    visible_type: codegen.visible_type,
                    type_instance_kind: codegen.type_instance_kind,
                    type_instance_decl_token: codegen.type_instance_decl_token,
                    type_instance_len_kind: codegen.type_instance_len_kind,
                    type_instance_len_payload: codegen.type_instance_len_payload,
                },
                codegen.visible_decl,
                codegen.fn_entrypoint_tag,
                feature_summary,
                external_scratch,
                timer.as_deref_mut(),
            )
            .map_err(|err| CompileError::GpuCodegen(err.to_string()))
    }

    fn x86_external_scratch_from_frontend_and_codegen_buffers<'a>(
        parse_bufs: &'a OwnedX86ParserBuffers,
        codegen: gpu_type_checker::GpuX86CodegenBuffers<'a>,
        token_capacity: u32,
        feature_summary: x86::X86FeatureSummary,
    ) -> x86::GpuX86ExternalScratchBuffers<'a> {
        // x86 backend recording starts only after typecheck has finished and
        // taken ownership of its codegen metadata. These parser HIR/type
        // workspace rows are not read by the backend input surface; borrowing
        // them here is the explicit arena-lifetime boundary between frontend
        // and backend.
        let token_words = token_capacity.max(1) as usize;
        x86::GpuX86ExternalScratchBuffers {
            expr_resolved_final: None,
            node_func: Some(&parse_bufs.hir_type_value_node),
            func_owner_scan_local_prefix: None,
            func_slot_by_node: Some(&parse_bufs.hir_type_len_token),
            match_pattern_owner: Some(&parse_bufs.hir_type_path_leaf_node),
            match_pattern_node_owner: Some(&parse_bufs.hir_type_arg_start),
            match_pattern_node_variant: Some(&parse_bufs.hir_type_arg_count),
            match_pattern_node_payload_decl: Some(&parse_bufs.hir_type_arg_next),
            match_pattern_first_use_node: Some(&parse_bufs.hir_type_alias_target_node),
            enclosing_let_node_a: None,
            enclosing_let_node_b: Some(&parse_bufs.hir_semantic_dense_node),
            node_inst_same_end_link_a: Some(&parse_bufs.hir_variant_payload_owner_a),
            node_inst_same_end_link_b: Some(&parse_bufs.hir_variant_payload_owner_b),
            node_inst_scan_local_prefix: None,
            call_record: if !feature_summary.has_call() && !feature_summary.has_param() {
                Some(&parse_bufs.hir_param_record)
            } else {
                None
            },
            call_type_record: None,
            node_inst_count_info: Some(codegen.fn_entrypoint_tag),
            node_inst_count_payload: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_range_start: Some(&parse_bufs.hir_type_path_leaf_link_a),
            node_inst_range_info: Some(&parse_bufs.hir_type_path_leaf_link_b),
            node_inst_subtree_bound_start: Some(&parse_bufs.hir_type_arg_rank_a),
            node_inst_subtree_bound_end: Some(&parse_bufs.hir_array_element_previous),
            node_inst_gen_node_record: None,
            decl_layout_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_kind,
                token_words * 4,
            ),
            const_value_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_namespace,
                token_words * 2,
            ),
            param_reg_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_visibility,
                token_words * 5,
            ),
            local_literal_record: buffer_if_wgpu_u32_words(
                &parse_bufs.hir_item_path_start,
                token_words * 3,
            ),
        }
    }

    pub async fn compile_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen(src)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_to_x86_64_from_path(
        &self,
        path: impl AsRef<Path>,
    ) -> Result<Vec<u8>, CompileError> {
        let src = prepare_source_for_gpu_codegen_from_path(path)?;
        self.compile_expanded_source_to_x86_64(&src).await
    }

    pub async fn compile_source_pack_to_x86_64<S: AsRef<str>>(
        &self,
        sources: &[S],
    ) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_source_pack_tokens_after_count(
                sources,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.record");
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("projected_tree_capacity");
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.source_pack.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, semantic_count) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |parse_bufs, encoder, timer| {
                                if let Some(timer) = timer.as_deref_mut() {
                                    timer.stamp(encoder, "parser.ll1_hir.done");
                                }
                                host_timer.stamp("parser_recorded");
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.source_pack.parser-boundary",
                        parser_encoder.finish(),
                    );
                    host_timer.stamp("parser_submitted");
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count?)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    host_timer.stamp("parser_cache_released");
                    let lexer_parse_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(bufs);
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok((
                        type_check,
                        token_count,
                        active_tree_capacity,
                        semantic_hir_count,
                        parser_tree_capacity,
                        lexer_parse_inputs,
                    ))
                },
                |device,
                 queue,
                 (
                    type_check,
                    token_count,
                    active_tree_capacity,
                    semantic_hir_count,
                    parser_tree_capacity,
                    lexer_parse_inputs,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.source_pack.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let mut codegen_buffers =
                        self.type_checker
                            .take_x86_codegen_buffers()
                            .ok_or_else(|| {
                                CompileError::GpuCodegen(
                                    "GPU x86 type metadata buffers missing".into(),
                                )
                            })?;
                    host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                    let token_capacity = token_count.max(1);
                    let x86_hir_node_count = active_tree_capacity.max(1);
                    let x86_inst_hir_node_count = x86_inst_hir_node_count_for_backend_capacity(
                        active_tree_capacity,
                        semantic_hir_count,
                    );
                    codegen_buffers.copy_backend_metadata_before_parser_replay(
                        device,
                        queue,
                        token_capacity.max(x86_hir_node_count),
                    );
                    let mut x86_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.source_pack.backend.encoder"),
                        });
                    let (x86_parse, reparsed_active_tree_capacity, reparsed_semantic_hir_count) =
                        self.reparse_x86_parser_buffers_from_lexer_inputs(
                            device,
                            queue,
                            &lexer_parse_inputs,
                            token_capacity,
                            parser_tree_capacity,
                        )?;
                    if reparsed_active_tree_capacity != active_tree_capacity
                        || reparsed_semantic_hir_count != semantic_hir_count
                    {
                        return Err(CompileError::GpuSyntax(format!(
                            "source-pack backend parser replay changed HIR capacity/count: initial=({active_tree_capacity}, {semantic_hir_count}) replay=({reparsed_active_tree_capacity}, {reparsed_semantic_hir_count})"
                        )));
                    }
                    let feature_summary = self
                        .x86_generator()?
                        .measure_x86_features(
                            device,
                            queue,
                            token_capacity,
                            x86_hir_node_count,
                            &x86_parse.ll1_status,
                            &x86_parse.hir_kind,
                            &x86_parse.hir_stmt_record,
                            &x86_parse.hir_expr_record,
                            &x86_parse.hir_token_pos,
                            &x86_parse.parent,
                            &x86_parse.first_child,
                            codegen_buffers.as_ref().enclosing_fn,
                        )
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                        device,
                        queue,
                        &mut x86_encoder,
                        lexer_parse_inputs.source_len,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        &x86_parse,
                        codegen_buffers.as_ref(),
                        feature_summary,
                        None,
                    )?;
                    host_timer.stamp("x86_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.source_pack.backend",
                        x86_encoder.finish(),
                    );
                    host_timer.stamp("x86_submitted");
                    let result = self
                        .x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source pack: {err}")))?
    }

    pub async fn compile_explicit_source_pack_paths_to_x86_64<SP, UP>(
        &self,
        stdlib_paths: &[SP],
        user_paths: &[UP],
    ) -> Result<Vec<u8>, CompileError>
    where
        SP: AsRef<Path>,
        UP: AsRef<Path>,
    {
        let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
        self.compile_source_pack_to_x86_64(&sources).await
    }

    #[allow(clippy::too_many_arguments)]
    fn record_typecheck_from_parse_buffers(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        source_file_capacity: u32,
        token_capacity: u32,
        lexer_bufs: &crate::lexer::buffers::GpuBuffers,
        parse_bufs: &OwnedTypecheckParserBuffers,
        hir_node_capacity: u32,
        timer: Option<&mut GpuTimer>,
    ) -> Result<gpu_type_checker::RecordedTypeCheck, CompileError> {
        // Typecheck metadata remains live across late module/generic/match
        // passes and is retained for x86 lowering. Keep it in typechecker-owned
        // rows instead of parser scratch so source-pack parser workspaces can
        // be replayed without corrupting semantic records.
        self.type_checker
            .record_resident_token_buffer_with_hir_items_on_gpu(
                device,
                queue,
                encoder,
                source_len,
                source_file_capacity,
                token_capacity,
                &lexer_bufs.tokens_out,
                &lexer_bufs.token_count,
                &lexer_bufs.token_file_id,
                &lexer_bufs.in_bytes,
                hir_node_capacity,
                &parse_bufs.hir_kind,
                &parse_bufs.hir_token_pos,
                &parse_bufs.hir_token_end,
                &parse_bufs.hir_token_file_id,
                &parse_bufs.ll1_status,
                parse_bufs.hir_item_buffers(),
                timer,
            )
            .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))
    }

    #[allow(dead_code)]
    fn typecheck_external_scratch_from_frontend_buffers<'a>(
        lexer_bufs: &'a LexerBuffers,
        parse_bufs: &'a OwnedTypecheckParserBuffers,
    ) -> gpu_type_checker::GpuTypeCheckExternalScratchBuffers<'a> {
        // Typecheck runs after lexing and parser HIR construction, but before
        // x86. Reuse frontend workspaces that are dead at this phase boundary;
        // do not borrow source/token buffers or parser HIR records that are
        // still read by typecheck or x86 lowering.
        gpu_type_checker::GpuTypeCheckExternalScratchBuffers {
            fn_entrypoint_tag: &parse_bufs.tree_prefix,
            // Path byte spans are consumed before type-instance metadata is
            // cleared and collected. Reuse their lexer-backed storage for the
            // type-expression ref rows instead of allocating two more
            // token-sized typecheck buffers.
            type_expr_ref_tag: &lexer_bufs.end_positions.buffer,
            type_expr_ref_payload: &lexer_bufs.types_compact.buffer,
            // Module-path key-radix scratch is consumed before type-instance
            // generic/const-param slot maps are cleared and populated.
            type_generic_param_slot_by_token: &parse_bufs.hir_list_rank_node,
            type_const_param_slot_by_token: &parse_bufs.hir_list_rank_local_prefix,
            record_family_flag: &parse_bufs.hir_type_alias_owner_value_a,
            module_record_prefix: &parse_bufs.hir_type_alias_owner_value_b,
            record_scan_local_prefix: &parse_bufs.hir_type_alias_owner_link_a,
            module_path_key_radix_block_histogram: &parse_bufs.hir_list_rank_local_prefix,
            module_path_key_radix_block_bucket_prefix: &parse_bufs.hir_list_rank_node,
            path_id_by_owner_hir: &parse_bufs.hir_type_alias_owner_link_b,
            decl_module_file_id: &parse_bufs.token_brace_semantic_kind,
            decl_module_id: &parse_bufs.token_bracket_semantic_kind,
            decl_name_id: &parse_bufs.token_statement_context_kind,
            decl_namespace: &parse_bufs.token_brace_match_depth,
            decl_visibility: &parse_bufs.semantic_token_kinds,
            decl_token_start: &parse_bufs.token_depth_brace_inblock,
            decl_token_end: &parse_bufs.token_depth_bracket_inblock,
            decl_key_to_decl_id: &parse_bufs.hir_semantic_prefix_before_node,
            decl_key_order_tmp: &parse_bufs.hir_array_element_previous,
            decl_status: &parse_bufs.out_headers,
            call_param_count: &parse_bufs.hir_type_arg_rank_b,
            call_param_type: &parse_bufs.out_headers,
            call_arg_record: &parse_bufs.hir_match_rank_node,
            function_lookup_key: &parse_bufs.hir_match_rank_local_prefix,
            function_lookup_fn: &parse_bufs.hir_match_arm_previous,
            // Declaration generic-arity counts are live after module-path
            // status scratch is consumed and before method-name token scratch
            // is cleared/filled.
            type_decl_generic_param_count: &parse_bufs.out_headers,
            type_decl_generic_param_count_by_node: &parse_bufs.hir_type_path_leaf_value_a,
            type_instance_head_token: &parse_bufs.default_token_file_id,
            // Module declaration file/end rows are consumed by the upfront
            // module-path pipeline before type-instance argument spans are
            // cleared and collected.
            type_instance_arg_start: &parse_bufs.token_brace_semantic_kind,
            type_instance_arg_count: &parse_bufs.token_depth_bracket_inblock,
            type_instance_arg_ref_tag: &parse_bufs.hir_variant_rank_a,
            type_instance_arg_ref_payload: &parse_bufs.hir_variant_payload_link_a,
            type_instance_elem_ref_tag: &lexer_bufs.dfa_02_ping.buffer,
            type_instance_elem_ref_payload: &lexer_bufs.dfa_02_pong.buffer,
            // Declaration visibility and type-key tables are consumed by the
            // upfront module-path pipeline before type-instance length
            // metadata is cleared and later handed to x86.
            type_instance_len_kind: &parse_bufs.semantic_token_kinds,
            type_instance_len_payload: &lexer_bufs.dfa_chunk_summaries.buffer,
            // Module declaration ids are consumed by the upfront module-path
            // pipeline before the type-instance state row is cleared. The row
            // is typecheck-only and is not handed to x86.
            type_instance_state: &parse_bufs.token_bracket_semantic_kind,
            decl_type_key_to_decl_id: &lexer_bufs.dfa_chunk_summaries.buffer,
            decl_value_key_to_decl_id: &parse_bufs.hir_variant_payload_link_b,
            method_decl_module_id: &parse_bufs.hir_type_alias_owner_value_b,
            method_decl_impl_node: &parse_bufs.hir_type_alias_owner_link_a,
            method_decl_name_token: &parse_bufs.match_for_index,
            method_decl_name_id: &parse_bufs.hir_variant_payload_rank_a,
            method_decl_param_offset: &parse_bufs.hir_semantic_parent,
            method_decl_receiver_mode: &parse_bufs.hir_variant_payload_rank_b,
            method_decl_visibility: &parse_bufs.hir_variant_payload_owner_a,
            method_key_to_fn_token: &parse_bufs.hir_fn_signature_owner_link_b,
            method_key_status: &parse_bufs.hir_match_rank_node,
            method_key_radix_block_histogram: &parse_bufs.hir_fn_signature_function_owner_a,
            method_key_radix_block_bucket_prefix: &parse_bufs.hir_fn_signature_function_owner_b,
            method_call_receiver_ref_tag: &parse_bufs.hir_type_arg_previous,
            method_call_receiver_ref_payload: &parse_bufs.hir_match_rank_local_prefix,
            method_call_name_id: &parse_bufs.hir_variant_payload_owner_b,
            method_call_site_module_id: &parse_bufs.hir_variant_payload_link_b,
            import_visible_type_count: &parse_bufs.hir_variant_payload_rank_a,
            import_visible_value_count: &parse_bufs.hir_variant_payload_rank_b,
            import_visible_type_prefix: &parse_bufs.hir_variant_payload_owner_a,
            import_visible_value_prefix: &parse_bufs.hir_variant_payload_owner_b,
            resolved_type_decl: &lexer_bufs.tok_types.buffer,
            resolved_value_decl: &lexer_bufs.flags_packed.buffer,
            resolved_type_status: &lexer_bufs.s_all_final.buffer,
            resolved_value_status: &lexer_bufs.s_keep_final.buffer,
            // List-ranking workspaces are dead after parser HIR construction
            // and are not borrowed by x86. Use them for retained member/struct
            // type metadata produced after type-instance collection.
            member_result_ref_payload: &parse_bufs.hir_call_arg_owner_a,
            member_result_field_ordinal: &parse_bufs.hir_call_arg_owner_b,
            struct_init_field_expected_ref_tag: &parse_bufs.hir_call_arg_link_a,
            struct_init_field_expected_ref_payload: &parse_bufs.hir_call_arg_link_b,
            struct_init_field_context_instance: &parse_bufs.hir_call_arg_rank_a,
            struct_init_field_ordinal: &parse_bufs.hir_call_arg_rank_b,
            path_start: &lexer_bufs.end_positions.buffer,
            path_len: &lexer_bufs.types_compact.buffer,
            path_segment_count: &lexer_bufs.all_index_compact.buffer,
            path_segment_base: &parse_bufs.sc_offsets,
            path_segment_name_id: &parse_bufs.emit_offsets,
            path_segment_token: &parse_bufs.pack_sc_prefix_a,
            path_owner_hir: &parse_bufs.pack_sc_prefix_b,
            path_owner_token: &parse_bufs.pack_emit_prefix_a,
            path_owner_module_id: &parse_bufs.pack_emit_prefix_b,
            path_kind: &parse_bufs.hir_list_rank_flag,
        }
    }

    fn reparse_x86_parser_buffers_from_lexer_inputs(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        lexer_inputs: &OwnedLexerParserInputBuffers,
        token_capacity: u32,
        parser_tree_capacity: u32,
    ) -> Result<(OwnedX86ParserBuffers, u32, u32), CompileError> {
        let mut parser_encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("compiler.x86.backend-parser-boundary.encoder"),
        });
        let mut parser_timer: Option<&mut GpuTimer> = None;
        let (parser_check, semantic_count) = self
            .parser
            .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                &mut parser_encoder,
                token_capacity,
                &lexer_inputs.tokens_out,
                &lexer_inputs.token_count,
                Some(&lexer_inputs.token_file_id),
                lexer_inputs.source_len,
                &lexer_inputs.in_bytes,
                &self.parse_tables,
                Some(parser_tree_capacity),
                &mut parser_timer,
                |parse_bufs, encoder, timer| {
                    self.parser
                        .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                },
            )
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "compiler.x86.backend-parser-boundary",
            parser_encoder.finish(),
        );
        let ll1 = self
            .parser
            .finish_recorded_resident_ll1_hir_check_result(&parser_check)
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        let semantic_hir_count = self
            .parser
            .finish_recorded_hir_semantic_count(&semantic_count?)
            .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
        let active_tree_capacity =
            hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
        let x86_parse = self
            .parser
            .with_current_resident_buffers_with_tree_capacity(
                token_capacity,
                &self.parse_tables,
                parser_tree_capacity,
                OwnedX86ParserBuffers::from_parser_buffers,
            );
        self.parser.release_current_resident_buffers();
        let _ = device.poll(wgpu::PollType::wait_indefinitely());
        Ok((x86_parse, active_tree_capacity, semantic_hir_count))
    }

    async fn compile_expanded_source_to_x86_64(&self, src: &str) -> Result<Vec<u8>, CompileError> {
        let _resident_guard = self.resident_pipeline_lock.lock().await;
        self.lexer
            .with_recorded_resident_tokens_after_count_releasing_lexer(
                src,
                |device, queue, bufs, token_count, encoder, mut timer| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.record");
                    let token_capacity = token_count.max(1);
                    let parser_tree_capacity = self
                        .parser
                        .read_resident_projected_tree_capacity(
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            &self.parse_tables,
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("projected_tree_capacity");
                    let mut parser_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.parser-boundary.encoder"),
                        });
                    let mut parser_timer: Option<&mut GpuTimer> = None;
                    let (parser_check, semantic_count) = self
                        .parser
                        .record_checked_resident_ll1_hir_artifacts_with_tree_capacity(
                            &mut parser_encoder,
                            token_capacity,
                            &bufs.tokens_out,
                            &bufs.token_count,
                            Some(&bufs.token_file_id),
                            bufs.n,
                            &bufs.in_bytes,
                            &self.parse_tables,
                            Some(parser_tree_capacity),
                            &mut parser_timer,
                            |parse_bufs, encoder, timer| {
                                self.parser
                                    .record_hir_semantic_count_readback(encoder, parse_bufs, timer)
                                    .map_err(|err| CompileError::GpuSyntax(err.to_string()))
                            },
                        )
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    host_timer.stamp("parser_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.parser-boundary",
                        parser_encoder.finish(),
                    );
                    host_timer.stamp("parser_submitted");
                    let ll1 = self
                        .parser
                        .finish_recorded_resident_ll1_hir_check_result(&parser_check)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let semantic_hir_count = self
                        .parser
                        .finish_recorded_hir_semantic_count(&semantic_count?)
                        .map_err(|err| CompileError::GpuSyntax(err.to_string()))?;
                    let active_tree_capacity =
                        hir_node_capacity_for_parser_emit(parser_tree_capacity, ll1.emit_len);
                    host_timer.stamp("parser_finished");
                    let typecheck_parse = self
                        .parser
                        .with_current_resident_buffers_with_tree_capacity(
                            token_capacity,
                            &self.parse_tables,
                            parser_tree_capacity,
                            OwnedTypecheckParserBuffers::from_parser_buffers,
                        );
                    self.parser.release_current_resident_buffers();
                    let _ = device.poll(wgpu::PollType::wait_indefinitely());
                    host_timer.stamp("parser_cache_released");
                    let lexer_parse_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(bufs);
                    let type_check = self.record_typecheck_from_parse_buffers(
                        device,
                        queue,
                        encoder,
                        bufs.n,
                        bufs.source_file_start.count as u32,
                        token_capacity,
                        bufs,
                        &typecheck_parse,
                        active_tree_capacity,
                        timer.as_deref_mut(),
                    )?;
                    host_timer.stamp("typecheck_recorded");
                    if let Some(timer) = timer.as_deref_mut() {
                        timer.stamp(encoder, "typecheck.done");
                    }
                    Ok((
                        type_check,
                        token_count,
                        active_tree_capacity,
                        semantic_hir_count,
                        bufs.n,
                        parser_tree_capacity,
                        lexer_parse_inputs,
                    ))
                },
                |device,
                 queue,
                 (
                    type_check,
                    token_count,
                    active_tree_capacity,
                    semantic_hir_count,
                    source_len,
                    parser_tree_capacity,
                    lexer_parse_inputs,
                )| {
                    let mut host_timer = CompilerHostTimer::new("compiler.x86.finish");
                    self.x86_generator()?;
                    host_timer.stamp("x86_generator_ready");
                    self.type_checker
                        .finish_recorded_check(device, &type_check)
                        .map_err(|err| CompileError::GpuTypeCheck(err.to_string()))?;
                    host_timer.stamp("typecheck_finish");
                    let mut codegen_buffers = self
                        .type_checker
                        .take_x86_codegen_buffers()
                        .ok_or_else(|| {
                            CompileError::GpuCodegen("GPU x86 type metadata buffers missing".into())
                        })?;
                    host_timer.stamp("typecheck_x86_codegen_buffers_retained");
                    let token_capacity = token_count.max(1);
                    let x86_hir_node_count = active_tree_capacity.max(1);
                    let x86_inst_hir_node_count = x86_inst_hir_node_count_for_backend_capacity(
                        active_tree_capacity,
                        semantic_hir_count,
                    );
                    codegen_buffers.copy_backend_metadata_before_parser_replay(
                        device,
                        queue,
                        token_capacity.max(x86_hir_node_count),
                    );
                    let (x86_parse, reparsed_active_tree_capacity, reparsed_semantic_hir_count) =
                        self.reparse_x86_parser_buffers_from_lexer_inputs(
                            device,
                            queue,
                            &lexer_parse_inputs,
                            token_capacity,
                            parser_tree_capacity,
                        )?;
                    if reparsed_active_tree_capacity != active_tree_capacity
                        || reparsed_semantic_hir_count != semantic_hir_count
                    {
                        return Err(CompileError::GpuSyntax(format!(
                            "backend parser replay changed HIR capacity/count: initial=({active_tree_capacity}, {semantic_hir_count}) replay=({reparsed_active_tree_capacity}, {reparsed_semantic_hir_count})"
                        )));
                    }
                    let mut x86_encoder =
                        device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
                            label: Some("compiler.x86.backend.encoder"),
                        });
                    let feature_summary = self
                        .x86_generator()?
                        .measure_x86_features(
                            device,
                            queue,
                            token_capacity,
                            x86_hir_node_count,
                            &x86_parse.ll1_status,
                            &x86_parse.hir_kind,
                            &x86_parse.hir_stmt_record,
                            &x86_parse.hir_expr_record,
                            &x86_parse.hir_token_pos,
                            &x86_parse.parent,
                            &x86_parse.first_child,
                            codegen_buffers.as_ref().enclosing_fn,
                        )
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()))?;
                    let x86_check = self.record_x86_from_parse_buffers_with_codegen(
                        device,
                        queue,
                        &mut x86_encoder,
                        source_len,
                        token_capacity,
                        x86_hir_node_count,
                        x86_inst_hir_node_count,
                        &x86_parse,
                        codegen_buffers.as_ref(),
                        feature_summary,
                        None,
                    )?;
                    host_timer.stamp("x86_recorded");
                    crate::gpu::passes_core::submit_with_progress(
                        queue,
                        "compiler.x86.backend",
                        x86_encoder.finish(),
                    );
                    host_timer.stamp("x86_submitted");
                    let result = self
                        .x86_generator()?
                        .finish_recorded_x86(device, queue, &x86_check)
                        .map_err(|err| CompileError::GpuCodegen(err.to_string()));
                    host_timer.stamp("x86_finish");
                    result
                },
            )
            .await
            .map_err(|err| CompileError::GpuFrontend(format!("lex source: {err}")))?
    }
}

fn x86_inst_hir_node_count_for_backend_capacity(
    parser_tree_capacity: u32,
    semantic_hir_count: u32,
) -> u32 {
    semantic_hir_count.max(1).min(parser_tree_capacity.max(1))
}

fn buffer_if_wgpu_u32_words(buffer: &wgpu::Buffer, words: usize) -> Option<&wgpu::Buffer> {
    (buffer.size() >= words.saturating_mul(4) as u64).then_some(buffer)
}

fn hir_node_capacity_for_parser_emit(parser_tree_capacity: u32, parser_emit_len: u32) -> u32 {
    parser_emit_len.max(1).min(parser_tree_capacity.max(1))
}

fn trace_wasm_compile(stage: &str) {
    if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
        eprintln!("[laniusc][wasm] {stage}");
    }
}

struct CompilerHostTimer {
    label: &'static str,
    print_enabled: bool,
    trace_enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl CompilerHostTimer {
    fn new(label: &'static str) -> Self {
        let now = std::time::Instant::now();
        Self {
            label,
            print_enabled: crate::gpu::env::env_bool_truthy(
                "LANIUS_GPU_COMPILE_HOST_TIMING",
                false,
            ),
            trace_enabled: crate::gpu::trace::enabled(),
            start: now,
            last: now,
        }
    }

    fn stamp(&mut self, stage: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let name = format!("{}.{stage}", self.label);
        if self.print_enabled {
            println!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.compiler", &name, self.last, now);
        }
        self.last = now;
    }

    fn pipeline_cache_size(&self, gpu: &GpuDevice, stage: &str) {
        if !crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_BREAKDOWN", false) {
            return;
        }
        let start = std::time::Instant::now();
        let size = gpu.pipeline_cache_data_len();
        let end = std::time::Instant::now();
        let sample_ms = end.duration_since(start).as_secs_f64() * 1000.0;
        match size {
            Some(bytes) => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes={bytes} sample_ms={sample_ms:.3}"
                );
                if self.trace_enabled {
                    crate::gpu::trace::record_host_span(
                        "host.pipeline_cache",
                        &format!("pipeline_cache.sample.{stage}"),
                        start,
                        end,
                    );
                    crate::gpu::trace::record_counter(
                        "host.pipeline_cache.size",
                        "pipeline_cache_bytes",
                        end,
                        bytes as f64,
                    );
                }
            }
            None => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes=unavailable sample_ms={sample_ms:.3}"
                );
            }
        }
    }
}

fn prepare_source_for_gpu(src: &str) -> Result<String, CompileError> {
    Ok(src.to_string())
}

fn prepare_source_for_gpu_from_path(path: impl AsRef<Path>) -> Result<String, CompileError> {
    fs::read_to_string(path.as_ref()).map_err(|err| {
        CompileError::GpuFrontend(format!("read {}: {err}", path.as_ref().display()))
    })
}

pub fn load_explicit_source_pack_from_paths<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<String>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let mut sources = Vec::with_capacity(stdlib_paths.len() + user_paths.len());
    read_explicit_source_paths("stdlib", stdlib_paths, &mut sources)?;
    read_explicit_source_paths("user", user_paths, &mut sources)?;
    if sources.is_empty() {
        return Err(CompileError::GpuFrontend(
            "explicit source pack has no source files".to_string(),
        ));
    }
    Ok(sources)
}

fn read_explicit_source_paths<P: AsRef<Path>>(
    label: &str,
    paths: &[P],
    sources: &mut Vec<String>,
) -> Result<(), CompileError> {
    for (i, path) in paths.iter().enumerate() {
        let path = path.as_ref();
        let source = fs::read_to_string(path).map_err(|err| {
            CompileError::GpuFrontend(format!(
                "read explicit {label} source file {i} ({}): {err}",
                path.display()
            ))
        })?;
        sources.push(source);
    }
    Ok(())
}

fn prepare_source_for_gpu_codegen(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn prepare_source_for_gpu_type_check(src: &str) -> Result<String, CompileError> {
    prepare_source_for_gpu(src)
}

fn prepare_source_for_gpu_type_check_from_path(
    path: impl AsRef<Path>,
) -> Result<String, CompileError> {
    prepare_source_for_gpu_from_path(path)
}

fn global_gpu_compiler_for(
    compiler: &'static OnceLock<Result<GpuCompiler<'static>, String>>,
    backends: GpuCompilerBackends,
    label: &'static str,
) -> Result<&'static GpuCompiler<'static>, CompileError> {
    compiler
        .get_or_init(|| {
            pollster::block_on(GpuCompiler::new_with_device_and_backends(
                device::global(),
                backends,
            ))
            .map_err(|err| err.to_string())
        })
        .as_ref()
        .map_err(|err| CompileError::GpuFrontend(format!("initialize {label} GPU compiler: {err}")))
}

fn global_frontend_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_FRONTEND_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(
        &GPU_FRONTEND_COMPILER,
        GpuCompilerBackends::frontend_only(),
        "frontend",
    )
}

fn global_wasm_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_WASM_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_WASM_COMPILER, GpuCompilerBackends::wasm_only(), "WASM")
}

fn global_x86_gpu_compiler() -> Result<&'static GpuCompiler<'static>, CompileError> {
    static GPU_X86_COMPILER: OnceLock<Result<GpuCompiler<'static>, String>> = OnceLock::new();
    global_gpu_compiler_for(&GPU_X86_COMPILER, GpuCompilerBackends::x86_only(), "x86")
}

pub async fn compile_source_to_wasm_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn type_check_source_with_gpu(src: &str) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_pack_with_gpu<S: AsRef<str>>(
    sources: &[S],
) -> Result<(), CompileError> {
    global_frontend_gpu_compiler()?
        .type_check_explicit_source_pack(sources)
        .await
}

pub async fn type_check_source_with_gpu_from_path(
    path: impl AsRef<Path>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    global_frontend_gpu_compiler()?
        .type_check_expanded_source(&src)
        .await
}

pub async fn type_check_source_with_gpu_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check(src)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn type_check_source_pack_with_gpu_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    compiler.type_check_explicit_source_pack(sources).await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(sources)
        .await
}

pub async fn compile_source_pack_to_wasm_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_wasm(sources).await
}

pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
    global_wasm_gpu_compiler()?
        .compile_source_pack_to_wasm(&sources)
        .await
}

pub async fn compile_explicit_source_pack_paths_to_wasm_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_to_wasm(stdlib_paths, user_paths)
        .await
}

pub async fn type_check_source_with_gpu_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<(), CompileError> {
    let src = prepare_source_for_gpu_type_check_from_path(path)?;
    compiler.type_check_expanded_source(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_wasm_gpu_compiler()?
        .compile_expanded_source_to_wasm(&src)
        .await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_wasm_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_wasm(&src).await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen(src: &str) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_from_path(
    path: impl AsRef<Path>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    global_x86_gpu_compiler()?
        .compile_expanded_source_to_x86_64(&src)
        .await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen<S: AsRef<str>>(
    sources: &[S],
) -> Result<Vec<u8>, CompileError> {
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(sources)
        .await
}

pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    let sources = load_explicit_source_pack_from_paths(stdlib_paths, user_paths)?;
    global_x86_gpu_compiler()?
        .compile_source_pack_to_x86_64(&sources)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using(
    src: &str,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen(src)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

pub async fn compile_source_pack_to_x86_64_with_gpu_codegen_using<S: AsRef<str>>(
    sources: &[S],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    compiler.compile_source_pack_to_x86_64(sources).await
}

pub async fn compile_explicit_source_pack_paths_to_x86_64_with_gpu_codegen_using<SP, UP>(
    stdlib_paths: &[SP],
    user_paths: &[UP],
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError>
where
    SP: AsRef<Path>,
    UP: AsRef<Path>,
{
    compiler
        .compile_explicit_source_pack_paths_to_x86_64(stdlib_paths, user_paths)
        .await
}

pub async fn compile_source_to_x86_64_with_gpu_codegen_using_path(
    path: impl AsRef<Path>,
    compiler: &GpuCompiler<'_>,
) -> Result<Vec<u8>, CompileError> {
    let src = prepare_source_for_gpu_codegen_from_path(path)?;
    compiler.compile_expanded_source_to_x86_64(&src).await
}

#[cfg(test)]
mod tests {
    use std::{
        collections::hash_map::DefaultHasher,
        hash::{Hash, Hasher},
    };

    use super::*;

    fn buffer_id(buffer: &wgpu::Buffer) -> u64 {
        let mut hasher = DefaultHasher::new();
        buffer.hash(&mut hasher);
        hasher.finish()
    }

    fn assert_distinct_from(buffer: &wgpu::Buffer, protected: &[&wgpu::Buffer]) {
        let id = buffer_id(buffer);
        for protected_buffer in protected {
            assert_ne!(id, buffer_id(protected_buffer));
        }
    }

    fn resident_parser_buffers_for_scratch_tests() -> ParserBuffers {
        let tables =
            PrecomputedParseTables::load_bin_bytes(include_bytes!("../tables/parse_tables.bin"))
                .expect("parse tables");
        let action_table = tables.to_action_header_grid_bytes();
        ParserBuffers::new_resident_capacity_with_tree_capacity(
            device::global().device.as_ref(),
            8,
            tables.n_kinds,
            &action_table,
            &tables,
            Some(64),
        )
    }

    fn resident_lexer_buffers_for_scratch_tests() -> LexerBuffers {
        let token_map = vec![0u32; crate::lexer::tables::dfa::N_STATES];
        let next_emit_words = vec![0u32; (256 * crate::lexer::tables::dfa::N_STATES).div_ceil(2)];
        let next_u8_words = vec![0u32; 256 * crate::lexer::tables::dfa::N_STATES.div_ceil(4)];
        LexerBuffers::new(
            device::global().device.as_ref(),
            128,
            1,
            0,
            &next_emit_words,
            &next_u8_words,
            &token_map,
            [u32::MAX; 4],
        )
    }

    fn scratch_u32_buffer(label: &str, words: usize) -> wgpu::Buffer {
        device::global()
            .device
            .create_buffer(&wgpu::BufferDescriptor {
                label: Some(label),
                size: (words.max(1) * 4) as u64,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC,
                mapped_at_creation: false,
            })
    }

    #[test]
    fn x86_inst_capacity_uses_semantic_hir_count() {
        assert_eq!(
            x86_inst_hir_node_count_for_backend_capacity(17_164_633, 14_614_800),
            14_614_800
        );
    }

    #[test]
    fn x86_inst_capacity_stays_within_parser_storage() {
        assert_eq!(x86_inst_hir_node_count_for_backend_capacity(128, 256), 128);
        assert_eq!(x86_inst_hir_node_count_for_backend_capacity(0, 0), 1);
    }

    #[test]
    fn x86_split_typecheck_capacity_uses_parser_emit_len() {
        assert_eq!(
            hir_node_capacity_for_parser_emit(17_164_633, 3_650_001),
            3_650_001
        );
        assert_eq!(hir_node_capacity_for_parser_emit(128, 256), 128);
        assert_eq!(hir_node_capacity_for_parser_emit(0, 0), 1);
    }

    #[test]
    fn x86_backend_parser_replay_handoff_keeps_only_lexer_inputs() {
        let lexer_bufs = resident_lexer_buffers_for_scratch_tests();
        let parser_bufs = resident_parser_buffers_for_scratch_tests();
        let replay_inputs = OwnedLexerParserInputBuffers::from_lexer_buffers(&lexer_bufs);

        assert_eq!(replay_inputs.source_len, lexer_bufs.n);
        assert_eq!(
            buffer_id(&replay_inputs.in_bytes),
            buffer_id(&lexer_bufs.in_bytes.buffer)
        );
        assert_eq!(
            buffer_id(&replay_inputs.tokens_out),
            buffer_id(&lexer_bufs.tokens_out.buffer)
        );
        assert_eq!(
            buffer_id(&replay_inputs.token_count),
            buffer_id(&lexer_bufs.token_count.buffer)
        );
        assert_eq!(
            buffer_id(&replay_inputs.token_file_id),
            buffer_id(&lexer_bufs.token_file_id.buffer)
        );

        let first_parse_hir_outputs = [
            &parser_bufs.ll1_status.buffer,
            &parser_bufs.hir_kind.buffer,
            &parser_bufs.parent.buffer,
            &parser_bufs.first_child.buffer,
            &parser_bufs.next_sibling.buffer,
            &parser_bufs.subtree_end.buffer,
            &parser_bufs.hir_token_pos.buffer,
            &parser_bufs.hir_expr_record.buffer,
            &parser_bufs.hir_stmt_record.buffer,
        ];
        for replay_input in [
            &replay_inputs.in_bytes,
            &replay_inputs.tokens_out,
            &replay_inputs.token_count,
            &replay_inputs.token_file_id,
        ] {
            assert_distinct_from(replay_input, &first_parse_hir_outputs);
        }
    }

    #[test]
    fn compiler_cross_phase_scratch_uses_dead_frontend_workspaces() {
        let lexer_bufs = resident_lexer_buffers_for_scratch_tests();
        let bufs = resident_parser_buffers_for_scratch_tests();
        let typecheck_parse = OwnedTypecheckParserBuffers::from_parser_buffers(&bufs);
        let typecheck_scratch = GpuCompiler::typecheck_external_scratch_from_frontend_buffers(
            &lexer_bufs,
            &typecheck_parse,
        );

        assert_eq!(
            buffer_id(typecheck_scratch.fn_entrypoint_tag),
            buffer_id(&bufs.tree_prefix.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_expr_ref_tag),
            buffer_id(&lexer_bufs.end_positions.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_expr_ref_payload),
            buffer_id(&lexer_bufs.types_compact.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_generic_param_slot_by_token),
            buffer_id(&bufs.hir_list_rank_node.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_const_param_slot_by_token),
            buffer_id(&bufs.hir_list_rank_local_prefix.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.record_family_flag),
            buffer_id(&bufs.hir_type_alias_owner_value_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.module_record_prefix),
            buffer_id(&bufs.hir_type_alias_owner_value_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.record_scan_local_prefix),
            buffer_id(&bufs.hir_type_alias_owner_link_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.module_path_key_radix_block_histogram),
            buffer_id(&bufs.hir_list_rank_local_prefix.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.module_path_key_radix_block_bucket_prefix),
            buffer_id(&bufs.hir_list_rank_node.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_generic_param_slot_by_token),
            buffer_id(typecheck_scratch.module_path_key_radix_block_bucket_prefix)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_const_param_slot_by_token),
            buffer_id(typecheck_scratch.module_path_key_radix_block_histogram)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_id_by_owner_hir),
            buffer_id(&bufs.hir_type_alias_owner_link_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_module_file_id),
            buffer_id(&bufs.token_brace_semantic_kind.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_module_id),
            buffer_id(&bufs.token_bracket_semantic_kind.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_name_id),
            buffer_id(&bufs.token_statement_context_kind.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_namespace),
            buffer_id(&bufs.token_brace_match_depth.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_visibility),
            buffer_id(&bufs.semantic_token_kinds.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_token_start),
            buffer_id(&bufs.token_depth_brace_inblock.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_token_end),
            buffer_id(&bufs.token_depth_bracket_inblock.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_key_to_decl_id),
            buffer_id(&bufs.hir_semantic_prefix_before_node.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_key_order_tmp),
            buffer_id(&bufs.hir_array_element_previous.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_status),
            buffer_id(&bufs.out_headers.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.call_param_count),
            buffer_id(&bufs.hir_type_arg_rank_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.call_arg_record),
            buffer_id(&bufs.hir_match_rank_node.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.function_lookup_key),
            buffer_id(&bufs.hir_match_rank_local_prefix.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.function_lookup_fn),
            buffer_id(&bufs.hir_match_arm_previous.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_decl_generic_param_count),
            buffer_id(&bufs.out_headers.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_decl_generic_param_count_by_node),
            buffer_id(&bufs.hir_type_path_leaf_value_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_head_token),
            buffer_id(&bufs.default_token_file_id.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_start),
            buffer_id(&bufs.token_brace_semantic_kind.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_count),
            buffer_id(&bufs.token_depth_bracket_inblock.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_start),
            buffer_id(typecheck_scratch.decl_module_file_id)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_count),
            buffer_id(typecheck_scratch.decl_token_end)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_ref_tag),
            buffer_id(&bufs.hir_variant_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_arg_ref_payload),
            buffer_id(&bufs.hir_variant_payload_link_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_elem_ref_tag),
            buffer_id(&lexer_bufs.dfa_02_ping.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_elem_ref_payload),
            buffer_id(&lexer_bufs.dfa_02_pong.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_len_kind),
            buffer_id(&bufs.semantic_token_kinds.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_len_payload),
            buffer_id(&lexer_bufs.dfa_chunk_summaries.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_len_kind),
            buffer_id(typecheck_scratch.decl_visibility)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_len_payload),
            buffer_id(typecheck_scratch.decl_type_key_to_decl_id)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_state),
            buffer_id(&bufs.token_bracket_semantic_kind.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_instance_state),
            buffer_id(typecheck_scratch.decl_module_id)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_type_key_to_decl_id),
            buffer_id(&lexer_bufs.dfa_chunk_summaries.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.decl_value_key_to_decl_id),
            buffer_id(&bufs.hir_variant_payload_link_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_module_id),
            buffer_id(&bufs.hir_type_alias_owner_value_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_impl_node),
            buffer_id(&bufs.hir_type_alias_owner_link_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_name_token),
            buffer_id(&bufs.match_for_index.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.call_param_type),
            buffer_id(&bufs.out_headers.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_decl_generic_param_count),
            buffer_id(typecheck_scratch.decl_status)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.type_decl_generic_param_count),
            buffer_id(typecheck_scratch.call_param_type)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_name_id),
            buffer_id(&bufs.hir_variant_payload_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_param_offset),
            buffer_id(&bufs.hir_semantic_parent.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_receiver_mode),
            buffer_id(&bufs.hir_variant_payload_rank_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_decl_visibility),
            buffer_id(&bufs.hir_variant_payload_owner_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_key_to_fn_token),
            buffer_id(&bufs.hir_fn_signature_owner_link_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_key_status),
            buffer_id(&bufs.hir_match_rank_node.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_key_radix_block_histogram),
            buffer_id(&bufs.hir_fn_signature_function_owner_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_key_radix_block_bucket_prefix),
            buffer_id(&bufs.hir_fn_signature_function_owner_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_call_receiver_ref_tag),
            buffer_id(&bufs.hir_type_arg_previous.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_call_receiver_ref_payload),
            buffer_id(&bufs.hir_match_rank_local_prefix.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_call_name_id),
            buffer_id(&bufs.hir_variant_payload_owner_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.method_call_site_module_id),
            buffer_id(&bufs.hir_variant_payload_link_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.import_visible_type_count),
            buffer_id(&bufs.hir_variant_payload_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.import_visible_value_count),
            buffer_id(&bufs.hir_variant_payload_rank_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.import_visible_type_prefix),
            buffer_id(&bufs.hir_variant_payload_owner_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.import_visible_value_prefix),
            buffer_id(&bufs.hir_variant_payload_owner_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.resolved_type_decl),
            buffer_id(&lexer_bufs.tok_types.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.resolved_value_decl),
            buffer_id(&lexer_bufs.flags_packed.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.resolved_type_status),
            buffer_id(&lexer_bufs.s_all_final.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.resolved_value_status),
            buffer_id(&lexer_bufs.s_keep_final.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.member_result_ref_payload),
            buffer_id(&bufs.hir_call_arg_owner_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.member_result_field_ordinal),
            buffer_id(&bufs.hir_call_arg_owner_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.struct_init_field_expected_ref_tag),
            buffer_id(&bufs.hir_call_arg_link_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.struct_init_field_expected_ref_payload),
            buffer_id(&bufs.hir_call_arg_link_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.struct_init_field_context_instance),
            buffer_id(&bufs.hir_call_arg_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.struct_init_field_ordinal),
            buffer_id(&bufs.hir_call_arg_rank_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_start),
            buffer_id(&lexer_bufs.end_positions.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_len),
            buffer_id(&lexer_bufs.types_compact.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_segment_count),
            buffer_id(&lexer_bufs.all_index_compact.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_segment_base),
            buffer_id(&bufs.sc_offsets.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_segment_name_id),
            buffer_id(&bufs.emit_offsets.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_segment_token),
            buffer_id(&bufs.pack_sc_prefix_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_owner_hir),
            buffer_id(&bufs.pack_sc_prefix_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_owner_token),
            buffer_id(&bufs.pack_emit_prefix_a.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_owner_module_id),
            buffer_id(&bufs.pack_emit_prefix_b.buffer)
        );
        assert_eq!(
            buffer_id(typecheck_scratch.path_kind),
            buffer_id(&bufs.hir_list_rank_flag.buffer)
        );

        let typecheck_hir_inputs = [
            &lexer_bufs.in_bytes.buffer,
            &lexer_bufs.tokens_out.buffer,
            &lexer_bufs.token_count.buffer,
            &lexer_bufs.token_file_id.buffer,
            &bufs.hir_kind.buffer,
            &bufs.hir_token_pos.buffer,
            &bufs.hir_token_end.buffer,
            &bufs.hir_token_file_id.buffer,
            &bufs.ll1_status.buffer,
            &bufs.node_kind.buffer,
            &bufs.parent.buffer,
            &bufs.first_child.buffer,
            &bufs.next_sibling.buffer,
            &bufs.subtree_end.buffer,
            &bufs.hir_type_path_leaf_node.buffer,
            &bufs.hir_type_arg_start.buffer,
            &bufs.hir_type_arg_count.buffer,
            &bufs.hir_type_arg_next.buffer,
            &bufs.hir_type_alias_target_node.buffer,
            &bufs.hir_fn_return_type_node.buffer,
        ];
        let typecheck_record_bytes = bufs.n_tokens.saturating_sub(2).max(1).saturating_mul(4);
        assert_distinct_from(typecheck_scratch.fn_entrypoint_tag, &typecheck_hir_inputs);
        assert_distinct_from(typecheck_scratch.type_expr_ref_tag, &typecheck_hir_inputs);
        assert_distinct_from(
            typecheck_scratch.type_expr_ref_payload,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_generic_param_slot_by_token,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_const_param_slot_by_token,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(typecheck_scratch.record_family_flag, &typecheck_hir_inputs);
        assert_distinct_from(
            typecheck_scratch.module_record_prefix,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.record_scan_local_prefix,
            &typecheck_hir_inputs,
        );
        for scratch in [
            typecheck_scratch.module_path_key_radix_block_histogram,
            typecheck_scratch.module_path_key_radix_block_bucket_prefix,
            typecheck_scratch.decl_module_file_id,
            typecheck_scratch.decl_module_id,
            typecheck_scratch.decl_name_id,
            typecheck_scratch.decl_namespace,
            typecheck_scratch.decl_visibility,
            typecheck_scratch.decl_token_start,
            typecheck_scratch.decl_token_end,
            typecheck_scratch.decl_key_to_decl_id,
            typecheck_scratch.decl_key_order_tmp,
            typecheck_scratch.decl_status,
        ] {
            assert_distinct_from(scratch, &typecheck_hir_inputs);
            assert!(scratch.size() >= typecheck_record_bytes as u64);
        }
        assert_distinct_from(
            typecheck_scratch.path_id_by_owner_hir,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_decl_generic_param_count,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_decl_generic_param_count_by_node,
            &typecheck_hir_inputs,
        );
        for scratch in [
            typecheck_scratch.call_param_count,
            typecheck_scratch.call_arg_record,
            typecheck_scratch.function_lookup_key,
            typecheck_scratch.function_lookup_fn,
        ] {
            assert_distinct_from(scratch, &typecheck_hir_inputs);
        }
        let call_workspace_ids = [
            buffer_id(typecheck_scratch.call_param_count),
            buffer_id(typecheck_scratch.call_arg_record),
            buffer_id(typecheck_scratch.function_lookup_key),
            buffer_id(typecheck_scratch.function_lookup_fn),
        ];
        for i in 0..call_workspace_ids.len() {
            for j in i + 1..call_workspace_ids.len() {
                assert_ne!(call_workspace_ids[i], call_workspace_ids[j]);
            }
        }
        assert_distinct_from(
            typecheck_scratch.type_instance_head_token,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_arg_start,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_arg_count,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_arg_ref_payload,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_arg_ref_tag,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_elem_ref_tag,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.type_instance_elem_ref_payload,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.decl_value_key_to_decl_id,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.decl_type_key_to_decl_id,
            &typecheck_hir_inputs,
        );
        for scratch in [
            typecheck_scratch.method_decl_module_id,
            typecheck_scratch.method_decl_impl_node,
            typecheck_scratch.method_decl_name_token,
            typecheck_scratch.method_decl_name_id,
            typecheck_scratch.method_decl_param_offset,
            typecheck_scratch.method_decl_receiver_mode,
            typecheck_scratch.method_decl_visibility,
            typecheck_scratch.method_key_to_fn_token,
            typecheck_scratch.method_key_status,
            typecheck_scratch.method_key_radix_block_histogram,
            typecheck_scratch.method_key_radix_block_bucket_prefix,
            typecheck_scratch.method_call_receiver_ref_tag,
            typecheck_scratch.method_call_receiver_ref_payload,
            typecheck_scratch.method_call_name_id,
            typecheck_scratch.method_call_site_module_id,
        ] {
            assert_distinct_from(scratch, &typecheck_hir_inputs);
        }
        let method_clear_scratch_ids = [
            buffer_id(typecheck_scratch.method_decl_module_id),
            buffer_id(typecheck_scratch.method_decl_impl_node),
            buffer_id(typecheck_scratch.method_decl_name_token),
            buffer_id(typecheck_scratch.method_decl_name_id),
            buffer_id(typecheck_scratch.method_decl_param_offset),
            buffer_id(typecheck_scratch.method_decl_receiver_mode),
            buffer_id(typecheck_scratch.method_decl_visibility),
            buffer_id(typecheck_scratch.method_key_to_fn_token),
            buffer_id(typecheck_scratch.method_key_status),
            buffer_id(typecheck_scratch.method_key_radix_block_histogram),
            buffer_id(typecheck_scratch.method_key_radix_block_bucket_prefix),
            buffer_id(typecheck_scratch.method_call_receiver_ref_tag),
            buffer_id(typecheck_scratch.method_call_receiver_ref_payload),
            buffer_id(typecheck_scratch.method_call_name_id),
            buffer_id(typecheck_scratch.method_call_site_module_id),
        ];
        for i in 0..method_clear_scratch_ids.len() {
            for j in i + 1..method_clear_scratch_ids.len() {
                assert_ne!(method_clear_scratch_ids[i], method_clear_scratch_ids[j]);
            }
        }
        assert_distinct_from(
            typecheck_scratch.import_visible_type_count,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.import_visible_value_count,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.import_visible_type_prefix,
            &typecheck_hir_inputs,
        );
        assert_distinct_from(
            typecheck_scratch.import_visible_value_prefix,
            &typecheck_hir_inputs,
        );
        for scratch in [
            typecheck_scratch.resolved_type_decl,
            typecheck_scratch.resolved_value_decl,
            typecheck_scratch.resolved_type_status,
            typecheck_scratch.resolved_value_status,
            typecheck_scratch.member_result_ref_payload,
            typecheck_scratch.member_result_field_ordinal,
            typecheck_scratch.struct_init_field_expected_ref_tag,
            typecheck_scratch.struct_init_field_expected_ref_payload,
            typecheck_scratch.struct_init_field_context_instance,
            typecheck_scratch.struct_init_field_ordinal,
            typecheck_scratch.path_start,
            typecheck_scratch.path_len,
            typecheck_scratch.path_segment_count,
            typecheck_scratch.path_segment_base,
            typecheck_scratch.path_segment_name_id,
            typecheck_scratch.path_segment_token,
            typecheck_scratch.path_owner_hir,
            typecheck_scratch.path_owner_token,
            typecheck_scratch.path_owner_module_id,
            typecheck_scratch.path_kind,
        ] {
            assert_distinct_from(scratch, &typecheck_hir_inputs);
            assert!(scratch.size() >= typecheck_record_bytes as u64);
        }
        assert!(
            bufs.hir_variant_rank_a.byte_size
                >= (bufs.n_tokens as usize)
                    .saturating_mul(gpu_type_checker::TYPE_INSTANCE_ARG_REF_STRIDE)
                    .saturating_mul(4)
        );
        assert!(
            bufs.hir_variant_payload_link_a.byte_size
                >= (bufs.n_tokens as usize)
                    .saturating_mul(gpu_type_checker::TYPE_INSTANCE_ARG_REF_STRIDE)
                    .saturating_mul(4)
        );
        for scratch in [
            typecheck_scratch.type_expr_ref_tag,
            typecheck_scratch.type_expr_ref_payload,
            typecheck_scratch.type_generic_param_slot_by_token,
            typecheck_scratch.type_const_param_slot_by_token,
            typecheck_scratch.call_param_count,
            typecheck_scratch.call_param_type,
            typecheck_scratch.method_decl_module_id,
            typecheck_scratch.method_decl_impl_node,
            typecheck_scratch.method_decl_name_id,
            typecheck_scratch.method_decl_param_offset,
            typecheck_scratch.method_decl_receiver_mode,
            typecheck_scratch.method_decl_visibility,
            typecheck_scratch.method_key_to_fn_token,
            typecheck_scratch.method_key_status,
            typecheck_scratch.method_key_radix_block_histogram,
            typecheck_scratch.method_key_radix_block_bucket_prefix,
            typecheck_scratch.method_call_receiver_ref_tag,
            typecheck_scratch.method_call_receiver_ref_payload,
            typecheck_scratch.method_call_name_id,
            typecheck_scratch.method_call_site_module_id,
            typecheck_scratch.type_instance_head_token,
            typecheck_scratch.type_instance_arg_start,
            typecheck_scratch.type_instance_arg_count,
            typecheck_scratch.type_instance_elem_ref_tag,
            typecheck_scratch.type_instance_elem_ref_payload,
            typecheck_scratch.type_decl_generic_param_count,
            typecheck_scratch.type_decl_generic_param_count_by_node,
            typecheck_scratch.type_instance_arg_ref_tag,
            typecheck_scratch.type_instance_arg_ref_payload,
            typecheck_scratch.decl_type_key_to_decl_id,
            typecheck_scratch.decl_value_key_to_decl_id,
            typecheck_scratch.import_visible_type_count,
            typecheck_scratch.import_visible_value_count,
            typecheck_scratch.import_visible_type_prefix,
            typecheck_scratch.import_visible_value_prefix,
        ] {
            assert!(scratch.size() >= (bufs.n_tokens as u64).saturating_mul(4));
        }
        assert!(
            typecheck_scratch.call_arg_record.size()
                >= (bufs.n_tokens as u64).saturating_mul(4).saturating_mul(4)
        );
        for scratch in [
            typecheck_scratch.function_lookup_key,
            typecheck_scratch.function_lookup_fn,
        ] {
            assert!(scratch.size() >= (bufs.n_tokens as u64).saturating_mul(2).saturating_mul(4));
        }

        let dummy_codegen = scratch_u32_buffer("test.codegen.dummy", 1);
        let codegen_fn_entrypoint_tag = scratch_u32_buffer(
            "test.codegen.fn_entrypoint_tag",
            bufs.tree_capacity as usize,
        );
        let codegen = gpu_type_checker::GpuX86CodegenBuffers {
            enclosing_fn: &dummy_codegen,
            visible_decl: &dummy_codegen,
            visible_type: &dummy_codegen,
            path_count_out: &dummy_codegen,
            path_id_by_owner_hir: &dummy_codegen,
            resolved_value_decl: &dummy_codegen,
            resolved_value_status: &dummy_codegen,
            decl_count_out: &dummy_codegen,
            decl_kind: &dummy_codegen,
            decl_name_token: &dummy_codegen,
            decl_id_by_name_token: &dummy_codegen,
            decl_hir_node: &dummy_codegen,
            decl_parent_type_decl: &dummy_codegen,
            decl_type_ref_tag: &dummy_codegen,
            decl_type_ref_payload: &dummy_codegen,
            call_fn_index: &dummy_codegen,
            call_intrinsic_tag: &dummy_codegen,
            fn_entrypoint_tag: &codegen_fn_entrypoint_tag,
            call_return_type: &dummy_codegen,
            call_return_type_token: &dummy_codegen,
            call_param_type: &dummy_codegen,
            method_decl_receiver_ref_tag: &dummy_codegen,
            method_decl_receiver_ref_payload: &dummy_codegen,
            method_decl_param_offset: &dummy_codegen,
            type_instance_kind: &dummy_codegen,
            type_instance_decl_token: &dummy_codegen,
            type_instance_len_kind: &dummy_codegen,
            type_instance_len_payload: &dummy_codegen,
            member_result_field_ordinal: &dummy_codegen,
            struct_init_field_ordinal: &dummy_codegen,
            struct_init_field_ordinal_by_node: &dummy_codegen,
        };

        let x86_parse = OwnedX86ParserBuffers::from_parser_buffers(&bufs);
        let x86_scratch = GpuCompiler::x86_external_scratch_from_frontend_and_codegen_buffers(
            &x86_parse,
            codegen,
            8,
            x86::X86FeatureSummary::default(),
        );
        assert_eq!(x86_scratch.borrowed_buffer_count(), 21);
        assert!(x86_scratch.node_inst_scan_local_prefix.is_none());
        assert_eq!(
            buffer_id(x86_scratch.call_record.expect("no-call scratch")),
            buffer_id(&bufs.hir_param_record.buffer)
        );
        assert!(x86_scratch.call_type_record.is_none());
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_count_info
                    .expect("count-info scratch")
            ),
            buffer_id(&codegen_fn_entrypoint_tag)
        );
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_count_payload
                    .expect("count-payload scratch")
            ),
            buffer_id(&bufs.hir_type_arg_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_subtree_bound_start
                    .expect("subtree-start scratch")
            ),
            buffer_id(&bufs.hir_type_arg_rank_a.buffer)
        );
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_subtree_bound_end
                    .expect("subtree-end scratch")
            ),
            buffer_id(&bufs.hir_array_element_previous.buffer)
        );
        assert!(x86_scratch.node_inst_gen_node_record.is_none());
        for scratch in [
            x86_scratch.node_inst_count_info.expect("count-info"),
            x86_scratch.node_inst_count_payload.expect("count-payload"),
            x86_scratch
                .node_inst_subtree_bound_start
                .expect("subtree-start"),
            x86_scratch
                .node_inst_subtree_bound_end
                .expect("subtree-end"),
        ] {
            assert!(scratch.size() >= (bufs.tree_capacity as u64).saturating_mul(4));
        }
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_range_start
                    .expect("range start scratch")
            ),
            buffer_id(&bufs.hir_type_path_leaf_link_a.buffer)
        );
        assert_eq!(
            buffer_id(
                x86_scratch
                    .node_inst_range_info
                    .expect("range info scratch")
            ),
            buffer_id(&bufs.hir_type_path_leaf_link_b.buffer)
        );
        assert!(x86_scratch.decl_layout_record.is_some());
        assert!(x86_scratch.const_value_record.is_some());
        assert!(x86_scratch.param_reg_record.is_some());
        assert!(x86_scratch.local_literal_record.is_some());
        let param_program_scratch =
            GpuCompiler::x86_external_scratch_from_frontend_and_codegen_buffers(
                &x86_parse,
                codegen,
                8,
                x86::X86FeatureSummary {
                    param_count: 1,
                    ..x86::X86FeatureSummary::default()
                },
            );
        assert!(param_program_scratch.call_record.is_none());
        assert!(param_program_scratch.call_type_record.is_none());
        assert!(
            bufs.hir_type_len_value.byte_size
                >= (bufs.tree_capacity as usize).saturating_add(1) * 4
        );
        assert_eq!(
            buffer_id(&bufs.hir_struct_field_type_node.buffer),
            buffer_id(&bufs.hir_struct_lit_field_value_node.buffer)
        );

        let x86_parser_inputs = [
            &bufs.parent.buffer,
            &bufs.first_child.buffer,
            &bufs.next_sibling.buffer,
            &bufs.subtree_end.buffer,
            &bufs.hir_kind.buffer,
            &bufs.hir_item_decl_token.buffer,
            &bufs.hir_item_name_token.buffer,
            &bufs.hir_token_pos.buffer,
            &bufs.hir_expr_record.buffer,
            &bufs.hir_expr_int_value.buffer,
            &bufs.hir_stmt_record.buffer,
            &bufs.hir_call_callee_node.buffer,
            &bufs.hir_call_arg_start.buffer,
            &bufs.hir_call_arg_end.buffer,
            &bufs.hir_call_arg_count.buffer,
            &bufs.hir_call_arg_parent_call.buffer,
            &bufs.hir_member_receiver_node.buffer,
            &bufs.hir_member_name_token.buffer,
            &bufs.hir_array_lit_first_element.buffer,
            &bufs.hir_array_lit_element_count.buffer,
            &bufs.hir_array_element_parent_lit.buffer,
            &bufs.hir_array_element_ordinal.buffer,
            &bufs.hir_array_element_next.buffer,
            &bufs.hir_variant_parent_enum.buffer,
            &bufs.hir_variant_ordinal.buffer,
            &bufs.hir_variant_payload_count.buffer,
            &bufs.hir_match_scrutinee_node.buffer,
            &bufs.hir_match_arm_start.buffer,
            &bufs.hir_match_arm_count.buffer,
            &bufs.hir_match_arm_next.buffer,
            &bufs.hir_match_arm_pattern_node.buffer,
            &bufs.hir_match_arm_payload_start.buffer,
            &bufs.hir_match_arm_payload_count.buffer,
            &bufs.hir_match_arm_result_node.buffer,
            &bufs.hir_struct_decl_field_count.buffer,
            &bufs.hir_struct_lit_field_parent_lit.buffer,
            &bufs.hir_struct_lit_field_start.buffer,
            &bufs.hir_struct_lit_field_count.buffer,
            &bufs.hir_struct_lit_field_value_node.buffer,
            &bufs.hir_struct_lit_field_next.buffer,
        ];

        for scratch in [
            x86_scratch.expr_resolved_final,
            x86_scratch.node_func,
            x86_scratch.func_owner_scan_local_prefix,
            x86_scratch.func_slot_by_node,
            x86_scratch.match_pattern_owner,
            x86_scratch.match_pattern_node_owner,
            x86_scratch.match_pattern_node_variant,
            x86_scratch.match_pattern_node_payload_decl,
            x86_scratch.match_pattern_first_use_node,
            x86_scratch.enclosing_let_node_a,
            x86_scratch.enclosing_let_node_b,
            x86_scratch.node_inst_same_end_link_a,
            x86_scratch.node_inst_same_end_link_b,
            x86_scratch.call_record,
            x86_scratch.call_type_record,
            x86_scratch.node_inst_count_info,
            x86_scratch.node_inst_count_payload,
            x86_scratch.node_inst_range_start,
            x86_scratch.node_inst_range_info,
            x86_scratch.node_inst_subtree_bound_start,
            x86_scratch.node_inst_subtree_bound_end,
            x86_scratch.node_inst_gen_node_record,
            x86_scratch.decl_layout_record,
            x86_scratch.const_value_record,
            x86_scratch.param_reg_record,
            x86_scratch.local_literal_record,
        ]
        .into_iter()
        .flatten()
        {
            assert_distinct_from(scratch, &x86_parser_inputs);
        }
    }

    #[test]
    fn x86_only_compiler_does_not_initialize_wasm_backend() {
        let compiler = pollster::block_on(GpuCompiler::new_with_device_and_backends(
            device::global(),
            GpuCompilerBackends::x86_only(),
        ))
        .expect("initialize x86-only GPU compiler");

        assert!(
            compiler.wasm_generator.is_err(),
            "x86-only global compiler path must not initialize legacy WASM backend pipelines"
        );
        assert!(
            compiler.x86_generator.is_ok(),
            "x86-only global compiler path should initialize x86 backend pipelines"
        );
    }
}
