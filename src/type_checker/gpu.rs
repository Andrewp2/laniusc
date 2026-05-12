use std::{
    collections::HashMap,
    sync::{Mutex, OnceLock},
};

use anyhow::{Result, anyhow};
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s, uniform_from_val},
        device,
        passes_core::{
            DispatchDim,
            InputElements,
            PassData,
            bind_group,
            make_pass_data,
            plan_workgroups,
        },
    },
    lexer::gpu::types::Token,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TypeCheckParams {
    n_tokens: u32,
    source_len: u32,
    n_hir_nodes: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct LoopDepthParams {
    n_tokens: u32,
    n_hir_nodes: u32,
    n_blocks: u32,
    scan_step: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct FnContextParams {
    n_tokens: u32,
    n_hir_nodes: u32,
    n_blocks: u32,
    scan_step: u32,
}

struct LoopDepthScanStep {
    params: LaniusBuffer<LoopDepthParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct FnContextScanStep {
    params: LaniusBuffer<FnContextParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct LoopDepthBindGroups {
    clear: wgpu::BindGroup,
    mark: wgpu::BindGroup,
    local: wgpu::BindGroup,
    scan: Vec<wgpu::BindGroup>,
    apply: wgpu::BindGroup,
}

struct VisibleBindGroups {
    clear: wgpu::BindGroup,
    scope_blocks: wgpu::BindGroup,
    scatter: wgpu::BindGroup,
    decode: wgpu::BindGroup,
}

struct FnContextBindGroups {
    clear: wgpu::BindGroup,
    mark: wgpu::BindGroup,
    local: wgpu::BindGroup,
    scan: Vec<wgpu::BindGroup>,
    apply: wgpu::BindGroup,
}

struct CallBindGroups {
    clear: wgpu::BindGroup,
    functions: wgpu::BindGroup,
    resolve: wgpu::BindGroup,
    erase_generic_params: wgpu::BindGroup,
}

struct MethodBindGroups {
    clear: wgpu::BindGroup,
    collect: wgpu::BindGroup,
    resolve: wgpu::BindGroup,
}

struct ModuleMetadataBindGroups {
    clear: wgpu::BindGroup,
    collect: wgpu::BindGroup,
    collect_decls: wgpu::BindGroup,
    resolve_imports: wgpu::BindGroup,
}

const CALL_PARAM_CACHE_STRIDE: usize = 16;
pub const TYPE_INSTANCE_ARG_REF_STRIDE: usize = 4;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuTypeCheckCode {
    UnknownType,
    UnresolvedIdent,
    AssignMismatch,
    ReturnMismatch,
    ConditionType,
    BadHir,
    LoopControl,
    InvalidMemberAccess,
    InvalidArrayReturn,
    CallMismatch,
    Unknown(u32),
}

impl GpuTypeCheckCode {
    fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::UnknownType,
            2 => Self::UnresolvedIdent,
            3 => Self::AssignMismatch,
            4 => Self::ReturnMismatch,
            5 => Self::ConditionType,
            6 => Self::BadHir,
            7 => Self::LoopControl,
            8 => Self::InvalidMemberAccess,
            9 => Self::InvalidArrayReturn,
            10 => Self::CallMismatch,
            other => Self::Unknown(other),
        }
    }
}

#[derive(Debug)]
pub enum GpuTypeCheckError {
    Rejected {
        token: u32,
        code: GpuTypeCheckCode,
        detail: u32,
    },
    Gpu(anyhow::Error),
}

impl std::fmt::Display for GpuTypeCheckError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuTypeCheckError::Rejected {
                token,
                code,
                detail,
            } => {
                write!(
                    f,
                    "GPU type check rejected token {token}: {code:?} ({detail})"
                )
            }
            GpuTypeCheckError::Gpu(err) => write!(f, "GPU type check failed: {err}"),
        }
    }
}

impl std::error::Error for GpuTypeCheckError {}

impl From<anyhow::Error> for GpuTypeCheckError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

pub struct GpuTypeChecker {
    passes: TypeCheckPasses,
    params_buf: LaniusBuffer<TypeCheckParams>,
    status_buf: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    bind_groups: Mutex<Option<ResidentTypeCheckBindGroups>>,
}

pub struct RecordedTypeCheck;

#[derive(Clone, Copy)]
pub struct HirItemMetadataBuffers<'a> {
    pub kind: &'a wgpu::Buffer,
    pub name_token: &'a wgpu::Buffer,
    pub namespace: &'a wgpu::Buffer,
    pub visibility: &'a wgpu::Buffer,
    pub path_start: &'a wgpu::Buffer,
    pub path_end: &'a wgpu::Buffer,
    pub file_id: &'a wgpu::Buffer,
    pub import_target_kind: &'a wgpu::Buffer,
}

struct TypeCheckPasses {
    modules_clear: PassData,
    modules_collect: PassData,
    modules_collect_decls: PassData,
    modules_resolve_imports: PassData,
    type_instances_collect: PassData,
    type_instances_struct_fields: PassData,
    type_instances_member_results: PassData,
    type_instances_struct_init_fields: PassData,
    type_instances_array_return_refs: PassData,
    type_instances_enum_ctors: PassData,
    type_instances_array_index_results: PassData,
    modules_types: PassData,
    modules_patch_visible: PassData,
    tokens: PassData,
    control: PassData,
    control_hir: PassData,
    scope: PassData,
    calls_clear: PassData,
    calls_functions: PassData,
    calls_resolve: PassData,
    calls_erase_generic_params: PassData,
    methods_clear: PassData,
    methods_collect: PassData,
    methods_resolve: PassData,
    visible_clear: PassData,
    visible_scope_blocks: PassData,
    visible_scatter: PassData,
    visible_decode: PassData,
    fn_context_clear: PassData,
    fn_context_mark: PassData,
    fn_context_local: PassData,
    fn_context_scan: PassData,
    fn_context_apply: PassData,
    loop_depth_clear: PassData,
    loop_depth_mark: PassData,
    loop_depth_local: PassData,
    loop_depth_scan: PassData,
    loop_depth_apply: PassData,
}

impl TypeCheckPasses {
    fn new(device: &wgpu::Device) -> Result<Self> {
        macro_rules! pass {
            ($label:literal, $file:literal) => {
                make_pass_data(
                    device,
                    $label,
                    "main",
                    include_bytes!(concat!(env!("OUT_DIR"), "/shaders/", $file, ".spv")),
                    include_bytes!(concat!(
                        env!("OUT_DIR"),
                        "/shaders/",
                        $file,
                        ".reflect.json"
                    )),
                )?
            };
        }

        Ok(Self {
            modules_clear: pass!("type_check_modules_00_clear", "type_check_modules_00_clear"),
            modules_collect: pass!(
                "type_check_modules_00_collect",
                "type_check_modules_00_collect"
            ),
            modules_collect_decls: pass!(
                "type_check_modules_00_collect_decls",
                "type_check_modules_00_collect_decls"
            ),
            modules_resolve_imports: pass!(
                "type_check_modules_00_resolve_imports",
                "type_check_modules_00_resolve_imports"
            ),
            type_instances_collect: pass!(
                "type_check_type_instances_01_collect",
                "type_check_type_instances_01_collect"
            ),
            type_instances_struct_fields: pass!(
                "type_check_type_instances_02_struct_fields",
                "type_check_type_instances_02_struct_fields"
            ),
            type_instances_member_results: pass!(
                "type_check_type_instances_03_member_results",
                "type_check_type_instances_03_member_results"
            ),
            type_instances_struct_init_fields: pass!(
                "type_check_type_instances_04_struct_init_fields",
                "type_check_type_instances_04_struct_init_fields"
            ),
            type_instances_array_return_refs: pass!(
                "type_check_type_instances_05_array_return_refs",
                "type_check_type_instances_05_array_return_refs"
            ),
            type_instances_enum_ctors: pass!(
                "type_check_type_instances_06_enum_ctors",
                "type_check_type_instances_06_enum_ctors"
            ),
            type_instances_array_index_results: pass!(
                "type_check_type_instances_07_array_index_results",
                "type_check_type_instances_07_array_index_results"
            ),
            modules_types: pass!(
                "type_check_modules_01_same_source_types",
                "type_check_modules_01_same_source_types"
            ),
            modules_patch_visible: pass!(
                "type_check_modules_02_patch_visible_types",
                "type_check_modules_02_patch_visible_types"
            ),
            tokens: pass!("type_check_tokens", "type_check_tokens_min"),
            control: pass!("type_check_control", "type_check_control"),
            control_hir: pass!("type_check_control_hir", "type_check_control_hir"),
            scope: pass!("type_check_scope", "type_check_scope"),
            calls_clear: pass!("type_check_calls_01_resolve", "type_check_calls_01_resolve"),
            calls_functions: pass!(
                "type_check_calls_02_functions",
                "type_check_calls_02_functions"
            ),
            calls_resolve: pass!("type_check_calls_03_resolve", "type_check_calls_03_resolve"),
            calls_erase_generic_params: pass!(
                "type_check_calls_04_erase_generic_params",
                "type_check_calls_04_erase_generic_params"
            ),
            methods_clear: pass!("type_check_methods_01_clear", "type_check_methods_01_clear"),
            methods_collect: pass!(
                "type_check_methods_02_collect",
                "type_check_methods_02_collect"
            ),
            methods_resolve: pass!(
                "type_check_methods_03_resolve",
                "type_check_methods_03_resolve"
            ),
            visible_clear: pass!("type_check_visible_01_clear", "type_check_visible_01_clear"),
            visible_scope_blocks: pass!(
                "type_check_visible_02_scope_blocks",
                "type_check_visible_02_scope_blocks"
            ),
            visible_scatter: pass!(
                "type_check_visible_02_scatter",
                "type_check_visible_02_scatter"
            ),
            visible_decode: pass!(
                "type_check_visible_03_decode",
                "type_check_visible_03_decode"
            ),
            fn_context_clear: pass!(
                "type_check_fn_context_01_clear",
                "type_check_fn_context_01_clear"
            ),
            fn_context_mark: pass!(
                "type_check_fn_context_02_mark",
                "type_check_fn_context_02_mark"
            ),
            fn_context_local: pass!(
                "type_check_fn_context_03_local",
                "type_check_fn_context_03_local"
            ),
            fn_context_scan: pass!(
                "type_check_fn_context_04_scan_blocks",
                "type_check_fn_context_04_scan_blocks"
            ),
            fn_context_apply: pass!(
                "type_check_fn_context_05_apply",
                "type_check_fn_context_05_apply"
            ),
            loop_depth_clear: pass!(
                "type_check_loop_depth_01_clear",
                "type_check_loop_depth_01_clear"
            ),
            loop_depth_mark: pass!(
                "type_check_loop_depth_02_mark",
                "type_check_loop_depth_02_mark"
            ),
            loop_depth_local: pass!(
                "type_check_loop_depth_03_local",
                "type_check_loop_depth_03_local"
            ),
            loop_depth_scan: pass!(
                "type_check_loop_depth_04_scan_blocks",
                "type_check_loop_depth_04_scan_blocks"
            ),
            loop_depth_apply: pass!(
                "type_check_loop_depth_05_apply",
                "type_check_loop_depth_05_apply"
            ),
        })
    }
}

