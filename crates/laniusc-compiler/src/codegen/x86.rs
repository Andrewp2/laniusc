//! GPU x86_64 backend lowering.
//!
//! This module records backend passes that lower parser HIR and retained
//! type-check metadata to ELF bytes. Public helpers expose target status,
//! feature/capacity estimates, and pass contracts used by tests and compiler
//! authors to reason about bounded backend behavior.

use std::fmt;

use anyhow::Result;
use encase::ShaderType;

use crate::gpu::{
    device,
    passes_core::{PassData, make_traced_main_pass},
};

mod finish;
mod record;
mod support;

pub use record::{RecordElfInputs, RecordedX86FeatureMeasurement};
use support::{PooledReadbackBuffer, PooledStorageBuffer, RetainedX86Buffer, trace_x86_codegen};

/// Target-level error reported by the GPU x86_64 emitter.
#[derive(Debug)]
pub struct X86OutputError {
    error_name: &'static str,
    error_code: u32,
    error_detail: u32,
}

impl X86OutputError {
    fn new(error_name: &'static str, error_code: u32, error_detail: u32) -> Self {
        Self {
            error_name,
            error_code,
            error_detail,
        }
    }

    /// Returns the backend status name associated with this error.
    pub fn error_name(&self) -> &'static str {
        self.error_name
    }

    /// Returns a user-facing diagnostic message for this backend boundary.
    pub fn public_message(&self) -> String {
        self.error_name.replace('_', " ")
    }

    /// Returns the numeric backend status code.
    pub fn error_code(&self) -> u32 {
        self.error_code
    }

    /// Returns the status detail word reported by the backend.
    pub fn error_detail(&self) -> u32 {
        self.error_detail
    }

    /// Returns whether `error_detail` should be interpreted as a HIR node id.
    pub fn detail_is_hir_node(&self) -> bool {
        matches!(
            self.error_code,
            X86_ERR_NODE_INST_COUNTS
                | 11
                | X86_ERR_VIRTUAL_LIVENESS
                | X86_ERR_NODE_INST_LOCATIONS
                | 17
                | X86_ERR_INTRINSIC_CALLS
                | 24
                | 26
                | 27
                | X86_ERR_STRUCT_RECORDS
                | 29
                | 30
                | 31
                | 32
                | 33
                | 34
                | 35
                | 37
                | 38
                | 39
                | 40
                | 41
                | 42
                | 43
                | 44
                | 45
                | 46
                | 47
                | X86_ERR_REGALLOC_BOUNDARY
                | 49
                | 51
                | 52
                | 53
                | 54
                | 55
                | X86_ERR_MULTIPLE_MAIN
                | X86_ERR_UNSUPPORTED_LITERAL_EXPR
                | X86_ERR_NESTED_AGGREGATE_MEMBER
                | X86_ERR_SIGNED_DIV_OVERFLOW
                | X86_ERR_HIR_TREE_SHAPE
                | X86_ERR_RODATA_SIZE
                | X86_ERR_RODATA_OFFSET
                | X86_ERR_RODATA_WRITE
        )
    }

    /// Returns whether `error_detail` should be interpreted as a token index.
    pub fn detail_is_token(&self) -> bool {
        matches!(self.error_code, 9 | 25 | 56)
    }
}

impl fmt::Display for X86OutputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("x86 code generation reached an unsupported backend boundary")
    }
}

impl std::error::Error for X86OutputError {}

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

/// Feature-mask bit for enum lowering.
pub const X86_FEATURE_ENUM: u32 = 1 << 0;
/// Feature-mask bit for match lowering.
pub const X86_FEATURE_MATCH: u32 = 1 << 1;
/// Feature-mask bit for aggregate literal/member lowering.
pub const X86_FEATURE_AGGREGATE: u32 = 1 << 2;
/// Feature-mask bit for function or intrinsic call lowering.
pub const X86_FEATURE_CALL: u32 = 1 << 3;
/// Status code for unsupported per-node instruction count planning.
pub(super) const X86_ERR_NODE_INST_COUNTS: u32 = 10;
/// Status code for unsupported virtual register liveness propagation.
pub(super) const X86_ERR_VIRTUAL_LIVENESS: u32 = 14;
/// Status code for unsupported instruction location assignment.
pub(super) const X86_ERR_NODE_INST_LOCATIONS: u32 = 16;
/// Status code for unsupported intrinsic call lowering.
pub(super) const X86_ERR_INTRINSIC_CALLS: u32 = 21;
/// Status code for unsupported struct or aggregate record lowering.
pub(super) const X86_ERR_STRUCT_RECORDS: u32 = 28;
/// Status code for register-allocation boundary failures.
pub(super) const X86_ERR_REGALLOC_BOUNDARY: u32 = 48;
/// Status code for unsupported HIR tree shapes.
pub(super) const X86_ERR_HIR_TREE_SHAPE: u32 = 57;
/// Status code for signed division overflow or zero-divisor checks.
pub(super) const X86_ERR_SIGNED_DIV_OVERFLOW: u32 = 59;
/// Status code for literal expressions not supported by x86 lowering.
pub(crate) const X86_ERR_UNSUPPORTED_LITERAL_EXPR: u32 = 60;
/// Status code for nested aggregate member lowering that is not supported.
pub(super) const X86_ERR_NESTED_AGGREGATE_MEMBER: u32 = 61;
/// Status code for programs with more than one x86 main entrypoint.
pub(super) const X86_ERR_MULTIPLE_MAIN: u32 = 62;
/// Status code for rodata byte-size planning failures.
pub(super) const X86_ERR_RODATA_SIZE: u32 = 63;
/// Status code for rodata offset planning failures.
pub(super) const X86_ERR_RODATA_OFFSET: u32 = 64;
/// Status code for rodata byte emission failures.
pub(super) const X86_ERR_RODATA_WRITE: u32 = 65;

/// Measured backend feature usage used for x86_64 capacity and pass selection.
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

    /// Returns whether enum lowering is required.
    pub fn has_enum(self) -> bool {
        self.mask & X86_FEATURE_ENUM != 0
    }

    /// Returns whether match lowering is required.
    pub fn has_match(self) -> bool {
        self.mask & X86_FEATURE_MATCH != 0
    }

    #[allow(dead_code)]
    /// Returns whether aggregate lowering is required.
    pub fn has_aggregate(self) -> bool {
        self.mask & X86_FEATURE_AGGREGATE != 0
    }

    /// Returns whether call lowering is required.
    pub fn has_call(self) -> bool {
        self.mask & X86_FEATURE_CALL != 0
    }

    /// Returns whether any function parameters were observed.
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

/// Type-check and parser metadata buffers needed by x86 expression lowering.
pub struct GpuX86ExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub expr_result_root_node: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub float_bits: &'a wgpu::Buffer,
    pub string_start: &'a wgpu::Buffer,
    pub string_len: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub type_form: &'a wgpu::Buffer,
    pub type_len_value: &'a wgpu::Buffer,
}

