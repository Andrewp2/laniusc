use anyhow::Result;
use encase::ShaderType;

use crate::gpu::{
    device,
    passes_core::{PassData, make_traced_main_pass},
};

mod finish;
mod record;
mod support;

use support::{PooledReadbackBuffer, PooledStorageBuffer, RetainedX86Buffer, trace_x86_codegen};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86Params {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
    inst_capacity: u32,
    virtual_next_call_step_count: u32,
    regalloc_rows_per_chunk: u32,
    regalloc_chunk_count: u32,
    function_slot_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86ScanParams {
    n_items: u32,
    n_blocks: u32,
    scan_step: u32,
    inst_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct X86RegallocParams {
    chunk_start: u32,
    chunk_len: u32,
    init_status: u32,
    reserved: u32,
}

pub const X86_FEATURE_ENUM: u32 = 1 << 0;
pub const X86_FEATURE_MATCH: u32 = 1 << 1;
pub const X86_FEATURE_AGGREGATE: u32 = 1 << 2;
pub const X86_FEATURE_CALL: u32 = 1 << 3;

#[derive(Clone, Copy, Debug, Default, Eq, PartialEq)]
pub struct X86FeatureSummary {
    pub mask: u32,
    pub enum_count: u32,
    pub match_count: u32,
    pub aggregate_count: u32,
    pub scalar_inst_capacity: u32,
    pub call_count: u32,
    pub param_count: u32,
}

impl X86FeatureSummary {
    fn from_record_words(words: [u32; 8]) -> Self {
        Self {
            mask: words[0],
            enum_count: words[1],
            match_count: words[2],
            aggregate_count: words[3],
            scalar_inst_capacity: words[4],
            call_count: words[5],
            param_count: words[6],
        }
    }

    fn record_words(self) -> [u32; 8] {
        [
            self.mask,
            self.enum_count,
            self.match_count,
            self.aggregate_count,
            self.scalar_inst_capacity,
            self.call_count,
            self.param_count,
            0,
        ]
    }

    pub fn has_enum(self) -> bool {
        self.mask & X86_FEATURE_ENUM != 0
    }

    pub fn has_match(self) -> bool {
        self.mask & X86_FEATURE_MATCH != 0
    }

    #[allow(dead_code)]
    pub fn has_aggregate(self) -> bool {
        self.mask & X86_FEATURE_AGGREGATE != 0
    }

    pub fn has_call(self) -> bool {
        self.mask & X86_FEATURE_CALL != 0
    }

    pub fn has_param(self) -> bool {
        self.param_count != 0
    }

    fn scalar_inst_capacity_limit(self) -> Option<usize> {
        if self.has_enum() || self.has_match() || self.has_aggregate() || self.has_call() {
            return None;
        }
        let estimate = self.scalar_inst_capacity as usize;
        if estimate == 0 {
            return None;
        }
        Some(
            estimate
                .saturating_add(estimate.div_ceil(4))
                .saturating_add(X86_INST_CAPACITY_SLACK)
                .max(X86_INST_CAPACITY_MIN),
        )
    }
}

pub struct GpuX86ExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub type_form: &'a wgpu::Buffer,
    pub type_len_value: &'a wgpu::Buffer,
}

pub struct GpuX86FunctionMetadataBuffers<'a> {
    pub node_decl_token: &'a wgpu::Buffer,
    pub node_name_token: &'a wgpu::Buffer,
    pub hir_token_pos: &'a wgpu::Buffer,
    pub fn_return_type_node: &'a wgpu::Buffer,
    pub param_record: &'a wgpu::Buffer,
    pub enclosing_fn: &'a wgpu::Buffer,
    pub method_decl_param_offset: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_payload: &'a wgpu::Buffer,
}

pub struct GpuX86CallMetadataBuffers<'a> {
    pub callee_node: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
    pub member_receiver_node: &'a wgpu::Buffer,
    pub member_name_token: &'a wgpu::Buffer,
    pub call_fn_index: &'a wgpu::Buffer,
    pub call_intrinsic_tag: &'a wgpu::Buffer,
    pub call_return_type: &'a wgpu::Buffer,
    pub call_return_type_token: &'a wgpu::Buffer,
    pub call_param_type: &'a wgpu::Buffer,
}

pub struct GpuX86ArrayMetadataBuffers<'a> {
    pub lit_first_element: &'a wgpu::Buffer,
    pub lit_element_count: &'a wgpu::Buffer,
    pub element_parent_lit: &'a wgpu::Buffer,
    pub element_ordinal: &'a wgpu::Buffer,
    pub element_next: &'a wgpu::Buffer,
}

pub struct GpuX86EnumMetadataBuffers<'a> {
    pub item_decl_token: &'a wgpu::Buffer,
    pub variant_parent_enum: &'a wgpu::Buffer,
    pub variant_ordinal: &'a wgpu::Buffer,
    pub variant_payload_count: &'a wgpu::Buffer,
    pub match_scrutinee_node: &'a wgpu::Buffer,
    pub match_arm_start: &'a wgpu::Buffer,
    pub match_arm_count: &'a wgpu::Buffer,
    pub match_arm_next: &'a wgpu::Buffer,
    pub match_arm_pattern_node: &'a wgpu::Buffer,
    pub match_arm_payload_start: &'a wgpu::Buffer,
    pub match_arm_payload_count: &'a wgpu::Buffer,
    pub match_arm_result_node: &'a wgpu::Buffer,
    pub hir_token_pos: &'a wgpu::Buffer,
    pub path_count_out: &'a wgpu::Buffer,
    pub path_id_by_owner_hir: &'a wgpu::Buffer,
    pub resolved_value_decl: &'a wgpu::Buffer,
    pub resolved_value_status: &'a wgpu::Buffer,
    pub decl_count_out: &'a wgpu::Buffer,
    pub decl_kind: &'a wgpu::Buffer,
    pub decl_name_token: &'a wgpu::Buffer,
    pub decl_id_by_name_token: &'a wgpu::Buffer,
    pub decl_hir_node: &'a wgpu::Buffer,
    pub decl_parent_type_decl: &'a wgpu::Buffer,
}