#[allow(dead_code)]
struct ResidentTypeCheckBindGroups {
    token_capacity: u32,
    hir_node_capacity: u32,
    has_hir_item_metadata: bool,
    uses_hir_control: bool,
    loop_n_blocks: u32,
    fn_n_blocks: u32,
    visible_decl: wgpu::Buffer,
    visible_type: wgpu::Buffer,
    scope_end: wgpu::Buffer,
    loop_delta: wgpu::Buffer,
    loop_depth_inblock: wgpu::Buffer,
    loop_block_sum: wgpu::Buffer,
    loop_prefix_a: wgpu::Buffer,
    loop_prefix_b: wgpu::Buffer,
    loop_block_prefix: wgpu::Buffer,
    loop_depth: wgpu::Buffer,
    enclosing_fn: wgpu::Buffer,
    enclosing_fn_end: wgpu::Buffer,
    fn_event_value: wgpu::Buffer,
    fn_event_end: wgpu::Buffer,
    fn_event_index: wgpu::Buffer,
    fn_event_inblock: wgpu::Buffer,
    fn_block_sum: wgpu::Buffer,
    fn_prefix_a: wgpu::Buffer,
    fn_prefix_b: wgpu::Buffer,
    fn_block_prefix: wgpu::Buffer,
    call_fn_index: wgpu::Buffer,
    call_return_type: wgpu::Buffer,
    call_return_type_token: wgpu::Buffer,
    call_param_count: wgpu::Buffer,
    call_param_type: wgpu::Buffer,
    function_lookup_key: wgpu::Buffer,
    function_lookup_fn: wgpu::Buffer,
    method_decl_receiver_type: wgpu::Buffer,
    method_decl_impl_token: wgpu::Buffer,
    method_decl_name_token: wgpu::Buffer,
    method_decl_param_offset: wgpu::Buffer,
    method_lookup_key: wgpu::Buffer,
    method_lookup_receiver: wgpu::Buffer,
    method_lookup_name_token: wgpu::Buffer,
    method_lookup_fn: wgpu::Buffer,
    module_item_kind: wgpu::Buffer,
    module_path_start: wgpu::Buffer,
    module_path_end: wgpu::Buffer,
    module_path_hash: wgpu::Buffer,
    import_enclosing_module_token: wgpu::Buffer,
    import_target_kind: wgpu::Buffer,
    import_resolved_module_token: wgpu::Buffer,
    decl_item_kind: wgpu::Buffer,
    decl_name_hash: wgpu::Buffer,
    decl_name_len: wgpu::Buffer,
    decl_namespace: wgpu::Buffer,
    decl_visibility: wgpu::Buffer,
    decl_file_id: wgpu::Buffer,
    decl_hir_node: wgpu::Buffer,
    type_expr_ref_tag: wgpu::Buffer,
    type_expr_ref_payload: wgpu::Buffer,
    type_instance_kind: wgpu::Buffer,
    type_instance_head_token: wgpu::Buffer,
    type_instance_decl_token: wgpu::Buffer,
    type_instance_arg_start: wgpu::Buffer,
    type_instance_arg_count: wgpu::Buffer,
    type_instance_arg_ref_tag: wgpu::Buffer,
    type_instance_arg_ref_payload: wgpu::Buffer,
    type_instance_elem_ref_tag: wgpu::Buffer,
    type_instance_elem_ref_payload: wgpu::Buffer,
    type_instance_len_kind: wgpu::Buffer,
    type_instance_len_payload: wgpu::Buffer,
    type_instance_state: wgpu::Buffer,
    fn_return_ref_tag: wgpu::Buffer,
    fn_return_ref_payload: wgpu::Buffer,
    member_result_ref_tag: wgpu::Buffer,
    member_result_ref_payload: wgpu::Buffer,
    struct_init_field_expected_ref_tag: wgpu::Buffer,
    struct_init_field_expected_ref_payload: wgpu::Buffer,
    loop_params: LaniusBuffer<LoopDepthParams>,
    loop_scan_steps: Vec<LoopDepthScanStep>,
    fn_params: LaniusBuffer<FnContextParams>,
    fn_scan_steps: Vec<FnContextScanStep>,
    loop_bind_groups: LoopDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
    methods: MethodBindGroups,
    module_metadata: ModuleMetadataBindGroups,
    type_instances_collect: wgpu::BindGroup,
    type_instances_struct_fields: wgpu::BindGroup,
    type_instances_member_results: wgpu::BindGroup,
    type_instances_struct_init_fields: wgpu::BindGroup,
    type_instances_array_return_refs: wgpu::BindGroup,
    type_instances_enum_ctors: wgpu::BindGroup,
    type_instances_array_index_results: wgpu::BindGroup,
    modules_types: wgpu::BindGroup,
    modules_patch_visible: wgpu::BindGroup,
    tokens: wgpu::BindGroup,
    control: wgpu::BindGroup,
    scope: wgpu::BindGroup,
}