/// Function and parameter metadata buffers needed by x86 lowering.
pub struct GpuX86FunctionMetadataBuffers<'a> {
    pub node_decl_token: &'a wgpu::Buffer,
    pub node_name_token: &'a wgpu::Buffer,
    pub hir_token_pos: &'a wgpu::Buffer,
    pub fn_return_type_node: &'a wgpu::Buffer,
    pub param_record: &'a wgpu::Buffer,
    pub enclosing_fn: &'a wgpu::Buffer,
    pub method_decl_param_offset: &'a wgpu::Buffer,
    pub method_decl_receiver_mode: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_tag: &'a wgpu::Buffer,
    pub method_decl_receiver_ref_payload: &'a wgpu::Buffer,
}

/// Call and call-argument metadata buffers needed by x86 lowering.
pub struct GpuX86CallMetadataBuffers<'a> {
    pub name_id_by_token: &'a wgpu::Buffer,
    pub language_name_id: &'a wgpu::Buffer,
    pub path_count_out: &'a wgpu::Buffer,
    pub path_id_by_owner_hir: &'a wgpu::Buffer,
    pub resolved_value_decl: &'a wgpu::Buffer,
    pub resolved_value_status: &'a wgpu::Buffer,
    pub decl_name_token: &'a wgpu::Buffer,
    pub callee_node: &'a wgpu::Buffer,
    pub context_stmt_node: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
    pub arg_row_node: &'a wgpu::Buffer,
    pub arg_row_start: &'a wgpu::Buffer,
    pub arg_row_count: &'a wgpu::Buffer,
    pub member_receiver_node: &'a wgpu::Buffer,
    pub member_name_token: &'a wgpu::Buffer,
    pub call_fn_index: &'a wgpu::Buffer,
    pub call_intrinsic_tag: &'a wgpu::Buffer,
    pub call_return_type: &'a wgpu::Buffer,
    pub call_return_type_token: &'a wgpu::Buffer,
    pub call_param_type: &'a wgpu::Buffer,
}

/// Array literal metadata buffers needed by x86 aggregate lowering.
pub struct GpuX86ArrayMetadataBuffers<'a> {
    pub lit_first_element: &'a wgpu::Buffer,
    pub lit_element_count: &'a wgpu::Buffer,
    pub element_parent_lit: &'a wgpu::Buffer,
    pub element_ordinal: &'a wgpu::Buffer,
    pub element_next: &'a wgpu::Buffer,
}

/// Enum, variant, path, and match metadata buffers needed by x86 lowering.
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

/// Struct declaration, literal, and member metadata buffers needed by x86 lowering.
pub struct GpuX86StructMetadataBuffers<'a> {
    pub item_name_token: &'a wgpu::Buffer,
    pub decl_hir_node: &'a wgpu::Buffer,
    pub struct_decl_field_count: &'a wgpu::Buffer,
    pub struct_lit_head_node: &'a wgpu::Buffer,
    pub struct_lit_context_stmt_node: &'a wgpu::Buffer,
    pub struct_field_parent_struct: &'a wgpu::Buffer,
    pub struct_field_ordinal: &'a wgpu::Buffer,
    pub struct_field_type_node: &'a wgpu::Buffer,
    pub struct_decl_field_start: &'a wgpu::Buffer,
    pub struct_lit_field_parent_lit: &'a wgpu::Buffer,
    pub struct_lit_field_start: &'a wgpu::Buffer,
    pub struct_lit_field_count: &'a wgpu::Buffer,
    pub struct_lit_field_value_node: &'a wgpu::Buffer,
    pub struct_lit_field_next: &'a wgpu::Buffer,
    pub member_result_field_ordinal: &'a wgpu::Buffer,
    pub member_result_field_node: &'a wgpu::Buffer,
    pub struct_init_field_ordinal: &'a wgpu::Buffer,
    pub struct_init_field_ordinal_by_node: &'a wgpu::Buffer,
    pub struct_init_field_decl_node_by_node: &'a wgpu::Buffer,
}

/// Type reference and type-instance metadata buffers needed by x86 lowering.
pub struct GpuX86TypeMetadataBuffers<'a> {
    pub type_value_node: &'a wgpu::Buffer,
    pub type_path_leaf_node: &'a wgpu::Buffer,
    pub decl_type_ref_tag: &'a wgpu::Buffer,
    pub decl_type_ref_payload: &'a wgpu::Buffer,
    pub type_expr_ref_tag: &'a wgpu::Buffer,
    pub type_expr_ref_payload: &'a wgpu::Buffer,
    pub module_type_path_type: &'a wgpu::Buffer,
    pub type_decl_hir_node_by_token: &'a wgpu::Buffer,
    pub visible_type: &'a wgpu::Buffer,
    pub type_instance_kind: &'a wgpu::Buffer,
    pub type_instance_decl_token: &'a wgpu::Buffer,
    pub type_instance_elem_ref_tag: &'a wgpu::Buffer,
    pub type_instance_elem_ref_payload: &'a wgpu::Buffer,
    pub type_instance_len_kind: &'a wgpu::Buffer,
    pub type_instance_len_payload: &'a wgpu::Buffer,
}

/// Optional caller-owned scratch buffers reused by one x86 recording.
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
    /// Counts scratch buffers borrowed by this recording.
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
const X86_ENCODE_MAX_BYTES_PER_INST: usize = 128;
// Mirror Pareas' lockstep register-allocation shape: each dispatch step
// advances a small fixed chunk for every function, carrying per-function
// active state between chunks. Regalloc consumes compact value-definition rows,
// so this bound is over semantic defs rather than every virtual instruction.
const X86_REGALLOC_ROWS_PER_CHUNK: usize = 32;

const X86_ENCODE_PASS_CONTRACT_SCHEMA: &str = "lanius.x86.encode-pass-contract.v1";
const X86_ENCODE_LOOP_STATUS: &str = "bounded-local";
const X86_ENCODE_FALLBACK_STATUS: &str = "fail-closed";
const X86_ENCODE_CLAIM_STATUS: &str = "not-blocking";
const X86_ENCODE_SOURCE_TEXT_STATUS: &str = "not-consumed";
const X86_ENCODE_BYTE_LOOP_BASIS: &str = "per_instruction_encoded_byte_width";
const X86_ENCODE_INPUT_ORDERING: &str =
    "prefix_instruction_sizes,scatter_instruction_bytes,patch_relocation_records";
const X86_ENCODE_GUARDS: &str =
    "text_status,reloc_status,text_len_matches_byte_offsets,out_capacity";
const X86_REGALLOC_PASS_CONTRACT_SCHEMA: &str = "lanius.x86.regalloc-pass-contract.v1";
const X86_REGALLOC_LOOP_STATUS: &str = "bounded";
const X86_REGALLOC_FALLBACK_STATUS: &str = "fail-closed";
const X86_REGALLOC_CLAIM_STATUS: &str = "blocked";
const X86_REGALLOC_CLAIM_BLOCKERS: &str =
    "bounded_value_def_chunk_loop,loop_carried_active_end,loop_carried_param_rank_mask";
const X86_REGALLOC_REQUIRED_REPLACEMENT: &str =
    "function_region_value_def_rows,segmented_state_composition,pressure_spill_stack_scans";
const X86_REGALLOC_RECORDED_SPAN_BASIS: &str = "instruction_capacity_not_source_len";
const X86_REGALLOC_CHUNK_SPAN_INVARIANT: &str =
    "recorded_chunks_times_rows_per_chunk_must_cover_inst_capacity";