pub struct GpuX86StructMetadataBuffers<'a> {
    pub item_name_token: &'a wgpu::Buffer,
    pub decl_hir_node: &'a wgpu::Buffer,
    pub struct_decl_field_count: &'a wgpu::Buffer,
    pub struct_lit_field_parent_lit: &'a wgpu::Buffer,
    pub struct_lit_field_start: &'a wgpu::Buffer,
    pub struct_lit_field_count: &'a wgpu::Buffer,
    pub struct_lit_field_value_node: &'a wgpu::Buffer,
    pub struct_lit_field_next: &'a wgpu::Buffer,
    pub member_result_field_ordinal: &'a wgpu::Buffer,
    pub struct_init_field_ordinal: &'a wgpu::Buffer,
    pub struct_init_field_ordinal_by_node: &'a wgpu::Buffer,
}

pub struct GpuX86TypeMetadataBuffers<'a> {
    pub decl_type_ref_tag: &'a wgpu::Buffer,
    pub decl_type_ref_payload: &'a wgpu::Buffer,
    pub visible_type: &'a wgpu::Buffer,
    pub type_instance_kind: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub type_instance_len_kind: &'a wgpu::Buffer,
    pub type_instance_len_payload: &'a wgpu::Buffer,
}

#[derive(Clone, Copy, Debug, Default)]
pub struct GpuX86ExternalScratchBuffers<'a> {
    pub expr_resolved_final: Option<&'a wgpu::Buffer>,
    pub node_func: Option<&'a wgpu::Buffer>,
    pub func_owner_scan_local_prefix: Option<&'a wgpu::Buffer>,
    pub func_slot_by_node: Option<&'a wgpu::Buffer>,
    pub match_pattern_owner: Option<&'a wgpu::Buffer>,
    pub match_pattern_node_owner: Option<&'a wgpu::Buffer>,
    pub match_pattern_node_variant: Option<&'a wgpu::Buffer>,
    pub match_pattern_node_payload_decl: Option<&'a wgpu::Buffer>,
    pub match_pattern_first_use_node: Option<&'a wgpu::Buffer>,
    pub enclosing_let_node_a: Option<&'a wgpu::Buffer>,
    pub enclosing_let_node_b: Option<&'a wgpu::Buffer>,
    pub node_inst_same_end_link_a: Option<&'a wgpu::Buffer>,
    pub node_inst_same_end_link_b: Option<&'a wgpu::Buffer>,
    pub node_inst_scan_local_prefix: Option<&'a wgpu::Buffer>,
    pub call_record: Option<&'a wgpu::Buffer>,
    pub call_type_record: Option<&'a wgpu::Buffer>,
    pub node_inst_count_info: Option<&'a wgpu::Buffer>,
    pub node_inst_count_payload: Option<&'a wgpu::Buffer>,
    pub node_inst_range_start: Option<&'a wgpu::Buffer>,
    pub node_inst_range_info: Option<&'a wgpu::Buffer>,
    pub node_inst_subtree_bound_start: Option<&'a wgpu::Buffer>,
    pub node_inst_subtree_bound_end: Option<&'a wgpu::Buffer>,
    pub node_inst_gen_node_record: Option<&'a wgpu::Buffer>,
    pub decl_layout_record: Option<&'a wgpu::Buffer>,
    pub const_value_record: Option<&'a wgpu::Buffer>,
    pub param_reg_record: Option<&'a wgpu::Buffer>,
    pub local_literal_record: Option<&'a wgpu::Buffer>,
}

impl GpuX86ExternalScratchBuffers<'_> {
    pub fn borrowed_buffer_count(&self) -> usize {
        [
            self.expr_resolved_final,
            self.node_func,
            self.func_owner_scan_local_prefix,
            self.func_slot_by_node,
            self.match_pattern_owner,
            self.match_pattern_node_owner,
            self.match_pattern_node_variant,
            self.match_pattern_node_payload_decl,
            self.match_pattern_first_use_node,
            self.enclosing_let_node_a,
            self.enclosing_let_node_b,
            self.node_inst_same_end_link_a,
            self.node_inst_same_end_link_b,
            self.node_inst_scan_local_prefix,
            self.call_record,
            self.call_type_record,
            self.node_inst_count_info,
            self.node_inst_count_payload,
            self.node_inst_range_start,
            self.node_inst_range_info,
            self.node_inst_subtree_bound_start,
            self.node_inst_subtree_bound_end,
            self.node_inst_gen_node_record,
            self.decl_layout_record,
            self.const_value_record,
            self.param_reg_record,
            self.local_literal_record,
        ]
        .into_iter()
        .flatten()
        .count()
    }
}

// Host-side conservative capacity estimate before GPU instruction counts are
// exact. The HIR-only path keeps a conservative floor; the live-token path uses
// measured token count plus slack so small/medium programs do not allocate a
// fixed 16k instruction rows when the frontend already knows the real token
// count.
const X86_INST_CAPACITY_HIR_ESTIMATE_CAP: usize = 16_384;
const MAX_X86_INSTS: usize = 2_097_152;
const X86_INST_CAPACITY_MIN: usize = 256;
const X86_INST_CAPACITY_SLACK: usize = 1_024;
const X86_INSTS_PER_HIR_NODE_CAPACITY: usize = 8;
const X86_INSTS_PER_TOKEN_CAPACITY: usize = 1;
const X86_SCALAR_INST_BASIS_DIVISOR: usize = 12;
const X86_FUNCTION_SLOT_TOKEN_DENSITY_DIVISOR: usize = 3;
const X86_FUNCTION_SLOT_CAPACITY_SLACK: usize = 64;
const X86_INITIAL_OUTPUT_READBACK_SOURCE_MULTIPLIER: usize = 3;
const X86_INITIAL_OUTPUT_READBACK_SLACK_BYTES: usize = 64 * 1024;
const X86_INITIAL_OUTPUT_READBACK_LARGE_SOURCE_SLACK_BYTES: usize = 128 * 1024;
const X86_INITIAL_OUTPUT_READBACK_CAPACITY_DIVISOR: usize = 2;
// Mirror Pareas' lockstep register-allocation shape: each dispatch step
// advances a small fixed row chunk for every function, carrying per-function
// active state between chunks. This avoids serial full-function walks inside a
// single shader invocation while keeping host command recording bounded.
const X86_REGALLOC_ROWS_PER_CHUNK: usize = 256;

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86CapacityEstimate {
    pub hir_words: usize,
    pub inst_basis_words: usize,
    pub requested_inst_capacity: usize,
    pub inst_capacity: usize,
    pub inst_capacity_capped: bool,
    pub output_capacity: usize,
}