impl GpuTypeChecker {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        Self::new(&gpu.device)
    }

    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let passes = TypeCheckPasses::new(device)?;
        let params_buf = uniform_from_val(
            device,
            "type_check.resident.params",
            &TypeCheckParams {
                n_tokens: 0,
                source_len: 0,
                n_hir_nodes: 0,
            },
        );
        let status_buf = storage_u32_rw(
            device,
            "type_check.resident.status",
            4,
            wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
        );
        let status_readback = readback_u32s(device, "rb.type_check.resident.status", 4);

        Ok(Self {
            passes,
            params_buf,
            status_buf,
            status_readback,
            bind_groups: Mutex::new(None),
        })
    }

    /// Checks resident compiler buffers. The cached bind groups assume buffer
    /// identities stay stable until the requested capacities grow.
    pub fn check_resident_token_buffer_with_hir_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        source_len: u32,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_item_metadata: Option<HirItemMetadataBuffers<'_>>,
    ) -> Result<(), GpuTypeCheckError> {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("type_check.resident.encoder"),
        });
        let recorded = self.record_resident_token_buffer_with_hir_on_gpu(
            device,
            queue,
            &mut encoder,
            source_len,
            token_capacity,
            token_buf,
            token_count_buf,
            source_buf,
            hir_node_capacity,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_token_file_id_buf,
            hir_status_buf,
            hir_item_metadata,
            None,
        )?;
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "type_check.resident-with-hir",
            encoder.finish(),
        );
        self.finish_recorded_check(device, &recorded)
    }

    /// Records resident type checking into an existing command encoder. The caller
    /// owns submission and must call `finish_recorded_check` after the submission
    /// has completed.
    #[allow(clippy::too_many_arguments)]
    pub fn record_resident_token_buffer_with_hir_on_gpu(
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
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_item_metadata: Option<HirItemMetadataBuffers<'_>>,
        mut timer: Option<&mut crate::gpu::timer::GpuTimer>,
    ) -> Result<RecordedTypeCheck, GpuTypeCheckError> {
        let params = TypeCheckParams {
            n_tokens: token_capacity,
            source_len,
            n_hir_nodes: hir_node_capacity,
        };
        queue.write_buffer(&self.params_buf, 0, &type_check_params_bytes(&params));
        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());

        let pass = &self.passes.tokens;
        let has_hir_item_metadata = hir_item_metadata.is_some();
        let uses_hir_control = hir_node_capacity > 0;
        let control_pass = if uses_hir_control {
            &self.passes.control_hir
        } else {
            &self.passes.control
        };
        let scope_pass = &self.passes.scope;

        {
            let mut bind_group_guard = self
                .bind_groups
                .lock()
                .expect("GpuTypeChecker.bind_groups poisoned");
            let needs_rebuild = bind_group_guard
                .as_ref()
                .map(|groups| {
                    token_capacity > groups.token_capacity
                        || hir_node_capacity > groups.hir_node_capacity
                        || has_hir_item_metadata != groups.has_hir_item_metadata
                        || uses_hir_control != groups.uses_hir_control
                })
                .unwrap_or(true);
            if needs_rebuild {
                *bind_group_guard = Some(self.create_bind_groups(
                    device,
                    token_capacity,
                    token_buf,
                    token_count_buf,
                    source_buf,
                    hir_node_capacity,
                    hir_kind_buf,
                    hir_token_pos_buf,
                    hir_token_end_buf,
                    hir_token_file_id_buf,
                    hir_status_buf,
                    hir_item_metadata,
                    &self.passes,
                    pass,
                    control_pass,
                    scope_pass,
                    uses_hir_control,
                )?);
            }
            let bind_groups = bind_group_guard
                .as_ref()
                .expect("resident type checker bind groups must exist");

            record_loop_depth_passes_with_passes(&self.passes, encoder, bind_groups)?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.loop_depth.done");
            }
            let n_work = token_capacity.max(hir_node_capacity).max(512);
            record_module_metadata_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
                &bind_groups.module_metadata,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.modules_metadata.done");
            }
            record_compute(
                encoder,
                &self.passes.modules_types,
                &bind_groups.modules_types,
                "type_check.resident.modules_types.pass",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.modules_types.done");
            }
            record_fn_context_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
                bind_groups.fn_n_blocks,
                &bind_groups.fn_context_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.fn_context.done");
            }
            record_visible_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                hir_node_capacity,
                &bind_groups.visible_bind_groups,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.visible.done");
            }

            record_compute(
                encoder,
                &self.passes.type_instances_collect,
                &bind_groups.type_instances_collect,
                "type_check.resident.type_instances_collect.pass",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances.done");
            }
            record_compute(
                encoder,
                &self.passes.type_instances_struct_fields,
                &bind_groups.type_instances_struct_fields,
                "type_check.resident.type_instances_struct_fields.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_member_results,
                &bind_groups.type_instances_member_results,
                "type_check.resident.type_instances_member_results.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_struct_init_fields,
                &bind_groups.type_instances_struct_init_fields,
                "type_check.resident.type_instances_struct_init_fields.pass",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instance_fields.done");
            }
            record_call_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                n_work,
                &bind_groups.calls,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.calls.done");
            }
            record_method_bind_groups_with_passes(
                &self.passes,
                encoder,
                token_capacity,
                n_work,
                &bind_groups.methods,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods.done");
            }
            record_compute(
                encoder,
                scope_pass,
                &bind_groups.scope,
                "type_check.resident.scope.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.scope.done");
            }
            record_compute(
                encoder,
                &self.passes.modules_patch_visible,
                &bind_groups.modules_patch_visible,
                "type_check.resident.modules_patch_visible.pass",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.modules_patch_visible.done");
            }
            record_compute(
                encoder,
                &self.passes.methods_resolve,
                &bind_groups.methods.resolve,
                "type_check.resident.methods.resolve",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.methods_resolve.done");
            }
            record_compute(
                encoder,
                &self.passes.type_instances_array_return_refs,
                &bind_groups.type_instances_array_return_refs,
                "type_check.resident.type_instances_array_return_refs.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_enum_ctors,
                &bind_groups.type_instances_enum_ctors,
                "type_check.resident.type_instances_enum_ctors.pass",
                token_capacity,
            )?;
            record_compute(
                encoder,
                &self.passes.type_instances_array_index_results,
                &bind_groups.type_instances_array_index_results,
                "type_check.resident.type_instances_array_index_results.pass",
                token_capacity,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.type_instances_late_consumers.done");
            }
            record_compute(
                encoder,
                pass,
                &bind_groups.tokens,
                "type_check.resident.tokens.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.tokens.done");
            }
            record_compute(
                encoder,
                control_pass,
                &bind_groups.control,
                "type_check.resident.control.pass",
                n_work,
            )?;
            if let Some(timer) = timer.as_deref_mut() {
                timer.stamp(encoder, "typecheck.control.done");
            }
        }
        encoder.copy_buffer_to_buffer(&self.status_buf, 0, &self.status_readback, 0, 16);
        Ok(RecordedTypeCheck)
    }

    pub fn finish_recorded_check(
        &self,
        device: &wgpu::Device,
        _recorded: &RecordedTypeCheck,
    ) -> Result<(), GpuTypeCheckError> {
        let slice = self.status_readback.slice(..);
        crate::gpu::passes_core::map_readback_for_progress(&slice, "type_check.status");
        crate::gpu::passes_core::wait_for_map_progress(
            device,
            "type_check.status",
            wgpu::PollType::Wait,
        );
        let mapped = slice.get_mapped_range();
        let words = read_status_words(&mapped)?;
        drop(mapped);
        self.status_readback.unmap();

        if words[0] != 0 {
            return Ok(());
        }
        Err(GpuTypeCheckError::Rejected {
            token: words[1],
            code: GpuTypeCheckCode::from_u32(words[2]),
            detail: words[3],
        })
    }

    pub fn with_visible_decl_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_decl))
    }

    pub fn with_visible_type_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.visible_type))
    }

    pub fn with_enclosing_fn_buffer<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard
            .as_ref()
            .map(|bind_groups| consume(&bind_groups.enclosing_fn))
    }

    pub fn with_codegen_buffers<R>(
        &self,
        consume: impl FnOnce(&wgpu::Buffer, &wgpu::Buffer, &wgpu::Buffer, &wgpu::Buffer) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard.as_ref().map(|bind_groups| {
            consume(
                &bind_groups.visible_decl,
                &bind_groups.visible_type,
                &bind_groups.call_fn_index,
                &bind_groups.call_return_type,
            )
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn with_type_expr_metadata_buffers<R>(
        &self,
        consume: impl FnOnce(
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
            &wgpu::Buffer,
        ) -> R,
    ) -> Option<R> {
        let guard = self
            .bind_groups
            .lock()
            .expect("GpuTypeChecker.bind_groups poisoned");
        guard.as_ref().map(|bind_groups| {
            consume(
                &bind_groups.type_expr_ref_tag,
                &bind_groups.type_expr_ref_payload,
                &bind_groups.type_instance_kind,
                &bind_groups.type_instance_decl_token,
                &bind_groups.type_instance_arg_start,
                &bind_groups.type_instance_arg_count,
                &bind_groups.type_instance_arg_ref_tag,
                &bind_groups.type_instance_arg_ref_payload,
                &bind_groups.member_result_ref_tag,
                &bind_groups.member_result_ref_payload,
                &bind_groups.type_instance_state,
                &bind_groups.type_instance_elem_ref_tag,
                &bind_groups.fn_return_ref_tag,
                &bind_groups.fn_return_ref_payload,
                &bind_groups.struct_init_field_expected_ref_tag,
                &bind_groups.struct_init_field_expected_ref_payload,
            )
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn create_bind_groups(
        &self,
        device: &wgpu::Device,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_token_file_id_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        hir_item_metadata: Option<HirItemMetadataBuffers<'_>>,
        passes: &TypeCheckPasses,
        pass: &PassData,
        control_pass: &PassData,
        scope_pass: &PassData,
        uses_hir_control: bool,
    ) -> Result<ResidentTypeCheckBindGroups> {
        let visible_decl = storage_u32_rw(
            device,
            "type_check.resident.visible_decl",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let visible_type = storage_u32_rw(
            device,
            "type_check.resident.visible_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let scope_end = storage_u32_rw(
            device,
            "type_check.resident.scope_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_n_blocks = token_capacity.div_ceil(256).max(1);
        let fn_n_blocks = token_capacity.div_ceil(256).max(1);
        let loop_params_value = LoopDepthParams {
            n_tokens: token_capacity,
            n_hir_nodes: hir_node_capacity,
            n_blocks: loop_n_blocks,
            scan_step: 0,
        };
        let fn_params_value = FnContextParams {
            n_tokens: token_capacity,
            n_hir_nodes: hir_node_capacity,
            n_blocks: fn_n_blocks,
            scan_step: 0,
        };
        let loop_params = uniform_from_val(
            device,
            "type_check.resident.loop_depth.params",
            &loop_params_value,
        );
        let loop_scan_steps = make_loop_depth_scan_steps(device, loop_params_value);
        let fn_params = uniform_from_val(
            device,
            "type_check.resident.fn_context.params",
            &fn_params_value,
        );
        let fn_scan_steps = make_fn_context_scan_steps(device, fn_params_value);
        let loop_delta = storage_i32_rw(
            device,
            "type_check.resident.loop_delta",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth_inblock = storage_i32_rw(
            device,
            "type_check.resident.loop_depth_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_sum = storage_i32_rw(
            device,
            "type_check.resident.loop_block_sum",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_a = storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_a",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_prefix_b = storage_i32_rw(
            device,
            "type_check.resident.loop_prefix_b",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_block_prefix = storage_i32_rw(
            device,
            "type_check.resident.loop_block_prefix",
            loop_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let loop_depth = storage_i32_rw(
            device,
            "type_check.resident.loop_depth",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn = storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let enclosing_fn_end = storage_u32_rw(
            device,
            "type_check.resident.enclosing_fn_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_value = storage_u32_rw(
            device,
            "type_check.resident.fn_event_value",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_end = storage_u32_rw(
            device,
            "type_check.resident.fn_event_end",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_index = storage_u32_rw(
            device,
            "type_check.resident.fn_event_index",
            token_capacity as usize + 1,
            wgpu::BufferUsages::empty(),
        );
        let fn_event_inblock = storage_u32_rw(
            device,
            "type_check.resident.fn_event_inblock",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_sum = storage_u32_rw(
            device,
            "type_check.resident.fn_block_sum",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_a = storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_a",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_prefix_b = storage_u32_rw(
            device,
            "type_check.resident.fn_prefix_b",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_block_prefix = storage_u32_rw(
            device,
            "type_check.resident.fn_block_prefix",
            fn_n_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_fn_index = storage_u32_rw(
            device,
            "type_check.resident.call_fn_index",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_return_type = storage_u32_rw(
            device,
            "type_check.resident.call_return_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_return_type_token = storage_u32_rw(
            device,
            "type_check.resident.call_return_type_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_count = storage_u32_rw(
            device,
            "type_check.resident.call_param_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let call_param_type = storage_u32_rw(
            device,
            "type_check.resident.call_param_type",
            (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
        let function_lookup_key = storage_u32_rw(
            device,
            "type_check.resident.function_lookup_key",
            function_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let function_lookup_fn = storage_u32_rw(
            device,
            "type_check.resident.function_lookup_fn",
            function_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_receiver_type = storage_u32_rw(
            device,
            "type_check.resident.method_decl_receiver_type",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_impl_token = storage_u32_rw(
            device,
            "type_check.resident.method_decl_impl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_name_token = storage_u32_rw(
            device,
            "type_check.resident.method_decl_name_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_decl_param_offset = storage_u32_rw(
            device,
            "type_check.resident.method_decl_param_offset",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let method_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
        let method_lookup_key = storage_u32_rw(
            device,
            "type_check.resident.method_lookup_key",
            method_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let method_lookup_receiver = storage_u32_rw(
            device,
            "type_check.resident.method_lookup_receiver",
            method_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let method_lookup_name_token = storage_u32_rw(
            device,
            "type_check.resident.method_lookup_name_token",
            method_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let method_lookup_fn = storage_u32_rw(
            device,
            "type_check.resident.method_lookup_fn",
            method_lookup_capacity,
            wgpu::BufferUsages::empty(),
        );
        let module_item_kind = storage_u32_rw(
            device,
            "type_check.resident.module_item_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_path_start = storage_u32_rw(
            device,
            "type_check.resident.module_path_start",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_path_end = storage_u32_rw(
            device,
            "type_check.resident.module_path_end",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let module_path_hash = storage_u32_rw(
            device,
            "type_check.resident.module_path_hash",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let import_enclosing_module_token = storage_u32_rw(
            device,
            "type_check.resident.import_enclosing_module_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let import_target_kind = storage_u32_rw(
            device,
            "type_check.resident.import_target_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let import_resolved_module_token = storage_u32_rw(
            device,
            "type_check.resident.import_resolved_module_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_item_kind = storage_u32_rw(
            device,
            "type_check.resident.decl_item_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_name_hash = storage_u32_rw(
            device,
            "type_check.resident.decl_name_hash",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_name_len = storage_u32_rw(
            device,
            "type_check.resident.decl_name_len",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_namespace = storage_u32_rw(
            device,
            "type_check.resident.decl_namespace",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_visibility = storage_u32_rw(
            device,
            "type_check.resident.decl_visibility",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_file_id = storage_u32_rw(
            device,
            "type_check.resident.decl_file_id",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let decl_hir_node = storage_u32_rw(
            device,
            "type_check.resident.decl_hir_node",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_expr_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_expr_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_expr_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_expr_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_kind = storage_u32_rw(
            device,
            "type_check.resident.type_instance_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_head_token = storage_u32_rw(
            device,
            "type_check.resident.type_instance_head_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_decl_token = storage_u32_rw(
            device,
            "type_check.resident.type_instance_decl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_start = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_start",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_count = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_count",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_ref_tag",
            (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_arg_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_arg_ref_payload",
            (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_elem_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.type_instance_elem_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_elem_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_elem_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_len_kind = storage_u32_rw(
            device,
            "type_check.resident.type_instance_len_kind",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_len_payload = storage_u32_rw(
            device,
            "type_check.resident.type_instance_len_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let type_instance_state = storage_u32_rw(
            device,
            "type_check.resident.type_instance_state",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_return_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.fn_return_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let fn_return_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.fn_return_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.member_result_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let member_result_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.member_result_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_expected_ref_tag = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_expected_ref_tag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let struct_init_field_expected_ref_payload = storage_u32_rw(
            device,
            "type_check.resident.struct_init_field_expected_ref_payload",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let empty_hir_item_kind =
            storage_ro_from_u32s(device, "type_check.resident.hir_item_kind.empty", &[0]);
        let empty_hir_item_name_token = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_item_name_token.empty",
            &[0],
        );
        let empty_hir_item_namespace =
            storage_ro_from_u32s(device, "type_check.resident.hir_item_namespace.empty", &[0]);
        let empty_hir_item_visibility = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_item_visibility.empty",
            &[0],
        );
        let empty_hir_item_path_start = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_item_path_start.empty",
            &[0],
        );
        let empty_hir_item_path_end =
            storage_ro_from_u32s(device, "type_check.resident.hir_item_path_end.empty", &[0]);
        let empty_hir_item_file_id =
            storage_ro_from_u32s(device, "type_check.resident.hir_item_file_id.empty", &[0]);
        let empty_hir_item_import_target_kind = storage_ro_from_u32s(
            device,
            "type_check.resident.hir_item_import_target_kind.empty",
            &[0],
        );
        let hir_item_kind_buf = hir_item_metadata
            .map(|metadata| metadata.kind)
            .unwrap_or(&empty_hir_item_kind);
        let hir_item_name_token_buf = hir_item_metadata
            .map(|metadata| metadata.name_token)
            .unwrap_or(&empty_hir_item_name_token);
        let hir_item_namespace_buf = hir_item_metadata
            .map(|metadata| metadata.namespace)
            .unwrap_or(&empty_hir_item_namespace);
        let hir_item_visibility_buf = hir_item_metadata
            .map(|metadata| metadata.visibility)
            .unwrap_or(&empty_hir_item_visibility);
        let hir_item_path_start_buf = hir_item_metadata
            .map(|metadata| metadata.path_start)
            .unwrap_or(&empty_hir_item_path_start);
        let hir_item_path_end_buf = hir_item_metadata
            .map(|metadata| metadata.path_end)
            .unwrap_or(&empty_hir_item_path_end);
        let hir_item_file_id_buf = hir_item_metadata
            .map(|metadata| metadata.file_id)
            .unwrap_or(&empty_hir_item_file_id);
        let hir_item_import_target_kind_buf = hir_item_metadata
            .map(|metadata| metadata.import_target_kind)
            .unwrap_or(&empty_hir_item_import_target_kind);
        let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        resources.insert("gParams".into(), self.params_buf.as_entire_binding());
        resources.insert("token_words".into(), token_buf.as_entire_binding());
        resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        resources.insert("source_bytes".into(), source_buf.as_entire_binding());
        resources.insert("hir_kind".into(), hir_kind_buf.as_entire_binding());
        resources.insert(
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_token_file_id".into(),
            hir_token_file_id_buf.as_entire_binding(),
        );
        resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
        resources.insert(
            "hir_item_kind".into(),
            hir_item_kind_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_name_token".into(),
            hir_item_name_token_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_namespace".into(),
            hir_item_namespace_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_visibility".into(),
            hir_item_visibility_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_path_start".into(),
            hir_item_path_start_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_path_end".into(),
            hir_item_path_end_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_file_id".into(),
            hir_item_file_id_buf.as_entire_binding(),
        );
        resources.insert(
            "hir_item_import_target_kind".into(),
            hir_item_import_target_kind_buf.as_entire_binding(),
        );
        resources.insert("status".into(), self.status_buf.as_entire_binding());
        resources.insert("visible_decl".into(), visible_decl.as_entire_binding());
        resources.insert("visible_type".into(), visible_type.as_entire_binding());
        resources.insert("scope_end".into(), scope_end.as_entire_binding());
        resources.insert("loop_depth".into(), loop_depth.as_entire_binding());
        resources.insert("enclosing_fn".into(), enclosing_fn.as_entire_binding());
        resources.insert(
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        );
        resources.insert("fn_event_value".into(), fn_event_value.as_entire_binding());
        resources.insert("fn_event_end".into(), fn_event_end.as_entire_binding());
        resources.insert("fn_event_index".into(), fn_event_index.as_entire_binding());
        resources.insert(
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        );
        resources.insert("block_sum".into(), fn_block_sum.as_entire_binding());
        resources.insert("block_prefix".into(), fn_block_prefix.as_entire_binding());
        resources.insert("call_fn_index".into(), call_fn_index.as_entire_binding());
        resources.insert(
            "call_return_type".into(),
            call_return_type.as_entire_binding(),
        );
        resources.insert(
            "call_return_type_token".into(),
            call_return_type_token.as_entire_binding(),
        );
        resources.insert(
            "call_param_count".into(),
            call_param_count.as_entire_binding(),
        );
        resources.insert(
            "call_param_type".into(),
            call_param_type.as_entire_binding(),
        );
        resources.insert(
            "function_lookup_key".into(),
            function_lookup_key.as_entire_binding(),
        );
        resources.insert(
            "function_lookup_fn".into(),
            function_lookup_fn.as_entire_binding(),
        );
        resources.insert(
            "method_decl_receiver_type".into(),
            method_decl_receiver_type.as_entire_binding(),
        );
        resources.insert(
            "method_decl_impl_token".into(),
            method_decl_impl_token.as_entire_binding(),
        );
        resources.insert(
            "method_decl_name_token".into(),
            method_decl_name_token.as_entire_binding(),
        );
        resources.insert(
            "method_decl_param_offset".into(),
            method_decl_param_offset.as_entire_binding(),
        );
        resources.insert(
            "method_lookup_key".into(),
            method_lookup_key.as_entire_binding(),
        );
        resources.insert(
            "method_lookup_receiver".into(),
            method_lookup_receiver.as_entire_binding(),
        );
        resources.insert(
            "method_lookup_name_token".into(),
            method_lookup_name_token.as_entire_binding(),
        );
        resources.insert(
            "method_lookup_fn".into(),
            method_lookup_fn.as_entire_binding(),
        );
        resources.insert(
            "module_item_kind".into(),
            module_item_kind.as_entire_binding(),
        );
        resources.insert(
            "module_path_start".into(),
            module_path_start.as_entire_binding(),
        );
        resources.insert(
            "module_path_end".into(),
            module_path_end.as_entire_binding(),
        );
        resources.insert(
            "module_path_hash".into(),
            module_path_hash.as_entire_binding(),
        );
        resources.insert(
            "import_enclosing_module_token".into(),
            import_enclosing_module_token.as_entire_binding(),
        );
        resources.insert(
            "import_target_kind".into(),
            import_target_kind.as_entire_binding(),
        );
        resources.insert(
            "import_resolved_module_token".into(),
            import_resolved_module_token.as_entire_binding(),
        );
        resources.insert("decl_item_kind".into(), decl_item_kind.as_entire_binding());
        resources.insert("decl_name_hash".into(), decl_name_hash.as_entire_binding());
        resources.insert("decl_name_len".into(), decl_name_len.as_entire_binding());
        resources.insert("decl_namespace".into(), decl_namespace.as_entire_binding());
        resources.insert(
            "decl_visibility".into(),
            decl_visibility.as_entire_binding(),
        );
        resources.insert("decl_file_id".into(), decl_file_id.as_entire_binding());
        resources.insert("decl_hir_node".into(), decl_hir_node.as_entire_binding());
        resources.insert(
            "type_expr_ref_tag".into(),
            type_expr_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_expr_ref_payload".into(),
            type_expr_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_kind".into(),
            type_instance_kind.as_entire_binding(),
        );
        resources.insert(
            "type_instance_head_token".into(),
            type_instance_head_token.as_entire_binding(),
        );
        resources.insert(
            "type_instance_decl_token".into(),
            type_instance_decl_token.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_start".into(),
            type_instance_arg_start.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_count".into(),
            type_instance_arg_count.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_ref_tag".into(),
            type_instance_arg_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_instance_arg_ref_payload".into(),
            type_instance_arg_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_elem_ref_tag".into(),
            type_instance_elem_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "type_instance_elem_ref_payload".into(),
            type_instance_elem_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_len_kind".into(),
            type_instance_len_kind.as_entire_binding(),
        );
        resources.insert(
            "type_instance_len_payload".into(),
            type_instance_len_payload.as_entire_binding(),
        );
        resources.insert(
            "type_instance_state".into(),
            type_instance_state.as_entire_binding(),
        );
        resources.insert(
            "fn_return_ref_tag".into(),
            fn_return_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "fn_return_ref_payload".into(),
            fn_return_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "member_result_ref_tag".into(),
            member_result_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "member_result_ref_payload".into(),
            member_result_ref_payload.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_expected_ref_tag".into(),
            struct_init_field_expected_ref_tag.as_entire_binding(),
        );
        resources.insert(
            "struct_init_field_expected_ref_payload".into(),
            struct_init_field_expected_ref_payload.as_entire_binding(),
        );
        let type_instances_collect = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_collect"),
            &passes.type_instances_collect.bind_group_layouts[0],
            &passes.type_instances_collect.reflection,
            0,
            &resources,
        )?;
        let type_instances_struct_fields = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_struct_fields"),
            &passes.type_instances_struct_fields.bind_group_layouts[0],
            &passes.type_instances_struct_fields.reflection,
            0,
            &resources,
        )?;
        let type_instances_member_results = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_member_results"),
            &passes.type_instances_member_results.bind_group_layouts[0],
            &passes.type_instances_member_results.reflection,
            0,
            &resources,
        )?;
        let type_instances_struct_init_fields = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_struct_init_fields"),
            &passes.type_instances_struct_init_fields.bind_group_layouts[0],
            &passes.type_instances_struct_init_fields.reflection,
            0,
            &resources,
        )?;
        let type_instances_array_return_refs = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_array_return_refs"),
            &passes.type_instances_array_return_refs.bind_group_layouts[0],
            &passes.type_instances_array_return_refs.reflection,
            0,
            &resources,
        )?;
        let type_instances_enum_ctors = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_enum_ctors"),
            &passes.type_instances_enum_ctors.bind_group_layouts[0],
            &passes.type_instances_enum_ctors.reflection,
            0,
            &resources,
        )?;
        let type_instances_array_index_results = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_type_instances_array_index_results"),
            &passes.type_instances_array_index_results.bind_group_layouts[0],
            &passes.type_instances_array_index_results.reflection,
            0,
            &resources,
        )?;
        let modules_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_clear"),
            &passes.modules_clear.bind_group_layouts[0],
            &passes.modules_clear.reflection,
            0,
            &resources,
        )?;
        let modules_collect = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_collect"),
            &passes.modules_collect.bind_group_layouts[0],
            &passes.modules_collect.reflection,
            0,
            &resources,
        )?;
        let modules_collect_decls = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_collect_decls"),
            &passes.modules_collect_decls.bind_group_layouts[0],
            &passes.modules_collect_decls.reflection,
            0,
            &resources,
        )?;
        let modules_resolve_imports = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_resolve_imports"),
            &passes.modules_resolve_imports.bind_group_layouts[0],
            &passes.modules_resolve_imports.reflection,
            0,
            &resources,
        )?;
        let module_metadata = ModuleMetadataBindGroups {
            clear: modules_clear,
            collect: modules_collect,
            collect_decls: modules_collect_decls,
            resolve_imports: modules_resolve_imports,
        };
        let modules_types = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_types"),
            &passes.modules_types.bind_group_layouts[0],
            &passes.modules_types.reflection,
            0,
            &resources,
        )?;
        let modules_patch_visible = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_modules_patch_visible"),
            &passes.modules_patch_visible.bind_group_layouts[0],
            &passes.modules_patch_visible.reflection,
            0,
            &resources,
        )?;
        let calls_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_clear"),
            &passes.calls_clear.bind_group_layouts[0],
            &passes.calls_clear.reflection,
            0,
            &resources,
        )?;
        let calls_functions = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_functions"),
            &passes.calls_functions.bind_group_layouts[0],
            &passes.calls_functions.reflection,
            0,
            &resources,
        )?;
        let calls_resolve = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_resolve"),
            &passes.calls_resolve.bind_group_layouts[0],
            &passes.calls_resolve.reflection,
            0,
            &resources,
        )?;
        let calls_erase_generic_params = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_calls_erase_generic_params"),
            &passes.calls_erase_generic_params.bind_group_layouts[0],
            &passes.calls_erase_generic_params.reflection,
            0,
            &resources,
        )?;
        let calls = CallBindGroups {
            clear: calls_clear,
            functions: calls_functions,
            resolve: calls_resolve,
            erase_generic_params: calls_erase_generic_params,
        };
        let methods_clear = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_clear"),
            &passes.methods_clear.bind_group_layouts[0],
            &passes.methods_clear.reflection,
            0,
            &resources,
        )?;
        let methods_collect = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_collect"),
            &passes.methods_collect.bind_group_layouts[0],
            &passes.methods_collect.reflection,
            0,
            &resources,
        )?;
        let methods_resolve = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_methods_resolve"),
            &passes.methods_resolve.bind_group_layouts[0],
            &passes.methods_resolve.reflection,
            0,
            &resources,
        )?;
        let methods = MethodBindGroups {
            clear: methods_clear,
            collect: methods_collect,
            resolve: methods_resolve,
        };

        let tokens = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_tokens"),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )?;
        let control = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_control"),
            &control_pass.bind_group_layouts[0],
            &control_pass.reflection,
            0,
            &resources,
        )?;
        let scope = bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_resident_scope"),
            &scope_pass.bind_group_layouts[0],
            &scope_pass.reflection,
            0,
            &resources,
        )?;
        let loop_bind_groups = create_loop_depth_bind_groups_with_passes(
            passes,
            device,
            &loop_params,
            &loop_scan_steps,
            token_buf,
            token_count_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            &loop_delta,
            &loop_depth_inblock,
            &loop_block_sum,
            &loop_prefix_a,
            &loop_prefix_b,
            &loop_block_prefix,
            &loop_depth,
        )?;
        let fn_context_bind_groups = create_fn_context_bind_groups_with_passes(
            passes,
            device,
            &fn_params,
            &fn_scan_steps,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            &enclosing_fn,
            &enclosing_fn_end,
            &fn_event_value,
            &fn_event_end,
            &fn_event_index,
            &fn_event_inblock,
            &fn_block_sum,
            &fn_prefix_a,
            &fn_prefix_b,
            &fn_block_prefix,
        )?;
        let visible_bind_groups =
            create_visible_bind_groups_with_passes(passes, device, &resources)?;

        Ok(ResidentTypeCheckBindGroups {
            token_capacity,
            hir_node_capacity,
            has_hir_item_metadata: hir_item_metadata.is_some(),
            uses_hir_control,
            loop_n_blocks,
            fn_n_blocks,
            visible_decl,
            visible_type,
            scope_end,
            loop_delta,
            loop_depth_inblock,
            loop_block_sum,
            loop_prefix_a,
            loop_prefix_b,
            loop_block_prefix,
            loop_depth,
            enclosing_fn,
            enclosing_fn_end,
            fn_event_value,
            fn_event_end,
            fn_event_index,
            fn_event_inblock,
            fn_block_sum,
            fn_prefix_a,
            fn_prefix_b,
            fn_block_prefix,
            call_fn_index,
            call_return_type,
            call_return_type_token,
            call_param_count,
            call_param_type,
            function_lookup_key,
            function_lookup_fn,
            method_decl_receiver_type,
            method_decl_impl_token,
            method_decl_name_token,
            method_decl_param_offset,
            method_lookup_key,
            method_lookup_receiver,
            method_lookup_name_token,
            method_lookup_fn,
            module_item_kind,
            module_path_start,
            module_path_end,
            module_path_hash,
            import_enclosing_module_token,
            import_target_kind,
            import_resolved_module_token,
            decl_item_kind,
            decl_name_hash,
            decl_name_len,
            decl_namespace,
            decl_visibility,
            decl_file_id,
            decl_hir_node,
            type_expr_ref_tag,
            type_expr_ref_payload,
            type_instance_kind,
            type_instance_head_token,
            type_instance_decl_token,
            type_instance_arg_start,
            type_instance_arg_count,
            type_instance_arg_ref_tag,
            type_instance_arg_ref_payload,
            type_instance_elem_ref_tag,
            type_instance_elem_ref_payload,
            type_instance_len_kind,
            type_instance_len_payload,
            type_instance_state,
            fn_return_ref_tag,
            fn_return_ref_payload,
            member_result_ref_tag,
            member_result_ref_payload,
            struct_init_field_expected_ref_tag,
            struct_init_field_expected_ref_payload,
            loop_params,
            loop_scan_steps,
            fn_params,
            fn_scan_steps,
            loop_bind_groups,
            fn_context_bind_groups,
            visible_bind_groups,
            calls,
            methods,
            module_metadata,
            type_instances_collect,
            type_instances_struct_fields,
            type_instances_member_results,
            type_instances_struct_init_fields,
            type_instances_array_return_refs,
            type_instances_enum_ctors,
            type_instances_array_index_results,
            modules_types,
            modules_patch_visible,
            tokens,
            control,
            scope,
        })
    }
}

pub async fn check_tokens_on_gpu(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    check_tokens_on_gpu_inner(src, tokens).await
}

async fn check_tokens_on_gpu_inner(src: &str, tokens: &[Token]) -> Result<(), GpuTypeCheckError> {
    let ctx = device::global();
    let device = &ctx.device;
    let queue = &ctx.queue;

    let token_bytes = token_bytes(tokens);
    let source_bytes = nonempty_bytes(src.as_bytes());

    let token_buf = storage_ro_from_bytes::<u32>(
        device,
        "type_check.tokens.tokens",
        &token_bytes,
        tokens.len(),
    );
    let token_count_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.token_count",
        &[tokens.len() as u32],
    );
    let source_buf = storage_ro_from_bytes::<u8>(
        device,
        "type_check.tokens.source",
        &source_bytes,
        source_bytes.len(),
    );
    let hir_kind_buf = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let hir_token_pos_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let hir_token_end_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let hir_token_file_id_buf =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let hir_status_buf = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        src.len() as u32,
        tokens.len() as u32,
        &token_buf,
        &token_count_buf,
        &source_buf,
        0,
        &hir_kind_buf,
        &hir_token_pos_buf,
        &hir_token_end_buf,
        &hir_token_file_id_buf,
        &hir_status_buf,
        None,
    )
}

pub fn check_token_buffer_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
) -> Result<(), GpuTypeCheckError> {
    let empty = storage_ro_from_u32s(device, "type_check.tokens.hir_kind.empty", &[0]);
    let empty_pos = storage_ro_from_u32s(device, "type_check.tokens.hir_token_pos.empty", &[0]);
    let empty_end = storage_ro_from_u32s(device, "type_check.tokens.hir_token_end.empty", &[0]);
    let empty_file_id =
        storage_ro_from_u32s(device, "type_check.tokens.hir_token_file_id.empty", &[0]);
    let empty_status = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    check_token_buffer_with_hir_on_gpu(
        device,
        queue,
        source_len,
        token_capacity,
        token_buf,
        token_count_buf,
        source_buf,
        0,
        &empty,
        &empty_pos,
        &empty_end,
        &empty_file_id,
        &empty_status,
        None,
    )
}

pub fn check_token_buffer_with_hir_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
    hir_node_capacity: u32,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_token_file_id_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    hir_item_metadata: Option<HirItemMetadataBuffers<'_>>,
) -> Result<(), GpuTypeCheckError> {
    let params = TypeCheckParams {
        n_tokens: token_capacity,
        source_len,
        n_hir_nodes: hir_node_capacity,
    };
    let params_buf = uniform_from_val(device, "type_check.tokens.params", &params);
    let status_buf = storage_u32_rw(
        device,
        "type_check.tokens.status",
        4,
        wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
    );
    let visible_decl_buf = storage_u32_rw(
        device,
        "type_check.tokens.visible_decl",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let visible_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.visible_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let scope_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.scope_end",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_n_blocks = token_capacity.div_ceil(256).max(1);
    let fn_n_blocks = token_capacity.div_ceil(256).max(1);
    let loop_params_value = LoopDepthParams {
        n_tokens: token_capacity,
        n_hir_nodes: hir_node_capacity,
        n_blocks: loop_n_blocks,
        scan_step: 0,
    };
    let fn_params_value = FnContextParams {
        n_tokens: token_capacity,
        n_hir_nodes: hir_node_capacity,
        n_blocks: fn_n_blocks,
        scan_step: 0,
    };
    let loop_params_buf = uniform_from_val(
        device,
        "type_check.tokens.loop_depth.params",
        &loop_params_value,
    );
    let loop_scan_steps = make_loop_depth_scan_steps(device, loop_params_value);
    let fn_params_buf = uniform_from_val(
        device,
        "type_check.tokens.fn_context.params",
        &fn_params_value,
    );
    let fn_scan_steps = make_fn_context_scan_steps(device, fn_params_value);
    let loop_delta_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_delta",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let loop_depth_inblock_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_depth_inblock",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_block_sum_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_block_sum",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_prefix_a_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_prefix_a",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_prefix_b_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_prefix_b",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_block_prefix_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_block_prefix",
        loop_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let loop_depth_buf = storage_i32_rw(
        device,
        "type_check.tokens.loop_depth",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let enclosing_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.enclosing_fn",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let enclosing_fn_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.enclosing_fn_end",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_value_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_value",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_end",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_index_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_index",
        token_capacity as usize + 1,
        wgpu::BufferUsages::empty(),
    );
    let fn_event_inblock_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_event_inblock",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_block_sum_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_block_sum",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_prefix_a_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_prefix_a",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_prefix_b_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_prefix_b",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_block_prefix_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_block_prefix",
        fn_n_blocks as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_fn_index_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_fn_index",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_return_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_return_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_return_type_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_return_type_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_param_count_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_count",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let call_param_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.call_param_type",
        (token_capacity as usize).max(1) * CALL_PARAM_CACHE_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let function_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
    let function_lookup_key_buf = storage_u32_rw(
        device,
        "type_check.tokens.function_lookup_key",
        function_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let function_lookup_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.function_lookup_fn",
        function_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_receiver_type_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_receiver_type",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_impl_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_impl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_name_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_name_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_decl_param_offset_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_decl_param_offset",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let method_lookup_capacity = token_capacity.saturating_mul(2).max(1) as usize;
    let method_lookup_key_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_lookup_key",
        method_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let method_lookup_receiver_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_lookup_receiver",
        method_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let method_lookup_name_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_lookup_name_token",
        method_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let method_lookup_fn_buf = storage_u32_rw(
        device,
        "type_check.tokens.method_lookup_fn",
        method_lookup_capacity,
        wgpu::BufferUsages::empty(),
    );
    let module_item_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_item_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_path_start_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_path_start",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_path_end_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_path_end",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let module_path_hash_buf = storage_u32_rw(
        device,
        "type_check.tokens.module_path_hash",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_enclosing_module_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.import_enclosing_module_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_target_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.import_target_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let import_resolved_module_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.import_resolved_module_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_item_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_item_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_name_hash_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_name_hash",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_name_len_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_name_len",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_namespace_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_namespace",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_visibility_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_visibility",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_file_id_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_file_id",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let decl_hir_node_buf = storage_u32_rw(
        device,
        "type_check.tokens.decl_hir_node",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_expr_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_expr_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_expr_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_expr_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_head_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_head_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_decl_token_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_decl_token",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_start_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_start",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_count_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_count",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_ref_tag",
        (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_arg_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_arg_ref_payload",
        (token_capacity as usize).max(1) * TYPE_INSTANCE_ARG_REF_STRIDE,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_elem_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_elem_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_elem_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_elem_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_len_kind_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_len_kind",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_len_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_len_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let type_instance_state_buf = storage_u32_rw(
        device,
        "type_check.tokens.type_instance_state",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_return_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_return_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let fn_return_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.fn_return_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let member_result_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.member_result_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_expected_ref_tag_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_expected_ref_tag",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    let struct_init_field_expected_ref_payload_buf = storage_u32_rw(
        device,
        "type_check.tokens.struct_init_field_expected_ref_payload",
        token_capacity as usize,
        wgpu::BufferUsages::empty(),
    );
    queue.write_buffer(&status_buf, 0, &status_init_bytes());
    let status_readback = readback_u32s(device, "rb.type_check.tokens.status", 4);

    let pass = type_check_tokens_pass(device)?;
    let control_pass = if hir_node_capacity > 0 {
        type_check_control_hir_pass(device)?
    } else {
        type_check_control_pass(device)?
    };
    let scope_pass = type_check_scope_pass(device)?;
    let calls_clear_pass = type_check_calls_clear_pass(device)?;
    let calls_functions_pass = type_check_calls_functions_pass(device)?;
    let calls_resolve_pass = type_check_calls_resolve_pass(device)?;
    let calls_erase_generic_params_pass = type_check_calls_erase_generic_params_pass(device)?;
    let methods_clear_pass = type_check_methods_clear_pass(device)?;
    let methods_collect_pass = type_check_methods_collect_pass(device)?;
    let methods_resolve_pass = type_check_methods_resolve_pass(device)?;
    let modules_types_pass = type_check_modules_types_pass(device)?;
    let modules_patch_visible_pass = type_check_modules_patch_visible_pass(device)?;
    let type_instances_collect_pass = type_check_type_instances_collect_pass(device)?;
    let type_instances_struct_fields_pass = type_check_type_instances_struct_fields_pass(device)?;
    let type_instances_member_results_pass = type_check_type_instances_member_results_pass(device)?;
    let type_instances_struct_init_fields_pass =
        type_check_type_instances_struct_init_fields_pass(device)?;
    let type_instances_array_return_refs_pass =
        type_check_type_instances_array_return_refs_pass(device)?;
    let type_instances_enum_ctors_pass = type_check_type_instances_enum_ctors_pass(device)?;
    let type_instances_array_index_results_pass =
        type_check_type_instances_array_index_results_pass(device)?;
    let empty_hir_item_kind =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_kind.empty", &[0]);
    let empty_hir_item_name_token =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_name_token.empty", &[0]);
    let empty_hir_item_namespace =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_namespace.empty", &[0]);
    let empty_hir_item_visibility =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_visibility.empty", &[0]);
    let empty_hir_item_path_start =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_path_start.empty", &[0]);
    let empty_hir_item_path_end =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_path_end.empty", &[0]);
    let empty_hir_item_file_id =
        storage_ro_from_u32s(device, "type_check.tokens.hir_item_file_id.empty", &[0]);
    let empty_hir_item_import_target_kind = storage_ro_from_u32s(
        device,
        "type_check.tokens.hir_item_import_target_kind.empty",
        &[0],
    );
    let hir_item_kind_buf = hir_item_metadata
        .map(|metadata| metadata.kind)
        .unwrap_or(&empty_hir_item_kind);
    let hir_item_name_token_buf = hir_item_metadata
        .map(|metadata| metadata.name_token)
        .unwrap_or(&empty_hir_item_name_token);
    let hir_item_namespace_buf = hir_item_metadata
        .map(|metadata| metadata.namespace)
        .unwrap_or(&empty_hir_item_namespace);
    let hir_item_visibility_buf = hir_item_metadata
        .map(|metadata| metadata.visibility)
        .unwrap_or(&empty_hir_item_visibility);
    let hir_item_path_start_buf = hir_item_metadata
        .map(|metadata| metadata.path_start)
        .unwrap_or(&empty_hir_item_path_start);
    let hir_item_path_end_buf = hir_item_metadata
        .map(|metadata| metadata.path_end)
        .unwrap_or(&empty_hir_item_path_end);
    let hir_item_file_id_buf = hir_item_metadata
        .map(|metadata| metadata.file_id)
        .unwrap_or(&empty_hir_item_file_id);
    let hir_item_import_target_kind_buf = hir_item_metadata
        .map(|metadata| metadata.import_target_kind)
        .unwrap_or(&empty_hir_item_import_target_kind);
    let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    resources.insert("gParams".into(), params_buf.as_entire_binding());
    resources.insert("token_words".into(), token_buf.as_entire_binding());
    resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    resources.insert("source_bytes".into(), source_buf.as_entire_binding());
    resources.insert("hir_kind".into(), hir_kind_buf.as_entire_binding());
    resources.insert(
        "hir_token_pos".into(),
        hir_token_pos_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_token_end".into(),
        hir_token_end_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_token_file_id".into(),
        hir_token_file_id_buf.as_entire_binding(),
    );
    resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
    resources.insert(
        "hir_item_kind".into(),
        hir_item_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_name_token".into(),
        hir_item_name_token_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_namespace".into(),
        hir_item_namespace_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_visibility".into(),
        hir_item_visibility_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_path_start".into(),
        hir_item_path_start_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_path_end".into(),
        hir_item_path_end_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_file_id".into(),
        hir_item_file_id_buf.as_entire_binding(),
    );
    resources.insert(
        "hir_item_import_target_kind".into(),
        hir_item_import_target_kind_buf.as_entire_binding(),
    );
    resources.insert("status".into(), status_buf.as_entire_binding());
    resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
    resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
    resources.insert("scope_end".into(), scope_end_buf.as_entire_binding());
    resources.insert("loop_depth".into(), loop_depth_buf.as_entire_binding());
    resources.insert("enclosing_fn".into(), enclosing_fn_buf.as_entire_binding());
    resources.insert(
        "enclosing_fn_end".into(),
        enclosing_fn_end_buf.as_entire_binding(),
    );
    resources.insert("fn_event_end".into(), fn_event_end_buf.as_entire_binding());
    resources.insert(
        "call_fn_index".into(),
        call_fn_index_buf.as_entire_binding(),
    );
    resources.insert(
        "call_return_type".into(),
        call_return_type_buf.as_entire_binding(),
    );
    resources.insert(
        "call_return_type_token".into(),
        call_return_type_token_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_count".into(),
        call_param_count_buf.as_entire_binding(),
    );
    resources.insert(
        "call_param_type".into(),
        call_param_type_buf.as_entire_binding(),
    );
    resources.insert(
        "function_lookup_key".into(),
        function_lookup_key_buf.as_entire_binding(),
    );
    resources.insert(
        "function_lookup_fn".into(),
        function_lookup_fn_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_receiver_type".into(),
        method_decl_receiver_type_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_impl_token".into(),
        method_decl_impl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_name_token".into(),
        method_decl_name_token_buf.as_entire_binding(),
    );
    resources.insert(
        "method_decl_param_offset".into(),
        method_decl_param_offset_buf.as_entire_binding(),
    );
    resources.insert(
        "method_lookup_key".into(),
        method_lookup_key_buf.as_entire_binding(),
    );
    resources.insert(
        "method_lookup_receiver".into(),
        method_lookup_receiver_buf.as_entire_binding(),
    );
    resources.insert(
        "method_lookup_name_token".into(),
        method_lookup_name_token_buf.as_entire_binding(),
    );
    resources.insert(
        "method_lookup_fn".into(),
        method_lookup_fn_buf.as_entire_binding(),
    );
    resources.insert(
        "module_item_kind".into(),
        module_item_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "module_path_start".into(),
        module_path_start_buf.as_entire_binding(),
    );
    resources.insert(
        "module_path_end".into(),
        module_path_end_buf.as_entire_binding(),
    );
    resources.insert(
        "module_path_hash".into(),
        module_path_hash_buf.as_entire_binding(),
    );
    resources.insert(
        "import_enclosing_module_token".into(),
        import_enclosing_module_token_buf.as_entire_binding(),
    );
    resources.insert(
        "import_target_kind".into(),
        import_target_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "import_resolved_module_token".into(),
        import_resolved_module_token_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_item_kind".into(),
        decl_item_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_name_hash".into(),
        decl_name_hash_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_name_len".into(),
        decl_name_len_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_namespace".into(),
        decl_namespace_buf.as_entire_binding(),
    );
    resources.insert(
        "decl_visibility".into(),
        decl_visibility_buf.as_entire_binding(),
    );
    resources.insert("decl_file_id".into(), decl_file_id_buf.as_entire_binding());
    resources.insert(
        "decl_hir_node".into(),
        decl_hir_node_buf.as_entire_binding(),
    );
    resources.insert(
        "type_expr_ref_tag".into(),
        type_expr_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_expr_ref_payload".into(),
        type_expr_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_kind".into(),
        type_instance_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_head_token".into(),
        type_instance_head_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_decl_token".into(),
        type_instance_decl_token_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_start".into(),
        type_instance_arg_start_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_count".into(),
        type_instance_arg_count_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_ref_tag".into(),
        type_instance_arg_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_arg_ref_payload".into(),
        type_instance_arg_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_elem_ref_tag".into(),
        type_instance_elem_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_elem_ref_payload".into(),
        type_instance_elem_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_len_kind".into(),
        type_instance_len_kind_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_len_payload".into(),
        type_instance_len_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "type_instance_state".into(),
        type_instance_state_buf.as_entire_binding(),
    );
    resources.insert(
        "fn_return_ref_tag".into(),
        fn_return_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "fn_return_ref_payload".into(),
        fn_return_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_ref_tag".into(),
        member_result_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "member_result_ref_payload".into(),
        member_result_ref_payload_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_expected_ref_tag".into(),
        struct_init_field_expected_ref_tag_buf.as_entire_binding(),
    );
    resources.insert(
        "struct_init_field_expected_ref_payload".into(),
        struct_init_field_expected_ref_payload_buf.as_entire_binding(),
    );
    let type_instances_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_collect"),
        &type_instances_collect_pass.bind_group_layouts[0],
        &type_instances_collect_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_struct_fields_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_struct_fields"),
        &type_instances_struct_fields_pass.bind_group_layouts[0],
        &type_instances_struct_fields_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_member_results_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_member_results"),
        &type_instances_member_results_pass.bind_group_layouts[0],
        &type_instances_member_results_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_struct_init_fields_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_struct_init_fields"),
            &type_instances_struct_init_fields_pass.bind_group_layouts[0],
            &type_instances_struct_init_fields_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_array_return_refs_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_return_refs"),
            &type_instances_array_return_refs_pass.bind_group_layouts[0],
            &type_instances_array_return_refs_pass.reflection,
            0,
            &resources,
        )?;
    let type_instances_enum_ctors_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_type_instances_enum_ctors"),
        &type_instances_enum_ctors_pass.bind_group_layouts[0],
        &type_instances_enum_ctors_pass.reflection,
        0,
        &resources,
    )?;
    let type_instances_array_index_results_bind_group =
        bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_type_instances_array_index_results"),
            &type_instances_array_index_results_pass.bind_group_layouts[0],
            &type_instances_array_index_results_pass.reflection,
            0,
            &resources,
        )?;
    let modules_clear_pass = type_check_modules_clear_pass(device)?;
    let modules_collect_pass = type_check_modules_collect_pass(device)?;
    let modules_collect_decls_pass = type_check_modules_collect_decls_pass(device)?;
    let modules_resolve_imports_pass = type_check_modules_resolve_imports_pass(device)?;
    let modules_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_clear"),
        &modules_clear_pass.bind_group_layouts[0],
        &modules_clear_pass.reflection,
        0,
        &resources,
    )?;
    let modules_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_collect"),
        &modules_collect_pass.bind_group_layouts[0],
        &modules_collect_pass.reflection,
        0,
        &resources,
    )?;
    let modules_collect_decls_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_collect_decls"),
        &modules_collect_decls_pass.bind_group_layouts[0],
        &modules_collect_decls_pass.reflection,
        0,
        &resources,
    )?;
    let modules_resolve_imports_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_resolve_imports"),
        &modules_resolve_imports_pass.bind_group_layouts[0],
        &modules_resolve_imports_pass.reflection,
        0,
        &resources,
    )?;
    let module_metadata_bind_groups = ModuleMetadataBindGroups {
        clear: modules_clear_bind_group,
        collect: modules_collect_bind_group,
        collect_decls: modules_collect_decls_bind_group,
        resolve_imports: modules_resolve_imports_bind_group,
    };
    let modules_types_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_types"),
        &modules_types_pass.bind_group_layouts[0],
        &modules_types_pass.reflection,
        0,
        &resources,
    )?;
    let modules_patch_visible_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_modules_patch_visible"),
        &modules_patch_visible_pass.bind_group_layouts[0],
        &modules_patch_visible_pass.reflection,
        0,
        &resources,
    )?;
    let calls_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_clear"),
        &calls_clear_pass.bind_group_layouts[0],
        &calls_clear_pass.reflection,
        0,
        &resources,
    )?;
    let calls_functions_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_functions"),
        &calls_functions_pass.bind_group_layouts[0],
        &calls_functions_pass.reflection,
        0,
        &resources,
    )?;
    let calls_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_resolve"),
        &calls_resolve_pass.bind_group_layouts[0],
        &calls_resolve_pass.reflection,
        0,
        &resources,
    )?;
    let calls_erase_generic_params_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_calls_erase_generic_params"),
        &calls_erase_generic_params_pass.bind_group_layouts[0],
        &calls_erase_generic_params_pass.reflection,
        0,
        &resources,
    )?;
    let calls_bind_groups = CallBindGroups {
        clear: calls_clear_bind_group,
        functions: calls_functions_bind_group,
        resolve: calls_resolve_bind_group,
        erase_generic_params: calls_erase_generic_params_bind_group,
    };
    let methods_clear_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_clear"),
        &methods_clear_pass.bind_group_layouts[0],
        &methods_clear_pass.reflection,
        0,
        &resources,
    )?;
    let methods_collect_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_collect"),
        &methods_collect_pass.bind_group_layouts[0],
        &methods_collect_pass.reflection,
        0,
        &resources,
    )?;
    let methods_resolve_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_methods_resolve"),
        &methods_resolve_pass.bind_group_layouts[0],
        &methods_resolve_pass.reflection,
        0,
        &resources,
    )?;
    let methods_bind_groups = MethodBindGroups {
        clear: methods_clear_bind_group,
        collect: methods_collect_bind_group,
        resolve: methods_resolve_bind_group,
    };
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )?;
    let control_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_control"),
        &control_pass.bind_group_layouts[0],
        &control_pass.reflection,
        0,
        &resources,
    )?;
    let scope_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_scope"),
        &scope_pass.bind_group_layouts[0],
        &scope_pass.reflection,
        0,
        &resources,
    )?;
    let loop_bind_groups = create_loop_depth_bind_groups(
        device,
        &loop_params_buf,
        &loop_scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        &loop_delta_buf,
        &loop_depth_inblock_buf,
        &loop_block_sum_buf,
        &loop_prefix_a_buf,
        &loop_prefix_b_buf,
        &loop_block_prefix_buf,
        &loop_depth_buf,
    )?;
    let fn_context_bind_groups = create_fn_context_bind_groups(
        device,
        &fn_params_buf,
        &fn_scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        &enclosing_fn_buf,
        &enclosing_fn_end_buf,
        &fn_event_value_buf,
        &fn_event_end_buf,
        &fn_event_index_buf,
        &fn_event_inblock_buf,
        &fn_block_sum_buf,
        &fn_prefix_a_buf,
        &fn_prefix_b_buf,
        &fn_block_prefix_buf,
    )?;
    let visible_bind_groups = create_visible_bind_groups(device, &resources)?;

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("type_check.tokens.encoder"),
    });
    let n_work = token_capacity.max(hir_node_capacity).max(512);
    record_loop_depth_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        loop_n_blocks,
        &loop_bind_groups,
    )?;
    record_module_metadata_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        &module_metadata_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        modules_types_pass,
        &modules_types_bind_group,
        "type_check.modules_types.pass",
        token_capacity,
    )?;
    record_fn_context_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        fn_n_blocks,
        &fn_context_bind_groups,
    )?;
    record_visible_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        hir_node_capacity,
        &visible_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        type_instances_collect_pass,
        &type_instances_collect_bind_group,
        "type_check.type_instances_collect.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_struct_fields_pass,
        &type_instances_struct_fields_bind_group,
        "type_check.type_instances_struct_fields.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_member_results_pass,
        &type_instances_member_results_bind_group,
        "type_check.type_instances_member_results.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_struct_init_fields_pass,
        &type_instances_struct_init_fields_bind_group,
        "type_check.type_instances_struct_init_fields.pass",
        token_capacity,
    )?;
    record_call_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        n_work,
        &calls_bind_groups,
    )?;
    record_method_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        n_work,
        &methods_bind_groups,
    )?;
    record_compute(
        &mut encoder,
        scope_pass,
        &scope_bind_group,
        "type_check.scope.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        modules_patch_visible_pass,
        &modules_patch_visible_bind_group,
        "type_check.modules_patch_visible.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        methods_resolve_pass,
        &methods_bind_groups.resolve,
        "type_check.methods.resolve",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        type_instances_array_return_refs_pass,
        &type_instances_array_return_refs_bind_group,
        "type_check.type_instances_array_return_refs.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_enum_ctors_pass,
        &type_instances_enum_ctors_bind_group,
        "type_check.type_instances_enum_ctors.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        type_instances_array_index_results_pass,
        &type_instances_array_index_results_bind_group,
        "type_check.type_instances_array_index_results.pass",
        token_capacity,
    )?;
    record_compute(
        &mut encoder,
        pass,
        &bind_group,
        "type_check.tokens.pass",
        n_work,
    )?;
    record_compute(
        &mut encoder,
        control_pass,
        &control_bind_group,
        "type_check.control.pass",
        n_work,
    )?;
    encoder.copy_buffer_to_buffer(&status_buf, 0, &status_readback, 0, 16);
    crate::gpu::passes_core::submit_with_progress(queue, "type_check.resident", encoder.finish());

    let slice = status_readback.slice(..);
    crate::gpu::passes_core::map_readback_for_progress(&slice, "type_check.resident.status");
    crate::gpu::passes_core::wait_for_map_progress(
        device,
        "type_check.resident.status",
        wgpu::PollType::Wait,
    );
    let mapped = slice.get_mapped_range();
    let words = read_status_words(&mapped)?;
    drop(mapped);
    status_readback.unmap();

    if words[0] != 0 {
        return Ok(());
    }
    Err(GpuTypeCheckError::Rejected {
        token: words[1],
        code: GpuTypeCheckCode::from_u32(words[2]),
        detail: words[3],
    })
}

