use std::{fmt, sync::Mutex};

use anyhow::Result;
use encase::ShaderType;

mod support;
use support::*;

use crate::gpu::{
    device,
    passes_core::{PassData, bind_group, make_traced_main_pass},
};

const HIR_MODULE_OUTPUT_TARGET_LIMIT: u32 = 512;

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmParams {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
}

pub struct RecordedWasmCodegen {
    output_capacity: usize,
    token_capacity: u32,
}

#[derive(Debug)]
pub struct WasmOutputError {
    error_name: &'static str,
    error_code: u32,
    error_detail: u32,
}

impl WasmOutputError {
    pub(super) fn new(error_name: &'static str, error_code: u32, error_detail: u32) -> Self {
        Self {
            error_name,
            error_code,
            error_detail,
        }
    }

    pub fn error_name(&self) -> &'static str {
        self.error_name
    }

    pub fn error_code(&self) -> u32 {
        self.error_code
    }

    pub fn error_detail(&self) -> u32 {
        self.error_detail
    }

    pub fn detail_is_token(&self) -> bool {
        self.error_detail != u32::MAX
            && (self.error_code == 2
                || ((800..=899).contains(&self.error_code)
                    && !matches!(self.error_code, 830 | 831)))
    }
}

impl fmt::Display for WasmOutputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        write!(
            f,
            "GPU WASM emitter rejected {} (code {}) at detail {}",
            self.error_name, self.error_code, self.error_detail
        )
    }
}

impl std::error::Error for WasmOutputError {}

#[derive(Clone, Copy)]
pub struct GpuWasmStructMetadataBuffers<'a> {
    pub field_parent_struct: &'a wgpu::Buffer,
    pub field_ordinal: &'a wgpu::Buffer,
    pub lit_field_parent_lit: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub struct GpuWasmEnumMatchMetadataBuffers<'a> {
    pub variant_ordinal: &'a wgpu::Buffer,
    pub match_scrutinee_node: &'a wgpu::Buffer,
    pub match_arm_start: &'a wgpu::Buffer,
    pub match_arm_count: &'a wgpu::Buffer,
    pub match_arm_next: &'a wgpu::Buffer,
    pub match_arm_pattern_node: &'a wgpu::Buffer,
    pub match_arm_payload_start: &'a wgpu::Buffer,
    pub match_arm_payload_count: &'a wgpu::Buffer,
    pub match_arm_result_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub struct GpuWasmCallMetadataBuffers<'a> {
    pub callee_node: &'a wgpu::Buffer,
    pub context_stmt: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
pub struct GpuWasmExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub result_root_node: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub nearest_stmt_node: &'a wgpu::Buffer,
    pub nearest_block_node: &'a wgpu::Buffer,
    pub nearest_enclosing_control_node: &'a wgpu::Buffer,
}

struct ResidentWasmBuffers {
    input_fingerprint: u64,
    output_capacity: usize,
    token_capacity: u32,
    hir_node_capacity: u32,
    params_buf: wgpu::Buffer,
    body_dispatch_buf: wgpu::Buffer,
    _body_buf: wgpu::Buffer,
    body_status_buf: wgpu::Buffer,
    _struct_field_count_by_decl_token_buf: wgpu::Buffer,
    _struct_field_index_by_token_buf: wgpu::Buffer,
    _struct_field_decl_by_token_buf: wgpu::Buffer,
    _struct_field_name_id_buf: wgpu::Buffer,
    _struct_field_ref_tag_buf: wgpu::Buffer,
    _struct_field_ref_payload_buf: wgpu::Buffer,
    _struct_field_scalar_offset_buf: wgpu::Buffer,
    _struct_field_scalar_width_buf: wgpu::Buffer,
    _struct_init_field_index_buf: wgpu::Buffer,
    _member_result_field_index_buf: wgpu::Buffer,
    _hir_enum_match_record_buf: wgpu::Buffer,
    wasm_const_value_record_buf: wgpu::Buffer,
    out_buf: wgpu::Buffer,
    packed_out_buf: wgpu::Buffer,
    status_buf: wgpu::Buffer,
    out_readback: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    agg_layout_clear_bind_group: wgpu::BindGroup,
    agg_layout_bind_group: wgpu::BindGroup,
    hir_body_bind_group: wgpu::BindGroup,
    hir_agg_body_bind_group: wgpu::BindGroup,
    hir_module_bind_group: wgpu::BindGroup,
    hir_assert_module_bind_group: wgpu::BindGroup,
    hir_enum_match_records_bind_group: wgpu::BindGroup,
    wasm_const_values_bind_group: wgpu::BindGroup,
    bind_group: wgpu::BindGroup,
    pack_bind_group: wgpu::BindGroup,
}