pub fn x86_capacity_estimate_for_hir(hir_words: usize) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_with_limit(hir_words, X86_INST_CAPACITY_HIR_ESTIMATE_CAP)
}

pub fn x86_capacity_estimate_for_hir_and_tokens(
    hir_words: usize,
    token_capacity: usize,
) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_tokens_and_inst_basis(hir_words, token_capacity, hir_words)
}

pub fn x86_capacity_estimate_for_hir_tokens_and_inst_basis(
    hir_words: usize,
    token_capacity: usize,
    inst_basis_words: usize,
) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_tokens_inst_basis_and_inst_limit(
        hir_words,
        token_capacity,
        inst_basis_words,
        None,
    )
}

pub fn x86_capacity_estimate_for_hir_tokens_inst_basis_and_feature_summary(
    hir_words: usize,
    token_capacity: usize,
    inst_basis_words: usize,
    feature_summary: X86FeatureSummary,
) -> X86CapacityEstimate {
    let scalar_inst_capacity_limit = feature_summary.scalar_inst_capacity_limit().map(|limit| {
        let semantic_floor = inst_basis_words
            .max(1)
            .div_ceil(X86_SCALAR_INST_BASIS_DIVISOR)
            .saturating_add(X86_INST_CAPACITY_SLACK)
            .max(X86_INST_CAPACITY_MIN);
        limit.max(semantic_floor)
    });
    x86_capacity_estimate_for_hir_tokens_inst_basis_and_inst_limit(
        hir_words,
        token_capacity,
        inst_basis_words,
        scalar_inst_capacity_limit,
    )
}

fn x86_capacity_estimate_for_hir_tokens_inst_basis_and_inst_limit(
    hir_words: usize,
    token_capacity: usize,
    inst_basis_words: usize,
    inst_capacity_limit_override: Option<usize>,
) -> X86CapacityEstimate {
    let token_scaled_limit = token_capacity
        .max(1)
        .saturating_mul(X86_INSTS_PER_TOKEN_CAPACITY)
        .saturating_add(X86_INST_CAPACITY_SLACK)
        .min(MAX_X86_INSTS);
    let inst_capacity_limit = inst_capacity_limit_override
        .map(|limit| limit.min(token_scaled_limit))
        .unwrap_or(token_scaled_limit);
    x86_capacity_estimate_for_hir_with_limit_and_inst_basis(
        hir_words,
        inst_capacity_limit,
        inst_basis_words,
    )
}

fn x86_capacity_estimate_for_hir_with_limit(
    hir_words: usize,
    inst_capacity_limit: usize,
) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_with_limit_and_inst_basis(
        hir_words,
        inst_capacity_limit,
        hir_words,
    )
}

fn x86_capacity_estimate_for_hir_with_limit_and_inst_basis(
    hir_words: usize,
    inst_capacity_limit: usize,
    inst_basis_words: usize,
) -> X86CapacityEstimate {
    let hir_words = hir_words.max(1);
    let inst_basis_words = inst_basis_words.max(1);
    let inst_capacity_limit = inst_capacity_limit.clamp(X86_INST_CAPACITY_MIN, MAX_X86_INSTS);
    let requested_inst_capacity = x86_requested_inst_capacity_for_hir(inst_basis_words);
    let inst_capacity = requested_inst_capacity.clamp(X86_INST_CAPACITY_MIN, inst_capacity_limit);
    X86CapacityEstimate {
        hir_words,
        inst_basis_words,
        requested_inst_capacity,
        inst_capacity,
        inst_capacity_capped: requested_inst_capacity > inst_capacity,
        output_capacity: x86_output_capacity_for_inst_capacity(inst_capacity),
    }
}

fn x86_requested_inst_capacity_for_hir(hir_words: usize) -> usize {
    hir_words
        .saturating_mul(X86_INSTS_PER_HIR_NODE_CAPACITY)
        .saturating_add(X86_INST_CAPACITY_SLACK)
}

fn x86_output_capacity_for_inst_capacity(inst_capacity: usize) -> usize {
    inst_capacity
        .saturating_mul(16)
        .saturating_add(4096)
        .max(4096)
}

fn x86_initial_output_readback_bytes(output_capacity: usize, source_len: usize) -> usize {
    let scaled_window = source_len
        .saturating_mul(X86_INITIAL_OUTPUT_READBACK_SOURCE_MULTIPLIER)
        .saturating_add(X86_INITIAL_OUTPUT_READBACK_SLACK_BYTES);
    let large_source_window =
        source_len.saturating_add(X86_INITIAL_OUTPUT_READBACK_LARGE_SOURCE_SLACK_BYTES);
    let source_window = scaled_window.min(large_source_window);
    let capacity_window = output_capacity.div_ceil(X86_INITIAL_OUTPUT_READBACK_CAPACITY_DIVISOR);
    let wanted = source_window.max(capacity_window).max(4096);
    wanted
        .min(output_capacity.max(1))
        .div_ceil(4)
        .saturating_mul(4)
}

pub fn x86_node_inst_order_rows(hir_words: usize, inst_capacity: usize) -> usize {
    inst_capacity.min(hir_words.max(1)).saturating_add(1)
}