fn type_check_tokens_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_tokens",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_tokens_min.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_tokens_min.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_collect_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_01_collect",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_01_collect.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_01_collect.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_struct_fields_pass(
    device: &wgpu::Device,
) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_02_struct_fields",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_02_struct_fields.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_02_struct_fields.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_member_results_pass(
    device: &wgpu::Device,
) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_03_member_results",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_03_member_results.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_03_member_results.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_struct_init_fields_pass(
    device: &wgpu::Device,
) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_04_struct_init_fields",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_04_struct_init_fields.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_04_struct_init_fields.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_array_return_refs_pass(
    device: &wgpu::Device,
) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_05_array_return_refs",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_05_array_return_refs.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_05_array_return_refs.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_enum_ctors_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_06_enum_ctors",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_06_enum_ctors.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_06_enum_ctors.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_type_instances_array_index_results_pass(
    device: &wgpu::Device,
) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_type_instances_07_array_index_results",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_07_array_index_results.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_type_instances_07_array_index_results.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_00_clear",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_clear.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_clear.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_collect_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_00_collect",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_collect.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_collect.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_collect_decls_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_00_collect_decls",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_collect_decls.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_collect_decls.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_resolve_imports_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_00_resolve_imports",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_resolve_imports.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_00_resolve_imports.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_types_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_01_same_source_types",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_01_same_source_types.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_01_same_source_types.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_modules_patch_visible_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_modules_02_patch_visible_types",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_02_patch_visible_types.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_modules_02_patch_visible_types.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_control_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_control",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/type_check_control.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_control.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_control_hir_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_control_hir",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_control_hir.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_control_hir.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_scope_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_scope",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/type_check_scope.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_scope.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_calls_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_calls_01_resolve",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_01_resolve.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_01_resolve.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_calls_functions_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_calls_02_functions",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_02_functions.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_02_functions.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_calls_resolve_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_calls_03_resolve",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_03_resolve.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_03_resolve.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_calls_erase_generic_params_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_calls_04_erase_generic_params",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_04_erase_generic_params.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_calls_04_erase_generic_params.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_methods_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_methods_01_clear",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_01_clear.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_01_clear.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_methods_collect_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_methods_02_collect",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_02_collect.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_02_collect.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_methods_resolve_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_methods_03_resolve",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_03_resolve.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_methods_03_resolve.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_visible_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_visible_01_clear",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_01_clear.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_01_clear.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_visible_scope_blocks_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_visible_02_scope_blocks",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_02_scope_blocks.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_02_scope_blocks.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_visible_scatter_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_visible_02_scatter",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_02_scatter.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_02_scatter.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_visible_decode_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_visible_03_decode",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_03_decode.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_visible_03_decode.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_fn_context_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_fn_context_01_clear",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_01_clear.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_01_clear.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_fn_context_mark_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_fn_context_02_mark",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_02_mark.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_02_mark.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_fn_context_local_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_fn_context_03_local",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_03_local.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_03_local.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_fn_context_scan_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_fn_context_04_scan_blocks",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_04_scan_blocks.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_04_scan_blocks.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn type_check_fn_context_apply_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_fn_context_05_apply",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_05_apply.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_fn_context_05_apply.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn loop_depth_01_clear_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_loop_depth_01_clear",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_01_clear.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_01_clear.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn loop_depth_02_mark_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_loop_depth_02_mark",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_02_mark.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_02_mark.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn loop_depth_03_local_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_loop_depth_03_local",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_03_local.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_03_local.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn loop_depth_04_scan_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_loop_depth_04_scan_blocks",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_04_scan_blocks.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_04_scan_blocks.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn loop_depth_05_apply_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "type_check_loop_depth_05_apply",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_05_apply.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_loop_depth_05_apply.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn create_visible_bind_groups(
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<VisibleBindGroups> {
    let clear_pass = type_check_visible_clear_pass(device)?;
    let scope_blocks_pass = type_check_visible_scope_blocks_pass(device)?;
    let scatter_pass = type_check_visible_scatter_pass(device)?;
    let decode_pass = type_check_visible_decode_pass(device)?;
    create_visible_bind_groups_from_passes(
        device,
        resources,
        clear_pass,
        scope_blocks_pass,
        scatter_pass,
        decode_pass,
    )
}

fn create_visible_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<VisibleBindGroups> {
    create_visible_bind_groups_from_passes(
        device,
        resources,
        &passes.visible_clear,
        &passes.visible_scope_blocks,
        &passes.visible_scatter,
        &passes.visible_decode,
    )
}

fn create_visible_bind_groups_from_passes(
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    clear_pass: &PassData,
    scope_blocks_pass: &PassData,
    scatter_pass: &PassData,
    decode_pass: &PassData,
) -> Result<VisibleBindGroups> {
    let clear = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_visible_01_clear"),
        &clear_pass.bind_group_layouts[0],
        &clear_pass.reflection,
        0,
        resources,
    )?;
    let scope_blocks = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_visible_02_scope_blocks"),
        &scope_blocks_pass.bind_group_layouts[0],
        &scope_blocks_pass.reflection,
        0,
        resources,
    )?;
    let scatter = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_visible_02_scatter"),
        &scatter_pass.bind_group_layouts[0],
        &scatter_pass.reflection,
        0,
        resources,
    )?;
    let decode = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_visible_03_decode"),
        &decode_pass.bind_group_layouts[0],
        &decode_pass.reflection,
        0,
        resources,
    )?;

    Ok(VisibleBindGroups {
        clear,
        scope_blocks,
        scatter,
        decode,
    })
}