const X86_CONTROL_FLOW_BRIDGE_PASS_CONTRACT_SCHEMA: &str =
    "lanius.x86.control-flow-bridge-pass-contract.v1";
const X86_CONTROL_FLOW_BRIDGE_LOOP_STATUS: &str = "bounded";
const X86_CONTROL_FLOW_BRIDGE_FALLBACK_STATUS: &str = "fail-closed";
const X86_CONTROL_FLOW_BRIDGE_CLAIM_STATUS: &str = "blocked";
const X86_CONTROL_FLOW_BRIDGE_RELATIONS: &str =
    "node_inst_same_end_rank,enclosing_loop,short_circuit_rhs,index_source_owner";
const X86_CONTROL_FLOW_BRIDGE_CLAIM_BLOCKERS: &str = "pre_basic_block_owner_bridge,pointer_jump_widths_scale_with_hir_rows,virtual_generation_consumes_bridge_rows";
const X86_CONTROL_FLOW_BRIDGE_REQUIRED_REPLACEMENT: &str =
    "basic_block_edge_rows,control_region_records,segmented_control_flow_scans";
const X86_CONTROL_FLOW_BRIDGE_RECORD_ORDERING: &str =
    "record_relations,prefix_control_regions,sort_join_edges,scatter_virtual_rows";
const X86_LOWERING_PASS_CONTRACT_SCHEMA: &str = "lanius.x86.lowering-pass-contract.v1";
const X86_LOWERING_LOOP_STATUS: &str = "bounded";
const X86_LOWERING_FALLBACK_STATUS: &str = "fail-closed";
const X86_LOWERING_CLAIM_STATUS: &str = "blocked";
const X86_LOWERING_SOURCE_TEXT_STATUS: &str = "not-consumed";
const X86_LOWERING_FUNCTION_BODY_RECOGNIZER_STATUS: &str = "forbidden";
const X86_LOWERING_RELATIONS: &str =
    "hir_expr_record,hir_stmt_record,visible_decl,x86_node_inst_order,x86_virtual_inst_record";
const X86_LOWERING_CLAIM_BLOCKERS: &str =
    "bounded_shape_specific_lowering,pre_basic_block_control_padding,non_ssa_virtual_generation";
const X86_LOWERING_REQUIRED_REPLACEMENT: &str =
    "generic_operation_records,basic_block_edge_rows,segmented_virtual_instruction_scatter";
const X86_LOWERING_RECORD_ORDERING: &str =
    "record_semantic_rows,prefix_instruction_counts,scatter_virtual_rows,encode_from_virtual_rows";

/// Documentation contract for the x86 byte encoding passes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86EncodePassContract {
    pub schema: &'static str,
    pub loop_status: &'static str,
    pub fallback_status: &'static str,
    pub claim_status: &'static str,
    pub source_text_status: &'static str,
    pub byte_loop_basis: &'static str,
    pub max_bytes_per_instruction: usize,
    pub input_ordering: &'static str,
    pub guards: &'static str,
}

/// Returns the byte-encoding pass contract used by audits and tests.
pub fn x86_encode_pass_contract() -> X86EncodePassContract {
    X86EncodePassContract {
        schema: X86_ENCODE_PASS_CONTRACT_SCHEMA,
        loop_status: X86_ENCODE_LOOP_STATUS,
        fallback_status: X86_ENCODE_FALLBACK_STATUS,
        claim_status: X86_ENCODE_CLAIM_STATUS,
        source_text_status: X86_ENCODE_SOURCE_TEXT_STATUS,
        byte_loop_basis: X86_ENCODE_BYTE_LOOP_BASIS,
        max_bytes_per_instruction: X86_ENCODE_MAX_BYTES_PER_INST,
        input_ordering: X86_ENCODE_INPUT_ORDERING,
        guards: X86_ENCODE_GUARDS,
    }
}

/// Documentation contract for the current x86 register-allocation passes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86RegallocPassContract {
    pub schema: &'static str,
    pub loop_status: &'static str,
    pub fallback_status: &'static str,
    pub claim_status: &'static str,
    pub claim_blockers: &'static str,
    pub required_replacement: &'static str,
    pub recorded_span_basis: &'static str,
    pub chunk_span_invariant: &'static str,
    pub rows_per_chunk: usize,
}

/// Returns the register-allocation pass contract used by audits and tests.
pub fn x86_regalloc_pass_contract() -> X86RegallocPassContract {
    X86RegallocPassContract {
        schema: X86_REGALLOC_PASS_CONTRACT_SCHEMA,
        loop_status: X86_REGALLOC_LOOP_STATUS,
        fallback_status: X86_REGALLOC_FALLBACK_STATUS,
        claim_status: X86_REGALLOC_CLAIM_STATUS,
        claim_blockers: X86_REGALLOC_CLAIM_BLOCKERS,
        required_replacement: X86_REGALLOC_REQUIRED_REPLACEMENT,
        recorded_span_basis: X86_REGALLOC_RECORDED_SPAN_BASIS,
        chunk_span_invariant: X86_REGALLOC_CHUNK_SPAN_INVARIANT,
        rows_per_chunk: X86_REGALLOC_ROWS_PER_CHUNK,
    }
}

/// Documentation contract for the current x86 control-flow bridge passes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86ControlFlowBridgePassContract {
    pub schema: &'static str,
    pub loop_status: &'static str,
    pub fallback_status: &'static str,
    pub claim_status: &'static str,
    pub relation_count: usize,
    pub relations: &'static str,
    pub claim_blockers: &'static str,
    pub required_replacement: &'static str,
    pub record_ordering: &'static str,
}

/// Returns the control-flow bridge pass contract used by audits and tests.
pub fn x86_control_flow_bridge_pass_contract() -> X86ControlFlowBridgePassContract {
    X86ControlFlowBridgePassContract {
        schema: X86_CONTROL_FLOW_BRIDGE_PASS_CONTRACT_SCHEMA,
        loop_status: X86_CONTROL_FLOW_BRIDGE_LOOP_STATUS,
        fallback_status: X86_CONTROL_FLOW_BRIDGE_FALLBACK_STATUS,
        claim_status: X86_CONTROL_FLOW_BRIDGE_CLAIM_STATUS,
        relation_count: 4,
        relations: X86_CONTROL_FLOW_BRIDGE_RELATIONS,
        claim_blockers: X86_CONTROL_FLOW_BRIDGE_CLAIM_BLOCKERS,
        required_replacement: X86_CONTROL_FLOW_BRIDGE_REQUIRED_REPLACEMENT,
        record_ordering: X86_CONTROL_FLOW_BRIDGE_RECORD_ORDERING,
    }
}

/// Documentation contract for the current x86 lowering passes.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86LoweringPassContract {
    pub schema: &'static str,
    pub loop_status: &'static str,
    pub fallback_status: &'static str,
    pub claim_status: &'static str,
    pub source_text_status: &'static str,
    pub function_body_recognizer_status: &'static str,
    pub relation_count: usize,
    pub relations: &'static str,
    pub claim_blockers: &'static str,
    pub required_replacement: &'static str,
    pub record_ordering: &'static str,
}

