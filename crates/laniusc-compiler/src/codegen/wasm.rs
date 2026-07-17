//! GPU WASM backend boundary.
//!
//! The WASM backend consumes the same parser HIR and retained type-check
//! metadata shape as other backends. It records target-specific GPU passes and
//! reports fail-closed backend status for unsupported shapes.

use std::{sync::Mutex, time::Instant};

use anyhow::{Result, anyhow};
use encase::ShaderType;

mod support;
use support::*;
mod object;
pub(crate) use object::{GPU_WASM_OBJECT_HEADER_BYTES, GpuWasmRelocatableObjectLayout};
pub use object::{
    GPU_WASM_OBJECT_VERSION,
    GpuWasmFunctionRecord,
    GpuWasmObjectSymbolRecord,
    GpuWasmRelocatableObject,
    GpuWasmRelocationRecord,
    GpuWasmRelocationTargetKind,
    GpuWasmSymbolKind,
};
mod error;
pub(crate) mod link;
pub use error::WasmOutputError;
use error::from_status as wasm_output_error_from_status;
pub(crate) use link::GpuWasmLinkInput;
mod body_features;
use body_features::*;
mod buffer_capacities;
use buffer_capacities::WasmBufferCapacities;
mod record_boundaries;
pub use record_boundaries::{WasmRecordBoundary, wasm_record_boundaries};
mod input_buffers;
pub use input_buffers::{
    GpuWasmArrayMetadataBuffers,
    GpuWasmCallMetadataBuffers,
    GpuWasmCodegenInputs,
    GpuWasmDependencySymbolBuffers,
    GpuWasmExprMetadataBuffers,
    GpuWasmPathMetadataBuffers,
    GpuWasmSemanticHirBuffers,
    GpuWasmStructMetadataBuffers,
};
mod lazy_pass;
use lazy_pass::{LazyWasmPass, create_wasm_bind_group};
mod create_resident_buffers;
mod finish;
mod readback_buffers;
mod record_body_plan;
mod record_initial;
mod record_scatter;
mod resident_buffers;
use readback_buffers::{WasmReadbackBuffers, create_wasm_readback_buffers};
mod working_buffers;
use working_buffers::{WasmWorkingBuffers, create_wasm_working_buffers};
mod prelude_bind_groups;
use prelude_bind_groups::WasmPreludeBindGroups;
mod function_bind_groups;
use function_bind_groups::WasmFunctionBindGroups;
mod body_plan_bind_groups;
use body_plan_bind_groups::WasmBodyPlanBindGroups;
mod body_sizing_bind_groups;
use body_sizing_bind_groups::WasmBodySizingBindGroups;
mod body_scatter_bind_groups;
use body_scatter_bind_groups::WasmBodyScatterBindGroups;
mod module_bind_groups;
use module_bind_groups::WasmModuleBindGroups;
mod body_binding_context;
use body_binding_context::WasmBodyBindingContext;
mod call_relocations;
use call_relocations::ResidentWasmCallRelocations;
mod object_codegen;
use object_codegen::WasmObjectInputBuffers;
mod expr_order;
use expr_order::ResidentWasmExprOrder;

use crate::gpu::{buffers::LaniusBuffer, device};

const WASM_ASSERT_OUTPUT_TARGET_LIMIT: u32 = 512;
const WASM_FUNCTION_REACHABILITY_ITERATIONS: u32 = 64;
const WASM_BODY_PLAN_FINALIZE_GROUPS: u32 = 1;
const WASM_BODY_STATUS_GROUPS: u32 = 1;
const WASM_MODULE_STATUS_GROUPS: u32 = 1;
const WASM_BODY_PLAN_WORDS: usize = 40;
const ERR_UNSUPPORTED_SOURCE_SHAPE: u32 = 1;
struct WasmFinishHostTimer {
    print_enabled: bool,
    trace_enabled: bool,
    start: Instant,
    last: Instant,
}