#[allow(clippy::too_many_arguments)]
fn create_fn_context_bind_groups(
    device: &wgpu::Device,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    let clear_pass = type_check_fn_context_clear_pass(device)?;
    let mark_pass = type_check_fn_context_mark_pass(device)?;
    let local_pass = type_check_fn_context_local_pass(device)?;
    let scan_pass = type_check_fn_context_scan_pass(device)?;
    let apply_pass = type_check_fn_context_apply_pass(device)?;
    create_fn_context_bind_groups_from_passes(
        device,
        &clear_pass,
        &mark_pass,
        &local_pass,
        &scan_pass,
        &apply_pass,
        params,
        scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        enclosing_fn,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )
}

#[allow(clippy::too_many_arguments)]
fn create_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    create_fn_context_bind_groups_from_passes(
        device,
        &passes.fn_context_clear,
        &passes.fn_context_mark,
        &passes.fn_context_local,
        &passes.fn_context_scan,
        &passes.fn_context_apply,
        params,
        scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        enclosing_fn,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )
}

#[allow(clippy::too_many_arguments)]
fn create_fn_context_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    scan_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    let clear_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("enclosing_fn".into(), enclosing_fn.as_entire_binding()),
        (
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        ),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), fn_block_sum.as_entire_binding()),
        ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
    ]);
    let clear = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_01_clear"),
        &clear_pass.bind_group_layouts[0],
        &clear_pass.reflection,
        0,
        &clear_resources,
    )?;

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
    ]);
    let mark = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_02_mark"),
        &mark_pass.bind_group_layouts[0],
        &mark_pass.reflection,
        0,
        &mark_resources,
    )?;

    let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), fn_block_sum.as_entire_binding()),
    ]);
    let local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_03_local"),
        &local_pass.bind_group_layouts[0],
        &local_pass.reflection,
        0,
        &local_resources,
    )?;

    let mut scan = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            fn_prefix_a
        } else {
            fn_prefix_b
        };
        let prefix_out = if step.write_to_a {
            fn_prefix_a
        } else {
            fn_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("block_sum".into(), fn_block_sum.as_entire_binding()),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
        ]);
        scan.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_fn_context_04_scan_blocks"),
            &scan_pass.bind_group_layouts[0],
            &scan_pass.reflection,
            0,
            &scan_resources,
        )?);
    }

    let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
        ("enclosing_fn".into(), enclosing_fn.as_entire_binding()),
        (
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        ),
    ]);
    let apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_05_apply"),
        &apply_pass.bind_group_layouts[0],
        &apply_pass.reflection,
        0,
        &apply_resources,
    )?;

    Ok(FnContextBindGroups {
        clear,
        mark,
        local,
        scan,
        apply,
    })
}