/// Returns the lowering pass contract used by audits and tests.
pub fn x86_lowering_pass_contract() -> X86LoweringPassContract {
    X86LoweringPassContract {
        schema: X86_LOWERING_PASS_CONTRACT_SCHEMA,
        loop_status: X86_LOWERING_LOOP_STATUS,
        fallback_status: X86_LOWERING_FALLBACK_STATUS,
        claim_status: X86_LOWERING_CLAIM_STATUS,
        source_text_status: X86_LOWERING_SOURCE_TEXT_STATUS,
        function_body_recognizer_status: X86_LOWERING_FUNCTION_BODY_RECOGNIZER_STATUS,
        relation_count: 5,
        relations: X86_LOWERING_RELATIONS,
        claim_blockers: X86_LOWERING_CLAIM_BLOCKERS,
        required_replacement: X86_LOWERING_REQUIRED_REPLACEMENT,
        record_ordering: X86_LOWERING_RECORD_ORDERING,
    }
}

/// Conservative x86 backend capacity estimate for one recording.
#[derive(Clone, Copy, Debug, Eq, PartialEq)]
pub struct X86CapacityEstimate {
    pub hir_words: usize,
    pub inst_basis_words: usize,
    pub requested_inst_capacity: usize,
    pub inst_capacity: usize,
    pub inst_capacity_capped: bool,
    pub output_capacity: usize,
}

/// Estimates x86 capacities from HIR size alone.
pub fn x86_capacity_estimate_for_hir(hir_words: usize) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_with_limit(hir_words, X86_INST_CAPACITY_HIR_ESTIMATE_CAP)
}

/// Estimates x86 capacities from HIR size and token capacity.
pub fn x86_capacity_estimate_for_hir_and_tokens(
    hir_words: usize,
    token_capacity: usize,
) -> X86CapacityEstimate {
    x86_capacity_estimate_for_hir_tokens_and_inst_basis(hir_words, token_capacity, hir_words)
}

/// Estimates x86 capacities from HIR, token, and instruction-basis counts.
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

/// Estimates x86 capacities using measured backend feature usage when available.
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
        .map(|limit| limit.min(MAX_X86_INSTS))
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

/// Returns rows needed by compact node-instruction ordering.
pub fn x86_node_inst_order_rows(hir_words: usize, inst_capacity: usize) -> usize {
    inst_capacity.min(hir_words.max(1)).saturating_add(1)
}

/// Returns rows needed by the node-instruction worklist.
pub fn x86_node_inst_worklist_rows(hir_words: usize, inst_capacity: usize) -> usize {
    inst_capacity.max(1).min(hir_words.max(1))
}

/// Returns words needed for call type records.
pub fn x86_call_type_record_words(hir_words: usize, has_call: bool) -> usize {
    if has_call {
        hir_words.saturating_mul(3)
    } else {
        1
    }
}

/// Returns words needed for node instruction-count records.
pub fn x86_node_inst_count_record_words(hir_words: usize) -> usize {
    hir_words.saturating_mul(2)
}

/// Returns words needed for instruction-generation node records.
pub fn x86_node_inst_gen_node_record_words(hir_words: usize, inst_capacity: usize) -> usize {
    x86_node_inst_worklist_rows(hir_words, inst_capacity).saturating_mul(2)
}

/// Returns words needed for instruction ordering plus function-slot fallback rows.
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

/// Returns a conservative function-slot capacity bound for one recording.
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

/// Returns the number of recorded register-allocation steps.
pub fn regalloc_recorded_step_count(inst_capacity: usize) -> usize {
    inst_capacity.max(1)
}

/// Returns the number of fixed register-allocation chunks.
pub fn regalloc_recorded_chunk_count(inst_capacity: usize) -> usize {
    regalloc_recorded_step_count(inst_capacity)
        .div_ceil(X86_REGALLOC_ROWS_PER_CHUNK)
        .max(1)
}

/// Returns the total recorded register-allocation row span.
pub fn regalloc_recorded_span_rows(inst_capacity: usize) -> usize {
    regalloc_recorded_chunk_count(inst_capacity).saturating_mul(X86_REGALLOC_ROWS_PER_CHUNK)
}

/// Returns whether the recorded register-allocation span covers instruction capacity.
pub fn regalloc_recorded_span_covers_inst_capacity(inst_capacity: usize) -> bool {
    regalloc_recorded_span_rows(inst_capacity) >= inst_capacity.max(1)
}

/// Recorded x86 backend work and retained buffers required for output readback.
pub struct RecordedX86Codegen {
    output_capacity: usize,
    output_status_offset: u64,
    _retained_buffers: Vec<RetainedX86Buffer>,
    _retained_bind_groups: Vec<wgpu::BindGroup>,
    out_buf: PooledStorageBuffer,
    output_readback: PooledReadbackBuffer,
    status_trace_readback: Option<wgpu::Buffer>,
}

/// GPU x86_64 code generator with loaded compute passes.
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
    struct_field_widths_pass: PassData,
    struct_field_stream_pass: PassData,
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
    intrinsic_calls_pass: PassData,
    call_abi_pass: PassData,
    for_iterable_nodes_pass: PassData,
    node_control_padding_pass: PassData,
    postfix_operand_owner_pass: PassData,
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
    short_circuit_rhs_init_pass: PassData,
    short_circuit_rhs_step_pass: PassData,
    index_source_owner_init_pass: PassData,
    index_source_owner_step_pass: PassData,
    node_inst_gen_inputs_pass: PassData,
    virtual_inst_clear_dispatch_args_pass: PassData,
    virtual_inst_clear_pass: PassData,
    node_inst_gen_pass: PassData,
    node_inst_gen_function_params_pass: PassData,
    node_inst_gen_host_calls_pass: PassData,
    node_inst_gen_for_stmt_pass: PassData,
    node_inst_gen_control_stmt_pass: PassData,
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
    rodata_sizes_pass: PassData,
    rodata_scan_local_pass: PassData,
    rodata_offsets_pass: PassData,
    rodata_write_pass: PassData,
    reloc_scan_local_pass: PassData,
    reloc_records_pass: PassData,
    reloc_patch_pass: PassData,
    encode_pass: PassData,
    elf_layout_pass: PassData,
    elf_write_pass: PassData,
}

impl GpuX86CodeGenerator {
    /// Loads all x86 backend compute passes for a GPU device.
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