impl WasmFinishHostTimer {
    fn new() -> Self {
        let now = Instant::now();
        Self {
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
        let now = Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let name = format!("codegen.wasm.finish.{stage}");
        if self.print_enabled {
            eprintln!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.wasm.finish", &name, self.last, now);
        }
        self.last = now;
    }
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmParams {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
    artifact_flags: u32,
}

pub(crate) const WASM_ARTIFACT_ALLOW_MISSING_ENTRYPOINT: u32 = 1;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmScanParams {
    n_items: u32,
    n_blocks: u32,
    scan_step: u32,
    out_capacity: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmExprRadixParams {
    n_items: u32,
    n_blocks: u32,
    key_step: u32,
    reserved: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmExprDepthTreeParams {
    n_blocks: u32,
    leaf_base: u32,
    start_node: u32,
    node_count: u32,
    mode: u32,
    reserved0: u32,
    reserved1: u32,
    reserved2: u32,
}

/// Recorded WASM backend work and retained capacity metadata for readback.
pub struct RecordedWasmCodegen {
    output_capacity: usize,
    token_capacity: u32,
}

struct ResidentWasmBuffers {
    input_fingerprint: u64,
    output_capacity: usize,
    token_capacity: u32,
    hir_node_capacity: u32,
    active_hir_dispatch_args_buf: wgpu::Buffer,
    params_buf: LaniusBuffer<WasmParams>,
    body_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    body_scan_blocks: u32,
    arg_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    arg_scan_blocks: u32,
    func_scan_param_bufs: Vec<LaniusBuffer<WasmScanParams>>,
    func_scan_blocks: u32,
    body_dispatch_buf: LaniusBuffer<u32>,
    _module_type_dispatch_buf: LaniusBuffer<u32>,
    _body_buf: LaniusBuffer<u32>,
    body_plan_buf: LaniusBuffer<u32>,
    _wasm_func_flag_buf: LaniusBuffer<u32>,
    _wasm_func_decl_flag_buf: LaniusBuffer<u32>,
    _wasm_func_slot_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_token_by_slot_buf: LaniusBuffer<u32>,
    _wasm_func_param_ordinal_by_decl_token_buf: LaniusBuffer<u32>,
    _wasm_func_body_len_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_local_max_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_return_count_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_invalid_count_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_return_token_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_detail_by_token_buf: LaniusBuffer<u32>,
    _wasm_func_scan_local_prefix_buf: LaniusBuffer<u32>,
    _wasm_func_scan_block_sum_buf: LaniusBuffer<u32>,
    _wasm_func_scan_prefix_a_buf: LaniusBuffer<u32>,
    _wasm_func_scan_prefix_b_buf: LaniusBuffer<u32>,
    _body_let_init_expr_by_decl_token_buf: LaniusBuffer<u32>,
    _body_fragment_len_buf: LaniusBuffer<u32>,
    _body_fragment_meta_buf: LaniusBuffer<u32>,
    _body_fragment_aux_buf: LaniusBuffer<u32>,
    _body_scan_local_prefix_buf: LaniusBuffer<u32>,
    _body_scan_block_sum_buf: LaniusBuffer<u32>,
    _body_scan_prefix_a_buf: LaniusBuffer<u32>,
    _body_scan_prefix_b_buf: LaniusBuffer<u32>,
    _expr_subtree_total_buf: LaniusBuffer<u32>,
    _expr_subtree_features_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_count_by_fragment_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_count_local_prefix_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_count_block_sum_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_count_prefix_a_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_count_prefix_b_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_len_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_meta_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_aux_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_byte_local_prefix_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_byte_block_sum_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_byte_prefix_a_buf: LaniusBuffer<u32>,
    _wasm_agg_call_arg_byte_prefix_b_buf: LaniusBuffer<u32>,
    body_status_buf: LaniusBuffer<u32>,
    _struct_field_count_by_decl_token_buf: LaniusBuffer<u32>,
    _struct_field_index_by_token_buf: LaniusBuffer<u32>,
    _struct_field_decl_by_token_buf: LaniusBuffer<u32>,
    _struct_field_name_id_buf: LaniusBuffer<u32>,
    _struct_field_ref_tag_buf: LaniusBuffer<u32>,
    _struct_field_ref_payload_buf: LaniusBuffer<u32>,
    _struct_field_scalar_offset_buf: LaniusBuffer<u32>,
    _struct_field_scalar_width_buf: LaniusBuffer<u32>,
    _struct_init_field_index_buf: LaniusBuffer<u32>,
    _member_result_field_index_buf: LaniusBuffer<u32>,
    _wasm_agg_local_width_by_token_buf: LaniusBuffer<u32>,
    _wasm_agg_local_base_by_token_buf: LaniusBuffer<u32>,
    _wasm_agg_scan_block_sum_buf: LaniusBuffer<u32>,
    _wasm_agg_scan_prefix_a_buf: LaniusBuffer<u32>,
    _wasm_agg_scan_prefix_b_buf: LaniusBuffer<u32>,
    wasm_const_value_record_buf: LaniusBuffer<u32>,
    call_relocations: ResidentWasmCallRelocations,
    expr_order: ResidentWasmExprOrder,
    object_inputs: WasmObjectInputBuffers,
    out_buf: LaniusBuffer<u32>,
    packed_out_buf: LaniusBuffer<u32>,
    status_buf: LaniusBuffer<u32>,
    out_readback: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    body_plan_readback: wgpu::Buffer,
    body_fragment_len_readback: wgpu::Buffer,
    body_fragment_meta_readback: wgpu::Buffer,
    body_fragment_aux_readback: wgpu::Buffer,
    wasm_func_invalid_count_readback: wgpu::Buffer,
    wasm_func_detail_readback: wgpu::Buffer,
    agg_layout_clear_bind_group: wgpu::BindGroup,
    agg_layout_bind_group: wgpu::BindGroup,
    hir_body_let_init_clear_bind_group: wgpu::BindGroup,
    hir_body_let_init_bind_group: wgpu::BindGroup,
    hir_functions_clear_bind_group: wgpu::BindGroup,
    hir_functions_mark_bind_group: wgpu::BindGroup,
    hir_functions_reach_bind_group: wgpu::BindGroup,
    hir_functions_count_bind_group: wgpu::BindGroup,
    hir_func_scan_local_bind_group: wgpu::BindGroup,
    hir_func_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    hir_agg_scan_local_bind_group: wgpu::BindGroup,
    hir_agg_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    hir_functions_scatter_bind_group: wgpu::BindGroup,
    hir_body_plan_collect_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_agg_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_nested_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_assign_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_control_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_agg_range_control_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_print_simple_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_host_void_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_host_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_host_env_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_host_io_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_host_string_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_host_io_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_return_host_string_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_direct_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_call_bind_group: wgpu::BindGroup,
    hir_body_plan_validate_let_call_status_bind_group: wgpu::BindGroup,
    hir_body_plan_agg_direct_call_bind_group: wgpu::BindGroup,
    hir_body_plan_agg_struct_bind_group: wgpu::BindGroup,
    hir_body_plan_arrays_bind_group: wgpu::BindGroup,
    hir_body_plan_functions_bind_group: wgpu::BindGroup,
    hir_body_plan_finalize_bind_group: wgpu::BindGroup,
    hir_body_clear_bind_group: wgpu::BindGroup,
    hir_body_counts_bind_group: wgpu::BindGroup,
    hir_body_scan_local_bind_group: wgpu::BindGroup,
    hir_body_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    hir_body_agg_call_arg_counts_bind_group: wgpu::BindGroup,
    hir_body_agg_call_arg_count_scan_local_bind_group: wgpu::BindGroup,
    hir_body_agg_call_arg_count_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    hir_body_agg_call_arg_records_bind_group: wgpu::BindGroup,
    hir_body_direct_call_arg_records_bind_group: wgpu::BindGroup,
    hir_body_agg_call_arg_byte_scan_local_bind_group: wgpu::BindGroup,
    hir_body_agg_call_arg_byte_scan_block_bind_groups: Vec<wgpu::BindGroup>,
    hir_body_agg_call_finalize_bind_group: wgpu::BindGroup,
    hir_body_direct_call_finalize_bind_group: wgpu::BindGroup,
    hir_body_status_bind_group: wgpu::BindGroup,
    hir_body_scatter_bind_group: wgpu::BindGroup,
    hir_body_scatter_frame_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_scalar_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_expr_bind_group: wgpu::BindGroup,
    hir_body_scatter_conversion_expr_bind_group: wgpu::BindGroup,
    hir_body_scatter_let_const_bind_group: wgpu::BindGroup,
    hir_body_scatter_expr_control_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_range_control_bind_group: wgpu::BindGroup,
    hir_body_scatter_let_direct_bind_group: wgpu::BindGroup,
    hir_body_scatter_direct_nested_call_bind_group: wgpu::BindGroup,
    hir_body_scatter_host_io_bind_group: wgpu::BindGroup,
    hir_body_scatter_host_bind_group: wgpu::BindGroup,
    hir_body_scatter_stored_expr_bind_group: wgpu::BindGroup,
    hir_body_scatter_array_lean_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_copy_bind_group: wgpu::BindGroup,
    hir_body_scatter_member_assign_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_call_args_bind_group: wgpu::BindGroup,
    hir_body_scatter_nested_call_args_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_direct_call_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_agg_direct_call_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_member_bind_group: wgpu::BindGroup,
    hir_body_scatter_binary_direct_call_bind_group: wgpu::BindGroup,
    hir_agg_body_bind_group: wgpu::BindGroup,
    hir_assert_module_bind_group: wgpu::BindGroup,
    wasm_const_values_bind_group: wgpu::BindGroup,
    module_type_lengths_bind_group: wgpu::BindGroup,
    module_type_dispatch_args_bind_group: wgpu::BindGroup,
    module_type_bytes_bind_group: wgpu::BindGroup,
    module_status_bind_group: wgpu::BindGroup,
    bind_group: wgpu::BindGroup,
    pack_bind_group: wgpu::BindGroup,
}

/// GPU WASM code generator with loaded compute passes and resident buffers.
pub struct GpuWasmCodeGenerator {
    agg_layout_clear_pass: LazyWasmPass,
    agg_layout_pass: LazyWasmPass,
    hir_body_let_init_clear_pass: LazyWasmPass,
    hir_body_let_init_pass: LazyWasmPass,
    hir_functions_clear_pass: LazyWasmPass,
    hir_functions_mark_pass: LazyWasmPass,
    hir_functions_reach_pass: LazyWasmPass,
    hir_functions_count_pass: LazyWasmPass,
    hir_functions_scatter_pass: LazyWasmPass,
    hir_body_plan_collect_pass: LazyWasmPass,
    hir_expr_same_end_rank_init_pass: LazyWasmPass,
    hir_expr_same_end_rank_step_pass: LazyWasmPass,
    hir_expr_order_init_pass: LazyWasmPass,
    hir_expr_order_histogram_pass: LazyWasmPass,
    hir_expr_order_scan_local_pass: LazyWasmPass,
    hir_expr_order_scatter_pass: LazyWasmPass,
    hir_expr_depth_init_pass: LazyWasmPass,
    hir_expr_depth_step_pass: LazyWasmPass,
    hir_expr_depth_block_min_pass: LazyWasmPass,
    hir_expr_depth_build_min_tree_pass: LazyWasmPass,
    hir_expr_contribution_pass: LazyWasmPass,
    hir_expr_contribution_scan_local_pass: LazyWasmPass,
    hir_expr_contribution_scan_blocks_pass: LazyWasmPass,
    hir_expr_root_prefix_pass: LazyWasmPass,
    hir_expr_root_total_pass: LazyWasmPass,
    hir_expr_subtree_total_pass: LazyWasmPass,
    hir_body_plan_validate_pass: LazyWasmPass,
    hir_body_plan_validate_return_pass: LazyWasmPass,
    hir_body_plan_validate_return_call_pass: LazyWasmPass,
    hir_body_plan_validate_return_agg_call_pass: LazyWasmPass,
    hir_body_plan_validate_return_nested_call_pass: LazyWasmPass,
    hir_body_plan_validate_assign_pass: LazyWasmPass,
    hir_body_plan_validate_control_pass: LazyWasmPass,
    hir_body_plan_validate_agg_range_control_pass: LazyWasmPass,
    hir_body_plan_validate_print_simple_pass: LazyWasmPass,
    hir_body_plan_validate_call_pass: LazyWasmPass,
    hir_body_plan_validate_host_void_call_pass: LazyWasmPass,
    hir_body_plan_validate_let_host_pass: LazyWasmPass,
    hir_body_plan_validate_let_host_env_pass: LazyWasmPass,
    hir_body_plan_validate_let_host_io_pass: LazyWasmPass,
    hir_body_plan_validate_let_host_string_pass: LazyWasmPass,
    hir_body_plan_validate_return_host_io_pass: LazyWasmPass,
    hir_body_plan_validate_return_host_string_pass: LazyWasmPass,
    hir_body_plan_validate_let_direct_call_pass: LazyWasmPass,
    hir_body_plan_validate_let_call_pass: LazyWasmPass,
    hir_body_plan_validate_let_call_status_pass: LazyWasmPass,
    hir_body_plan_agg_direct_call_pass: LazyWasmPass,
    hir_body_plan_agg_struct_pass: LazyWasmPass,
    hir_body_plan_arrays_pass: LazyWasmPass,
    hir_body_plan_functions_pass: LazyWasmPass,
    hir_body_plan_finalize_pass: LazyWasmPass,
    hir_body_clear_pass: LazyWasmPass,
    hir_body_counts_pass: LazyWasmPass,
    hir_body_scan_local_pass: LazyWasmPass,
    hir_body_scan_blocks_pass: LazyWasmPass,
    hir_body_agg_call_arg_counts_pass: LazyWasmPass,
    hir_body_agg_call_arg_records_pass: LazyWasmPass,
    hir_body_agg_call_finalize_pass: LazyWasmPass,
    hir_body_direct_call_arg_records_pass: LazyWasmPass,
    hir_body_direct_call_finalize_pass: LazyWasmPass,
    hir_body_scatter_agg_call_args_pass: LazyWasmPass,
    hir_body_status_pass: LazyWasmPass,
    hir_body_scatter_pass: LazyWasmPass,
    hir_body_scatter_frame_pass: LazyWasmPass,
    hir_body_scatter_return_scalar_pass: LazyWasmPass,
    hir_body_scatter_return_expr_pass: LazyWasmPass,
    hir_body_scatter_conversion_expr_pass: LazyWasmPass,
    hir_body_scatter_let_const_pass: LazyWasmPass,
    hir_body_scatter_expr_control_pass: LazyWasmPass,
    hir_body_scatter_agg_range_control_pass: LazyWasmPass,
    hir_body_scatter_let_direct_pass: LazyWasmPass,
    hir_body_scatter_direct_nested_call_pass: LazyWasmPass,
    hir_body_scatter_host_io_pass: LazyWasmPass,
    hir_body_scatter_host_pass: LazyWasmPass,
    hir_body_scatter_stored_expr_pass: LazyWasmPass,
    hir_body_scatter_array_lean_pass: LazyWasmPass,
    hir_body_scatter_agg_copy_pass: LazyWasmPass,
    hir_body_scatter_member_assign_pass: LazyWasmPass,
    hir_body_scatter_agg_direct_call_pass: LazyWasmPass,
    hir_body_scatter_nested_call_args_pass: LazyWasmPass,
    hir_body_scatter_return_agg_direct_call_pass: LazyWasmPass,
    hir_body_scatter_return_member_pass: LazyWasmPass,
    hir_body_scatter_binary_direct_call_pass: LazyWasmPass,
    hir_agg_body_pass: LazyWasmPass,
    hir_assert_module_pass: LazyWasmPass,
    wasm_const_values_pass: LazyWasmPass,
    module_type_lengths_pass: LazyWasmPass,
    module_type_dispatch_args_pass: LazyWasmPass,
    module_type_bytes_pass: LazyWasmPass,
    module_status_pass: LazyWasmPass,
    pass: LazyWasmPass,
    pack_pass: LazyWasmPass,
    call_reloc_scan_local_pass: LazyWasmPass,
    call_reloc_scatter_pass: LazyWasmPass,
    object_functions_pass: LazyWasmPass,
    object_function_bodies_pass: LazyWasmPass,
    object_symbols_pass: LazyWasmPass,
    object_bytes_pass: LazyWasmPass,
    object_metadata_pass: LazyWasmPass,
    link_module_pass: LazyWasmPass,
    link_symbol_clear_pass: LazyWasmPass,
    link_symbol_insert_pass: LazyWasmPass,
    link_symbol_define_pass: LazyWasmPass,
    link_resolve_pass: LazyWasmPass,
    link_relocate_pass: LazyWasmPass,
    buffers: Mutex<Option<ResidentWasmBuffers>>,
}

impl GpuWasmCodeGenerator {
    /// Loads all WASM backend compute passes for a GPU device.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! wasm_pass {
            ($stage:literal, $label:literal, $spv:literal, $reflection:literal) => {{
                let device = gpu.device.clone();
                std::thread::spawn(move || {
                    LazyWasmPass::from_artifacts(&device, $stage, $label, $spv, $reflection)
                })
            }};
        }
        macro_rules! join_wasm_pass {
            ($handle:ident, $stage:literal) => {{
                let pass = $handle
                    .join()
                    .map_err(|_| anyhow!("WASM pass {} initialization panicked", $stage))??;
                // A constructed backend is ready to compile. Materialize every
                // pipeline here so no source-dependent recording path can move
                // driver compilation into a daemon job's measured interval.
                pass.pipeline()?;
                if crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_INCREMENTAL", false) {
                    gpu.persist_pipeline_cache();
                }
                pass
            }};
        }

        let agg_layout_clear_pass = wasm_pass!(
            "agg_layout_clear",
            "codegen_wasm_agg_layout_clear",
            "codegen/wasm/agg/layout/clear.spv",
            "codegen/wasm/agg/layout/clear.reflect.json"
        );
        let agg_layout_pass = wasm_pass!(
            "agg_layout",
            "codegen_wasm_agg_layout",
            "codegen/wasm/agg/layout.spv",
            "codegen/wasm/agg/layout.reflect.json"
        );
        let hir_body_let_init_clear_pass = wasm_pass!(
            "hir_body_let_init_clear",
            "codegen_wasm_hir_body_let_init_clear",
            "codegen/wasm/hir/body_let_init_clear.spv",
            "codegen/wasm/hir/body_let_init_clear.reflect.json"
        );
        let hir_body_let_init_pass = wasm_pass!(
            "hir_body_let_init",
            "codegen_wasm_hir_body_let_init",
            "codegen/wasm/hir/body_let_init.spv",
            "codegen/wasm/hir/body_let_init.reflect.json"
        );
        let hir_functions_clear_pass = wasm_pass!(
            "hir_functions_clear",
            "codegen_wasm_hir_functions_clear",
            "codegen/wasm/hir/functions_clear.spv",
            "codegen/wasm/hir/functions_clear.reflect.json"
        );
        let hir_functions_mark_pass = wasm_pass!(
            "hir_functions_mark",
            "codegen_wasm_hir_functions_mark",
            "codegen/wasm/hir/functions_mark.spv",
            "codegen/wasm/hir/functions_mark.reflect.json"
        );
        let hir_functions_reach_pass = wasm_pass!(
            "hir_functions_reach",
            "codegen_wasm_hir_functions_reach",
            "codegen/wasm/hir/functions_reach.spv",
            "codegen/wasm/hir/functions_reach.reflect.json"
        );
        let hir_functions_count_pass = wasm_pass!(
            "hir_functions_count",
            "codegen_wasm_hir_functions_count",
            "codegen/wasm/hir/functions_count.spv",
            "codegen/wasm/hir/functions_count.reflect.json"
        );
        let hir_functions_scatter_pass = wasm_pass!(
            "hir_functions_scatter",
            "codegen_wasm_hir_functions_scatter",
            "codegen/wasm/hir/functions_scatter.spv",
            "codegen/wasm/hir/functions_scatter.reflect.json"
        );
        let hir_body_plan_collect_pass = wasm_pass!(
            "hir_body_plan_collect",
            "codegen_wasm_hir_body_plan_collect",
            "codegen/wasm/hir/body_plan_collect.spv",
            "codegen/wasm/hir/body_plan_collect.reflect.json"
        );
        let hir_expr_same_end_rank_init_pass = wasm_pass!(
            "hir_expr_same_end_rank_init",
            "codegen_wasm_hir_expr_same_end_rank_init",
            "codegen/wasm/hir/expr_same_end_rank_init.spv",
            "codegen/wasm/hir/expr_same_end_rank_init.reflect.json"
        );
        let hir_expr_same_end_rank_step_pass = wasm_pass!(
            "hir_expr_same_end_rank_step",
            "codegen_wasm_hir_expr_same_end_rank_step",
            "codegen/wasm/hir/expr_same_end_rank_step.spv",
            "codegen/wasm/hir/expr_same_end_rank_step.reflect.json"
        );
        let hir_expr_order_init_pass = wasm_pass!(
            "hir_expr_order_init",
            "codegen_wasm_hir_expr_order_init",
            "codegen/wasm/hir/expr_order_init.spv",
            "codegen/wasm/hir/expr_order_init.reflect.json"
        );
        let hir_expr_order_histogram_pass = wasm_pass!(
            "hir_expr_order_histogram",
            "codegen_wasm_hir_expr_order_histogram",
            "codegen/wasm/hir/expr_order_histogram.spv",
            "codegen/wasm/hir/expr_order_histogram.reflect.json"
        );
        let hir_expr_order_scan_local_pass = wasm_pass!(
            "hir_expr_order_scan_local",
            "codegen_wasm_hir_expr_order_scan_local",
            "codegen/wasm/hir/expr_order_scan_local.spv",
            "codegen/wasm/hir/expr_order_scan_local.reflect.json"
        );
        let hir_expr_order_scatter_pass = wasm_pass!(
            "hir_expr_order_scatter",
            "codegen_wasm_hir_expr_order_scatter",
            "codegen/wasm/hir/expr_order_scatter.spv",
            "codegen/wasm/hir/expr_order_scatter.reflect.json"
        );
        let hir_expr_depth_init_pass = wasm_pass!(
            "hir_expr_depth_init",
            "codegen_wasm_hir_expr_depth_init",
            "codegen/wasm/hir/expr_depth_init.spv",
            "codegen/wasm/hir/expr_depth_init.reflect.json"
        );
        let hir_expr_depth_step_pass = wasm_pass!(
            "hir_expr_depth_step",
            "codegen_wasm_hir_expr_depth_step",
            "codegen/wasm/hir/expr_depth_step.spv",
            "codegen/wasm/hir/expr_depth_step.reflect.json"
        );
        let hir_expr_depth_block_min_pass = wasm_pass!(
            "hir_expr_depth_block_min",
            "codegen_wasm_hir_expr_depth_block_min",
            "codegen/wasm/hir/expr_depth_block_min.spv",
            "codegen/wasm/hir/expr_depth_block_min.reflect.json"
        );
        let hir_expr_depth_build_min_tree_pass = wasm_pass!(
            "hir_expr_depth_build_min_tree",
            "codegen_wasm_hir_expr_depth_build_min_tree",
            "codegen/wasm/hir/expr_depth_build_min_tree.spv",
            "codegen/wasm/hir/expr_depth_build_min_tree.reflect.json"
        );
        let hir_expr_contribution_pass = wasm_pass!(
            "hir_expr_contribution",
            "codegen_wasm_hir_expr_contribution",
            "codegen/wasm/hir/expr_contribution.spv",
            "codegen/wasm/hir/expr_contribution.reflect.json"
        );
        let hir_expr_contribution_scan_local_pass = wasm_pass!(
            "hir_expr_contribution_scan_local",
            "codegen_wasm_hir_expr_contribution_scan_local",
            "codegen/wasm/hir/expr_contribution_scan_local.spv",
            "codegen/wasm/hir/expr_contribution_scan_local.reflect.json"
        );
        let hir_expr_contribution_scan_blocks_pass = wasm_pass!(
            "hir_expr_contribution_scan_blocks",
            "codegen_wasm_hir_expr_contribution_scan_blocks",
            "codegen/wasm/hir/expr_contribution_scan_blocks.spv",
            "codegen/wasm/hir/expr_contribution_scan_blocks.reflect.json"
        );
        let hir_expr_root_prefix_pass = wasm_pass!(
            "hir_expr_root_prefix",
            "codegen_wasm_hir_expr_root_prefix",
            "codegen/wasm/hir/expr_root_prefix.spv",
            "codegen/wasm/hir/expr_root_prefix.reflect.json"
        );
        let hir_expr_root_total_pass = wasm_pass!(
            "hir_expr_root_total",
            "codegen_wasm_hir_expr_root_total",
            "codegen/wasm/hir/expr_root_total.spv",
            "codegen/wasm/hir/expr_root_total.reflect.json"
        );
        let hir_expr_subtree_total_pass = wasm_pass!(
            "hir_expr_subtree_total",
            "codegen_wasm_hir_expr_subtree_total",
            "codegen/wasm/hir/expr_subtree_total.spv",
            "codegen/wasm/hir/expr_subtree_total.reflect.json"
        );
        let hir_body_plan_validate_pass = wasm_pass!(
            "hir_body_plan_validate",
            "codegen_wasm_hir_body_plan_validate",
            "codegen/wasm/hir/body_plan_validate.spv",
            "codegen/wasm/hir/body_plan_validate.reflect.json"
        );
        let hir_body_plan_validate_return_pass = wasm_pass!(
            "hir_body_plan_validate_return",
            "codegen_wasm_hir_body_plan_validate_return",
            "codegen/wasm/hir/body_plan_validate_return.spv",
            "codegen/wasm/hir/body_plan_validate_return.reflect.json"
        );
        let hir_body_plan_validate_return_call_pass = wasm_pass!(
            "hir_body_plan_validate_return_call",
            "codegen_wasm_hir_body_plan_validate_return_call",
            "codegen/wasm/hir/body_plan_validate_return_call.spv",
            "codegen/wasm/hir/body_plan_validate_return_call.reflect.json"
        );
        let hir_body_plan_validate_return_agg_call_pass = wasm_pass!(
            "hir_body_plan_validate_return_agg_call",
            "codegen_wasm_hir_body_plan_validate_return_agg_call",
            "codegen/wasm/hir/body_plan_validate_return_agg_call.spv",
            "codegen/wasm/hir/body_plan_validate_return_agg_call.reflect.json"
        );
        let hir_body_plan_validate_return_nested_call_pass = wasm_pass!(
            "hir_body_plan_validate_return_nested_call",
            "codegen_wasm_hir_body_plan_validate_return_nested_call",
            "codegen/wasm/hir/body_plan_validate_return_nested_call.spv",
            "codegen/wasm/hir/body_plan_validate_return_nested_call.reflect.json"
        );
        let hir_body_plan_validate_assign_pass = wasm_pass!(
            "hir_body_plan_validate_assign",
            "codegen_wasm_hir_body_plan_validate_assign",
            "codegen/wasm/hir/body_plan_validate_assign.spv",
            "codegen/wasm/hir/body_plan_validate_assign.reflect.json"
        );
        let hir_body_plan_validate_control_pass = wasm_pass!(
            "hir_body_plan_validate_control",
            "codegen_wasm_hir_body_plan_validate_control",
            "codegen/wasm/hir/body_plan_validate_control.spv",
            "codegen/wasm/hir/body_plan_validate_control.reflect.json"
        );
        let hir_body_plan_validate_agg_range_control_pass = wasm_pass!(
            "hir_body_plan_validate_agg_range_control",
            "codegen_wasm_hir_body_plan_validate_agg_range_control",
            "codegen/wasm/hir/body_plan_validate_agg_range_control.spv",
            "codegen/wasm/hir/body_plan_validate_agg_range_control.reflect.json"
        );
        let hir_body_plan_validate_print_simple_pass = wasm_pass!(
            "hir_body_plan_validate_print_simple",
            "codegen_wasm_hir_body_plan_validate_print_simple",
            "codegen/wasm/hir/body_plan_validate_print_simple.spv",
            "codegen/wasm/hir/body_plan_validate_print_simple.reflect.json"
        );
        let hir_body_plan_validate_call_pass = wasm_pass!(
            "hir_body_plan_validate_call",
            "codegen_wasm_hir_body_plan_validate_call",
            "codegen/wasm/hir/body_plan_validate_call.spv",
            "codegen/wasm/hir/body_plan_validate_call.reflect.json"
        );
        let hir_body_plan_validate_host_void_call_pass = wasm_pass!(
            "hir_body_plan_validate_host_void_call",
            "codegen_wasm_hir_body_plan_validate_host_void_call",
            "codegen/wasm/hir/body_plan_validate_host_void_call.spv",
            "codegen/wasm/hir/body_plan_validate_host_void_call.reflect.json"
        );
        let hir_body_plan_validate_let_host_pass = wasm_pass!(
            "hir_body_plan_validate_let_host",
            "codegen_wasm_hir_body_plan_validate_let_host",
            "codegen/wasm/hir/body_plan_validate_let_host.spv",
            "codegen/wasm/hir/body_plan_validate_let_host.reflect.json"
        );
        let hir_body_plan_validate_let_host_env_pass = wasm_pass!(
            "hir_body_plan_validate_let_host_env",
            "codegen_wasm_hir_body_plan_validate_let_host_env",
            "codegen/wasm/hir/body_plan_validate_let_host_env.spv",
            "codegen/wasm/hir/body_plan_validate_let_host_env.reflect.json"
        );
        let hir_body_plan_validate_let_host_io_pass = wasm_pass!(
            "hir_body_plan_validate_let_host_io",
            "codegen_wasm_hir_body_plan_validate_let_host_io",
            "codegen/wasm/hir/body_plan_validate_let_host_io.spv",
            "codegen/wasm/hir/body_plan_validate_let_host_io.reflect.json"
        );
        let hir_body_plan_validate_let_host_string_pass = wasm_pass!(
            "hir_body_plan_validate_let_host_string",
            "codegen_wasm_hir_body_plan_validate_let_host_string",
            "codegen/wasm/hir/body_plan_validate_let_host_string.spv",
            "codegen/wasm/hir/body_plan_validate_let_host_string.reflect.json"
        );
        let hir_body_plan_validate_return_host_io_pass = wasm_pass!(
            "hir_body_plan_validate_return_host_io",
            "codegen_wasm_hir_body_plan_validate_return_host_io",
            "codegen/wasm/hir/body_plan_validate_return_host_io.spv",
            "codegen/wasm/hir/body_plan_validate_return_host_io.reflect.json"
        );
        let hir_body_plan_validate_return_host_string_pass = wasm_pass!(
            "hir_body_plan_validate_return_host_string",
            "codegen_wasm_hir_body_plan_validate_return_host_string",
            "codegen/wasm/hir/body_plan_validate_return_host_string.spv",
            "codegen/wasm/hir/body_plan_validate_return_host_string.reflect.json"
        );
        let hir_body_plan_validate_let_direct_call_pass = wasm_pass!(
            "hir_body_plan_validate_let_direct_call",
            "codegen_wasm_hir_body_plan_validate_let_direct_call",
            "codegen/wasm/hir/body_plan_validate_let_direct_call.spv",
            "codegen/wasm/hir/body_plan_validate_let_direct_call.reflect.json"
        );
        let hir_body_plan_validate_let_call_pass = wasm_pass!(
            "hir_body_plan_validate_let_call",
            "codegen_wasm_hir_body_plan_validate_let_call",
            "codegen/wasm/hir/body_plan_validate_let_call.spv",
            "codegen/wasm/hir/body_plan_validate_let_call.reflect.json"
        );
        let hir_body_plan_validate_let_call_status_pass = wasm_pass!(
            "hir_body_plan_validate_let_call_status",
            "codegen_wasm_hir_body_plan_validate_let_call_status",
            "codegen/wasm/hir/body_plan_validate_let_call_status.spv",
            "codegen/wasm/hir/body_plan_validate_let_call_status.reflect.json"
        );
        let hir_body_plan_agg_direct_call_pass = wasm_pass!(
            "hir_body_plan_agg_direct_call",
            "codegen_wasm_hir_body_plan_agg_direct_call",
            "codegen/wasm/hir/body_plan_agg_direct_call.spv",
            "codegen/wasm/hir/body_plan_agg_direct_call.reflect.json"
        );
        let hir_body_plan_agg_struct_pass = wasm_pass!(
            "hir_body_plan_agg_struct",
            "codegen_wasm_hir_body_plan_agg_struct",
            "codegen/wasm/hir/body_plan_agg_struct.spv",
            "codegen/wasm/hir/body_plan_agg_struct.reflect.json"
        );
        let hir_body_plan_arrays_pass = wasm_pass!(
            "hir_body_plan_arrays",
            "codegen_wasm_hir_body_plan_arrays",
            "codegen/wasm/hir/body_plan_arrays.spv",
            "codegen/wasm/hir/body_plan_arrays.reflect.json"
        );
        let hir_body_plan_functions_pass = wasm_pass!(
            "hir_body_plan_functions",
            "codegen_wasm_hir_body_plan_functions",
            "codegen/wasm/hir/body_plan_functions.spv",
            "codegen/wasm/hir/body_plan_functions.reflect.json"
        );
        let hir_body_plan_finalize_pass = wasm_pass!(
            "hir_body_plan_finalize",
            "codegen_wasm_hir_body_plan_finalize",
            "codegen/wasm/hir/body_plan.spv",
            "codegen/wasm/hir/body_plan.reflect.json"
        );
        let hir_body_clear_pass = wasm_pass!(
            "hir_body_clear",
            "codegen_wasm_hir_body_clear",
            "codegen/wasm/hir/body_clear.spv",
            "codegen/wasm/hir/body_clear.reflect.json"
        );
        let hir_body_counts_pass = wasm_pass!(
            "hir_body_counts",
            "codegen_wasm_hir_body_counts",
            "codegen/wasm/hir/body.spv",
            "codegen/wasm/hir/body.reflect.json"
        );
        let hir_body_scan_local_pass = wasm_pass!(
            "hir_body_scan_local",
            "codegen_wasm_hir_body_scan_local",
            "codegen/wasm/hir/body_scan_local.spv",
            "codegen/wasm/hir/body_scan_local.reflect.json"
        );
        let hir_body_scan_blocks_pass = wasm_pass!(
            "hir_body_scan_blocks",
            "codegen_wasm_hir_body_scan_blocks",
            "codegen/wasm/hir/body_scan_blocks.spv",
            "codegen/wasm/hir/body_scan_blocks.reflect.json"
        );
        let hir_body_agg_call_arg_counts_pass = wasm_pass!(
            "hir_body_agg_call_arg_counts",
            "codegen_wasm_hir_body_agg_call_arg_counts",
            "codegen/wasm/hir/body_agg_call_arg_counts.spv",
            "codegen/wasm/hir/body_agg_call_arg_counts.reflect.json"
        );
        let hir_body_agg_call_arg_records_pass = wasm_pass!(
            "hir_body_agg_call_arg_records",
            "codegen_wasm_hir_body_agg_call_arg_records",
            "codegen/wasm/hir/body_agg_call_arg_records.spv",
            "codegen/wasm/hir/body_agg_call_arg_records.reflect.json"
        );
        let hir_body_agg_call_finalize_pass = wasm_pass!(
            "hir_body_agg_call_finalize",
            "codegen_wasm_hir_body_agg_call_finalize",
            "codegen/wasm/hir/body_agg_call_finalize.spv",
            "codegen/wasm/hir/body_agg_call_finalize.reflect.json"
        );
        let hir_body_direct_call_arg_records_pass = wasm_pass!(
            "hir_body_direct_call_arg_records",
            "codegen_wasm_hir_body_direct_call_arg_records",
            "codegen/wasm/hir/body_direct_call_arg_records.spv",
            "codegen/wasm/hir/body_direct_call_arg_records.reflect.json"
        );
        let hir_body_direct_call_finalize_pass = wasm_pass!(
            "hir_body_direct_call_finalize",
            "codegen_wasm_hir_body_direct_call_finalize",
            "codegen/wasm/hir/body_direct_call_finalize.spv",
            "codegen/wasm/hir/body_direct_call_finalize.reflect.json"
        );
        let hir_body_status_pass = wasm_pass!(
            "hir_body_status",
            "codegen_wasm_hir_body_status",
            "codegen/wasm/hir/body_status.spv",
            "codegen/wasm/hir/body_status.reflect.json"
        );
        let hir_body_scatter_pass = wasm_pass!(
            "hir_body_scatter",
            "codegen_wasm_hir_body_scatter",
            "codegen/wasm/hir/body_scatter.spv",
            "codegen/wasm/hir/body_scatter.reflect.json"
        );
        let hir_body_scatter_frame_pass = wasm_pass!(
            "hir_body_scatter_frame",
            "codegen_wasm_hir_body_scatter_frame",
            "codegen/wasm/hir/body_scatter_frame.spv",
            "codegen/wasm/hir/body_scatter_frame.reflect.json"
        );
        let hir_body_scatter_return_scalar_pass = wasm_pass!(
            "hir_body_scatter_return_scalar",
            "codegen_wasm_hir_body_scatter_return_scalar",
            "codegen/wasm/hir/body_scatter_return_scalar.spv",
            "codegen/wasm/hir/body_scatter_return_scalar.reflect.json"
        );
        let hir_body_scatter_return_expr_pass = wasm_pass!(
            "hir_body_scatter_return_expr",
            "codegen_wasm_hir_body_scatter_return_expr",
            "codegen/wasm/hir/body_scatter_return_expr.spv",
            "codegen/wasm/hir/body_scatter_return_expr.reflect.json"
        );
        let hir_body_scatter_conversion_expr_pass = wasm_pass!(
            "hir_body_scatter_conversion_expr",
            "codegen_wasm_hir_body_scatter_conversion_expr",
            "codegen/wasm/hir/body_scatter_conversion_expr.spv",
            "codegen/wasm/hir/body_scatter_conversion_expr.reflect.json"
        );
        let hir_body_scatter_let_const_pass = wasm_pass!(
            "hir_body_scatter_let_const",
            "codegen_wasm_hir_body_scatter_let_const",
            "codegen/wasm/hir/body_scatter_let_const.spv",
            "codegen/wasm/hir/body_scatter_let_const.reflect.json"
        );
        let hir_body_scatter_expr_control_pass = wasm_pass!(
            "hir_body_scatter_expr_control",
            "codegen_wasm_hir_body_scatter_expr_control",
            "codegen/wasm/hir/body_scatter_expr_control.spv",
            "codegen/wasm/hir/body_scatter_expr_control.reflect.json"
        );
        let hir_body_scatter_agg_range_control_pass = wasm_pass!(
            "hir_body_scatter_agg_range_control",
            "codegen_wasm_hir_body_scatter_agg_range_control",
            "codegen/wasm/hir/body_scatter_agg_range_control.spv",
            "codegen/wasm/hir/body_scatter_agg_range_control.reflect.json"
        );
        let hir_body_scatter_let_direct_pass = wasm_pass!(
            "hir_body_scatter_let_direct",
            "codegen_wasm_hir_body_scatter_let_direct",
            "codegen/wasm/hir/body_scatter_let_direct.spv",
            "codegen/wasm/hir/body_scatter_let_direct.reflect.json"
        );
        let hir_body_scatter_direct_nested_call_pass = wasm_pass!(
            "hir_body_scatter_direct_nested_call",
            "codegen_wasm_hir_body_scatter_direct_nested_call",
            "codegen/wasm/hir/body_scatter_direct_nested_call.spv",
            "codegen/wasm/hir/body_scatter_direct_nested_call.reflect.json"
        );
        let hir_body_scatter_host_io_pass = wasm_pass!(
            "hir_body_scatter_host_io",
            "codegen_wasm_hir_body_scatter_host_io",
            "codegen/wasm/hir/body_scatter_host_io.spv",
            "codegen/wasm/hir/body_scatter_host_io.reflect.json"
        );
        let hir_body_scatter_host_pass = wasm_pass!(
            "hir_body_scatter_host",
            "codegen_wasm_hir_body_scatter_host",
            "codegen/wasm/hir/body_scatter_host.spv",
            "codegen/wasm/hir/body_scatter_host.reflect.json"
        );
        let hir_body_scatter_stored_expr_pass = wasm_pass!(
            "hir_body_scatter_stored_expr",
            "codegen_wasm_hir_body_scatter_stored_expr",
            "codegen/wasm/hir/body_scatter_stored_expr.spv",
            "codegen/wasm/hir/body_scatter_stored_expr.reflect.json"
        );
        let hir_body_scatter_array_lean_pass = wasm_pass!(
            "hir_body_scatter_array_lean",
            "codegen_wasm_hir_body_scatter_array_lean",
            "codegen/wasm/hir/body_scatter_array_lean.spv",
            "codegen/wasm/hir/body_scatter_array_lean.reflect.json"
        );
        let hir_body_scatter_agg_copy_pass = wasm_pass!(
            "hir_body_scatter_agg_copy",
            "codegen_wasm_hir_body_scatter_agg_copy",
            "codegen/wasm/hir/body_scatter_agg_copy.spv",
            "codegen/wasm/hir/body_scatter_agg_copy.reflect.json"
        );
        let hir_body_scatter_member_assign_pass = wasm_pass!(
            "hir_body_scatter_member_assign",
            "codegen_wasm_hir_body_scatter_member_assign",
            "codegen/wasm/hir/body_scatter_member_assign.spv",
            "codegen/wasm/hir/body_scatter_member_assign.reflect.json"
        );
        let hir_body_scatter_agg_direct_call_pass = wasm_pass!(
            "hir_body_scatter_agg_direct_call",
            "codegen_wasm_hir_body_scatter_agg_direct_call",
            "codegen/wasm/hir/body_scatter_agg_direct_call.spv",
            "codegen/wasm/hir/body_scatter_agg_direct_call.reflect.json"
        );
        let hir_body_scatter_agg_call_args_pass = wasm_pass!(
            "hir_body_scatter_agg_call_args",
            "codegen_wasm_hir_body_scatter_agg_call_args",
            "codegen/wasm/hir/body_scatter_agg_call_args.spv",
            "codegen/wasm/hir/body_scatter_agg_call_args.reflect.json"
        );
        let hir_body_scatter_nested_call_args_pass = wasm_pass!(
            "hir_body_scatter_nested_call_args",
            "codegen_wasm_hir_body_scatter_nested_call_args",
            "codegen/wasm/hir/body_scatter_nested_call_args.spv",
            "codegen/wasm/hir/body_scatter_nested_call_args.reflect.json"
        );
        let hir_body_scatter_return_agg_direct_call_pass = wasm_pass!(
            "hir_body_scatter_return_agg_direct_call",
            "codegen_wasm_hir_body_scatter_return_agg_direct_call",
            "codegen/wasm/hir/body_scatter_return_agg_direct_call.spv",
            "codegen/wasm/hir/body_scatter_return_agg_direct_call.reflect.json"
        );
        let hir_body_scatter_return_member_pass = wasm_pass!(
            "hir_body_scatter_return_member",
            "codegen_wasm_hir_body_scatter_return_member",
            "codegen/wasm/hir/body_scatter_return_member.spv",
            "codegen/wasm/hir/body_scatter_return_member.reflect.json"
        );
        let hir_body_scatter_binary_direct_call_pass = wasm_pass!(
            "hir_body_scatter_binary_direct_call",
            "codegen_wasm_hir_body_scatter_binary_direct_call",
            "codegen/wasm/hir/body_scatter_binary_direct_call.spv",
            "codegen/wasm/hir/body_scatter_binary_direct_call.reflect.json"
        );
        let hir_agg_body_pass = wasm_pass!(
            "hir_agg_body",
            "codegen_wasm_hir_agg_body",
            "codegen/wasm/hir/agg_body.spv",
            "codegen/wasm/hir/agg_body.reflect.json"
        );
        let hir_assert_module_pass = wasm_pass!(
            "hir_assert_module",
            "codegen_wasm_hir_assert_module",
            "codegen/wasm/hir/assert_module.spv",
            "codegen/wasm/hir/assert_module.reflect.json"
        );
        let wasm_const_values_pass = wasm_pass!(
            "const_values",
            "codegen_wasm_const_values",
            "codegen/wasm/const_values.spv",
            "codegen/wasm/const_values.reflect.json"
        );
        let module_type_lengths_pass = wasm_pass!(
            "module_type_lengths",
            "codegen_wasm_module_type_lengths",
            "codegen/wasm/module_type_lengths.spv",
            "codegen/wasm/module_type_lengths.reflect.json"
        );
        let module_type_dispatch_args_pass = wasm_pass!(
            "module_type_dispatch_args",
            "codegen_wasm_module_type_dispatch_args",
            "codegen/wasm/module_type_dispatch_args.spv",
            "codegen/wasm/module_type_dispatch_args.reflect.json"
        );
        let module_type_bytes_pass = wasm_pass!(
            "module_type_bytes",
            "codegen_wasm_module_type_bytes",
            "codegen/wasm/module_type_bytes.spv",
            "codegen/wasm/module_type_bytes.reflect.json"
        );
        let module_status_pass = wasm_pass!(
            "module_status",
            "codegen_wasm_module_status",
            "codegen/wasm/module_status.spv",
            "codegen/wasm/module_status.reflect.json"
        );
        let pass = wasm_pass!(
            "module",
            "codegen_wasm_module",
            "codegen/wasm/module.spv",
            "codegen/wasm/module.reflect.json"
        );
        let pack_pass = wasm_pass!(
            "pack",
            "codegen_pack_output",
            "codegen/pack_output.spv",
            "codegen/pack_output.reflect.json"
        );
        let call_reloc_scan_local_pass = wasm_pass!(
            "call_reloc_scan_local",
            "codegen_wasm_call_reloc_scan_local",
            "codegen/wasm/object/call_reloc_scan_local.spv",
            "codegen/wasm/object/call_reloc_scan_local.reflect.json"
        );
        let call_reloc_scatter_pass = wasm_pass!(
            "call_reloc_scatter",
            "codegen_wasm_call_reloc_scatter",
            "codegen/wasm/object/call_reloc_scatter.spv",
            "codegen/wasm/object/call_reloc_scatter.reflect.json"
        );
        let object_functions_pass = wasm_pass!(
            "object_functions",
            "codegen_wasm_object_functions",
            "codegen/wasm/object/functions.spv",
            "codegen/wasm/object/functions.reflect.json"
        );
        let object_function_bodies_pass = wasm_pass!(
            "object_function_bodies",
            "codegen_wasm_object_function_bodies",
            "codegen/wasm/object/function_bodies.spv",
            "codegen/wasm/object/function_bodies.reflect.json"
        );
        let object_symbols_pass = wasm_pass!(
            "object_symbols",
            "codegen_wasm_object_symbols",
            "codegen/wasm/object/symbols.spv",
            "codegen/wasm/object/symbols.reflect.json"
        );
        let object_bytes_pass = wasm_pass!(
            "object_bytes",
            "codegen_wasm_object_bytes",
            "codegen/wasm/object/bytes.spv",
            "codegen/wasm/object/bytes.reflect.json"
        );
        let object_metadata_pass = wasm_pass!(
            "object_metadata",
            "codegen_wasm_object_metadata",
            "codegen/wasm/object/metadata.spv",
            "codegen/wasm/object/metadata.reflect.json"
        );
        let link_module_pass = wasm_pass!(
            "link_module",
            "codegen_wasm_link_module",
            "codegen/wasm/link/module.spv",
            "codegen/wasm/link/module.reflect.json"
        );
        let link_symbol_clear_pass = wasm_pass!(
            "link_symbol_clear",
            "codegen_wasm_link_symbol_clear",
            "codegen/wasm/link/symbol_clear.spv",
            "codegen/wasm/link/symbol_clear.reflect.json"
        );
        let link_symbol_insert_pass = wasm_pass!(
            "link_symbol_insert",
            "codegen_wasm_link_symbol_insert",
            "codegen/wasm/link/symbol_insert.spv",
            "codegen/wasm/link/symbol_insert.reflect.json"
        );
        let link_symbol_define_pass = wasm_pass!(
            "link_symbol_define",
            "codegen_wasm_link_symbol_define",
            "codegen/wasm/link/symbol_define.spv",
            "codegen/wasm/link/symbol_define.reflect.json"
        );
        let link_resolve_pass = wasm_pass!(
            "link_resolve",
            "codegen_wasm_link_resolve",
            "codegen/wasm/link/resolve.spv",
            "codegen/wasm/link/resolve.reflect.json"
        );
        let link_relocate_pass = wasm_pass!(
            "link_relocate",
            "codegen_wasm_link_relocate",
            "codegen/wasm/link/relocate.spv",
            "codegen/wasm/link/relocate.reflect.json"
        );
        let generator = Self {
            agg_layout_clear_pass: join_wasm_pass!(agg_layout_clear_pass, "agg_layout_clear"),
            agg_layout_pass: join_wasm_pass!(agg_layout_pass, "agg_layout"),
            hir_body_let_init_clear_pass: join_wasm_pass!(
                hir_body_let_init_clear_pass,
                "hir_body_let_init_clear"
            ),
            hir_body_let_init_pass: join_wasm_pass!(hir_body_let_init_pass, "hir_body_let_init"),
            hir_functions_clear_pass: join_wasm_pass!(
                hir_functions_clear_pass,
                "hir_functions_clear"
            ),
            hir_functions_mark_pass: join_wasm_pass!(hir_functions_mark_pass, "hir_functions_mark"),
            hir_functions_reach_pass: join_wasm_pass!(
                hir_functions_reach_pass,
                "hir_functions_reach"
            ),
            hir_functions_count_pass: join_wasm_pass!(
                hir_functions_count_pass,
                "hir_functions_count"
            ),
            hir_functions_scatter_pass: join_wasm_pass!(
                hir_functions_scatter_pass,
                "hir_functions_scatter"
            ),
            hir_body_plan_collect_pass: join_wasm_pass!(
                hir_body_plan_collect_pass,
                "hir_body_plan_collect"
            ),
            hir_expr_same_end_rank_init_pass: join_wasm_pass!(
                hir_expr_same_end_rank_init_pass,
                "hir_expr_same_end_rank_init"
            ),
            hir_expr_same_end_rank_step_pass: join_wasm_pass!(
                hir_expr_same_end_rank_step_pass,
                "hir_expr_same_end_rank_step"
            ),
            hir_expr_order_init_pass: join_wasm_pass!(
                hir_expr_order_init_pass,
                "hir_expr_order_init"
            ),
            hir_expr_order_histogram_pass: join_wasm_pass!(
                hir_expr_order_histogram_pass,
                "hir_expr_order_histogram"
            ),
            hir_expr_order_scan_local_pass: join_wasm_pass!(
                hir_expr_order_scan_local_pass,
                "hir_expr_order_scan_local"
            ),
            hir_expr_order_scatter_pass: join_wasm_pass!(
                hir_expr_order_scatter_pass,
                "hir_expr_order_scatter"
            ),
            hir_expr_depth_init_pass: join_wasm_pass!(
                hir_expr_depth_init_pass,
                "hir_expr_depth_init"
            ),
            hir_expr_depth_step_pass: join_wasm_pass!(
                hir_expr_depth_step_pass,
                "hir_expr_depth_step"
            ),
            hir_expr_depth_block_min_pass: join_wasm_pass!(
                hir_expr_depth_block_min_pass,
                "hir_expr_depth_block_min"
            ),
            hir_expr_depth_build_min_tree_pass: join_wasm_pass!(
                hir_expr_depth_build_min_tree_pass,
                "hir_expr_depth_build_min_tree"
            ),
            hir_expr_contribution_pass: join_wasm_pass!(
                hir_expr_contribution_pass,
                "hir_expr_contribution"
            ),
            hir_expr_contribution_scan_local_pass: join_wasm_pass!(
                hir_expr_contribution_scan_local_pass,
                "hir_expr_contribution_scan_local"
            ),
            hir_expr_contribution_scan_blocks_pass: join_wasm_pass!(
                hir_expr_contribution_scan_blocks_pass,
                "hir_expr_contribution_scan_blocks"
            ),
            hir_expr_root_prefix_pass: join_wasm_pass!(
                hir_expr_root_prefix_pass,
                "hir_expr_root_prefix"
            ),
            hir_expr_root_total_pass: join_wasm_pass!(
                hir_expr_root_total_pass,
                "hir_expr_root_total"
            ),
            hir_expr_subtree_total_pass: join_wasm_pass!(
                hir_expr_subtree_total_pass,
                "hir_expr_subtree_total"
            ),
            hir_body_plan_validate_pass: join_wasm_pass!(
                hir_body_plan_validate_pass,
                "hir_body_plan_validate"
            ),
            hir_body_plan_validate_return_pass: join_wasm_pass!(
                hir_body_plan_validate_return_pass,
                "hir_body_plan_validate_return"
            ),
            hir_body_plan_validate_return_call_pass: join_wasm_pass!(
                hir_body_plan_validate_return_call_pass,
                "hir_body_plan_validate_return_call"
            ),
            hir_body_plan_validate_return_agg_call_pass: join_wasm_pass!(
                hir_body_plan_validate_return_agg_call_pass,
                "hir_body_plan_validate_return_agg_call"
            ),
            hir_body_plan_validate_return_nested_call_pass: join_wasm_pass!(
                hir_body_plan_validate_return_nested_call_pass,
                "hir_body_plan_validate_return_nested_call"
            ),
            hir_body_plan_validate_assign_pass: join_wasm_pass!(
                hir_body_plan_validate_assign_pass,
                "hir_body_plan_validate_assign"
            ),
            hir_body_plan_validate_control_pass: join_wasm_pass!(
                hir_body_plan_validate_control_pass,
                "hir_body_plan_validate_control"
            ),
            hir_body_plan_validate_agg_range_control_pass: join_wasm_pass!(
                hir_body_plan_validate_agg_range_control_pass,
                "hir_body_plan_validate_agg_range_control"
            ),
            hir_body_plan_validate_print_simple_pass: join_wasm_pass!(
                hir_body_plan_validate_print_simple_pass,
                "hir_body_plan_validate_print_simple"
            ),
            hir_body_plan_validate_call_pass: join_wasm_pass!(
                hir_body_plan_validate_call_pass,
                "hir_body_plan_validate_call"
            ),
            hir_body_plan_validate_host_void_call_pass: join_wasm_pass!(
                hir_body_plan_validate_host_void_call_pass,
                "hir_body_plan_validate_host_void_call"
            ),
            hir_body_plan_validate_let_host_pass: join_wasm_pass!(
                hir_body_plan_validate_let_host_pass,
                "hir_body_plan_validate_let_host"
            ),
            hir_body_plan_validate_let_host_env_pass: join_wasm_pass!(
                hir_body_plan_validate_let_host_env_pass,
                "hir_body_plan_validate_let_host_env"
            ),
            hir_body_plan_validate_let_host_io_pass: join_wasm_pass!(
                hir_body_plan_validate_let_host_io_pass,
                "hir_body_plan_validate_let_host_io"
            ),
            hir_body_plan_validate_let_host_string_pass: join_wasm_pass!(
                hir_body_plan_validate_let_host_string_pass,
                "hir_body_plan_validate_let_host_string"
            ),
            hir_body_plan_validate_return_host_io_pass: join_wasm_pass!(
                hir_body_plan_validate_return_host_io_pass,
                "hir_body_plan_validate_return_host_io"
            ),
            hir_body_plan_validate_return_host_string_pass: join_wasm_pass!(
                hir_body_plan_validate_return_host_string_pass,
                "hir_body_plan_validate_return_host_string"
            ),
            hir_body_plan_validate_let_direct_call_pass: join_wasm_pass!(
                hir_body_plan_validate_let_direct_call_pass,
                "hir_body_plan_validate_let_direct_call"
            ),
            hir_body_plan_validate_let_call_pass: join_wasm_pass!(
                hir_body_plan_validate_let_call_pass,
                "hir_body_plan_validate_let_call"
            ),
            hir_body_plan_validate_let_call_status_pass: join_wasm_pass!(
                hir_body_plan_validate_let_call_status_pass,
                "hir_body_plan_validate_let_call_status"
            ),
            hir_body_plan_agg_direct_call_pass: join_wasm_pass!(
                hir_body_plan_agg_direct_call_pass,
                "hir_body_plan_agg_direct_call"
            ),
            hir_body_plan_agg_struct_pass: join_wasm_pass!(
                hir_body_plan_agg_struct_pass,
                "hir_body_plan_agg_struct"
            ),
            hir_body_plan_arrays_pass: join_wasm_pass!(
                hir_body_plan_arrays_pass,
                "hir_body_plan_arrays"
            ),
            hir_body_plan_functions_pass: join_wasm_pass!(
                hir_body_plan_functions_pass,
                "hir_body_plan_functions"
            ),
            hir_body_plan_finalize_pass: join_wasm_pass!(
                hir_body_plan_finalize_pass,
                "hir_body_plan_finalize"
            ),
            hir_body_clear_pass: join_wasm_pass!(hir_body_clear_pass, "hir_body_clear"),
            hir_body_counts_pass: join_wasm_pass!(hir_body_counts_pass, "hir_body_counts"),
            hir_body_scan_local_pass: join_wasm_pass!(
                hir_body_scan_local_pass,
                "hir_body_scan_local"
            ),
            hir_body_scan_blocks_pass: join_wasm_pass!(
                hir_body_scan_blocks_pass,
                "hir_body_scan_blocks"
            ),
            hir_body_agg_call_arg_counts_pass: join_wasm_pass!(
                hir_body_agg_call_arg_counts_pass,
                "hir_body_agg_call_arg_counts"
            ),
            hir_body_agg_call_arg_records_pass: join_wasm_pass!(
                hir_body_agg_call_arg_records_pass,
                "hir_body_agg_call_arg_records"
            ),
            hir_body_agg_call_finalize_pass: join_wasm_pass!(
                hir_body_agg_call_finalize_pass,
                "hir_body_agg_call_finalize"
            ),
            hir_body_direct_call_arg_records_pass: join_wasm_pass!(
                hir_body_direct_call_arg_records_pass,
                "hir_body_direct_call_arg_records"
            ),
            hir_body_direct_call_finalize_pass: join_wasm_pass!(
                hir_body_direct_call_finalize_pass,
                "hir_body_direct_call_finalize"
            ),
            hir_body_status_pass: join_wasm_pass!(hir_body_status_pass, "hir_body_status"),
            hir_body_scatter_pass: join_wasm_pass!(hir_body_scatter_pass, "hir_body_scatter"),
            hir_body_scatter_frame_pass: join_wasm_pass!(
                hir_body_scatter_frame_pass,
                "hir_body_scatter_frame"
            ),
            hir_body_scatter_return_scalar_pass: join_wasm_pass!(
                hir_body_scatter_return_scalar_pass,
                "hir_body_scatter_return_scalar"
            ),
            hir_body_scatter_return_expr_pass: join_wasm_pass!(
                hir_body_scatter_return_expr_pass,
                "hir_body_scatter_return_expr"
            ),
            hir_body_scatter_conversion_expr_pass: join_wasm_pass!(
                hir_body_scatter_conversion_expr_pass,
                "hir_body_scatter_conversion_expr"
            ),
            hir_body_scatter_let_const_pass: join_wasm_pass!(
                hir_body_scatter_let_const_pass,
                "hir_body_scatter_let_const"
            ),
            hir_body_scatter_expr_control_pass: join_wasm_pass!(
                hir_body_scatter_expr_control_pass,
                "hir_body_scatter_expr_control"
            ),
            hir_body_scatter_agg_range_control_pass: join_wasm_pass!(
                hir_body_scatter_agg_range_control_pass,
                "hir_body_scatter_agg_range_control"
            ),
            hir_body_scatter_let_direct_pass: join_wasm_pass!(
                hir_body_scatter_let_direct_pass,
                "hir_body_scatter_let_direct"
            ),
            hir_body_scatter_direct_nested_call_pass: join_wasm_pass!(
                hir_body_scatter_direct_nested_call_pass,
                "hir_body_scatter_direct_nested_call"
            ),
            hir_body_scatter_host_io_pass: join_wasm_pass!(
                hir_body_scatter_host_io_pass,
                "hir_body_scatter_host_io"
            ),
            hir_body_scatter_host_pass: join_wasm_pass!(
                hir_body_scatter_host_pass,
                "hir_body_scatter_host"
            ),
            hir_body_scatter_stored_expr_pass: join_wasm_pass!(
                hir_body_scatter_stored_expr_pass,
                "hir_body_scatter_stored_expr"
            ),
            hir_body_scatter_array_lean_pass: join_wasm_pass!(
                hir_body_scatter_array_lean_pass,
                "hir_body_scatter_array_lean"
            ),
            hir_body_scatter_agg_copy_pass: join_wasm_pass!(
                hir_body_scatter_agg_copy_pass,
                "hir_body_scatter_agg_copy"
            ),
            hir_body_scatter_member_assign_pass: join_wasm_pass!(
                hir_body_scatter_member_assign_pass,
                "hir_body_scatter_member_assign"
            ),
            hir_body_scatter_agg_direct_call_pass: join_wasm_pass!(
                hir_body_scatter_agg_direct_call_pass,
                "hir_body_scatter_agg_direct_call"
            ),
            hir_body_scatter_agg_call_args_pass: join_wasm_pass!(
                hir_body_scatter_agg_call_args_pass,
                "hir_body_scatter_agg_call_args"
            ),
            hir_body_scatter_nested_call_args_pass: join_wasm_pass!(
                hir_body_scatter_nested_call_args_pass,
                "hir_body_scatter_nested_call_args"
            ),
            hir_body_scatter_return_agg_direct_call_pass: join_wasm_pass!(
                hir_body_scatter_return_agg_direct_call_pass,
                "hir_body_scatter_return_agg_direct_call"
            ),
            hir_body_scatter_return_member_pass: join_wasm_pass!(
                hir_body_scatter_return_member_pass,
                "hir_body_scatter_return_member"
            ),
            hir_body_scatter_binary_direct_call_pass: join_wasm_pass!(
                hir_body_scatter_binary_direct_call_pass,
                "hir_body_scatter_binary_direct_call"
            ),
            hir_agg_body_pass: join_wasm_pass!(hir_agg_body_pass, "hir_agg_body"),
            hir_assert_module_pass: join_wasm_pass!(hir_assert_module_pass, "hir_assert_module"),
            wasm_const_values_pass: join_wasm_pass!(wasm_const_values_pass, "const_values"),
            module_type_lengths_pass: join_wasm_pass!(
                module_type_lengths_pass,
                "module_type_lengths"
            ),
            module_type_dispatch_args_pass: join_wasm_pass!(
                module_type_dispatch_args_pass,
                "module_type_dispatch_args"
            ),
            module_type_bytes_pass: join_wasm_pass!(module_type_bytes_pass, "module_type_bytes"),
            module_status_pass: join_wasm_pass!(module_status_pass, "module_status"),
            pass: join_wasm_pass!(pass, "module"),
            pack_pass: join_wasm_pass!(pack_pass, "pack"),
            call_reloc_scan_local_pass: join_wasm_pass!(
                call_reloc_scan_local_pass,
                "call_reloc_scan_local"
            ),
            call_reloc_scatter_pass: join_wasm_pass!(call_reloc_scatter_pass, "call_reloc_scatter"),
            object_functions_pass: join_wasm_pass!(object_functions_pass, "object_functions"),
            object_function_bodies_pass: join_wasm_pass!(
                object_function_bodies_pass,
                "object_function_bodies"
            ),
            object_symbols_pass: join_wasm_pass!(object_symbols_pass, "object_symbols"),
            object_bytes_pass: join_wasm_pass!(object_bytes_pass, "object_bytes"),
            object_metadata_pass: join_wasm_pass!(object_metadata_pass, "object_metadata"),
            link_module_pass: join_wasm_pass!(link_module_pass, "link_module"),
            link_symbol_clear_pass: join_wasm_pass!(link_symbol_clear_pass, "link_symbol_clear"),
            link_symbol_insert_pass: join_wasm_pass!(link_symbol_insert_pass, "link_symbol_insert"),
            link_symbol_define_pass: join_wasm_pass!(link_symbol_define_pass, "link_symbol_define"),
            link_resolve_pass: join_wasm_pass!(link_resolve_pass, "link_resolve"),
            link_relocate_pass: join_wasm_pass!(link_relocate_pass, "link_relocate"),
            buffers: Mutex::new(None),
        };
        gpu.persist_pipeline_cache();
        Ok(generator)
    }

    /// Releases reusable WASM working buffers and bind groups while retaining
    /// all lazily created backend pipelines.
    pub(crate) fn release_current_resident_buffers(&self) {
        *self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned") = None;
    }
}