#[allow(clippy::too_many_arguments)]
fn create_loop_depth_bind_groups(
    device: &wgpu::Device,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    let clear_pass = loop_depth_01_clear_pass(device)?;
    let mark_pass = loop_depth_02_mark_pass(device)?;
    let local_pass = loop_depth_03_local_pass(device)?;
    let scan_pass = loop_depth_04_scan_pass(device)?;
    let apply_pass = loop_depth_05_apply_pass(device)?;
    create_loop_depth_bind_groups_from_passes(
        device,
        &clear_pass,
        &mark_pass,
        &local_pass,
        &scan_pass,
        &apply_pass,
        params,
        scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        loop_delta,
        loop_depth_inblock,
        loop_block_sum,
        loop_prefix_a,
        loop_prefix_b,
        loop_block_prefix,
        loop_depth,
    )
}

#[allow(clippy::too_many_arguments)]
fn create_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    create_loop_depth_bind_groups_from_passes(
        device,
        &passes.loop_depth_clear,
        &passes.loop_depth_mark,
        &passes.loop_depth_local,
        &passes.loop_depth_scan,
        &passes.loop_depth_apply,
        params,
        scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        loop_delta,
        loop_depth_inblock,
        loop_block_sum,
        loop_prefix_a,
        loop_prefix_b,
        loop_block_prefix,
        loop_depth,
    )
}