pub fn x86_node_inst_worklist_rows(hir_words: usize, inst_capacity: usize) -> usize {
    inst_capacity.max(1).min(hir_words.max(1))
}

pub fn x86_call_type_record_words(hir_words: usize, has_call: bool) -> usize {
    if has_call {
        hir_words.saturating_mul(3)
    } else {
        1
    }
}

pub fn x86_node_inst_count_record_words(hir_words: usize) -> usize {
    hir_words.saturating_mul(2)
}

pub fn x86_node_inst_gen_node_record_words(hir_words: usize, inst_capacity: usize) -> usize {
    x86_node_inst_worklist_rows(hir_words, inst_capacity).saturating_mul(2)
}

pub fn x86_node_inst_order_record_words(
    hir_words: usize,
    inst_capacity: usize,
    function_slot_capacity: usize,
) -> usize {
    let order_rows = x86_node_inst_order_rows(hir_words, inst_capacity);
    order_rows
        .saturating_mul(3)
        .max(function_slot_capacity.max(1).saturating_mul(14))
}

pub fn x86_function_slot_capacity(
    inst_hir_node_count: usize,
    hir_words: usize,
    token_capacity: usize,
) -> usize {
    let structural_limit = inst_hir_node_count
        .max(1)
        .min(hir_words.max(1))
        .min(token_capacity.max(1));
    // Valid function records require multiple lexed tokens. Use a divisor below
    // the grammar minimum so this stays a conservative allocation bound, not a
    // semantic classifier.
    let token_density_bound = token_capacity
        .max(1)
        .div_ceil(X86_FUNCTION_SLOT_TOKEN_DENSITY_DIVISOR)
        .saturating_add(X86_FUNCTION_SLOT_CAPACITY_SLACK);
    structural_limit.min(token_density_bound).max(1)
}

pub fn x86_regalloc_recorded_step_count(inst_capacity: usize, inst_basis_words: usize) -> usize {
    let _ = inst_basis_words;
    inst_capacity.max(1)
}

pub struct RecordedX86Codegen {
    output_capacity: usize,
    output_status_offset: u64,
    _retained_buffers: Vec<RetainedX86Buffer>,
    _retained_bind_groups: Vec<wgpu::BindGroup>,
    out_buf: PooledStorageBuffer,
    output_readback: PooledReadbackBuffer,
    status_trace_readback: Option<wgpu::Buffer>,
}

pub struct GpuX86CodeGenerator {
    fill_u32_pass: PassData,
    active_clear_u32_pass: PassData,
    active_scan_dispatch_args_pass: PassData,
    virtual_dispatch_args_pass: PassData,
    output_dispatch_args_pass: PassData,
    feature_counts_pass: PassData,
    node_tree_info_pass: PassData,
    func_discover_pass: PassData,
    func_slot_flags_pass: PassData,
    func_slot_scatter_pass: PassData,
    func_owner_scan_local_pass: PassData,
    func_owner_scan_blocks_pass: PassData,
    func_assign_nodes_pass: PassData,
    func_assign_nodes_step_pass: PassData,
    expr_resolve_init_pass: PassData,
    expr_resolve_step_pass: PassData,
    expr_semantic_type_init_pass: PassData,
    expr_semantic_type_step_pass: PassData,
    enum_records_pass: PassData,
    struct_records_pass: PassData,
    array_records_pass: PassData,
    match_records_pass: PassData,
    match_result_owner_init_pass: PassData,
    match_result_owner_step_pass: PassData,
    match_pattern_owner_init_pass: PassData,
    match_pattern_owner_step_pass: PassData,
    match_pattern_records_pass: PassData,
    match_pattern_finalize_pass: PassData,
    return_match_records_pass: PassData,
    match_ownership_pass: PassData,
    enclosing_return_init_pass: PassData,
    enclosing_return_step_pass: PassData,
    enclosing_let_init_pass: PassData,
    enclosing_let_step_pass: PassData,
    enclosing_stmt_init_pass: PassData,
    enclosing_stmt_step_pass: PassData,
    decl_widths_pass: PassData,
    decl_layout_pass: PassData,
    call_records_pass: PassData,
    call_callee_owner_init_pass: PassData,
    call_callee_owner_step_pass: PassData,
    const_values_pass: PassData,
    param_regs_pass: PassData,
    local_literals_pass: PassData,
    call_arg_values_pass: PassData,
    intrinsic_calls_pass: PassData,
    call_abi_pass: PassData,
    node_inst_counts_pass: PassData,
    node_inst_same_end_rank_init_pass: PassData,
    node_inst_same_end_rank_step_pass: PassData,
    node_inst_end_counts_pass: PassData,
    node_inst_order_pass: PassData,
    node_order_dispatch_args_pass: PassData,
    node_inst_scan_local_pass: PassData,
    node_inst_scan_blocks_pass: PassData,
    node_inst_prefix_scan_pass: PassData,
    node_inst_subtree_bounds_pass: PassData,
    node_inst_locations_pass: PassData,
    node_inst_gen_worklist_scatter_pass: PassData,
    node_inst_gen_worklist_dispatch_args_pass: PassData,
    enclosing_loop_init_pass: PassData,
    enclosing_loop_step_pass: PassData,
    node_inst_gen_inputs_pass: PassData,
    virtual_inst_clear_dispatch_args_pass: PassData,
    virtual_inst_clear_pass: PassData,
    node_inst_gen_pass: PassData,
    aggregate_literal_return_copy_flags_pass: PassData,
    aggregate_literal_return_copy_pass: PassData,
    node_inst_gen_aggregate_copy_pass: PassData,
    virtual_liveness_init_pass: PassData,
    virtual_liveness_pass: PassData,
    virtual_next_calls_pass: PassData,
    virtual_spans_fixed_barrier_pass: PassData,
    virtual_value_def_flags_pass: PassData,
    virtual_value_def_compact_pass: PassData,
    virtual_param_masks_pass: PassData,
    virtual_regalloc_pass: PassData,
    virtual_func_rows_init_pass: PassData,
    virtual_func_first_row_pass: PassData,
    virtual_func_span_max_pass: PassData,
    virtual_regalloc_dispatch_args_pass: PassData,
    select_pass: PassData,
    inst_size_pass: PassData,
    text_scan_local_pass: PassData,
    text_offsets_pass: PassData,
    encode_pass: PassData,
    elf_layout_pass: PassData,
    elf_write_pass: PassData,
}

