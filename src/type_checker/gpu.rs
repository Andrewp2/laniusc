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
}

const CALL_PARAM_CACHE_STRIDE: usize = 16;

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

struct TypeCheckPasses {
    tokens: PassData,
    control: PassData,
    control_hir: PassData,
    scope: PassData,
    calls_clear: PassData,
    calls_functions: PassData,
    calls_resolve: PassData,
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
            tokens: pass!("type_check_tokens", "type_check_tokens"),
            control: pass!("type_check_control", "type_check_control"),
            control_hir: pass!("type_check_control_hir", "type_check_control_hir"),
            scope: pass!("type_check_scope", "type_check_scope"),
            calls_clear: pass!("type_check_calls_01_resolve", "type_check_calls_01_resolve"),
            calls_functions: pass!(
                "type_check_calls_02_functions",
                "type_check_calls_02_functions"
            ),
            calls_resolve: pass!("type_check_calls_03_resolve", "type_check_calls_03_resolve"),
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
    loop_params: LaniusBuffer<LoopDepthParams>,
    loop_scan_steps: Vec<LoopDepthScanStep>,
    fn_params: LaniusBuffer<FnContextParams>,
    fn_scan_steps: Vec<FnContextScanStep>,
    loop_bind_groups: LoopDepthBindGroups,
    fn_context_bind_groups: FnContextBindGroups,
    visible_bind_groups: VisibleBindGroups,
    calls: CallBindGroups,
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
        hir_status_buf: &wgpu::Buffer,
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
            hir_status_buf,
            None,
        )?;
        queue.submit(Some(encoder.finish()));
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
        hir_status_buf: &wgpu::Buffer,
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
                    hir_status_buf,
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
        slice.map_async(wgpu::MapMode::Read, |_| {});
        let _ = device.poll(wgpu::PollType::Wait);
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
        hir_status_buf: &wgpu::Buffer,
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
        resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
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
        let calls = CallBindGroups {
            clear: calls_clear,
            functions: calls_functions,
            resolve: calls_resolve,
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
            loop_params,
            loop_scan_steps,
            fn_params,
            fn_scan_steps,
            loop_bind_groups,
            fn_context_bind_groups,
            visible_bind_groups,
            calls,
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
        &hir_status_buf,
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
        &empty_status,
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
    hir_status_buf: &wgpu::Buffer,
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
    resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
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
    let calls_bind_groups = CallBindGroups {
        clear: calls_clear_bind_group,
        functions: calls_functions_bind_group,
        resolve: calls_resolve_bind_group,
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
    record_call_bind_groups(
        device,
        &mut encoder,
        token_capacity,
        n_work,
        &calls_bind_groups,
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
        scope_pass,
        &scope_bind_group,
        "type_check.scope.pass",
        n_work,
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
    queue.submit(Some(encoder.finish()));

    let slice = status_readback.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);
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
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/type_check_tokens.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/type_check_tokens.reflect.json"
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
        usage: wgpu::BufferUsages::STORAGE | extra_usage,
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