#[allow(clippy::too_many_arguments)]
fn create_loop_depth_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    scan_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    let clear_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
    ]);
    let clear = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_01_clear"),
        &clear_pass.bind_group_layouts[0],
        &clear_pass.reflection,
        0,
        &clear_resources,
    )?;

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("token_count".into(), token_count_buf.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
    ]);
    let mark = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_02_mark"),
        &mark_pass.bind_group_layouts[0],
        &mark_pass.reflection,
        0,
        &mark_resources,
    )?;

    let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
        (
            "loop_depth_inblock".into(),
            loop_depth_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), loop_block_sum.as_entire_binding()),
    ]);
    let local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_03_local"),
        &local_pass.bind_group_layouts[0],
        &local_pass.reflection,
        0,
        &local_resources,
    )?;

    let mut scan = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            loop_prefix_a
        } else {
            loop_prefix_b
        };
        let prefix_out = if step.write_to_a {
            loop_prefix_a
        } else {
            loop_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("block_sum".into(), loop_block_sum.as_entire_binding()),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            ("block_prefix".into(), loop_block_prefix.as_entire_binding()),
        ]);
        scan.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_loop_depth_04_scan_blocks"),
            &scan_pass.bind_group_layouts[0],
            &scan_pass.reflection,
            0,
            &scan_resources,
        )?);
    }

    let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "loop_depth_inblock".into(),
            loop_depth_inblock.as_entire_binding(),
        ),
        ("block_prefix".into(), loop_block_prefix.as_entire_binding()),
        ("loop_depth".into(), loop_depth.as_entire_binding()),
    ]);
    let apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_05_apply"),
        &apply_pass.bind_group_layouts[0],
        &apply_pass.reflection,
        0,
        &apply_resources,
    )?;

    Ok(LoopDepthBindGroups {
        clear,
        mark,
        local,
        scan,
        apply,
    })
}