impl GpuX86CodeGenerator {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! load_x86_pass {
            ($name:literal, $spv:literal, $reflection:literal) => {{
                make_traced_main_pass!(
                    &gpu.device,
                    trace_x86_codegen,
                    $name,
                    concat!("codegen_x86_", $name),
                    artifacts: ($spv, $reflection)
                )
            }};
        }

        let fill_u32_pass =
            load_x86_pass!("fill_u32", "x86_fill_u32.spv", "x86_fill_u32.reflect.json");
        let active_clear_u32_pass = load_x86_pass!(
            "active_clear_u32",
            "x86_active_clear_u32.spv",
            "x86_active_clear_u32.reflect.json"
        );
        let active_scan_dispatch_args_pass = load_x86_pass!(
            "active_scan_dispatch_args",
            "x86_active_scan_dispatch_args.spv",
            "x86_active_scan_dispatch_args.reflect.json"
        );
        let virtual_dispatch_args_pass = load_x86_pass!(
            "virtual_dispatch_args",
            "x86_virtual_dispatch_args.spv",
            "x86_virtual_dispatch_args.reflect.json"
        );
        let output_dispatch_args_pass = load_x86_pass!(
            "output_dispatch_args",
            "x86_output_dispatch_args.spv",
            "x86_output_dispatch_args.reflect.json"
        );
        let feature_counts_pass = load_x86_pass!(
            "feature_counts",
            "x86_feature_counts.spv",
            "x86_feature_counts.reflect.json"
        );
        let node_tree_info_pass = load_x86_pass!(
            "node_tree_info",
            "x86_node_tree_info.spv",
            "x86_node_tree_info.reflect.json"
        );
        let func_discover_pass = load_x86_pass!(
            "func_discover",
            "x86_func_discover.spv",
            "x86_func_discover.reflect.json"
        );
        let func_slot_flags_pass = load_x86_pass!(
            "func_slot_flags",
            "x86_func_slot_flags.spv",
            "x86_func_slot_flags.reflect.json"
        );
        let func_slot_scatter_pass = load_x86_pass!(
            "func_slot_scatter",
            "x86_func_slot_scatter.spv",
            "x86_func_slot_scatter.reflect.json"
        );
        let func_owner_scan_local_pass = load_x86_pass!(
            "func_owner_scan_local",
            "x86_func_owner_scan_local.spv",
            "x86_func_owner_scan_local.reflect.json"
        );
        let func_owner_scan_blocks_pass = load_x86_pass!(
            "func_owner_scan_blocks",
            "x86_func_owner_scan_blocks.spv",
            "x86_func_owner_scan_blocks.reflect.json"
        );
        let func_assign_nodes_pass = load_x86_pass!(
            "func_assign_nodes",
            "x86_func_assign_nodes.spv",
            "x86_func_assign_nodes.reflect.json"
        );
        let func_assign_nodes_step_pass = load_x86_pass!(
            "func_assign_nodes_step",
            "x86_func_assign_nodes_step.spv",
            "x86_func_assign_nodes_step.reflect.json"
        );
        let expr_resolve_init_pass = load_x86_pass!(
            "expr_resolve_init",
            "x86_expr_resolve_init.spv",
            "x86_expr_resolve_init.reflect.json"
        );
        let expr_resolve_step_pass = load_x86_pass!(
            "expr_resolve_step",
            "x86_expr_resolve_step.spv",
            "x86_expr_resolve_step.reflect.json"
        );
        let expr_semantic_type_init_pass = load_x86_pass!(
            "expr_semantic_type_init",
            "x86_expr_semantic_type_init.spv",
            "x86_expr_semantic_type_init.reflect.json"
        );
        let expr_semantic_type_step_pass = load_x86_pass!(
            "expr_semantic_type_step",
            "x86_expr_semantic_type_step.spv",
            "x86_expr_semantic_type_step.reflect.json"
        );
        let enum_records_pass = load_x86_pass!(
            "enum_records",
            "x86_enum_records.spv",
            "x86_enum_records.reflect.json"
        );
        let struct_records_pass = load_x86_pass!(
            "struct_records",
            "x86_struct_records.spv",
            "x86_struct_records.reflect.json"
        );
        let array_records_pass = load_x86_pass!(
            "array_records",
            "x86_array_records.spv",
            "x86_array_records.reflect.json"
        );
        let match_records_pass = load_x86_pass!(
            "match_records",
            "x86_match_records.spv",
            "x86_match_records.reflect.json"
        );
        let match_result_owner_init_pass = load_x86_pass!(
            "match_result_owner_init",
            "x86_match_result_owner_init.spv",
            "x86_match_result_owner_init.reflect.json"
        );
        let match_result_owner_step_pass = load_x86_pass!(
            "match_result_owner_step",
            "x86_match_result_owner_step.spv",
            "x86_match_result_owner_step.reflect.json"
        );
        let match_pattern_owner_init_pass = load_x86_pass!(
            "match_pattern_owner_init",
            "x86_match_pattern_owner_init.spv",
            "x86_match_pattern_owner_init.reflect.json"
        );
        let match_pattern_owner_step_pass = load_x86_pass!(
            "match_pattern_owner_step",
            "x86_match_pattern_owner_step.spv",
            "x86_match_pattern_owner_step.reflect.json"
        );
        let match_pattern_records_pass = load_x86_pass!(
            "match_pattern_records",
            "x86_match_pattern_records.spv",
            "x86_match_pattern_records.reflect.json"
        );
        let match_pattern_finalize_pass = load_x86_pass!(
            "match_pattern_finalize",
            "x86_match_pattern_finalize.spv",
            "x86_match_pattern_finalize.reflect.json"
        );
        let return_match_records_pass = load_x86_pass!(
            "return_match_records",
            "x86_return_match_records.spv",
            "x86_return_match_records.reflect.json"
        );
        let match_ownership_pass = load_x86_pass!(
            "match_ownership",
            "x86_match_ownership.spv",
            "x86_match_ownership.reflect.json"
        );
        let enclosing_return_init_pass = load_x86_pass!(
            "enclosing_return_init",
            "x86_enclosing_return_init.spv",
            "x86_enclosing_return_init.reflect.json"
        );
        let enclosing_return_step_pass = load_x86_pass!(
            "enclosing_return_step",
            "x86_enclosing_return_step.spv",
            "x86_enclosing_return_step.reflect.json"
        );
        let enclosing_let_init_pass = load_x86_pass!(
            "enclosing_let_init",
            "x86_enclosing_let_init.spv",
            "x86_enclosing_let_init.reflect.json"
        );
        let enclosing_let_step_pass = load_x86_pass!(
            "enclosing_let_step",
            "x86_enclosing_let_step.spv",
            "x86_enclosing_let_step.reflect.json"
        );
        let enclosing_stmt_init_pass = load_x86_pass!(
            "enclosing_stmt_init",
            "x86_enclosing_stmt_init.spv",
            "x86_enclosing_stmt_init.reflect.json"
        );
        let enclosing_stmt_step_pass = load_x86_pass!(
            "enclosing_stmt_step",
            "x86_enclosing_stmt_step.spv",
            "x86_enclosing_stmt_step.reflect.json"
        );
        let decl_widths_pass = load_x86_pass!(
            "decl_widths",
            "x86_decl_widths.spv",
            "x86_decl_widths.reflect.json"
        );
        let decl_layout_pass = load_x86_pass!(
            "decl_layout",
            "x86_decl_layout.spv",
            "x86_decl_layout.reflect.json"
        );
        let call_records_pass = load_x86_pass!(
            "call_records",
            "x86_call_records.spv",
            "x86_call_records.reflect.json"
        );
        let call_callee_owner_init_pass = load_x86_pass!(
            "call_callee_owner_init",
            "x86_call_callee_owner_init.spv",
            "x86_call_callee_owner_init.reflect.json"
        );
        let call_callee_owner_step_pass = load_x86_pass!(
            "call_callee_owner_step",
            "x86_call_callee_owner_step.spv",
            "x86_call_callee_owner_step.reflect.json"
        );
        let const_values_pass = load_x86_pass!(
            "const_values",
            "x86_const_values.spv",
            "x86_const_values.reflect.json"
        );
        let param_regs_pass = load_x86_pass!(
            "param_regs",
            "x86_param_regs.spv",
            "x86_param_regs.reflect.json"
        );
        let local_literals_pass = load_x86_pass!(
            "local_literals",
            "x86_local_literals.spv",
            "x86_local_literals.reflect.json"
        );
        let call_arg_values_pass = load_x86_pass!(
            "call_arg_values",
            "x86_call_arg_values.spv",
            "x86_call_arg_values.reflect.json"
        );
        let intrinsic_calls_pass = load_x86_pass!(
            "intrinsic_calls",
            "x86_intrinsic_calls.spv",
            "x86_intrinsic_calls.reflect.json"
        );
        let call_abi_pass =
            load_x86_pass!("call_abi", "x86_call_abi.spv", "x86_call_abi.reflect.json");
        let node_inst_counts_pass = load_x86_pass!(
            "node_inst_counts",
            "x86_node_inst_counts.spv",
            "x86_node_inst_counts.reflect.json"
        );
        let node_inst_same_end_rank_init_pass = load_x86_pass!(
            "node_inst_same_end_rank_init",
            "x86_node_inst_same_end_rank_init.spv",
            "x86_node_inst_same_end_rank_init.reflect.json"
        );
        let node_inst_same_end_rank_step_pass = load_x86_pass!(
            "node_inst_same_end_rank_step",
            "x86_node_inst_same_end_rank_step.spv",
            "x86_node_inst_same_end_rank_step.reflect.json"
        );
        let node_inst_end_counts_pass = load_x86_pass!(
            "node_inst_end_counts",
            "x86_node_inst_end_counts.spv",
            "x86_node_inst_end_counts.reflect.json"
        );
        let node_inst_order_pass = load_x86_pass!(
            "node_inst_order",
            "x86_node_inst_order.spv",
            "x86_node_inst_order.reflect.json"
        );
        let node_order_dispatch_args_pass = load_x86_pass!(
            "node_order_dispatch_args",
            "x86_node_order_dispatch_args.spv",
            "x86_node_order_dispatch_args.reflect.json"
        );
        let node_inst_scan_local_pass = load_x86_pass!(
            "node_inst_scan_local",
            "x86_node_inst_scan_local.spv",
            "x86_node_inst_scan_local.reflect.json"
        );
        let node_inst_scan_blocks_pass = load_x86_pass!(
            "node_inst_scan_blocks",
            "x86_node_inst_scan_blocks.spv",
            "x86_node_inst_scan_blocks.reflect.json"
        );
        let node_inst_prefix_scan_pass = load_x86_pass!(
            "node_inst_prefix_scan",
            "x86_node_inst_prefix_scan.spv",
            "x86_node_inst_prefix_scan.reflect.json"
        );
        let node_inst_subtree_bounds_pass = load_x86_pass!(
            "node_inst_subtree_bounds",
            "x86_node_inst_subtree_bounds.spv",
            "x86_node_inst_subtree_bounds.reflect.json"
        );
        let node_inst_locations_pass = load_x86_pass!(
            "node_inst_locations",
            "x86_node_inst_locations.spv",
            "x86_node_inst_locations.reflect.json"
        );
        let node_inst_gen_worklist_scatter_pass = load_x86_pass!(
            "node_inst_gen_worklist_scatter",
            "x86_node_inst_gen_worklist_scatter.spv",
            "x86_node_inst_gen_worklist_scatter.reflect.json"
        );
        let node_inst_gen_worklist_dispatch_args_pass = load_x86_pass!(
            "node_inst_gen_worklist_dispatch_args",
            "x86_node_inst_gen_worklist_dispatch_args.spv",
            "x86_node_inst_gen_worklist_dispatch_args.reflect.json"
        );
        let enclosing_loop_init_pass = load_x86_pass!(
            "enclosing_loop_init",
            "x86_enclosing_loop_init.spv",
            "x86_enclosing_loop_init.reflect.json"
        );
        let enclosing_loop_step_pass = load_x86_pass!(
            "enclosing_loop_step",
            "x86_enclosing_loop_step.spv",
            "x86_enclosing_loop_step.reflect.json"
        );
        let node_inst_gen_inputs_pass = load_x86_pass!(
            "node_inst_gen_inputs",
            "x86_node_inst_gen_inputs.spv",
            "x86_node_inst_gen_inputs.reflect.json"
        );
        let virtual_inst_clear_dispatch_args_pass = load_x86_pass!(
            "virtual_inst_clear_dispatch_args",
            "x86_virtual_inst_clear_dispatch_args.spv",
            "x86_virtual_inst_clear_dispatch_args.reflect.json"
        );
        let virtual_inst_clear_pass = load_x86_pass!(
            "virtual_inst_clear",
            "x86_virtual_inst_clear.spv",
            "x86_virtual_inst_clear.reflect.json"
        );
        let node_inst_gen_pass = load_x86_pass!(
            "node_inst_gen",
            "x86_node_inst_gen.spv",
            "x86_node_inst_gen.reflect.json"
        );
        let aggregate_literal_return_copy_flags_pass = load_x86_pass!(
            "aggregate_literal_return_copy_flags",
            "x86_aggregate_literal_return_copy_flags.spv",
            "x86_aggregate_literal_return_copy_flags.reflect.json"
        );
        let aggregate_literal_return_copy_pass = load_x86_pass!(
            "aggregate_literal_return_copy",
            "x86_aggregate_literal_return_copy.spv",
            "x86_aggregate_literal_return_copy.reflect.json"
        );
        let node_inst_gen_aggregate_copy_pass = load_x86_pass!(
            "node_inst_gen_aggregate_copy",
            "x86_node_inst_gen_aggregate_copy.spv",
            "x86_node_inst_gen_aggregate_copy.reflect.json"
        );
        let virtual_liveness_init_pass = load_x86_pass!(
            "virtual_liveness_init",
            "x86_virtual_liveness_init.spv",
            "x86_virtual_liveness_init.reflect.json"
        );
        let virtual_liveness_pass = load_x86_pass!(
            "virtual_liveness",
            "x86_virtual_liveness.spv",
            "x86_virtual_liveness.reflect.json"
        );
        let virtual_next_calls_pass = load_x86_pass!(
            "virtual_next_calls",
            "x86_virtual_next_calls.spv",
            "x86_virtual_next_calls.reflect.json"
        );
        let virtual_spans_fixed_barrier_pass = load_x86_pass!(
            "virtual_spans_fixed_barrier",
            "x86_virtual_spans_fixed_barrier.spv",
            "x86_virtual_spans_fixed_barrier.reflect.json"
        );
        let virtual_value_def_flags_pass = load_x86_pass!(
            "virtual_value_def_flags",
            "x86_virtual_value_def_flags.spv",
            "x86_virtual_value_def_flags.reflect.json"
        );
        let virtual_value_def_compact_pass = load_x86_pass!(
            "virtual_value_def_compact",
            "x86_virtual_value_def_compact.spv",
            "x86_virtual_value_def_compact.reflect.json"
        );
        let virtual_param_masks_pass = load_x86_pass!(
            "virtual_param_masks",
            "x86_virtual_param_masks.spv",
            "x86_virtual_param_masks.reflect.json"
        );
        let virtual_regalloc_pass = load_x86_pass!(
            "virtual_regalloc",
            "x86_virtual_regalloc.spv",
            "x86_virtual_regalloc.reflect.json"
        );
        let virtual_func_rows_init_pass = load_x86_pass!(
            "virtual_func_rows_init",
            "x86_virtual_func_rows_init.spv",
            "x86_virtual_func_rows_init.reflect.json"
        );
        let virtual_func_first_row_pass = load_x86_pass!(
            "virtual_func_first_row",
            "x86_virtual_func_first_row.spv",
            "x86_virtual_func_first_row.reflect.json"
        );
        let virtual_func_span_max_pass = load_x86_pass!(
            "virtual_func_span_max",
            "x86_virtual_func_span_max.spv",
            "x86_virtual_func_span_max.reflect.json"
        );
        let virtual_regalloc_dispatch_args_pass = load_x86_pass!(
            "virtual_regalloc_dispatch_args",
            "x86_virtual_regalloc_dispatch_args.spv",
            "x86_virtual_regalloc_dispatch_args.reflect.json"
        );
        let select_pass = load_x86_pass!("select", "x86_select.spv", "x86_select.reflect.json");
        let inst_size_pass = load_x86_pass!(
            "inst_size",
            "x86_inst_size.spv",
            "x86_inst_size.reflect.json"
        );
        let text_scan_local_pass = load_x86_pass!(
            "text_scan_local",
            "x86_text_scan_local.spv",
            "x86_text_scan_local.reflect.json"
        );
        let text_offsets_pass = load_x86_pass!(
            "text_offsets",
            "x86_text_offsets.spv",
            "x86_text_offsets.reflect.json"
        );
        let encode_pass = load_x86_pass!("encode", "x86_encode.spv", "x86_encode.reflect.json");
        let elf_layout_pass = load_x86_pass!(
            "elf_layout",
            "x86_elf_layout.spv",
            "x86_elf_layout.reflect.json"
        );
        let elf_write_pass = load_x86_pass!(
            "elf_write",
            "x86_elf_write.spv",
            "x86_elf_write.reflect.json"
        );
        Ok(Self {
            fill_u32_pass,
            active_clear_u32_pass,
            active_scan_dispatch_args_pass,
            virtual_dispatch_args_pass,
            output_dispatch_args_pass,
            feature_counts_pass,
            node_tree_info_pass,
            func_discover_pass,
            func_slot_flags_pass,
            func_slot_scatter_pass,
            func_owner_scan_local_pass,
            func_owner_scan_blocks_pass,
            func_assign_nodes_pass,
            func_assign_nodes_step_pass,
            expr_resolve_init_pass,
            expr_resolve_step_pass,
            expr_semantic_type_init_pass,
            expr_semantic_type_step_pass,
            enum_records_pass,
            struct_records_pass,
            array_records_pass,
            match_records_pass,
            match_result_owner_init_pass,
            match_result_owner_step_pass,
            match_pattern_owner_init_pass,
            match_pattern_owner_step_pass,
            match_pattern_records_pass,
            match_pattern_finalize_pass,
            return_match_records_pass,
            match_ownership_pass,
            enclosing_return_init_pass,
            enclosing_return_step_pass,
            enclosing_let_init_pass,
            enclosing_let_step_pass,
            enclosing_stmt_init_pass,
            enclosing_stmt_step_pass,
            decl_widths_pass,
            decl_layout_pass,
            call_records_pass,
            call_callee_owner_init_pass,
            call_callee_owner_step_pass,
            const_values_pass,
            param_regs_pass,
            local_literals_pass,
            call_arg_values_pass,
            intrinsic_calls_pass,
            call_abi_pass,
            node_inst_counts_pass,
            node_inst_same_end_rank_init_pass,
            node_inst_same_end_rank_step_pass,
            node_inst_end_counts_pass,
            node_inst_order_pass,
            node_order_dispatch_args_pass,
            node_inst_scan_local_pass,
            node_inst_scan_blocks_pass,
            node_inst_prefix_scan_pass,
            node_inst_subtree_bounds_pass,
            node_inst_locations_pass,
            node_inst_gen_worklist_scatter_pass,
            node_inst_gen_worklist_dispatch_args_pass,
            enclosing_loop_init_pass,
            enclosing_loop_step_pass,
            node_inst_gen_inputs_pass,
            virtual_inst_clear_dispatch_args_pass,
            virtual_inst_clear_pass,
            node_inst_gen_pass,
            aggregate_literal_return_copy_flags_pass,
            aggregate_literal_return_copy_pass,
            node_inst_gen_aggregate_copy_pass,
            virtual_liveness_init_pass,
            virtual_liveness_pass,
            virtual_next_calls_pass,
            virtual_spans_fixed_barrier_pass,
            virtual_value_def_flags_pass,
            virtual_value_def_compact_pass,
            virtual_param_masks_pass,
            virtual_regalloc_pass,
            virtual_func_rows_init_pass,
            virtual_func_first_row_pass,
            virtual_func_span_max_pass,
            virtual_regalloc_dispatch_args_pass,
            select_pass,
            inst_size_pass,
            text_scan_local_pass,
            text_offsets_pass,
            encode_pass,
            elf_layout_pass,
            elf_write_pass,
        })
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn x86_function_slot_capacity_shrinks_sparse_token_sized_slots() {
        let capacity = x86_function_slot_capacity(424_994, 424_994, 92_102);
        assert_eq!(capacity, 30_765);
        assert!(
            capacity < 92_102,
            "function-slot scratch should not default to one slot per token"
        );
    }