        let fill_u32_pass = load_x86_pass!(
            "fill_u32",
            "codegen/x86/fill_u32.spv",
            "codegen/x86/fill_u32.reflect.json"
        );
        let active_clear_u32_pass = load_x86_pass!(
            "active_clear_u32",
            "codegen/x86/active/clear_u32.spv",
            "codegen/x86/active/clear_u32.reflect.json"
        );
        let active_scan_dispatch_args_pass = load_x86_pass!(
            "active_scan_dispatch_args",
            "codegen/x86/active/scan_dispatch_args.spv",
            "codegen/x86/active/scan_dispatch_args.reflect.json"
        );
        let virtual_dispatch_args_pass = load_x86_pass!(
            "virtual_dispatch_args",
            "codegen/x86/virtual/dispatch_args.spv",
            "codegen/x86/virtual/dispatch_args.reflect.json"
        );
        let output_dispatch_args_pass = load_x86_pass!(
            "output_dispatch_args",
            "codegen/x86/output_dispatch_args.spv",
            "codegen/x86/output_dispatch_args.reflect.json"
        );
        let feature_counts_pass = load_x86_pass!(
            "feature_counts",
            "codegen/x86/feature_counts.spv",
            "codegen/x86/feature_counts.reflect.json"
        );
        let node_tree_info_pass = load_x86_pass!(
            "node_tree_info",
            "codegen/x86/node/tree_info.spv",
            "codegen/x86/node/tree_info.reflect.json"
        );
        let func_discover_pass = load_x86_pass!(
            "func_discover",
            "codegen/x86/func/discover.spv",
            "codegen/x86/func/discover.reflect.json"
        );
        let func_slot_flags_pass = load_x86_pass!(
            "func_slot_flags",
            "codegen/x86/func/slot/flags.spv",
            "codegen/x86/func/slot/flags.reflect.json"
        );
        let func_slot_scatter_pass = load_x86_pass!(
            "func_slot_scatter",
            "codegen/x86/func/slot/scatter.spv",
            "codegen/x86/func/slot/scatter.reflect.json"
        );
        let func_owner_scan_local_pass = load_x86_pass!(
            "func_owner_scan_local",
            "codegen/x86/func/owner/scan/local.spv",
            "codegen/x86/func/owner/scan/local.reflect.json"
        );
        let func_owner_scan_blocks_pass = load_x86_pass!(
            "func_owner_scan_blocks",
            "codegen/x86/func/owner/scan/blocks.spv",
            "codegen/x86/func/owner/scan/blocks.reflect.json"
        );
        let func_assign_nodes_pass = load_x86_pass!(
            "func_assign_nodes",
            "codegen/x86/func/assign/nodes.spv",
            "codegen/x86/func/assign/nodes.reflect.json"
        );
        let func_assign_nodes_step_pass = load_x86_pass!(
            "func_assign_nodes_step",
            "codegen/x86/func/assign/nodes/step.spv",
            "codegen/x86/func/assign/nodes/step.reflect.json"
        );
        let expr_resolve_init_pass = load_x86_pass!(
            "expr_resolve_init",
            "codegen/x86/expr/resolve/init.spv",
            "codegen/x86/expr/resolve/init.reflect.json"
        );
        let expr_resolve_step_pass = load_x86_pass!(
            "expr_resolve_step",
            "codegen/x86/expr/resolve/step.spv",
            "codegen/x86/expr/resolve/step.reflect.json"
        );
        let expr_semantic_type_init_pass = load_x86_pass!(
            "expr_semantic_type_init",
            "codegen/x86/expr/semantic/type/init.spv",
            "codegen/x86/expr/semantic/type/init.reflect.json"
        );
        let expr_semantic_type_step_pass = load_x86_pass!(
            "expr_semantic_type_step",
            "codegen/x86/expr/semantic/type/step.spv",
            "codegen/x86/expr/semantic/type/step.reflect.json"
        );
        let enum_records_pass = load_x86_pass!(
            "enum_records",
            "codegen/x86/enum_records.spv",
            "codegen/x86/enum_records.reflect.json"
        );
        let struct_field_widths_pass = load_x86_pass!(
            "struct_field_widths",
            "codegen/x86/struct_field_widths.spv",
            "codegen/x86/struct_field_widths.reflect.json"
        );
        let struct_field_stream_pass = load_x86_pass!(
            "struct_field_stream",
            "codegen/x86/struct_field_stream.spv",
            "codegen/x86/struct_field_stream.reflect.json"
        );
        let struct_records_pass = load_x86_pass!(
            "struct_records",
            "codegen/x86/struct_records.spv",
            "codegen/x86/struct_records.reflect.json"
        );
        let array_records_pass = load_x86_pass!(
            "array_records",
            "codegen/x86/array_records.spv",
            "codegen/x86/array_records.reflect.json"
        );
        let match_records_pass = load_x86_pass!(
            "match_records",
            "codegen/x86/match/records.spv",
            "codegen/x86/match/records.reflect.json"
        );
        let match_result_owner_init_pass = load_x86_pass!(
            "match_result_owner_init",
            "codegen/x86/match/result/owner/init.spv",
            "codegen/x86/match/result/owner/init.reflect.json"
        );
        let match_result_owner_step_pass = load_x86_pass!(
            "match_result_owner_step",
            "codegen/x86/match/result/owner/step.spv",
            "codegen/x86/match/result/owner/step.reflect.json"
        );
        let match_pattern_owner_init_pass = load_x86_pass!(
            "match_pattern_owner_init",
            "codegen/x86/match/pattern/owner/init.spv",
            "codegen/x86/match/pattern/owner/init.reflect.json"
        );
        let match_pattern_owner_step_pass = load_x86_pass!(
            "match_pattern_owner_step",
            "codegen/x86/match/pattern/owner/step.spv",
            "codegen/x86/match/pattern/owner/step.reflect.json"
        );
        let match_pattern_records_pass = load_x86_pass!(
            "match_pattern_records",
            "codegen/x86/match/pattern/records.spv",
            "codegen/x86/match/pattern/records.reflect.json"
        );
        let match_pattern_finalize_pass = load_x86_pass!(
            "match_pattern_finalize",
            "codegen/x86/match/pattern/finalize.spv",
            "codegen/x86/match/pattern/finalize.reflect.json"
        );
        let return_match_records_pass = load_x86_pass!(
            "return_match_records",
            "codegen/x86/return_match_records.spv",
            "codegen/x86/return_match_records.reflect.json"
        );
        let match_ownership_pass = load_x86_pass!(
            "match_ownership",
            "codegen/x86/match/ownership.spv",
            "codegen/x86/match/ownership.reflect.json"
        );
        let enclosing_return_init_pass = load_x86_pass!(
            "enclosing_return_init",
            "codegen/x86/enclosing/return/init.spv",
            "codegen/x86/enclosing/return/init.reflect.json"
        );
        let enclosing_return_step_pass = load_x86_pass!(
            "enclosing_return_step",
            "codegen/x86/enclosing/return/step.spv",
            "codegen/x86/enclosing/return/step.reflect.json"
        );
        let enclosing_let_init_pass = load_x86_pass!(
            "enclosing_let_init",
            "codegen/x86/enclosing/let/init.spv",
            "codegen/x86/enclosing/let/init.reflect.json"
        );
        let enclosing_let_step_pass = load_x86_pass!(
            "enclosing_let_step",
            "codegen/x86/enclosing/let/step.spv",
            "codegen/x86/enclosing/let/step.reflect.json"
        );
        let enclosing_stmt_init_pass = load_x86_pass!(
            "enclosing_stmt_init",
            "codegen/x86/enclosing/stmt/init.spv",
            "codegen/x86/enclosing/stmt/init.reflect.json"
        );
        let enclosing_stmt_step_pass = load_x86_pass!(
            "enclosing_stmt_step",
            "codegen/x86/enclosing/stmt/step.spv",
            "codegen/x86/enclosing/stmt/step.reflect.json"
        );
        let decl_widths_pass = load_x86_pass!(
            "decl_widths",
            "codegen/x86/decl/widths.spv",
            "codegen/x86/decl/widths.reflect.json"
        );
        let decl_layout_pass = load_x86_pass!(
            "decl_layout",
            "codegen/x86/decl/layout.spv",
            "codegen/x86/decl/layout.reflect.json"
        );
        let call_records_pass = load_x86_pass!(
            "call_records",
            "codegen/x86/call/records.spv",
            "codegen/x86/call/records.reflect.json"
        );
        let call_callee_owner_init_pass = load_x86_pass!(
            "call_callee_owner_init",
            "codegen/x86/call/callee/owner/init.spv",
            "codegen/x86/call/callee/owner/init.reflect.json"
        );
        let call_callee_owner_step_pass = load_x86_pass!(
            "call_callee_owner_step",
            "codegen/x86/call/callee/owner/step.spv",
            "codegen/x86/call/callee/owner/step.reflect.json"
        );
        let const_values_pass = load_x86_pass!(
            "const_values",
            "codegen/x86/const_values.spv",
            "codegen/x86/const_values.reflect.json"
        );
        let param_regs_pass = load_x86_pass!(
            "param_regs",
            "codegen/x86/param_regs.spv",
            "codegen/x86/param_regs.reflect.json"
        );
        let local_literals_pass = load_x86_pass!(
            "local_literals",
            "codegen/x86/local_literals.spv",
            "codegen/x86/local_literals.reflect.json"
        );
        let intrinsic_calls_pass = load_x86_pass!(
            "intrinsic_calls",
            "codegen/x86/intrinsic_calls.spv",
            "codegen/x86/intrinsic_calls.reflect.json"
        );
        let call_abi_pass = load_x86_pass!(
            "call_abi",
            "codegen/x86/call/abi.spv",
            "codegen/x86/call/abi.reflect.json"
        );
        let for_iterable_nodes_pass = load_x86_pass!(
            "for_iterable_nodes",
            "codegen/x86/for_iterable_nodes.spv",
            "codegen/x86/for_iterable_nodes.reflect.json"
        );
        let node_control_padding_pass = load_x86_pass!(
            "node_control_padding",
            "codegen/x86/node/control_padding.spv",
            "codegen/x86/node/control_padding.reflect.json"
        );
        let postfix_operand_owner_pass = load_x86_pass!(
            "postfix_operand_owner",
            "codegen/x86/postfix_operand_owner.spv",
            "codegen/x86/postfix_operand_owner.reflect.json"
        );
        let node_inst_counts_pass = load_x86_pass!(
            "node_inst_counts",
            "codegen/x86/node/inst/counts.spv",
            "codegen/x86/node/inst/counts.reflect.json"
        );
        let node_inst_same_end_rank_init_pass = load_x86_pass!(
            "node_inst_same_end_rank_init",
            "codegen/x86/node/inst/same/end/rank/init.spv",
            "codegen/x86/node/inst/same/end/rank/init.reflect.json"
        );
        let node_inst_same_end_rank_step_pass = load_x86_pass!(
            "node_inst_same_end_rank_step",
            "codegen/x86/node/inst/same/end/rank/step.spv",
            "codegen/x86/node/inst/same/end/rank/step.reflect.json"
        );
        let node_inst_end_counts_pass = load_x86_pass!(
            "node_inst_end_counts",
            "codegen/x86/node/inst/end_counts.spv",
            "codegen/x86/node/inst/end_counts.reflect.json"
        );
        let node_inst_order_pass = load_x86_pass!(
            "node_inst_order",
            "codegen/x86/node/inst/order.spv",
            "codegen/x86/node/inst/order.reflect.json"
        );
        let node_order_dispatch_args_pass = load_x86_pass!(
            "node_order_dispatch_args",
            "codegen/x86/node/order_dispatch_args.spv",
            "codegen/x86/node/order_dispatch_args.reflect.json"
        );
        let node_inst_scan_local_pass = load_x86_pass!(
            "node_inst_scan_local",
            "codegen/x86/node/inst/scan/local.spv",
            "codegen/x86/node/inst/scan/local.reflect.json"
        );
        let node_inst_scan_blocks_pass = load_x86_pass!(
            "node_inst_scan_blocks",
            "codegen/x86/node/inst/scan/blocks.spv",
            "codegen/x86/node/inst/scan/blocks.reflect.json"
        );
        let node_inst_prefix_scan_pass = load_x86_pass!(
            "node_inst_prefix_scan",
            "codegen/x86/node/inst/prefix_scan_pass.spv",
            "codegen/x86/node/inst/prefix_scan_pass.reflect.json"
        );
        let node_inst_subtree_bounds_pass = load_x86_pass!(
            "node_inst_subtree_bounds",
            "codegen/x86/node/inst/subtree_bounds.spv",
            "codegen/x86/node/inst/subtree_bounds.reflect.json"
        );
        let node_inst_locations_pass = load_x86_pass!(
            "node_inst_locations",
            "codegen/x86/node/inst/locations.spv",
            "codegen/x86/node/inst/locations.reflect.json"
        );
        let node_inst_gen_worklist_scatter_pass = load_x86_pass!(
            "node_inst_gen_worklist_scatter",
            "codegen/x86/node/inst/gen/worklist/scatter.spv",
            "codegen/x86/node/inst/gen/worklist/scatter.reflect.json"
        );
        let node_inst_gen_worklist_dispatch_args_pass = load_x86_pass!(
            "node_inst_gen_worklist_dispatch_args",
            "codegen/x86/node/inst/gen/worklist/dispatch_args.spv",
            "codegen/x86/node/inst/gen/worklist/dispatch_args.reflect.json"
        );
        let enclosing_loop_init_pass = load_x86_pass!(
            "enclosing_loop_init",
            "codegen/x86/enclosing/loop/init.spv",
            "codegen/x86/enclosing/loop/init.reflect.json"
        );
        let enclosing_loop_step_pass = load_x86_pass!(
            "enclosing_loop_step",
            "codegen/x86/enclosing/loop/step.spv",
            "codegen/x86/enclosing/loop/step.reflect.json"
        );
        let short_circuit_rhs_init_pass = load_x86_pass!(
            "short_circuit_rhs_init",
            "codegen/x86/short/circuit/rhs/init.spv",
            "codegen/x86/short/circuit/rhs/init.reflect.json"
        );
        let short_circuit_rhs_step_pass = load_x86_pass!(
            "short_circuit_rhs_step",
            "codegen/x86/short/circuit/rhs/step.spv",
            "codegen/x86/short/circuit/rhs/step.reflect.json"
        );
        let index_source_owner_init_pass = load_x86_pass!(
            "index_source_owner_init",
            "codegen/x86/index/source/owner/init.spv",
            "codegen/x86/index/source/owner/init.reflect.json"
        );
        let index_source_owner_step_pass = load_x86_pass!(
            "index_source_owner_step",
            "codegen/x86/index/source/owner/step.spv",
            "codegen/x86/index/source/owner/step.reflect.json"
        );
        let node_inst_gen_inputs_pass = load_x86_pass!(
            "node_inst_gen_inputs",
            "codegen/x86/node/inst/gen/inputs.spv",
            "codegen/x86/node/inst/gen/inputs.reflect.json"
        );
        let virtual_inst_clear_dispatch_args_pass = load_x86_pass!(
            "virtual_inst_clear_dispatch_args",
            "codegen/x86/virtual/inst/clear/dispatch_args.spv",
            "codegen/x86/virtual/inst/clear/dispatch_args.reflect.json"
        );
        let virtual_inst_clear_pass = load_x86_pass!(
            "virtual_inst_clear",
            "codegen/x86/virtual/inst/clear.spv",
            "codegen/x86/virtual/inst/clear.reflect.json"
        );
        let node_inst_gen_pass = load_x86_pass!(
            "node_inst_gen",
            "codegen/x86/node/inst/gen.spv",
            "codegen/x86/node/inst/gen.reflect.json"
        );
        let node_inst_gen_function_params_pass = load_x86_pass!(
            "node_inst_gen_function_params",
            "codegen/x86/node/inst/gen/function_params.spv",
            "codegen/x86/node/inst/gen/function_params.reflect.json"
        );
        let node_inst_gen_host_calls_pass = load_x86_pass!(
            "node_inst_gen_host_calls",
            "codegen/x86/node/inst/gen/host_calls.spv",
            "codegen/x86/node/inst/gen/host_calls.reflect.json"
        );
        let node_inst_gen_for_stmt_pass = load_x86_pass!(
            "node_inst_gen_for_stmt",
            "codegen/x86/node/inst/gen/for_stmt.spv",
            "codegen/x86/node/inst/gen/for_stmt.reflect.json"
        );
        let node_inst_gen_control_stmt_pass = load_x86_pass!(
            "node_inst_gen_control_stmt",
            "codegen/x86/node/inst/gen/control_stmt.spv",
            "codegen/x86/node/inst/gen/control_stmt.reflect.json"
        );
        let aggregate_literal_return_copy_flags_pass = load_x86_pass!(
            "aggregate_literal_return_copy_flags",
            "codegen/x86/aggregate/literal/return/copy/flags.spv",
            "codegen/x86/aggregate/literal/return/copy/flags.reflect.json"
        );
        let aggregate_literal_return_copy_pass = load_x86_pass!(
            "aggregate_literal_return_copy",
            "codegen/x86/aggregate/literal/return/copy.spv",
            "codegen/x86/aggregate/literal/return/copy.reflect.json"
        );
        let node_inst_gen_aggregate_copy_pass = load_x86_pass!(
            "node_inst_gen_aggregate_copy",
            "codegen/x86/node/inst/gen/aggregate_copy.spv",
            "codegen/x86/node/inst/gen/aggregate_copy.reflect.json"
        );
        let virtual_liveness_init_pass = load_x86_pass!(
            "virtual_liveness_init",
            "codegen/x86/virtual/liveness/init.spv",
            "codegen/x86/virtual/liveness/init.reflect.json"
        );
        let virtual_liveness_pass = load_x86_pass!(
            "virtual_liveness",
            "codegen/x86/virtual/liveness.spv",
            "codegen/x86/virtual/liveness.reflect.json"
        );
        let virtual_next_calls_pass = load_x86_pass!(
            "virtual_next_calls",
            "codegen/x86/virtual/next_calls.spv",
            "codegen/x86/virtual/next_calls.reflect.json"
        );
        let virtual_spans_fixed_barrier_pass = load_x86_pass!(
            "virtual_spans_fixed_barrier",
            "codegen/x86/virtual/spans_fixed_barrier.spv",
            "codegen/x86/virtual/spans_fixed_barrier.reflect.json"
        );
        let virtual_value_def_flags_pass = load_x86_pass!(
            "virtual_value_def_flags",
            "codegen/x86/virtual/value/def/flags.spv",
            "codegen/x86/virtual/value/def/flags.reflect.json"
        );
        let virtual_value_def_compact_pass = load_x86_pass!(
            "virtual_value_def_compact",
            "codegen/x86/virtual/value/def/compact.spv",
            "codegen/x86/virtual/value/def/compact.reflect.json"
        );
        let virtual_param_masks_pass = load_x86_pass!(
            "virtual_param_masks",
            "codegen/x86/virtual/param_masks.spv",
            "codegen/x86/virtual/param_masks.reflect.json"
        );
        let virtual_regalloc_pass = load_x86_pass!(
            "virtual_regalloc",
            "codegen/x86/virtual/regalloc.spv",
            "codegen/x86/virtual/regalloc.reflect.json"
        );
        let virtual_func_rows_init_pass = load_x86_pass!(
            "virtual_func_rows_init",
            "codegen/x86/virtual/func/rows_init.spv",
            "codegen/x86/virtual/func/rows_init.reflect.json"
        );
        let virtual_func_first_row_pass = load_x86_pass!(
            "virtual_func_first_row",
            "codegen/x86/virtual/func/first_row.spv",
            "codegen/x86/virtual/func/first_row.reflect.json"
        );
        let virtual_func_span_max_pass = load_x86_pass!(
            "virtual_func_span_max",
            "codegen/x86/virtual/func/span_max.spv",
            "codegen/x86/virtual/func/span_max.reflect.json"
        );
        let virtual_regalloc_dispatch_args_pass = load_x86_pass!(
            "virtual_regalloc_dispatch_args",
            "codegen/x86/virtual/regalloc/dispatch_args.spv",
            "codegen/x86/virtual/regalloc/dispatch_args.reflect.json"
        );
        let select_pass = load_x86_pass!(
            "select",
            "codegen/x86/select.spv",
            "codegen/x86/select.reflect.json"
        );
        let inst_size_pass = load_x86_pass!(
            "inst_size",
            "codegen/x86/inst_size.spv",
            "codegen/x86/inst_size.reflect.json"
        );
        let text_scan_local_pass = load_x86_pass!(
            "text_scan_local",
            "codegen/x86/text/scan_local.spv",
            "codegen/x86/text/scan_local.reflect.json"
        );
        let text_offsets_pass = load_x86_pass!(
            "text_offsets",
            "codegen/x86/text/offsets.spv",
            "codegen/x86/text/offsets.reflect.json"
        );
        let rodata_sizes_pass = load_x86_pass!(
            "rodata_sizes",
            "codegen/x86/rodata/sizes.spv",
            "codegen/x86/rodata/sizes.reflect.json"
        );
        let rodata_scan_local_pass = load_x86_pass!(
            "rodata_scan_local",
            "codegen/x86/rodata/scan_local.spv",
            "codegen/x86/rodata/scan_local.reflect.json"
        );
        let rodata_offsets_pass = load_x86_pass!(
            "rodata_offsets",
            "codegen/x86/rodata/offsets.spv",
            "codegen/x86/rodata/offsets.reflect.json"
        );
        let rodata_write_pass = load_x86_pass!(
            "rodata_write",
            "codegen/x86/rodata/write.spv",
            "codegen/x86/rodata/write.reflect.json"
        );
        let reloc_scan_local_pass = load_x86_pass!(
            "reloc_scan_local",
            "codegen/x86/reloc/scan_local.spv",
            "codegen/x86/reloc/scan_local.reflect.json"
        );
        let reloc_records_pass = load_x86_pass!(
            "reloc_records",
            "codegen/x86/reloc/records.spv",
            "codegen/x86/reloc/records.reflect.json"
        );
        let reloc_patch_pass = load_x86_pass!(
            "reloc_patch",
            "codegen/x86/reloc/patch.spv",
            "codegen/x86/reloc/patch.reflect.json"
        );
        let encode_pass = load_x86_pass!(
            "encode",
            "codegen/x86/encode.spv",
            "codegen/x86/encode.reflect.json"
        );
        let elf_layout_pass = load_x86_pass!(
            "elf_layout",
            "codegen/x86/elf/layout.spv",
            "codegen/x86/elf/layout.reflect.json"
        );
        let elf_write_pass = load_x86_pass!(
            "elf_write",
            "codegen/x86/elf/write.spv",
            "codegen/x86/elf/write.reflect.json"
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
            struct_field_widths_pass,
            struct_field_stream_pass,
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
            intrinsic_calls_pass,
            call_abi_pass,
            for_iterable_nodes_pass,
            node_control_padding_pass,
            postfix_operand_owner_pass,
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
            short_circuit_rhs_init_pass,
            short_circuit_rhs_step_pass,
            index_source_owner_init_pass,
            index_source_owner_step_pass,
            node_inst_gen_inputs_pass,
            virtual_inst_clear_dispatch_args_pass,
            virtual_inst_clear_pass,
            node_inst_gen_pass,
            node_inst_gen_function_params_pass,
            node_inst_gen_host_calls_pass,
            node_inst_gen_for_stmt_pass,
            node_inst_gen_control_stmt_pass,
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
            rodata_sizes_pass,
            rodata_scan_local_pass,
            rodata_offsets_pass,
            rodata_write_pass,
            reloc_scan_local_pass,
            reloc_records_pass,
            reloc_patch_pass,
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
    fn x86_output_error_display_is_user_facing() {
        let error = X86OutputError::new("unsupported_scalar_return", 48, 12);
        let rendered = error.to_string();

        assert_eq!(
            rendered,
            "x86 code generation reached an unsupported backend boundary"
        );
        assert!(!rendered.contains("GPU"));
        assert!(!rendered.contains("emitter rejected"));
        assert!(!rendered.contains("unsupported_scalar_return"));
        assert!(!rendered.contains("code 48"));
        assert!(!rendered.contains("detail 12"));
    }

    #[test]
    fn x86_output_error_public_message_humanizes_backend_status() {
        let error = X86OutputError::new("unsupported_scalar_return", 48, 12);

        let message = error.public_message();
        assert_eq!(message, "unsupported scalar return");
        assert!(!message.contains("unsupported_scalar_return"));
        assert!(!message.contains("48"));
        assert!(!message.contains("12"));
    }

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
        let prior_words = hir_words.saturating_add(1).saturating_mul(2);

        assert_eq!(worklist_words, inst_capacity.saturating_mul(2));
        assert!(worklist_words < prior_words);
    }