fn make_loop_depth_scan_steps(
    device: &wgpu::Device,
    base: LoopDepthParams,
) -> Vec<LoopDepthScanStep> {
    let mut steps = Vec::new();
    steps.push(LoopDepthScanStep {
        params: uniform_from_val(
            device,
            "type_check.loop_depth.scan.params.init",
            &LoopDepthParams {
                scan_step: 0,
                ..base
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < base.n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(LoopDepthScanStep {
            params: uniform_from_val(
                device,
                "type_check.loop_depth.scan.params.step",
                &LoopDepthParams {
                    scan_step: step,
                    ..base
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    let read_from_a = step_count % 2 == 0;
    steps.push(LoopDepthScanStep {
        params: uniform_from_val(
            device,
            "type_check.loop_depth.scan.params.finalize",
            &LoopDepthParams {
                scan_step: base.n_blocks,
                ..base
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });
    steps
}

fn make_fn_context_scan_steps(
    device: &wgpu::Device,
    base: FnContextParams,
) -> Vec<FnContextScanStep> {
    let mut steps = Vec::new();
    steps.push(FnContextScanStep {
        params: uniform_from_val(
            device,
            "type_check.fn_context.scan.params.init",
            &FnContextParams {
                scan_step: 0,
                ..base
            },
        ),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < base.n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(FnContextScanStep {
            params: uniform_from_val(
                device,
                "type_check.fn_context.scan.params.step",
                &FnContextParams {
                    scan_step: step,
                    ..base
                },
            ),
            read_from_a,
            write_to_a: !read_from_a,
        });
        step <<= 1;
        step_count += 1;
    }

    let read_from_a = step_count % 2 == 0;
    steps.push(FnContextScanStep {
        params: uniform_from_val(
            device,
            "type_check.fn_context.scan.params.finalize",
            &FnContextParams {
                scan_step: base.n_blocks,
                ..base
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });
    steps
}

fn record_visible_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &VisibleBindGroups,
) -> Result<()> {
    let n = token_capacity.max(1);
    record_compute(
        encoder,
        type_check_visible_clear_pass(device)?,
        &groups.clear,
        "type_check.visible.clear",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_scope_blocks_pass(device)?,
        &groups.scope_blocks,
        "type_check.visible.scope_blocks",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_visible_scatter_pass(device)?,
        &groups.scatter,
        "type_check.visible.scatter",
        n,
    )?;
    record_compute(
        encoder,
        type_check_visible_decode_pass(device)?,
        &groups.decode,
        "type_check.visible.decode",
        n,
    )
}

fn record_fn_context_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &FnContextBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        type_check_fn_context_clear_pass(device)?,
        &groups.clear,
        "type_check.fn_context.clear",
        token_capacity.max(n_blocks).max(1),
    )?;
    record_compute(
        encoder,
        type_check_fn_context_mark_pass(device)?,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_fn_context_local_pass(device)?,
        &groups.local,
        "type_check.fn_context.local",
        token_capacity.max(1),
    )?;
    for bind_group in &groups.scan {
        record_compute(
            encoder,
            type_check_fn_context_scan_pass(device)?,
            bind_group,
            "type_check.fn_context.scan",
            n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        type_check_fn_context_apply_pass(device)?,
        &groups.apply,
        "type_check.fn_context.apply",
        token_capacity.max(1),
    )
}

fn record_call_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        type_check_calls_clear_pass(device)?,
        &groups.clear,
        "type_check.calls.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_functions_pass(device)?,
        &groups.functions,
        "type_check.calls.functions",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_resolve_pass(device)?,
        &groups.resolve,
        "type_check.calls.resolve",
        n_work,
    )?;
    record_compute(
        encoder,
        type_check_calls_erase_generic_params_pass(device)?,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}

fn record_module_metadata_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &ModuleMetadataBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        type_check_modules_clear_pass(device)?,
        &groups.clear,
        "type_check.modules.clear",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_modules_collect_pass(device)?,
        &groups.collect,
        "type_check.modules.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_modules_collect_decls_pass(device)?,
        &groups.collect_decls,
        "type_check.modules.collect_decls",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        type_check_modules_resolve_imports_pass(device)?,
        &groups.resolve_imports,
        "type_check.modules.resolve_imports",
        token_capacity.max(1),
    )
}

fn record_method_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        type_check_methods_clear_pass(device)?,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        type_check_methods_collect_pass(device)?,
        &groups.collect,
        "type_check.methods.collect",
        token_capacity.max(1),
    )
}

fn record_loop_depth_bind_groups(
    device: &wgpu::Device,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &LoopDepthBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        loop_depth_01_clear_pass(device)?,
        &groups.clear,
        "type_check.loop_depth.clear",
        token_capacity.saturating_add(1),
    )?;
    record_compute(
        encoder,
        loop_depth_02_mark_pass(device)?,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        loop_depth_03_local_pass(device)?,
        &groups.local,
        "type_check.loop_depth.local",
        n_blocks.saturating_mul(256),
    )?;
    let scan_pass = loop_depth_04_scan_pass(device)?;
    for scan_group in &groups.scan {
        record_compute(
            encoder,
            scan_pass,
            scan_group,
            "type_check.loop_depth.scan",
            n_blocks,
        )?;
    }
    record_compute(
        encoder,
        loop_depth_05_apply_pass(device)?,
        &groups.apply,
        "type_check.loop_depth.apply",
        token_capacity.max(1),
    )
}

fn record_loop_depth_passes_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    groups: &ResidentTypeCheckBindGroups,
) -> Result<()> {
    record_loop_depth_bind_groups_with_passes(
        passes,
        encoder,
        groups.token_capacity,
        groups.hir_node_capacity,
        groups.loop_n_blocks,
        &groups.loop_bind_groups,
    )
}

fn record_visible_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &VisibleBindGroups,
) -> Result<()> {
    let n = token_capacity.max(1);
    record_compute(
        encoder,
        &passes.visible_clear,
        &groups.clear,
        "type_check.visible.clear",
        n,
    )?;
    record_compute(
        encoder,
        &passes.visible_scope_blocks,
        &groups.scope_blocks,
        "type_check.visible.scope_blocks",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.visible_scatter,
        &groups.scatter,
        "type_check.visible.scatter",
        n,
    )?;
    record_compute(
        encoder,
        &passes.visible_decode,
        &groups.decode,
        "type_check.visible.decode",
        n,
    )
}

fn record_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &FnContextBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.fn_context_clear,
        &groups.clear,
        "type_check.fn_context.clear",
        token_capacity.max(n_blocks).max(1),
    )?;
    record_compute(
        encoder,
        &passes.fn_context_mark,
        &groups.mark,
        "type_check.fn_context.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.fn_context_local,
        &groups.local,
        "type_check.fn_context.local",
        token_capacity.max(1),
    )?;
    for bind_group in &groups.scan {
        record_compute(
            encoder,
            &passes.fn_context_scan,
            bind_group,
            "type_check.fn_context.scan",
            n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        &passes.fn_context_apply,
        &groups.apply,
        "type_check.fn_context.apply",
        token_capacity.max(1),
    )
}

fn record_call_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &CallBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        &passes.calls_clear,
        &groups.clear,
        "type_check.calls.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_functions,
        &groups.functions,
        "type_check.calls.functions",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_resolve,
        &groups.resolve,
        "type_check.calls.resolve",
        n_work,
    )?;
    record_compute(
        encoder,
        &passes.calls_erase_generic_params,
        &groups.erase_generic_params,
        "type_check.calls.erase_generic_params",
        token_capacity
            .saturating_mul(CALL_PARAM_CACHE_STRIDE as u32)
            .max(1),
    )
}

fn record_module_metadata_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    groups: &ModuleMetadataBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.modules_clear,
        &groups.clear,
        "type_check.modules.clear",
        token_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_collect,
        &groups.collect,
        "type_check.modules.collect",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_collect_decls,
        &groups.collect_decls,
        "type_check.modules.collect_decls",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.modules_resolve_imports,
        &groups.resolve_imports,
        "type_check.modules.resolve_imports",
        token_capacity.max(1),
    )
}

fn record_method_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    n_work: u32,
    groups: &MethodBindGroups,
) -> Result<()> {
    let lookup_work = token_capacity.saturating_mul(2).max(n_work);
    record_compute(
        encoder,
        &passes.methods_clear,
        &groups.clear,
        "type_check.methods.clear",
        lookup_work,
    )?;
    record_compute(
        encoder,
        &passes.methods_collect,
        &groups.collect,
        "type_check.methods.collect",
        token_capacity.max(1),
    )
}

fn record_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    hir_node_capacity: u32,
    n_blocks: u32,
    groups: &LoopDepthBindGroups,
) -> Result<()> {
    record_compute(
        encoder,
        &passes.loop_depth_clear,
        &groups.clear,
        "type_check.loop_depth.clear",
        token_capacity.saturating_add(1),
    )?;
    record_compute(
        encoder,
        &passes.loop_depth_mark,
        &groups.mark,
        "type_check.loop_depth.mark",
        hir_node_capacity.max(1),
    )?;
    record_compute(
        encoder,
        &passes.loop_depth_local,
        &groups.local,
        "type_check.loop_depth.local",
        n_blocks.saturating_mul(256),
    )?;
    for scan_group in &groups.scan {
        record_compute(
            encoder,
            &passes.loop_depth_scan,
            scan_group,
            "type_check.loop_depth.scan",
            n_blocks,
        )?;
    }
    record_compute(
        encoder,
        &passes.loop_depth_apply,
        &groups.apply,
        "type_check.loop_depth.apply",
        token_capacity.max(1),
    )
}

fn record_compute(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    n_elements: u32,
) -> Result<()> {
    let [tgsx, tgsy, _] = pass.thread_group_size;
    let (gx, gy, gz) = plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [tgsx, tgsy, 1],
    )?;
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(gx, gy, gz);
    Ok(())
}

fn status_init_bytes() -> Vec<u8> {
    [1u32, u32::MAX, 0, 0]
        .into_iter()
        .flat_map(u32::to_le_bytes)
        .collect()
}

fn type_check_params_bytes(params: &TypeCheckParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode type checker params");
    ub.as_ref().to_vec()
}

fn read_status_words(bytes: &[u8]) -> Result<[u32; 4]> {
    if bytes.len() < 16 {
        return Err(anyhow!("type checker status readback was truncated"));
    }
    Ok([
        u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
        u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
        u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        u32::from_le_bytes(bytes[12..16].try_into().unwrap()),
    ])
}

fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_SRC | extra_usage,
        mapped_at_creation: false,
    })
}

fn storage_i32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> wgpu::Buffer {
    storage_u32_rw(device, label, count, extra_usage)
}

fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn token_bytes(tokens: &[Token]) -> Vec<u8> {
    let mut out = Vec::with_capacity(tokens.len().max(1) * 12);
    for token in tokens {
        out.extend_from_slice(&(token.kind as u32).to_le_bytes());
        out.extend_from_slice(&(token.start as u32).to_le_bytes());
        out.extend_from_slice(&(token.len as u32).to_le_bytes());
    }
    if out.is_empty() {
        out.resize(12, 0);
    }
    out
}

fn nonempty_bytes(bytes: &[u8]) -> Vec<u8> {
    let mut out = if bytes.is_empty() {
        vec![0]
    } else {
        bytes.to_vec()
    };
    let aligned_len = out.len().div_ceil(4) * 4;
    if out.len() < aligned_len {
        out.resize(aligned_len, 0);
    }
    out
}