    #[test]
    fn x86_function_slot_capacity_keeps_structural_limits_when_smaller() {
        assert_eq!(x86_function_slot_capacity(20, 10_000, 100_000), 20);
        assert_eq!(x86_function_slot_capacity(10_000, 20, 100_000), 20);
        assert_eq!(x86_function_slot_capacity(10_000, 100_000, 20), 20);
    }

    #[test]
    fn x86_function_slot_capacity_keeps_at_least_one_slot() {
        assert_eq!(x86_function_slot_capacity(0, 0, 0), 1);
        assert_eq!(x86_function_slot_capacity(0, 100, 100), 1);
    }

    #[test]
    fn x86_node_inst_gen_worklist_is_compact_instruction_bounded() {
        let hir_words = 18_260_036;
        let inst_capacity = 1_048_576;
        let worklist_words = x86_node_inst_gen_node_record_words(hir_words, inst_capacity);
        let legacy_words = hir_words.saturating_add(1).saturating_mul(2);

        assert_eq!(worklist_words, inst_capacity.saturating_mul(2));
        assert!(worklist_words < legacy_words);
    }

    #[test]
    fn x86_node_inst_gen_worklist_does_not_grow_small_programs() {
        let hir_words = 512;
        let inst_capacity = 8_000;
        let worklist_words = x86_node_inst_gen_node_record_words(hir_words, inst_capacity);
        let legacy_words = hir_words.saturating_add(1).saturating_mul(2);

        assert!(worklist_words <= legacy_words);
    }

    #[test]
    fn x86_initial_output_readback_uses_source_and_capacity_sized_window() {
        let output_capacity = 1_493_000;
        let source_len = 308_800;
        let readback = x86_initial_output_readback_bytes(output_capacity, source_len);

        assert_eq!(readback % 4, 0);
        assert!(readback < output_capacity);
        assert!(readback >= source_len);
        assert!(readback >= output_capacity / 2);
    }

    #[test]
    fn x86_initial_output_readback_covers_output_dense_generated_programs() {
        let output_capacity = 1_877_808;
        let source_len = 305_424;
        let observed_mixed_output_len = 830_683;
        let readback = x86_initial_output_readback_bytes(output_capacity, source_len);

        assert!(readback >= observed_mixed_output_len);
        assert!(readback < output_capacity);
    }

    #[test]
    fn x86_initial_output_readback_keeps_small_outputs_whole() {
        assert_eq!(x86_initial_output_readback_bytes(4096, 10), 4096);
        assert_eq!(x86_initial_output_readback_bytes(1024, 0), 1024);
    }
}