    #[test]
    fn x86_node_inst_gen_worklist_does_not_grow_small_programs() {
        let hir_words = 512;
        let inst_capacity = 8_000;
        let worklist_words = x86_node_inst_gen_node_record_words(hir_words, inst_capacity);
        let prior_words = hir_words.saturating_add(1).saturating_mul(2);

        assert!(worklist_words <= prior_words);
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

    #[test]
    fn x86_scalar_feature_summary_can_exceed_token_scaled_limit() {
        let feature_summary = X86FeatureSummary {
            scalar_inst_capacity: 4_000,
            ..Default::default()
        };
        let capacity = x86_capacity_estimate_for_hir_tokens_inst_basis_and_feature_summary(
            600,
            100,
            600,
            feature_summary,
        );

        assert!(
            capacity.inst_capacity > 100usize.saturating_add(X86_INST_CAPACITY_SLACK),
            "dense scalar programs should use the measured scalar instruction summary"
        );
    }

    #[test]
    fn x86_regalloc_recorded_span_is_capacity_sized() {
        let contract = x86_regalloc_pass_contract();

        assert_eq!(
            contract.recorded_span_basis,
            "instruction_capacity_not_source_len"
        );
        assert_eq!(
            contract.chunk_span_invariant,
            "recorded_chunks_times_rows_per_chunk_must_cover_inst_capacity"
        );
        assert_eq!(regalloc_recorded_chunk_count(0), 1);
        assert_eq!(regalloc_recorded_chunk_count(contract.rows_per_chunk), 1);
        assert_eq!(
            regalloc_recorded_chunk_count(contract.rows_per_chunk + 1),
            2
        );
        assert!(regalloc_recorded_span_covers_inst_capacity(0));
        assert!(regalloc_recorded_span_covers_inst_capacity(1_025));
    }

    #[test]
    fn x86_encode_contract_marks_byte_scatter_as_local_bounded_work() {
        let contract = x86_encode_pass_contract();

        assert_eq!(contract.schema, "lanius.x86.encode-pass-contract.v1");
        assert_eq!(contract.loop_status, "bounded-local");
        assert_eq!(contract.fallback_status, "fail-closed");
        assert_eq!(contract.claim_status, "not-blocking");
        assert_eq!(contract.source_text_status, "not-consumed");
        assert_eq!(
            contract.byte_loop_basis,
            "per_instruction_encoded_byte_width"
        );
        assert_eq!(contract.max_bytes_per_instruction, 128);
        assert!(
            contract.input_ordering.contains("prefix_instruction_sizes")
                && contract.input_ordering.contains("patch_relocation_records"),
            "encoding must stay ordered after byte-prefix and relocation-record publication"
        );
        assert!(
            contract.guards.contains("text_status") && contract.guards.contains("reloc_status"),
            "encoding must stay gated by GPU-published text and relocation status"
        );
    }

    #[test]
    fn x86_control_flow_bridge_contract_marks_transitional_rows_fail_closed() {
        let contract = x86_control_flow_bridge_pass_contract();

        assert_eq!(
            contract.schema,
            "lanius.x86.control-flow-bridge-pass-contract.v1"
        );
        assert_eq!(contract.loop_status, "bounded");
        assert_eq!(contract.fallback_status, "fail-closed");
        assert_eq!(contract.claim_status, "blocked");
        assert_eq!(contract.relation_count, 4);
        assert_eq!(
            contract.relations,
            "node_inst_same_end_rank,enclosing_loop,short_circuit_rhs,index_source_owner"
        );
        assert!(
            contract
                .required_replacement
                .contains("basic_block_edge_rows"),
            "control-flow bridge must not be claimable before basic-block edge records exist"
        );
        assert_eq!(
            contract.record_ordering,
            "record_relations,prefix_control_regions,sort_join_edges,scatter_virtual_rows"
        );
    }

    #[test]
    fn x86_lowering_contract_blocks_claims_until_generic_record_rows() {
        let contract = x86_lowering_pass_contract();

        assert_eq!(contract.schema, "lanius.x86.lowering-pass-contract.v1");
        assert_eq!(contract.loop_status, "bounded");
        assert_eq!(contract.fallback_status, "fail-closed");
        assert_eq!(contract.claim_status, "blocked");
        assert_eq!(contract.source_text_status, "not-consumed");
        assert_eq!(contract.function_body_recognizer_status, "forbidden");
        assert_eq!(contract.relation_count, 5);
        assert!(
            contract.relations.contains("hir_expr_record")
                && contract.relations.contains("x86_virtual_inst_record"),
            "lowering contract must describe record rows, not source or helper names"
        );
        assert!(
            contract
                .required_replacement
                .contains("generic_operation_records"),
            "generic operation rows are required before lowering is claimable"
        );
        assert_eq!(
            contract.record_ordering,
            "record_semantic_rows,prefix_instruction_counts,scatter_virtual_rows,encode_from_virtual_rows"
        );
    }
}