pub struct GpuWasmCodeGenerator {
    agg_layout_clear_pass: PassData,
    agg_layout_pass: PassData,
    hir_body_pass: PassData,
    hir_agg_body_pass: PassData,
    hir_module_pass: PassData,
    hir_assert_module_pass: PassData,
    hir_enum_match_records_pass: PassData,
    wasm_const_values_pass: PassData,
    pass: PassData,
    pack_pass: PassData,
    buffers: Mutex<Option<ResidentWasmBuffers>>,
}

impl GpuWasmCodeGenerator {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        macro_rules! wasm_pass {
            ($stage:literal, $label:literal, $spv:literal, $reflection:literal) => {
                make_traced_main_pass!(
                    &gpu.device,
                    trace_wasm_codegen,
                    $stage,
                    $label,
                    artifacts: ($spv, $reflection)
                )
            };
        }

        let agg_layout_clear_pass = wasm_pass!(
            "agg_layout_clear",
            "codegen_wasm_agg_layout_clear",
            "wasm_agg_layout_clear.spv",
            "wasm_agg_layout_clear.reflect.json"
        );
        let agg_layout_pass = wasm_pass!(
            "agg_layout",
            "codegen_wasm_agg_layout",
            "wasm_agg_layout.spv",
            "wasm_agg_layout.reflect.json"
        );
        let hir_body_pass = wasm_pass!(
            "hir_body",
            "codegen_wasm_hir_body",
            "wasm_hir_body.spv",
            "wasm_hir_body.reflect.json"
        );
        let hir_agg_body_pass = wasm_pass!(
            "hir_agg_body",
            "codegen_wasm_hir_agg_body",
            "wasm_hir_agg_body.spv",
            "wasm_hir_agg_body.reflect.json"
        );
        let hir_module_pass = wasm_pass!(
            "hir_module",
            "codegen_wasm_hir_module",
            "wasm_hir_module.spv",
            "wasm_hir_module.reflect.json"
        );
        let hir_assert_module_pass = wasm_pass!(
            "hir_assert_module",
            "codegen_wasm_hir_assert_module",
            "wasm_hir_assert_module.spv",
            "wasm_hir_assert_module.reflect.json"
        );
        let hir_enum_match_records_pass = wasm_pass!(
            "hir_enum_match_records",
            "codegen_wasm_hir_enum_match_records",
            "wasm_hir_enum_match_records.spv",
            "wasm_hir_enum_match_records.reflect.json"
        );
        let wasm_const_values_pass = wasm_pass!(
            "const_values",
            "codegen_wasm_const_values",
            "wasm_const_values.spv",
            "wasm_const_values.reflect.json"
        );
        let pass = wasm_pass!(
            "module",
            "codegen_wasm_module",
            "wasm_module.spv",
            "wasm_module.reflect.json"
        );
        let pack_pass = wasm_pass!(
            "pack",
            "codegen_pack_output",
            "pack_output.spv",
            "pack_output.reflect.json"
        );
        Ok(Self {
            agg_layout_clear_pass,
            agg_layout_pass,
            hir_body_pass,
            hir_agg_body_pass,
            hir_module_pass,
            hir_assert_module_pass,
            hir_enum_match_records_pass,
            wasm_const_values_pass,
            pass,
            pack_pass,
            buffers: Mutex::new(None),
        })
    }

    pub fn record_wasm_from_gpu_token_buffer(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        source_len: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        hir_param_record_buf: &wgpu::Buffer,
        type_expr_ref_tag_buf: &wgpu::Buffer,
        type_expr_ref_payload_buf: &wgpu::Buffer,
        module_value_path_call_head_buf: &wgpu::Buffer,
        module_value_path_call_open_buf: &wgpu::Buffer,
        module_value_path_const_head_buf: &wgpu::Buffer,
        module_value_path_const_end_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_intrinsic_tag_buf: &wgpu::Buffer,
        fn_entrypoint_tag_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        call_return_type_token_buf: &wgpu::Buffer,
        call_param_count_buf: &wgpu::Buffer,
        call_param_type_buf: &wgpu::Buffer,
        method_decl_receiver_ref_tag_buf: &wgpu::Buffer,
        method_decl_receiver_ref_payload_buf: &wgpu::Buffer,
        method_decl_param_offset_buf: &wgpu::Buffer,
        method_decl_receiver_mode_buf: &wgpu::Buffer,
        method_call_receiver_ref_tag_buf: &wgpu::Buffer,
        method_call_receiver_ref_payload_buf: &wgpu::Buffer,
        type_instance_decl_token_buf: &wgpu::Buffer,
        type_instance_arg_start_buf: &wgpu::Buffer,
        type_instance_arg_count_buf: &wgpu::Buffer,
        type_instance_arg_ref_tag_buf: &wgpu::Buffer,
        type_instance_arg_ref_payload_buf: &wgpu::Buffer,
        fn_return_ref_tag_buf: &wgpu::Buffer,
        fn_return_ref_payload_buf: &wgpu::Buffer,
        member_result_ref_tag_buf: &wgpu::Buffer,
        member_result_ref_payload_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_tag_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_payload_buf: &wgpu::Buffer,
    ) -> Result<RecordedWasmCodegen> {
        trace_wasm_codegen("record.start");
        let output_capacity = estimate_wasm_output_capacity(source_len as usize, token_capacity);
        trace_wasm_codegen(&format!(
            "record.capacity output={output_capacity} tokens={token_capacity} hir_nodes={hir_node_capacity}"
        ));
        trace_wasm_codegen("record.fingerprint.start");
        let input_fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            source_buf,
            node_kind_buf,
            parent_buf,
            first_child_buf,
            next_sibling_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            visible_decl_buf,
            visible_type_buf,
            name_id_by_token_buf,
            enclosing_fn_buf,
            struct_metadata.field_parent_struct,
            struct_metadata.field_ordinal,
            struct_metadata.lit_field_parent_lit,
            enum_match_metadata.variant_ordinal,
            enum_match_metadata.match_scrutinee_node,
            enum_match_metadata.match_arm_start,
            enum_match_metadata.match_arm_count,
            enum_match_metadata.match_arm_next,
            enum_match_metadata.match_arm_pattern_node,
            enum_match_metadata.match_arm_payload_start,
            enum_match_metadata.match_arm_payload_count,
            enum_match_metadata.match_arm_result_node,
            call_metadata.callee_node,
            call_metadata.context_stmt,
            call_metadata.arg_start,
            call_metadata.arg_parent_call,
            call_metadata.arg_end,
            call_metadata.arg_count,
            call_metadata.arg_ordinal,
            expr_metadata.record,
            expr_metadata.result_root_node,
            expr_metadata.int_value,
            expr_metadata.stmt_record,
            hir_param_record_buf,
            type_expr_ref_tag_buf,
            type_expr_ref_payload_buf,
            module_value_path_call_head_buf,
            module_value_path_call_open_buf,
            module_value_path_const_head_buf,
            module_value_path_const_end_buf,
            call_fn_index_buf,
            call_intrinsic_tag_buf,
            fn_entrypoint_tag_buf,
            call_return_type_buf,
            call_return_type_token_buf,
            call_param_count_buf,
            call_param_type_buf,
            method_decl_receiver_ref_tag_buf,
            method_decl_receiver_ref_payload_buf,
            method_decl_param_offset_buf,
            method_decl_receiver_mode_buf,
            method_call_receiver_ref_tag_buf,
            method_call_receiver_ref_payload_buf,
            type_instance_decl_token_buf,
            type_instance_arg_start_buf,
            type_instance_arg_count_buf,
            type_instance_arg_ref_tag_buf,
            type_instance_arg_ref_payload_buf,
            fn_return_ref_tag_buf,
            fn_return_ref_payload_buf,
            member_result_ref_tag_buf,
            member_result_ref_payload_buf,
            struct_init_field_expected_ref_tag_buf,
            struct_init_field_expected_ref_payload_buf,
        ]);
        trace_wasm_codegen("record.fingerprint.done");
        trace_wasm_codegen("record.lock.start");
        let mut guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        trace_wasm_codegen("record.lock.done");
        trace_wasm_codegen("record.resident.start");
        let bufs = self.resident_buffers_for(
            &mut guard,
            device,
            input_fingerprint,
            output_capacity,
            token_capacity,
            hir_node_capacity,
            token_buf,
            token_count_buf,
            source_buf,
            node_kind_buf,
            parent_buf,
            first_child_buf,
            next_sibling_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            visible_decl_buf,
            visible_type_buf,
            name_id_by_token_buf,
            enclosing_fn_buf,
            struct_metadata,
            enum_match_metadata,
            call_metadata,
            expr_metadata,
            hir_param_record_buf,
            type_expr_ref_tag_buf,
            type_expr_ref_payload_buf,
            module_value_path_call_head_buf,
            module_value_path_call_open_buf,
            module_value_path_const_head_buf,
            module_value_path_const_end_buf,
            call_fn_index_buf,
            call_intrinsic_tag_buf,
            fn_entrypoint_tag_buf,
            call_return_type_buf,
            call_return_type_token_buf,
            call_param_count_buf,
            call_param_type_buf,
            method_decl_receiver_ref_tag_buf,
            method_decl_receiver_ref_payload_buf,
            method_decl_param_offset_buf,
            method_decl_receiver_mode_buf,
            method_call_receiver_ref_tag_buf,
            method_call_receiver_ref_payload_buf,
            type_instance_decl_token_buf,
            type_instance_arg_start_buf,
            type_instance_arg_count_buf,
            type_instance_arg_ref_tag_buf,
            type_instance_arg_ref_payload_buf,
            fn_return_ref_tag_buf,
            fn_return_ref_payload_buf,
            member_result_ref_tag_buf,
            member_result_ref_payload_buf,
            struct_init_field_expected_ref_tag_buf,
            struct_init_field_expected_ref_payload_buf,
        )?;
        trace_wasm_codegen("record.resident.done");

        let params = WasmParams {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes: hir_node_capacity,
        };
        trace_wasm_codegen("record.write_params.start");
        queue.write_buffer(&bufs.params_buf, 0, &wasm_params_bytes(&params));
        queue.write_buffer(&bufs.body_status_buf, 0, &body_status_init_bytes());
        queue.write_buffer(&bufs.status_buf, 0, &unsupported_shape_status_init_bytes());
        let const_value_clear = vec![0u8; bufs.token_capacity as usize * 2 * 4];
        queue.write_buffer(&bufs.wasm_const_value_record_buf, 0, &const_value_clear);
        queue.write_buffer(&bufs.body_dispatch_buf, 0, &dispatch_args_bytes(1, 1, 1));
        trace_wasm_codegen("record.write_params.done");

        let token_groups = token_capacity.div_ceil(256).max(1);
        let agg_layout_groups = token_capacity.max(hir_node_capacity).div_ceil(256).max(1);
        let (agg_layout_groups_x, agg_layout_groups_y) = workgroup_grid_1d(agg_layout_groups);
        let hir_module_output_groups = ((output_capacity as u32)
            .min(HIR_MODULE_OUTPUT_TARGET_LIMIT))
        .div_ceil(256)
        .max(1);
        let (hir_module_output_groups_x, hir_module_output_groups_y) =
            workgroup_grid_1d(hir_module_output_groups);

        trace_wasm_codegen("record.dispatch.agg_layout_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.agg_layout_clear_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.agg_layout_clear_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout_clear.done");

        trace_wasm_codegen("record.dispatch.agg_layout.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.agg_layout_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.agg_layout_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout.done");

        trace_wasm_codegen("record.dispatch.const_values.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.const_values"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.wasm_const_values_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.wasm_const_values_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.const_values.done");

        trace_wasm_codegen("record.dispatch.legacy_source_shape.skipped");

        trace_wasm_codegen("record.dispatch.hir_body.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.hir_body_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.hir_body_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body.done");

        trace_wasm_codegen("record.dispatch.hir_agg_body.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_agg_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.hir_agg_body_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.hir_agg_body_bind_group), &[]);
        compute.dispatch_workgroups(token_groups, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_agg_body.done");

        trace_wasm_codegen("record.dispatch.hir_enum_match_records.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_enum_match_records"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.hir_enum_match_records_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.hir_enum_match_records_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_enum_match_records.done");

        trace_wasm_codegen("record.dispatch.hir_enum_match_module.retired_not_loaded");

        trace_wasm_codegen("record.dispatch.module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.module.done");

        trace_wasm_codegen("record.dispatch.hir_module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.hir_module_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.hir_module_bind_group), &[]);
        compute.dispatch_workgroups(hir_module_output_groups_x, hir_module_output_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_module.done");

        trace_wasm_codegen("record.dispatch.hir_assert_module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_assert_module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.hir_assert_module_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.hir_assert_module_bind_group), &[]);
        compute.dispatch_workgroups(hir_module_output_groups_x, hir_module_output_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_assert_module.done");

        trace_wasm_codegen("record.dispatch.pack_output.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.pack_output"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&self.pack_pass.pipeline);
        compute.set_bind_group(0, Some(&bufs.pack_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.pack_output.done");
        trace_wasm_codegen("record.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        trace_wasm_codegen("record.copy_status.done");

        Ok(RecordedWasmCodegen {
            output_capacity,
            token_capacity,
        })
    }

    pub fn finish_recorded_wasm(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedWasmCodegen,
    ) -> Result<Vec<u8>> {
        let guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("GPU WASM codegen buffers missing"))?;
        read_wasm_output(
            device,
            queue,
            &bufs.out_buf,
            &bufs.packed_out_buf,
            &bufs.status_readback,
            &bufs.out_readback,
            recorded.output_capacity,
            recorded.token_capacity,
        )
    }

    fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentWasmBuffers>,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        hir_node_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        hir_param_record_buf: &wgpu::Buffer,
        type_expr_ref_tag_buf: &wgpu::Buffer,
        type_expr_ref_payload_buf: &wgpu::Buffer,
        module_value_path_call_head_buf: &wgpu::Buffer,
        module_value_path_call_open_buf: &wgpu::Buffer,
        module_value_path_const_head_buf: &wgpu::Buffer,
        module_value_path_const_end_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_intrinsic_tag_buf: &wgpu::Buffer,
        fn_entrypoint_tag_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        call_return_type_token_buf: &wgpu::Buffer,
        call_param_count_buf: &wgpu::Buffer,
        call_param_type_buf: &wgpu::Buffer,
        method_decl_receiver_ref_tag_buf: &wgpu::Buffer,
        method_decl_receiver_ref_payload_buf: &wgpu::Buffer,
        method_decl_param_offset_buf: &wgpu::Buffer,
        method_decl_receiver_mode_buf: &wgpu::Buffer,
        method_call_receiver_ref_tag_buf: &wgpu::Buffer,
        method_call_receiver_ref_payload_buf: &wgpu::Buffer,
        type_instance_decl_token_buf: &wgpu::Buffer,
        type_instance_arg_start_buf: &wgpu::Buffer,
        type_instance_arg_count_buf: &wgpu::Buffer,
        type_instance_arg_ref_tag_buf: &wgpu::Buffer,
        type_instance_arg_ref_payload_buf: &wgpu::Buffer,
        fn_return_ref_tag_buf: &wgpu::Buffer,
        fn_return_ref_payload_buf: &wgpu::Buffer,
        member_result_ref_tag_buf: &wgpu::Buffer,
        member_result_ref_payload_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_tag_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_payload_buf: &wgpu::Buffer,
    ) -> Result<&'a ResidentWasmBuffers> {
        let needs_rebuild = slot.as_ref().is_none_or(|cached| {
            cached.input_fingerprint != input_fingerprint
                || cached.output_capacity < output_capacity
                || cached.token_capacity < token_capacity
                || cached.hir_node_capacity < hir_node_capacity
        });
        if needs_rebuild {
            *slot = Some(self.create_resident_buffers(
                device,
                input_fingerprint,
                output_capacity,
                token_capacity,
                hir_node_capacity,
                token_buf,
                token_count_buf,
                source_buf,
                node_kind_buf,
                parent_buf,
                first_child_buf,
                next_sibling_buf,
                hir_kind_buf,
                hir_token_pos_buf,
                hir_token_end_buf,
                hir_status_buf,
                visible_decl_buf,
                visible_type_buf,
                name_id_by_token_buf,
                enclosing_fn_buf,
                struct_metadata,
                enum_match_metadata,
                call_metadata,
                expr_metadata,
                hir_param_record_buf,
                type_expr_ref_tag_buf,
                type_expr_ref_payload_buf,
                module_value_path_call_head_buf,
                module_value_path_call_open_buf,
                module_value_path_const_head_buf,
                module_value_path_const_end_buf,
                call_fn_index_buf,
                call_intrinsic_tag_buf,
                fn_entrypoint_tag_buf,
                call_return_type_buf,
                call_return_type_token_buf,
                call_param_count_buf,
                call_param_type_buf,
                method_decl_receiver_ref_tag_buf,
                method_decl_receiver_ref_payload_buf,
                method_decl_param_offset_buf,
                method_decl_receiver_mode_buf,
                method_call_receiver_ref_tag_buf,
                method_call_receiver_ref_payload_buf,
                type_instance_decl_token_buf,
                type_instance_arg_start_buf,
                type_instance_arg_count_buf,
                type_instance_arg_ref_tag_buf,
                type_instance_arg_ref_payload_buf,
                fn_return_ref_tag_buf,
                fn_return_ref_payload_buf,
                member_result_ref_tag_buf,
                member_result_ref_payload_buf,
                struct_init_field_expected_ref_tag_buf,
                struct_init_field_expected_ref_payload_buf,
            )?);
        }
        Ok(slot.as_ref().expect("resident wasm buffers allocated"))
    }

    fn create_resident_buffers(
        &self,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        hir_node_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        _visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        hir_param_record_buf: &wgpu::Buffer,
        type_expr_ref_tag_buf: &wgpu::Buffer,
        type_expr_ref_payload_buf: &wgpu::Buffer,
        module_value_path_call_head_buf: &wgpu::Buffer,
        module_value_path_call_open_buf: &wgpu::Buffer,
        module_value_path_const_head_buf: &wgpu::Buffer,
        module_value_path_const_end_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_intrinsic_tag_buf: &wgpu::Buffer,
        fn_entrypoint_tag_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        _call_return_type_token_buf: &wgpu::Buffer,
        call_param_count_buf: &wgpu::Buffer,
        call_param_type_buf: &wgpu::Buffer,
        method_decl_receiver_ref_tag_buf: &wgpu::Buffer,
        method_decl_receiver_ref_payload_buf: &wgpu::Buffer,
        method_decl_param_offset_buf: &wgpu::Buffer,
        method_decl_receiver_mode_buf: &wgpu::Buffer,
        method_call_receiver_ref_tag_buf: &wgpu::Buffer,
        method_call_receiver_ref_payload_buf: &wgpu::Buffer,
        type_instance_decl_token_buf: &wgpu::Buffer,
        type_instance_arg_start_buf: &wgpu::Buffer,
        type_instance_arg_count_buf: &wgpu::Buffer,
        type_instance_arg_ref_tag_buf: &wgpu::Buffer,
        type_instance_arg_ref_payload_buf: &wgpu::Buffer,
        fn_return_ref_tag_buf: &wgpu::Buffer,
        fn_return_ref_payload_buf: &wgpu::Buffer,
        member_result_ref_tag_buf: &wgpu::Buffer,
        member_result_ref_payload_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_tag_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_payload_buf: &wgpu::Buffer,
    ) -> Result<ResidentWasmBuffers> {
        let params_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("codegen.wasm.params"),
            size: 16,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let out_buf = storage_u32_rw(
            device,
            "codegen.wasm.out_words",
            output_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_dispatch_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_dispatch",
            3,
            wgpu::BufferUsages::INDIRECT,
        );
        let packed_out_buf = storage_u32_rw(
            device,
            "codegen.wasm.packed_out_words",
            output_capacity.div_ceil(4),
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_words",
            output_capacity,
            wgpu::BufferUsages::empty(),
        );
        let body_status_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_status",
            4,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_count_by_decl_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_count_by_decl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_index_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_index_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_decl_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_decl_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_name_id_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_name_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_ref_tag_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_ref_payload_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_scalar_offset_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_scalar_offset",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_field_scalar_width_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_field_scalar_width",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_index_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.struct_init_field_index",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_field_index_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.member_result_field_index",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let hir_enum_match_record_buf = storage_u32_rw(
            device,
            "codegen.wasm.hir_enum_match_record",
            hir_node_capacity as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let wasm_const_value_record_buf = storage_u32_rw(
            device,
            "codegen.wasm.const_value_record",
            token_capacity as usize * 2,
            wgpu::BufferUsages::empty(),
        );
        let status_buf = storage_u32_rw(
            device,
            "codegen.wasm.status",
            4,
            wgpu::BufferUsages::COPY_SRC,
        );
        let out_readback = readback_u32s(
            device,
            "rb.codegen.wasm.out_words",
            output_capacity.div_ceil(4),
        );
        let status_readback = readback_u32s(device, "rb.codegen.wasm.status", 4);

        let wasm_const_values_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_const_values"),
            &self.wasm_const_values_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_result_root_node",
                    expr_metadata.result_root_node.as_entire_binding(),
                ),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "wasm_const_value_record",
                    wasm_const_value_record_buf.as_entire_binding(),
                ),
            ],
        )?;

        macro_rules! add_codegen_metadata_bindings {
            ($bindings:expr) => {{
                $bindings.extend([
                    ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                    (
                        "type_expr_ref_tag",
                        type_expr_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "type_expr_ref_payload",
                        type_expr_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "method_decl_receiver_ref_tag",
                        method_decl_receiver_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "method_decl_receiver_ref_payload",
                        method_decl_receiver_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "method_decl_param_offset",
                        method_decl_param_offset_buf.as_entire_binding(),
                    ),
                    (
                        "method_decl_receiver_mode",
                        method_decl_receiver_mode_buf.as_entire_binding(),
                    ),
                    (
                        "method_call_receiver_ref_tag",
                        method_call_receiver_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "method_call_receiver_ref_payload",
                        method_call_receiver_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "type_instance_decl_token",
                        type_instance_decl_token_buf.as_entire_binding(),
                    ),
                    (
                        "type_instance_arg_start",
                        type_instance_arg_start_buf.as_entire_binding(),
                    ),
                    (
                        "type_instance_arg_count",
                        type_instance_arg_count_buf.as_entire_binding(),
                    ),
                    (
                        "type_instance_arg_ref_tag",
                        type_instance_arg_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "type_instance_arg_ref_payload",
                        type_instance_arg_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "fn_return_ref_tag",
                        fn_return_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "fn_return_ref_payload",
                        fn_return_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_ref_tag",
                        member_result_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_ref_payload",
                        member_result_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "struct_init_field_expected_ref_tag",
                        struct_init_field_expected_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "struct_init_field_expected_ref_payload",
                        struct_init_field_expected_ref_payload_buf.as_entire_binding(),
                    ),
                ]);
            }};
        }

        macro_rules! add_aggregate_layout_output_bindings {
            ($bindings:expr) => {{
                $bindings.extend([
                    (
                        "struct_field_count_by_decl_token",
                        struct_field_count_by_decl_token_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_index_by_token",
                        struct_field_index_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_decl_by_token",
                        struct_field_decl_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_name_id",
                        struct_field_name_id_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_ref_tag",
                        struct_field_ref_tag_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_ref_payload",
                        struct_field_ref_payload_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_scalar_offset",
                        struct_field_scalar_offset_buf.as_entire_binding(),
                    ),
                    (
                        "struct_field_scalar_width",
                        struct_field_scalar_width_buf.as_entire_binding(),
                    ),
                    (
                        "struct_init_field_index",
                        struct_init_field_index_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_field_index",
                        member_result_field_index_buf.as_entire_binding(),
                    ),
                ]);
            }};
        }

        let mut agg_layout_clear_bindings = vec![("gParams", params_buf.as_entire_binding())];
        add_aggregate_layout_output_bindings!(agg_layout_clear_bindings);
        let agg_layout_clear_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_agg_layout_clear"),
            &self.agg_layout_clear_pass,
            0,
            &agg_layout_clear_bindings,
        )?;

        let mut agg_layout_bindings = vec![
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("node_kind", node_kind_buf.as_entire_binding()),
            ("parent", parent_buf.as_entire_binding()),
            ("first_child", first_child_buf.as_entire_binding()),
            ("next_sibling", next_sibling_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_struct_field_parent_struct",
                struct_metadata.field_parent_struct.as_entire_binding(),
            ),
            (
                "hir_struct_field_ordinal",
                struct_metadata.field_ordinal.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                struct_metadata.lit_field_parent_lit.as_entire_binding(),
            ),
            ("visible_decl", visible_decl_buf.as_entire_binding()),
            ("call_fn_index", call_fn_index_buf.as_entire_binding()),
        ];
        add_codegen_metadata_bindings!(agg_layout_bindings);
        add_aggregate_layout_output_bindings!(agg_layout_bindings);
        let agg_layout_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_agg_layout"),
            &self.agg_layout_pass,
            0,
            &agg_layout_bindings,
        )?;

        let hir_body_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_hir_body"),
            &self.hir_body_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("parent", parent_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("hir_token_end", hir_token_end_buf.as_entire_binding()),
                ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                (
                    "fn_entrypoint_tag",
                    fn_entrypoint_tag_buf.as_entire_binding(),
                ),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "wasm_const_value_record",
                    wasm_const_value_record_buf.as_entire_binding(),
                ),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "hir_expr_result_root_node",
                    expr_metadata.result_root_node.as_entire_binding(),
                ),
                (
                    "hir_expr_int_value",
                    expr_metadata.int_value.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_call_context_stmt_node",
                    call_metadata.context_stmt.as_entire_binding(),
                ),
                (
                    "hir_nearest_stmt_node",
                    expr_metadata.nearest_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_nearest_block_node",
                    expr_metadata.nearest_block_node.as_entire_binding(),
                ),
                (
                    "hir_nearest_enclosing_control_node",
                    expr_metadata
                        .nearest_enclosing_control_node
                        .as_entire_binding(),
                ),
                (
                    "hir_call_arg_start",
                    call_metadata.arg_start.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "call_intrinsic_tag",
                    call_intrinsic_tag_buf.as_entire_binding(),
                ),
                ("body_words", body_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let hir_agg_body_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_agg_body_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_hir_agg_body"),
            &self.hir_agg_body_pass,
            0,
            &hir_agg_body_bindings,
        )?;

        let mut hir_module_bindings = vec![
            ("gParams", params_buf.as_entire_binding()),
            ("token_words", token_buf.as_entire_binding()),
            ("token_count", token_count_buf.as_entire_binding()),
            ("source_bytes", source_buf.as_entire_binding()),
            ("node_kind", node_kind_buf.as_entire_binding()),
            ("first_child", first_child_buf.as_entire_binding()),
            ("next_sibling", next_sibling_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            ("hir_token_end", hir_token_end_buf.as_entire_binding()),
            (
                "hir_call_callee_node",
                call_metadata.callee_node.as_entire_binding(),
            ),
            (
                "hir_call_arg_start",
                call_metadata.arg_start.as_entire_binding(),
            ),
            (
                "hir_call_arg_parent_call",
                call_metadata.arg_parent_call.as_entire_binding(),
            ),
            (
                "hir_call_arg_end",
                call_metadata.arg_end.as_entire_binding(),
            ),
            (
                "hir_call_arg_count",
                call_metadata.arg_count.as_entire_binding(),
            ),
            ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
            ("hir_param_record", hir_param_record_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            ("hir_expr_record", expr_metadata.record.as_entire_binding()),
            (
                "hir_expr_result_root_node",
                expr_metadata.result_root_node.as_entire_binding(),
            ),
            (
                "hir_expr_int_value",
                expr_metadata.int_value.as_entire_binding(),
            ),
            ("visible_decl", visible_decl_buf.as_entire_binding()),
            (
                "module_value_path_call_head",
                module_value_path_call_head_buf.as_entire_binding(),
            ),
            (
                "module_value_path_call_open",
                module_value_path_call_open_buf.as_entire_binding(),
            ),
            (
                "module_value_path_const_head",
                module_value_path_const_head_buf.as_entire_binding(),
            ),
            (
                "module_value_path_const_end",
                module_value_path_const_end_buf.as_entire_binding(),
            ),
            ("call_fn_index", call_fn_index_buf.as_entire_binding()),
            (
                "call_intrinsic_tag",
                call_intrinsic_tag_buf.as_entire_binding(),
            ),
            (
                "fn_entrypoint_tag",
                fn_entrypoint_tag_buf.as_entire_binding(),
            ),
            ("call_return_type", call_return_type_buf.as_entire_binding()),
            ("call_param_count", call_param_count_buf.as_entire_binding()),
            ("call_param_type", call_param_type_buf.as_entire_binding()),
            ("out_words", out_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        add_codegen_metadata_bindings!(hir_module_bindings);
        let hir_module_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_hir_module"),
            &self.hir_module_pass,
            0,
            &hir_module_bindings,
        )?;

        let hir_assert_module_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_assert_module_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_hir_assert_module"),
            &self.hir_assert_module_pass,
            0,
            &hir_assert_module_bindings,
        )?;

        let hir_enum_match_records_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_hir_enum_match_records"),
            &self.hir_enum_match_records_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "hir_match_scrutinee_node",
                    enum_match_metadata.match_scrutinee_node.as_entire_binding(),
                ),
                (
                    "hir_match_arm_start",
                    enum_match_metadata.match_arm_start.as_entire_binding(),
                ),
                (
                    "hir_match_arm_count",
                    enum_match_metadata.match_arm_count.as_entire_binding(),
                ),
                (
                    "hir_match_arm_next",
                    enum_match_metadata.match_arm_next.as_entire_binding(),
                ),
                (
                    "hir_match_arm_pattern_node",
                    enum_match_metadata
                        .match_arm_pattern_node
                        .as_entire_binding(),
                ),
                (
                    "hir_match_arm_payload_start",
                    enum_match_metadata
                        .match_arm_payload_start
                        .as_entire_binding(),
                ),
                (
                    "hir_match_arm_payload_count",
                    enum_match_metadata
                        .match_arm_payload_count
                        .as_entire_binding(),
                ),
                (
                    "hir_match_arm_result_node",
                    enum_match_metadata
                        .match_arm_result_node
                        .as_entire_binding(),
                ),
                (
                    "hir_enum_match_record",
                    hir_enum_match_record_buf.as_entire_binding(),
                ),
            ],
        )?;

        let bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_module"),
            &self.pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let pack_bind_group = bind_group::create_bind_group_from_bindings(
            device,
            Some("codegen_wasm_pack_output"),
            &self.pack_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("unpacked_words", out_buf.as_entire_binding()),
                ("packed_words", packed_out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        Ok(ResidentWasmBuffers {
            input_fingerprint,
            output_capacity,
            token_capacity,
            hir_node_capacity,
            params_buf,
            body_dispatch_buf,
            _body_buf: body_buf,
            body_status_buf,
            _struct_field_count_by_decl_token_buf: struct_field_count_by_decl_token_buf,
            _struct_field_index_by_token_buf: struct_field_index_by_token_buf,
            _struct_field_decl_by_token_buf: struct_field_decl_by_token_buf,
            _struct_field_name_id_buf: struct_field_name_id_buf,
            _struct_field_ref_tag_buf: struct_field_ref_tag_buf,
            _struct_field_ref_payload_buf: struct_field_ref_payload_buf,
            _struct_field_scalar_offset_buf: struct_field_scalar_offset_buf,
            _struct_field_scalar_width_buf: struct_field_scalar_width_buf,
            _struct_init_field_index_buf: struct_init_field_index_buf,
            _member_result_field_index_buf: member_result_field_index_buf,
            _hir_enum_match_record_buf: hir_enum_match_record_buf,
            wasm_const_value_record_buf,
            out_buf,
            packed_out_buf,
            status_buf,
            out_readback,
            status_readback,
            agg_layout_clear_bind_group,
            agg_layout_bind_group,
            hir_body_bind_group,
            hir_agg_body_bind_group,
            hir_module_bind_group,
            hir_assert_module_bind_group,
            hir_enum_match_records_bind_group,
            wasm_const_values_bind_group,
            bind_group,
            pack_bind_group,
        })
    }
}
