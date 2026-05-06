use std::{
    collections::HashMap,
    hash::{Hash, Hasher},
    sync::{Mutex, OnceLock},
};

use anyhow::Result;
use encase::ShaderType;

use crate::{
    gpu::{
        buffers::{LaniusBuffer, storage_ro_from_bytes, storage_ro_from_u32s, uniform_from_val},
        device,
        passes_core::{PassData, bind_group, make_pass_data},
    },
    lexer::gpu::types::Token,
};

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct TokenEmitParams {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    segment_count: u32,
    segment_len: u32,
    block_count: u32,
    scan_step: u32,
    n_hir_nodes: u32,
    emit_phase: u32,
}

const EMIT_PHASE_LEGACY: u32 = 0;
const EMIT_PHASE_FUNCTIONS: u32 = 1;
const EMIT_PHASE_TOP_LEVEL: u32 = 2;

#[derive(Debug)]
pub enum GpuCCodegenError {
    UnsupportedSlice(String),
    Gpu(anyhow::Error),
    Utf8(std::string::FromUtf8Error),
}

impl std::fmt::Display for GpuCCodegenError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuCCodegenError::UnsupportedSlice(msg) => write!(f, "unsupported GPU C slice: {msg}"),
            GpuCCodegenError::Gpu(err) => write!(f, "GPU C codegen failed: {err}"),
            GpuCCodegenError::Utf8(err) => write!(f, "GPU C output was not UTF-8: {err}"),
        }
    }
}

impl std::error::Error for GpuCCodegenError {}

impl From<anyhow::Error> for GpuCCodegenError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

impl From<std::string::FromUtf8Error> for GpuCCodegenError {
    fn from(err: std::string::FromUtf8Error) -> Self {
        Self::Utf8(err)
    }
}

pub async fn emit_c_on_gpu(src: &str, tokens: &[Token]) -> Result<String, GpuCCodegenError> {
    emit_c_on_gpu_inner(src, tokens).await
}

fn map_buffer(device: &wgpu::Device, buffer: &wgpu::Buffer) {
    let slice = buffer.slice(..);
    slice.map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Poll);
}

const TOKEN_EMIT_SEGMENTS: &[&str] = &[
    "#include <stdbool.h>\n#include <stdint.h>\n#include <stdio.h>\n\nstatic inline void lanius_print_i64(int64_t value) {\n    printf(\"%lld\\n\", (long long)value);\n}\n\n",
    "int",
    "void",
    "int8_t",
    "int16_t",
    "int32_t",
    "int64_t",
    "intptr_t",
    "uint8_t",
    "uint16_t",
    "uint32_t",
    "uint64_t",
    "uintptr_t",
    "float",
    "double",
    "bool",
    "char",
    " ",
    "(",
    ")",
    "void)",
    ",",
    "=",
    ";\n",
    "return ",
    "if",
    "while",
    "{\n",
    "}\n",
    "else",
    "lanius_print_i64",
    "[",
    "]",
    "{",
    "}",
    ".",
    "+",
    "-",
    "*",
    "/",
    "%",
    "<",
    ">",
    "<=",
    ">=",
    "==",
    "!=",
    "&&",
    "||",
    "!",
    "&",
    "|",
    "^",
    "<<",
    ">>",
    "~",
    "+=",
    "-=",
    "*=",
    "/=",
    "%=",
    "^=",
    "<<=",
    ">>=",
    "&=",
    "|=",
    "++",
    "--",
    "int main(void){\n",
    "return 0;\n}\n",
    "const char *",
];

pub struct GpuCCodeGenerator {
    passes: CodegenTokenPasses,
    params_buf: LaniusBuffer<TokenEmitParams>,
    segment_buf: LaniusBuffer<u32>,
    segment_meta_buf: LaniusBuffer<u32>,
    segment_len: u32,
    buffers: Mutex<Option<ResidentCCodegenBuffers>>,
}

#[allow(dead_code)]
struct ResidentCCodegenBuffers {
    input_fingerprint: u64,
    token_capacity: u32,
    hir_node_capacity: u32,
    output_capacity: usize,
    token_block_count: u32,
    token_hir_role_buf: wgpu::Buffer,
    token_codegen_flags_buf: wgpu::Buffer,
    token_function_delta_buf: wgpu::Buffer,
    codegen_bounds_buf: wgpu::Buffer,
    lengths_buf: wgpu::Buffer,
    offsets_buf: wgpu::Buffer,
    block_prefix_a: wgpu::Buffer,
    block_prefix_b: wgpu::Buffer,
    out_buf: wgpu::Buffer,
    status_buf: wgpu::Buffer,
    out_readback: wgpu::Buffer,
    status_readback: wgpu::Buffer,
    clear_roles_bind_group: wgpu::BindGroup,
    hir_roles_bind_group: wgpu::BindGroup,
    function_scan_bind_group: wgpu::BindGroup,
    function_scan_block_bind_groups: Vec<ResidentBlockScanBindGroup>,
    function_flags_bind_group_a: wgpu::BindGroup,
    function_flags_bind_group_b: wgpu::BindGroup,
    top_level_bounds_bind_group: wgpu::BindGroup,
    plan_bind_group: wgpu::BindGroup,
    scan_bind_group: wgpu::BindGroup,
    block_scan_bind_groups: Vec<ResidentBlockScanBindGroup>,
    emit_bind_group_a: wgpu::BindGroup,
    emit_bind_group_b: wgpu::BindGroup,
    top_level_params_buf: LaniusBuffer<TokenEmitParams>,
    top_level_plan_bind_group: wgpu::BindGroup,
    top_level_scan_bind_group: wgpu::BindGroup,
    top_level_block_scan_bind_groups: Vec<ResidentBlockScanBindGroup>,
    top_level_emit_bind_group_a: wgpu::BindGroup,
    top_level_emit_bind_group_b: wgpu::BindGroup,
}

struct ResidentBlockScanBindGroup {
    params_buf: LaniusBuffer<TokenEmitParams>,
    bind_group: wgpu::BindGroup,
}

pub struct RecordedCCodegen {
    output_capacity: usize,
    token_capacity: u32,
}

impl GpuCCodeGenerator {
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        Self::new(&gpu.device)
    }

    pub fn new(device: &wgpu::Device) -> Result<Self> {
        let passes = CodegenTokenPasses::new(device)?;
        let (segment_words, segment_meta) = pack_segments(TOKEN_EMIT_SEGMENTS);
        let segment_len = segment_words.len() as u32;
        let params_buf = uniform_from_val(
            device,
            "codegen.c_tokens.resident.params",
            &TokenEmitParams {
                n_tokens: 0,
                source_len: 0,
                out_capacity: 0,
                segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
                segment_len,
                block_count: 1,
                scan_step: 0,
                n_hir_nodes: 0,
                emit_phase: EMIT_PHASE_LEGACY,
            },
        );
        let segment_buf =
            storage_ro_from_u32s(device, "codegen.c_tokens.resident.segments", &segment_words);
        let segment_meta_buf = storage_ro_from_u32s(
            device,
            "codegen.c_tokens.resident.segment_meta",
            &segment_meta,
        );
        Ok(Self {
            passes,
            params_buf,
            segment_buf,
            segment_meta_buf,
            segment_len,
            buffers: Mutex::new(None),
        })
    }

    #[allow(clippy::too_many_arguments)]
    pub fn emit_c_from_gpu_token_buffer_with_hir(
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
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
    ) -> Result<String, GpuCCodegenError> {
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.c_tokens.resident.recorded.encoder"),
        });
        let recorded = self.record_c_from_gpu_token_buffer_with_hir(
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
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
        )?;
        queue.submit(Some(encoder.finish()));
        self.finish_recorded_c_codegen(device, &recorded)
    }

    #[allow(clippy::too_many_arguments)]
    pub fn record_c_from_gpu_token_buffer_with_hir(
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
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
    ) -> Result<RecordedCCodegen, GpuCCodegenError> {
        let output_capacity = estimate_output_capacity_from_counts(
            source_len as usize,
            token_capacity as usize,
            self.segment_len as usize,
        );
        let token_block_count = token_capacity.div_ceil(256).max(1);
        let params = TokenEmitParams {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
            segment_len: self.segment_len,
            block_count: token_block_count,
            scan_step: 0,
            n_hir_nodes: hir_node_capacity,
            emit_phase: EMIT_PHASE_FUNCTIONS,
        };

        let passes = &self.passes;
        let input_fingerprint = buffer_fingerprint(&[
            token_buf,
            token_count_buf,
            source_buf,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
        ]);
        let mut guard = self
            .buffers
            .lock()
            .expect("GpuCCodeGenerator.buffers poisoned");
        let bufs = self.resident_buffers_for(
            &mut guard,
            device,
            input_fingerprint,
            token_capacity,
            output_capacity,
            token_block_count,
            token_buf,
            token_count_buf,
            source_buf,
            hir_node_capacity,
            hir_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
            passes,
        )?;

        write_resident_phase_params(
            queue,
            &self.params_buf,
            &bufs.block_scan_bind_groups,
            params,
            token_block_count,
            EMIT_PHASE_FUNCTIONS,
        );
        write_resident_phase_params(
            queue,
            &bufs.top_level_params_buf,
            &bufs.top_level_block_scan_bind_groups,
            params,
            token_block_count,
            EMIT_PHASE_TOP_LEVEL,
        );
        dispatch_token_blocks(
            encoder,
            &passes.clear_roles,
            &bufs.clear_roles_bind_group,
            "codegen.c_tokens.resident.clear_roles",
            token_block_count,
        );
        if hir_node_capacity > 0 {
            dispatch_token_blocks(
                encoder,
                &passes.hir_roles,
                &bufs.hir_roles_bind_group,
                "codegen.c_tokens.resident.hir_roles",
                hir_node_capacity.div_ceil(256).max(1),
            );
            record_resident_function_flags(
                encoder,
                passes,
                bufs,
                token_block_count,
                "codegen.c_tokens.resident.function",
            );
            dispatch_token_blocks(
                encoder,
                &passes.top_level_bounds,
                &bufs.top_level_bounds_bind_group,
                "codegen.c_tokens.resident.top_level_bounds",
                token_block_count,
            );
        }
        record_resident_emit_phase(
            encoder,
            passes,
            bufs,
            token_block_count,
            "codegen.c_tokens.resident.functions",
        );
        record_resident_top_level_emit_phase(
            encoder,
            passes,
            bufs,
            token_block_count,
            "codegen.c_tokens.resident.top_level",
        );
        encoder.copy_buffer_to_buffer(
            &bufs.out_buf,
            0,
            &bufs.out_readback,
            0,
            (output_capacity * 4) as u64,
        );
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 8);

        Ok(RecordedCCodegen {
            output_capacity,
            token_capacity,
        })
    }

    pub fn finish_recorded_c_codegen(
        &self,
        device: &wgpu::Device,
        recorded: &RecordedCCodegen,
    ) -> Result<String, GpuCCodegenError> {
        let guard = self
            .buffers
            .lock()
            .expect("GpuCCodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("GPU C codegen buffers missing"))?;
        read_codegen_output(
            device,
            &bufs.status_readback,
            &bufs.out_readback,
            recorded.output_capacity,
            recorded.token_capacity,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentCCodegenBuffers>,
        device: &wgpu::Device,
        input_fingerprint: u64,
        token_capacity: u32,
        output_capacity: usize,
        token_block_count: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        passes: &CodegenTokenPasses,
    ) -> Result<&'a ResidentCCodegenBuffers> {
        let needs_allocate = slot.as_ref().is_none_or(|cached| {
            input_fingerprint != cached.input_fingerprint
                || token_capacity > cached.token_capacity
                || hir_node_capacity > cached.hir_node_capacity
                || output_capacity > cached.output_capacity
                || token_block_count > cached.token_block_count
        });

        if needs_allocate {
            let grown_token_capacity = slot
                .as_ref()
                .map(|cached| cached.token_capacity.saturating_mul(2))
                .unwrap_or(0)
                .max(token_capacity)
                .max(1);
            let grown_hir_node_capacity = slot
                .as_ref()
                .map(|cached| cached.hir_node_capacity.saturating_mul(2))
                .unwrap_or(0)
                .max(hir_node_capacity)
                .max(1);
            let grown_output_capacity = slot
                .as_ref()
                .map(|cached| cached.output_capacity.saturating_mul(2))
                .unwrap_or(0)
                .max(output_capacity)
                .max(1);
            let grown_token_block_count = slot
                .as_ref()
                .map(|cached| cached.token_block_count.saturating_mul(2))
                .unwrap_or(0)
                .max(token_block_count)
                .max(1);

            *slot = Some(self.create_resident_buffers(
                device,
                input_fingerprint,
                grown_token_capacity,
                grown_output_capacity,
                grown_token_block_count,
                token_buf,
                token_count_buf,
                source_buf,
                grown_hir_node_capacity,
                hir_kind_buf,
                hir_token_pos_buf,
                hir_token_end_buf,
                hir_status_buf,
                visible_decl_buf,
                visible_type_buf,
                call_fn_index_buf,
                call_return_type_buf,
                passes,
            )?);
        }

        Ok(slot
            .as_ref()
            .expect("resident codegen buffers must be allocated"))
    }

    #[allow(clippy::too_many_arguments)]
    fn create_resident_buffers(
        &self,
        device: &wgpu::Device,
        input_fingerprint: u64,
        token_capacity: u32,
        output_capacity: usize,
        token_block_count: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        hir_node_capacity: u32,
        hir_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        passes: &CodegenTokenPasses,
    ) -> Result<ResidentCCodegenBuffers> {
        let token_hir_role_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.token_hir_role",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let token_codegen_flags_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.token_codegen_flags",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let token_function_delta_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.token_function_delta",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let codegen_bounds_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.codegen_bounds",
            2,
            wgpu::BufferUsages::empty(),
        );
        let lengths_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.lengths",
            token_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let offsets_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.offsets",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_a = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.block_prefix_a",
            token_block_count as usize,
            wgpu::BufferUsages::empty(),
        );
        let block_prefix_b = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.block_prefix_b",
            token_block_count as usize,
            wgpu::BufferUsages::empty(),
        );
        let out_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.out_words",
            output_capacity,
            wgpu::BufferUsages::COPY_SRC,
        );
        let status_buf = storage_u32_rw(
            device,
            "codegen.c_tokens.resident.status",
            2,
            wgpu::BufferUsages::COPY_SRC,
        );
        let out_readback = readback_u32s(
            device,
            "rb.codegen.c_tokens.resident.out_words",
            output_capacity,
        );
        let status_readback = readback_u32s(device, "rb.codegen.c_tokens.resident.status", 2);

        let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        resources.insert("gParams".into(), self.params_buf.as_entire_binding());
        resources.insert(
            "token_hir_role".into(),
            token_hir_role_buf.as_entire_binding(),
        );
        resources.insert(
            "token_codegen_flags".into(),
            token_codegen_flags_buf.as_entire_binding(),
        );
        resources.insert(
            "token_function_delta".into(),
            token_function_delta_buf.as_entire_binding(),
        );
        resources.insert(
            "codegen_bounds".into(),
            codegen_bounds_buf.as_entire_binding(),
        );
        resources.insert("token_words".into(), token_buf.as_entire_binding());
        resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        resources.insert("source_bytes".into(), source_buf.as_entire_binding());
        resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
        resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
        resources.insert(
            "call_fn_index".into(),
            call_fn_index_buf.as_entire_binding(),
        );
        resources.insert(
            "call_return_type".into(),
            call_return_type_buf.as_entire_binding(),
        );
        resources.insert("segments".into(), self.segment_buf.as_entire_binding());
        resources.insert(
            "segment_meta".into(),
            self.segment_meta_buf.as_entire_binding(),
        );
        resources.insert("lengths".into(), lengths_buf.as_entire_binding());
        resources.insert("lengths_out".into(), lengths_buf.as_entire_binding());
        resources.insert("offsets".into(), offsets_buf.as_entire_binding());
        resources.insert("offsets_out".into(), offsets_buf.as_entire_binding());
        resources.insert("block_prefix".into(), block_prefix_a.as_entire_binding());
        resources.insert(
            "block_prefix_out".into(),
            block_prefix_a.as_entire_binding(),
        );
        resources.insert("out_words".into(), out_buf.as_entire_binding());
        resources.insert("status".into(), status_buf.as_entire_binding());

        let clear_roles_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_00_clear_roles"),
            &passes.clear_roles.bind_group_layouts[0],
            &passes.clear_roles.reflection,
            0,
            &resources,
        )?;

        let mut hir_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        hir_resources.insert("gParams".into(), self.params_buf.as_entire_binding());
        hir_resources.insert("hir_kind".into(), hir_kind_buf.as_entire_binding());
        hir_resources.insert(
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        );
        hir_resources.insert(
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        );
        hir_resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
        hir_resources.insert("token_words".into(), token_buf.as_entire_binding());
        hir_resources.insert(
            "token_hir_role".into(),
            token_hir_role_buf.as_entire_binding(),
        );
        hir_resources.insert(
            "token_function_delta".into(),
            token_function_delta_buf.as_entire_binding(),
        );
        let hir_roles_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_01_hir_roles"),
            &passes.hir_roles.bind_group_layouts[0],
            &passes.hir_roles.reflection,
            0,
            &hir_resources,
        )?;

        let function_scan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_02_function_scan"),
            &passes.function_scan.bind_group_layouts[0],
            &passes.function_scan.reflection,
            0,
            &resources,
        )?;
        let mut function_scan_block_bind_groups = Vec::new();
        let mut scan_step = 1u32;
        let mut scan_step_count = 0usize;
        while scan_step < token_block_count {
            let step_params = TokenEmitParams {
                n_tokens: token_capacity,
                source_len: 0,
                out_capacity: output_capacity as u32,
                segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
                segment_len: self.segment_len,
                block_count: token_block_count,
                scan_step,
                n_hir_nodes: hir_node_capacity,
                emit_phase: EMIT_PHASE_FUNCTIONS,
            };
            let step_params_buf = uniform_from_val(
                device,
                "codegen.c_tokens.resident.function_scan_step.params",
                &step_params,
            );
            let read_from_a = scan_step_count % 2 == 0;
            let mut step_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
            step_resources.insert("gParams".into(), step_params_buf.as_entire_binding());
            step_resources.insert(
                "block_prefix_in".into(),
                if read_from_a {
                    block_prefix_a.as_entire_binding()
                } else {
                    block_prefix_b.as_entire_binding()
                },
            );
            step_resources.insert(
                "block_prefix_out".into(),
                if read_from_a {
                    block_prefix_b.as_entire_binding()
                } else {
                    block_prefix_a.as_entire_binding()
                },
            );
            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("codegen_c_tokens_resident_02_function_scan_blocks_step"),
                &passes.function_scan_blocks_step.bind_group_layouts[0],
                &passes.function_scan_blocks_step.reflection,
                0,
                &step_resources,
            )?;
            function_scan_block_bind_groups.push(ResidentBlockScanBindGroup {
                params_buf: step_params_buf,
                bind_group,
            });
            scan_step <<= 1;
            scan_step_count += 1;
        }
        let function_flags_bind_group_a = self.create_function_flags_bind_group(
            device,
            token_count_buf,
            &token_codegen_flags_buf,
            &lengths_buf,
            &block_prefix_a,
            &passes.function_flags,
            "codegen_c_tokens_resident_02_function_flags_a",
        )?;
        let function_flags_bind_group_b = self.create_function_flags_bind_group(
            device,
            token_count_buf,
            &token_codegen_flags_buf,
            &lengths_buf,
            &block_prefix_b,
            &passes.function_flags,
            "codegen_c_tokens_resident_02_function_flags_b",
        )?;

        let top_level_bounds_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_02_top_level_bounds"),
            &passes.top_level_bounds.bind_group_layouts[0],
            &passes.top_level_bounds.reflection,
            0,
            &resources,
        )?;

        let plan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_01_plan"),
            &passes.plan.bind_group_layouts[0],
            &passes.plan.reflection,
            0,
            &resources,
        )?;
        let scan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_02_scan"),
            &passes.scan.bind_group_layouts[0],
            &passes.scan.reflection,
            0,
            &resources,
        )?;

        let mut block_scan_bind_groups = Vec::new();
        let mut scan_step = 1u32;
        let mut scan_step_count = 0usize;
        while scan_step < token_block_count {
            let step_params = TokenEmitParams {
                n_tokens: token_capacity,
                source_len: 0,
                out_capacity: output_capacity as u32,
                segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
                segment_len: self.segment_len,
                block_count: token_block_count,
                scan_step,
                n_hir_nodes: hir_node_capacity,
                emit_phase: EMIT_PHASE_FUNCTIONS,
            };
            let step_params_buf = uniform_from_val(
                device,
                "codegen.c_tokens.resident.scan_step.params",
                &step_params,
            );
            let read_from_a = scan_step_count % 2 == 0;
            let mut step_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
            step_resources.insert("gParams".into(), step_params_buf.as_entire_binding());
            step_resources.insert(
                "block_prefix_in".into(),
                if read_from_a {
                    block_prefix_a.as_entire_binding()
                } else {
                    block_prefix_b.as_entire_binding()
                },
            );
            step_resources.insert(
                "block_prefix_out".into(),
                if read_from_a {
                    block_prefix_b.as_entire_binding()
                } else {
                    block_prefix_a.as_entire_binding()
                },
            );
            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("codegen_c_tokens_resident_03_scan_blocks_step"),
                &passes.scan_blocks_step.bind_group_layouts[0],
                &passes.scan_blocks_step.reflection,
                0,
                &step_resources,
            )?;
            block_scan_bind_groups.push(ResidentBlockScanBindGroup {
                params_buf: step_params_buf,
                bind_group,
            });
            scan_step <<= 1;
            scan_step_count += 1;
        }

        let emit_bind_group_a = self.create_emit_bind_group(
            device,
            token_buf,
            token_count_buf,
            source_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
            &token_hir_role_buf,
            &token_codegen_flags_buf,
            &codegen_bounds_buf,
            &offsets_buf,
            &block_prefix_a,
            &out_buf,
            &status_buf,
            &self.params_buf,
            &passes.emit,
            "codegen_c_tokens_resident_03_emit_a",
        )?;
        let emit_bind_group_b = self.create_emit_bind_group(
            device,
            token_buf,
            token_count_buf,
            source_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
            &token_hir_role_buf,
            &token_codegen_flags_buf,
            &codegen_bounds_buf,
            &offsets_buf,
            &block_prefix_b,
            &out_buf,
            &status_buf,
            &self.params_buf,
            &passes.emit,
            "codegen_c_tokens_resident_03_emit_b",
        )?;

        let top_level_params = TokenEmitParams {
            n_tokens: token_capacity,
            source_len: 0,
            out_capacity: output_capacity as u32,
            segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
            segment_len: self.segment_len,
            block_count: token_block_count,
            scan_step: 0,
            n_hir_nodes: hir_node_capacity,
            emit_phase: EMIT_PHASE_TOP_LEVEL,
        };
        let top_level_params_buf = uniform_from_val(
            device,
            "codegen.c_tokens.resident.top_level.params",
            &top_level_params,
        );
        let mut top_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        top_resources.insert("gParams".into(), top_level_params_buf.as_entire_binding());
        top_resources.insert(
            "token_hir_role".into(),
            token_hir_role_buf.as_entire_binding(),
        );
        top_resources.insert(
            "token_codegen_flags".into(),
            token_codegen_flags_buf.as_entire_binding(),
        );
        top_resources.insert(
            "token_function_delta".into(),
            token_function_delta_buf.as_entire_binding(),
        );
        top_resources.insert(
            "codegen_bounds".into(),
            codegen_bounds_buf.as_entire_binding(),
        );
        top_resources.insert("token_words".into(), token_buf.as_entire_binding());
        top_resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        top_resources.insert("source_bytes".into(), source_buf.as_entire_binding());
        top_resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
        top_resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
        top_resources.insert(
            "call_fn_index".into(),
            call_fn_index_buf.as_entire_binding(),
        );
        top_resources.insert(
            "call_return_type".into(),
            call_return_type_buf.as_entire_binding(),
        );
        top_resources.insert("segments".into(), self.segment_buf.as_entire_binding());
        top_resources.insert(
            "segment_meta".into(),
            self.segment_meta_buf.as_entire_binding(),
        );
        top_resources.insert("lengths".into(), lengths_buf.as_entire_binding());
        top_resources.insert("lengths_out".into(), lengths_buf.as_entire_binding());
        top_resources.insert("offsets".into(), offsets_buf.as_entire_binding());
        top_resources.insert("offsets_out".into(), offsets_buf.as_entire_binding());
        top_resources.insert("block_prefix".into(), block_prefix_a.as_entire_binding());
        top_resources.insert(
            "block_prefix_out".into(),
            block_prefix_a.as_entire_binding(),
        );
        top_resources.insert("out_words".into(), out_buf.as_entire_binding());
        top_resources.insert("status".into(), status_buf.as_entire_binding());

        let top_level_plan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_top_level_01_plan"),
            &passes.plan.bind_group_layouts[0],
            &passes.plan.reflection,
            0,
            &top_resources,
        )?;
        let top_level_scan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_resident_top_level_02_scan"),
            &passes.scan.bind_group_layouts[0],
            &passes.scan.reflection,
            0,
            &top_resources,
        )?;

        let mut top_level_block_scan_bind_groups = Vec::new();
        let mut scan_step = 1u32;
        let mut scan_step_count = 0usize;
        while scan_step < token_block_count {
            let step_params = TokenEmitParams {
                scan_step,
                ..top_level_params
            };
            let step_params_buf = uniform_from_val(
                device,
                "codegen.c_tokens.resident.top_level.scan_step.params",
                &step_params,
            );
            let read_from_a = scan_step_count % 2 == 0;
            let mut step_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
            step_resources.insert("gParams".into(), step_params_buf.as_entire_binding());
            step_resources.insert(
                "block_prefix_in".into(),
                if read_from_a {
                    block_prefix_a.as_entire_binding()
                } else {
                    block_prefix_b.as_entire_binding()
                },
            );
            step_resources.insert(
                "block_prefix_out".into(),
                if read_from_a {
                    block_prefix_b.as_entire_binding()
                } else {
                    block_prefix_a.as_entire_binding()
                },
            );
            let bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("codegen_c_tokens_resident_top_level_03_scan_blocks_step"),
                &passes.scan_blocks_step.bind_group_layouts[0],
                &passes.scan_blocks_step.reflection,
                0,
                &step_resources,
            )?;
            top_level_block_scan_bind_groups.push(ResidentBlockScanBindGroup {
                params_buf: step_params_buf,
                bind_group,
            });
            scan_step <<= 1;
            scan_step_count += 1;
        }

        let top_level_emit_bind_group_a = self.create_emit_bind_group(
            device,
            token_buf,
            token_count_buf,
            source_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
            &token_hir_role_buf,
            &token_codegen_flags_buf,
            &codegen_bounds_buf,
            &offsets_buf,
            &block_prefix_a,
            &out_buf,
            &status_buf,
            &top_level_params_buf,
            &passes.emit,
            "codegen_c_tokens_resident_top_level_03_emit_a",
        )?;
        let top_level_emit_bind_group_b = self.create_emit_bind_group(
            device,
            token_buf,
            token_count_buf,
            source_buf,
            visible_decl_buf,
            visible_type_buf,
            call_fn_index_buf,
            call_return_type_buf,
            &token_hir_role_buf,
            &token_codegen_flags_buf,
            &codegen_bounds_buf,
            &offsets_buf,
            &block_prefix_b,
            &out_buf,
            &status_buf,
            &top_level_params_buf,
            &passes.emit,
            "codegen_c_tokens_resident_top_level_03_emit_b",
        )?;

        Ok(ResidentCCodegenBuffers {
            input_fingerprint,
            token_capacity,
            hir_node_capacity,
            output_capacity,
            token_block_count,
            token_hir_role_buf,
            token_codegen_flags_buf,
            token_function_delta_buf,
            codegen_bounds_buf,
            lengths_buf,
            offsets_buf,
            block_prefix_a,
            block_prefix_b,
            out_buf,
            status_buf,
            out_readback,
            status_readback,
            clear_roles_bind_group,
            hir_roles_bind_group,
            function_scan_bind_group,
            function_scan_block_bind_groups,
            function_flags_bind_group_a,
            function_flags_bind_group_b,
            top_level_bounds_bind_group,
            plan_bind_group,
            scan_bind_group,
            block_scan_bind_groups,
            emit_bind_group_a,
            emit_bind_group_b,
            top_level_params_buf,
            top_level_plan_bind_group,
            top_level_scan_bind_group,
            top_level_block_scan_bind_groups,
            top_level_emit_bind_group_a,
            top_level_emit_bind_group_b,
        })
    }

    #[allow(clippy::too_many_arguments)]
    fn create_function_flags_bind_group(
        &self,
        device: &wgpu::Device,
        token_count_buf: &wgpu::Buffer,
        token_codegen_flags_buf: &wgpu::Buffer,
        lengths_buf: &wgpu::Buffer,
        block_prefix_buf: &wgpu::Buffer,
        pass: &PassData,
        label: &str,
    ) -> Result<wgpu::BindGroup> {
        let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        resources.insert("gParams".into(), self.params_buf.as_entire_binding());
        resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        resources.insert("lengths".into(), lengths_buf.as_entire_binding());
        resources.insert("block_prefix".into(), block_prefix_buf.as_entire_binding());
        resources.insert(
            "token_codegen_flags".into(),
            token_codegen_flags_buf.as_entire_binding(),
        );
        bind_group::create_bind_group_from_reflection(
            device,
            Some(label),
            &pass.bind_group_layouts[0],
            &pass.reflection,
            0,
            &resources,
        )
    }

    #[allow(clippy::too_many_arguments)]
    fn create_emit_bind_group(
        &self,
        device: &wgpu::Device,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        call_fn_index_buf: &wgpu::Buffer,
        call_return_type_buf: &wgpu::Buffer,
        token_hir_role_buf: &wgpu::Buffer,
        token_codegen_flags_buf: &wgpu::Buffer,
        codegen_bounds_buf: &wgpu::Buffer,
        offsets_buf: &wgpu::Buffer,
        block_prefix_buf: &wgpu::Buffer,
        out_buf: &wgpu::Buffer,
        status_buf: &wgpu::Buffer,
        params_buf: &LaniusBuffer<TokenEmitParams>,
        emit: &PassData,
        label: &str,
    ) -> Result<wgpu::BindGroup> {
        let mut emit_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        emit_resources.insert("gParams".into(), params_buf.as_entire_binding());
        emit_resources.insert("token_words".into(), token_buf.as_entire_binding());
        emit_resources.insert("token_count".into(), token_count_buf.as_entire_binding());
        emit_resources.insert("source_bytes".into(), source_buf.as_entire_binding());
        emit_resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
        emit_resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
        emit_resources.insert(
            "call_fn_index".into(),
            call_fn_index_buf.as_entire_binding(),
        );
        emit_resources.insert(
            "call_return_type".into(),
            call_return_type_buf.as_entire_binding(),
        );
        emit_resources.insert("segments".into(), self.segment_buf.as_entire_binding());
        emit_resources.insert(
            "segment_meta".into(),
            self.segment_meta_buf.as_entire_binding(),
        );
        emit_resources.insert(
            "token_hir_role".into(),
            token_hir_role_buf.as_entire_binding(),
        );
        emit_resources.insert(
            "token_codegen_flags".into(),
            token_codegen_flags_buf.as_entire_binding(),
        );
        emit_resources.insert(
            "codegen_bounds".into(),
            codegen_bounds_buf.as_entire_binding(),
        );
        emit_resources.insert("offsets".into(), offsets_buf.as_entire_binding());
        emit_resources.insert("block_prefix".into(), block_prefix_buf.as_entire_binding());
        emit_resources.insert("out_words".into(), out_buf.as_entire_binding());
        emit_resources.insert("status".into(), status_buf.as_entire_binding());
        bind_group::create_bind_group_from_reflection(
            device,
            Some(label),
            &emit.bind_group_layouts[0],
            &emit.reflection,
            0,
            &emit_resources,
        )
    }
}

fn write_resident_phase_params(
    queue: &wgpu::Queue,
    params_buf: &LaniusBuffer<TokenEmitParams>,
    block_scan_bind_groups: &[ResidentBlockScanBindGroup],
    params: TokenEmitParams,
    token_block_count: u32,
    emit_phase: u32,
) {
    let phase_params = TokenEmitParams {
        scan_step: 0,
        emit_phase,
        ..params
    };
    queue.write_buffer(params_buf, 0, &token_emit_params_bytes(&phase_params));

    for (scan_step_count, step) in block_scan_bind_groups.iter().enumerate() {
        let scan_step = 1u32 << scan_step_count;
        if scan_step >= token_block_count {
            break;
        }
        let step_params = TokenEmitParams {
            scan_step,
            emit_phase,
            ..params
        };
        queue.write_buffer(&step.params_buf, 0, &token_emit_params_bytes(&step_params));
    }
}

fn record_resident_function_flags(
    encoder: &mut wgpu::CommandEncoder,
    passes: &CodegenTokenPasses,
    bufs: &ResidentCCodegenBuffers,
    token_block_count: u32,
    label_prefix: &str,
) {
    dispatch_token_blocks(
        encoder,
        &passes.function_scan,
        &bufs.function_scan_bind_group,
        &format!("{label_prefix}.scan"),
        token_block_count,
    );
    let mut scan_step = 1u32;
    let mut scan_step_count = 0usize;
    while scan_step < token_block_count {
        dispatch_token_blocks(
            encoder,
            &passes.function_scan_blocks_step,
            &bufs.function_scan_block_bind_groups[scan_step_count].bind_group,
            &format!("{label_prefix}.scan_blocks_step"),
            token_block_count,
        );
        scan_step <<= 1;
        scan_step_count += 1;
    }
    let flags_bind_group = if scan_step_count % 2 == 0 {
        &bufs.function_flags_bind_group_a
    } else {
        &bufs.function_flags_bind_group_b
    };
    dispatch_token_blocks(
        encoder,
        &passes.function_flags,
        flags_bind_group,
        &format!("{label_prefix}.flags"),
        token_block_count,
    );
}

fn record_resident_emit_phase(
    encoder: &mut wgpu::CommandEncoder,
    passes: &CodegenTokenPasses,
    bufs: &ResidentCCodegenBuffers,
    token_block_count: u32,
    label_prefix: &str,
) {
    dispatch_token_blocks(
        encoder,
        &passes.plan,
        &bufs.plan_bind_group,
        &format!("{label_prefix}.plan"),
        token_block_count,
    );
    dispatch_token_blocks(
        encoder,
        &passes.scan,
        &bufs.scan_bind_group,
        &format!("{label_prefix}.scan"),
        token_block_count,
    );
    let mut scan_step = 1u32;
    let mut scan_step_count = 0usize;
    while scan_step < token_block_count {
        dispatch_token_blocks(
            encoder,
            &passes.scan_blocks_step,
            &bufs.block_scan_bind_groups[scan_step_count].bind_group,
            &format!("{label_prefix}.scan_blocks_step"),
            token_block_count,
        );
        scan_step <<= 1;
        scan_step_count += 1;
    }
    let emit_bind_group = if scan_step_count % 2 == 0 {
        &bufs.emit_bind_group_a
    } else {
        &bufs.emit_bind_group_b
    };
    dispatch_token_blocks(
        encoder,
        &passes.emit,
        emit_bind_group,
        &format!("{label_prefix}.emit"),
        token_block_count,
    );
}

fn record_resident_top_level_emit_phase(
    encoder: &mut wgpu::CommandEncoder,
    passes: &CodegenTokenPasses,
    bufs: &ResidentCCodegenBuffers,
    token_block_count: u32,
    label_prefix: &str,
) {
    dispatch_token_blocks(
        encoder,
        &passes.plan,
        &bufs.top_level_plan_bind_group,
        &format!("{label_prefix}.plan"),
        token_block_count,
    );
    dispatch_token_blocks(
        encoder,
        &passes.scan,
        &bufs.top_level_scan_bind_group,
        &format!("{label_prefix}.scan"),
        token_block_count,
    );
    let mut scan_step = 1u32;
    let mut scan_step_count = 0usize;
    while scan_step < token_block_count {
        dispatch_token_blocks(
            encoder,
            &passes.scan_blocks_step,
            &bufs.top_level_block_scan_bind_groups[scan_step_count].bind_group,
            &format!("{label_prefix}.scan_blocks_step"),
            token_block_count,
        );
        scan_step <<= 1;
        scan_step_count += 1;
    }
    let emit_bind_group = if scan_step_count % 2 == 0 {
        &bufs.top_level_emit_bind_group_a
    } else {
        &bufs.top_level_emit_bind_group_b
    };
    dispatch_token_blocks(
        encoder,
        &passes.emit,
        emit_bind_group,
        &format!("{label_prefix}.emit"),
        token_block_count,
    );
}

async fn emit_c_on_gpu_inner(src: &str, tokens: &[Token]) -> Result<String, GpuCCodegenError> {
    let ctx = device::global();
    let device = &ctx.device;
    let queue = &ctx.queue;

    let source_bytes = nonempty_bytes(src.as_bytes());
    let token_bytes = token_bytes(tokens);
    let token_buf = storage_ro_from_bytes::<u32>(
        device,
        "codegen.c_tokens.tokens",
        &token_bytes,
        tokens.len(),
    );
    let token_count_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.token_count",
        &[tokens.len() as u32],
    );
    let source_buf = storage_ro_from_bytes::<u8>(
        device,
        "codegen.c_tokens.source",
        &source_bytes,
        source_bytes.len(),
    );
    let hir_kind_buf = storage_ro_from_u32s(device, "codegen.c_tokens.hir_kind.empty", &[0]);
    let hir_token_pos_buf =
        storage_ro_from_u32s(device, "codegen.c_tokens.hir_token_pos.empty", &[0]);
    let hir_token_end_buf =
        storage_ro_from_u32s(device, "codegen.c_tokens.hir_token_end.empty", &[0]);
    let hir_status_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    emit_c_from_gpu_token_buffer_with_hir(
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

pub fn emit_c_from_gpu_token_buffer(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    source_len: u32,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
) -> Result<String, GpuCCodegenError> {
    let hir_kind_buf = storage_ro_from_u32s(device, "codegen.c_tokens.hir_kind.empty", &[0]);
    let hir_token_pos_buf =
        storage_ro_from_u32s(device, "codegen.c_tokens.hir_token_pos.empty", &[0]);
    let hir_token_end_buf =
        storage_ro_from_u32s(device, "codegen.c_tokens.hir_token_end.empty", &[0]);
    let hir_status_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.hir_status.empty",
        &[0, 0, 0, 0, 0, 0],
    );
    emit_c_from_gpu_token_buffer_with_hir(
        device,
        queue,
        source_len,
        token_capacity,
        token_buf,
        token_count_buf,
        source_buf,
        0,
        &hir_kind_buf,
        &hir_token_pos_buf,
        &hir_token_end_buf,
        &hir_status_buf,
    )
}

pub fn emit_c_from_gpu_token_buffer_with_hir(
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
) -> Result<String, GpuCCodegenError> {
    let (segment_words, segment_meta) = pack_segments(TOKEN_EMIT_SEGMENTS);

    let output_capacity = estimate_output_capacity_from_counts(
        source_len as usize,
        token_capacity as usize,
        segment_words.len(),
    );
    let token_block_count = token_capacity.div_ceil(256).max(1);
    let params = TokenEmitParams {
        n_tokens: token_capacity,
        source_len,
        out_capacity: output_capacity as u32,
        segment_count: TOKEN_EMIT_SEGMENTS.len() as u32,
        segment_len: segment_words.len() as u32,
        block_count: token_block_count,
        scan_step: 0,
        n_hir_nodes: hir_node_capacity,
        emit_phase: EMIT_PHASE_LEGACY,
    };

    let params_buf = uniform_from_val(device, "codegen.c_tokens.params", &params);
    let segment_buf = storage_ro_from_u32s(device, "codegen.c_tokens.segments", &segment_words);
    let segment_meta_buf =
        storage_ro_from_u32s(device, "codegen.c_tokens.segment_meta", &segment_meta);
    let visible_decl_values = vec![u32::MAX; (token_capacity as usize).max(1)];
    let visible_decl_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.visible_decl.empty",
        &visible_decl_values,
    );
    let visible_type_values = vec![0u32; (token_capacity as usize).max(1)];
    let visible_type_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.visible_type.empty",
        &visible_type_values,
    );
    let call_return_type_values = vec![0u32; (token_capacity as usize).max(1)];
    let call_return_type_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.call_return_type.empty",
        &call_return_type_values,
    );
    let call_fn_index_values = vec![u32::MAX; (token_capacity as usize).max(1)];
    let call_fn_index_buf = storage_ro_from_u32s(
        device,
        "codegen.c_tokens.call_fn_index.empty",
        &call_fn_index_values,
    );
    let token_hir_role_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.token_hir_role",
        (token_capacity as usize).max(1),
        wgpu::BufferUsages::empty(),
    );
    let token_codegen_flags_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.token_codegen_flags",
        (token_capacity as usize).max(1),
        wgpu::BufferUsages::empty(),
    );
    let token_function_delta_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.token_function_delta",
        (token_capacity as usize).max(1),
        wgpu::BufferUsages::empty(),
    );
    let codegen_bounds_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.codegen_bounds",
        2,
        wgpu::BufferUsages::empty(),
    );
    let lengths_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.lengths",
        (token_capacity as usize).max(1),
        wgpu::BufferUsages::COPY_SRC,
    );
    let offsets_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.offsets",
        (token_capacity as usize).max(1),
        wgpu::BufferUsages::empty(),
    );
    let block_prefix_a = storage_u32_rw(
        device,
        "codegen.c_tokens.block_prefix_a",
        token_block_count as usize,
        wgpu::BufferUsages::empty(),
    );
    let block_prefix_b = storage_u32_rw(
        device,
        "codegen.c_tokens.block_prefix_b",
        token_block_count as usize,
        wgpu::BufferUsages::empty(),
    );
    let out_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.out_words",
        output_capacity,
        wgpu::BufferUsages::COPY_SRC,
    );
    let status_buf = storage_u32_rw(
        device,
        "codegen.c_tokens.status",
        2,
        wgpu::BufferUsages::COPY_SRC,
    );
    let out_readback = readback_u32s(device, "rb.codegen.c_tokens.out_words", output_capacity);
    let status_readback = readback_u32s(device, "rb.codegen.c_tokens.status", 2);

    let passes = codegen_token_passes(device)?;
    let clear_roles = &passes.clear_roles;
    let hir_roles = &passes.hir_roles;
    let function_scan = &passes.function_scan;
    let function_scan_blocks_step = &passes.function_scan_blocks_step;
    let function_flags = &passes.function_flags;
    let top_level_bounds = &passes.top_level_bounds;
    let plan = &passes.plan;
    let scan = &passes.scan;
    let scan_blocks_step = &passes.scan_blocks_step;
    let emit = &passes.emit;

    let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    resources.insert("gParams".into(), params_buf.as_entire_binding());
    resources.insert(
        "token_hir_role".into(),
        token_hir_role_buf.as_entire_binding(),
    );
    resources.insert(
        "token_codegen_flags".into(),
        token_codegen_flags_buf.as_entire_binding(),
    );
    resources.insert(
        "token_function_delta".into(),
        token_function_delta_buf.as_entire_binding(),
    );
    resources.insert(
        "codegen_bounds".into(),
        codegen_bounds_buf.as_entire_binding(),
    );
    resources.insert("token_words".into(), token_buf.as_entire_binding());
    resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    resources.insert("source_bytes".into(), source_buf.as_entire_binding());
    resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
    resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
    resources.insert(
        "call_fn_index".into(),
        call_fn_index_buf.as_entire_binding(),
    );
    resources.insert(
        "call_return_type".into(),
        call_return_type_buf.as_entire_binding(),
    );
    resources.insert("segments".into(), segment_buf.as_entire_binding());
    resources.insert("segment_meta".into(), segment_meta_buf.as_entire_binding());
    resources.insert("lengths".into(), lengths_buf.as_entire_binding());
    resources.insert("lengths_out".into(), lengths_buf.as_entire_binding());
    resources.insert("offsets".into(), offsets_buf.as_entire_binding());
    resources.insert("offsets_out".into(), offsets_buf.as_entire_binding());
    resources.insert("block_prefix".into(), block_prefix_a.as_entire_binding());
    resources.insert(
        "block_prefix_out".into(),
        block_prefix_a.as_entire_binding(),
    );
    resources.insert("out_words".into(), out_buf.as_entire_binding());
    resources.insert("status".into(), status_buf.as_entire_binding());

    let clear_roles_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_00_clear_roles"),
        &clear_roles.bind_group_layouts[0],
        &clear_roles.reflection,
        0,
        &resources,
    )?;

    let hir_roles_bind_group = if hir_node_capacity > 0 {
        let mut hir_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        hir_resources.insert("gParams".into(), params_buf.as_entire_binding());
        hir_resources.insert("hir_kind".into(), hir_kind_buf.as_entire_binding());
        hir_resources.insert(
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        );
        hir_resources.insert(
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        );
        hir_resources.insert("hir_status".into(), hir_status_buf.as_entire_binding());
        hir_resources.insert("token_words".into(), token_buf.as_entire_binding());
        hir_resources.insert(
            "token_hir_role".into(),
            token_hir_role_buf.as_entire_binding(),
        );
        hir_resources.insert(
            "token_function_delta".into(),
            token_function_delta_buf.as_entire_binding(),
        );
        Some(bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_01_hir_roles"),
            &hir_roles.bind_group_layouts[0],
            &hir_roles.reflection,
            0,
            &hir_resources,
        )?)
    } else {
        None
    };

    let function_scan_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_02_function_scan"),
        &function_scan.bind_group_layouts[0],
        &function_scan.reflection,
        0,
        &resources,
    )?;
    let mut function_scan_block_bind_groups = Vec::new();
    let mut function_scan_step = 1u32;
    let mut function_scan_step_count = 0usize;
    while function_scan_step < token_block_count {
        let step_params = TokenEmitParams {
            scan_step: function_scan_step,
            ..params
        };
        let step_params_buf = uniform_from_val(
            device,
            "codegen.c_tokens.function_scan_step.params",
            &step_params,
        );
        let read_from_a = function_scan_step_count % 2 == 0;
        let mut step_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        step_resources.insert("gParams".into(), step_params_buf.as_entire_binding());
        step_resources.insert(
            "block_prefix_in".into(),
            if read_from_a {
                block_prefix_a.as_entire_binding()
            } else {
                block_prefix_b.as_entire_binding()
            },
        );
        step_resources.insert(
            "block_prefix_out".into(),
            if read_from_a {
                block_prefix_b.as_entire_binding()
            } else {
                block_prefix_a.as_entire_binding()
            },
        );
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_02_function_scan_blocks_step"),
            &function_scan_blocks_step.bind_group_layouts[0],
            &function_scan_blocks_step.reflection,
            0,
            &step_resources,
        )?;
        function_scan_block_bind_groups.push((step_params_buf, bind_group));
        function_scan_step <<= 1;
        function_scan_step_count += 1;
    }
    let final_function_block_prefix_is_a = function_scan_step_count % 2 == 0;
    let mut function_flags_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    function_flags_resources.insert("gParams".into(), params_buf.as_entire_binding());
    function_flags_resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    function_flags_resources.insert("lengths".into(), lengths_buf.as_entire_binding());
    function_flags_resources.insert(
        "block_prefix".into(),
        if final_function_block_prefix_is_a {
            block_prefix_a.as_entire_binding()
        } else {
            block_prefix_b.as_entire_binding()
        },
    );
    function_flags_resources.insert(
        "token_codegen_flags".into(),
        token_codegen_flags_buf.as_entire_binding(),
    );
    let function_flags_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_02_function_flags"),
        &function_flags.bind_group_layouts[0],
        &function_flags.reflection,
        0,
        &function_flags_resources,
    )?;

    let plan_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_01_plan"),
        &plan.bind_group_layouts[0],
        &plan.reflection,
        0,
        &resources,
    )?;
    let top_level_bounds_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_02_top_level_bounds"),
        &top_level_bounds.bind_group_layouts[0],
        &top_level_bounds.reflection,
        0,
        &resources,
    )?;
    let scan_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_02_scan"),
        &scan.bind_group_layouts[0],
        &scan.reflection,
        0,
        &resources,
    )?;

    let mut block_scan_bind_groups = Vec::new();
    let mut scan_step = 1u32;
    let mut scan_step_count = 0usize;
    while scan_step < token_block_count {
        let step_params = TokenEmitParams {
            scan_step,
            ..params
        };
        let step_params_buf =
            uniform_from_val(device, "codegen.c_tokens.scan_step.params", &step_params);
        let read_from_a = scan_step_count % 2 == 0;
        let mut step_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
        step_resources.insert("gParams".into(), step_params_buf.as_entire_binding());
        step_resources.insert(
            "block_prefix_in".into(),
            if read_from_a {
                block_prefix_a.as_entire_binding()
            } else {
                block_prefix_b.as_entire_binding()
            },
        );
        step_resources.insert(
            "block_prefix_out".into(),
            if read_from_a {
                block_prefix_b.as_entire_binding()
            } else {
                block_prefix_a.as_entire_binding()
            },
        );
        let bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("codegen_c_tokens_03_scan_blocks_step"),
            &scan_blocks_step.bind_group_layouts[0],
            &scan_blocks_step.reflection,
            0,
            &step_resources,
        )?;
        block_scan_bind_groups.push((step_params_buf, bind_group));
        scan_step <<= 1;
        scan_step_count += 1;
    }

    let final_block_prefix_is_a = scan_step_count % 2 == 0;
    let mut emit_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    emit_resources.insert("gParams".into(), params_buf.as_entire_binding());
    emit_resources.insert("token_words".into(), token_buf.as_entire_binding());
    emit_resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    emit_resources.insert("source_bytes".into(), source_buf.as_entire_binding());
    emit_resources.insert("visible_decl".into(), visible_decl_buf.as_entire_binding());
    emit_resources.insert("visible_type".into(), visible_type_buf.as_entire_binding());
    emit_resources.insert(
        "call_fn_index".into(),
        call_fn_index_buf.as_entire_binding(),
    );
    emit_resources.insert(
        "call_return_type".into(),
        call_return_type_buf.as_entire_binding(),
    );
    emit_resources.insert("segments".into(), segment_buf.as_entire_binding());
    emit_resources.insert("segment_meta".into(), segment_meta_buf.as_entire_binding());
    emit_resources.insert(
        "token_hir_role".into(),
        token_hir_role_buf.as_entire_binding(),
    );
    emit_resources.insert(
        "token_codegen_flags".into(),
        token_codegen_flags_buf.as_entire_binding(),
    );
    emit_resources.insert(
        "codegen_bounds".into(),
        codegen_bounds_buf.as_entire_binding(),
    );
    emit_resources.insert("offsets".into(), offsets_buf.as_entire_binding());
    emit_resources.insert(
        "block_prefix".into(),
        if final_block_prefix_is_a {
            block_prefix_a.as_entire_binding()
        } else {
            block_prefix_b.as_entire_binding()
        },
    );
    emit_resources.insert("out_words".into(), out_buf.as_entire_binding());
    emit_resources.insert("status".into(), status_buf.as_entire_binding());
    let emit_bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("codegen_c_tokens_03_emit"),
        &emit.bind_group_layouts[0],
        &emit.reflection,
        0,
        &emit_resources,
    )?;

    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("codegen.c_tokens.encoder"),
    });
    dispatch_token_blocks(
        &mut encoder,
        clear_roles,
        &clear_roles_bind_group,
        "codegen.c_tokens.clear_roles",
        token_block_count,
    );
    if let Some(bind_group) = &hir_roles_bind_group {
        dispatch_token_blocks(
            &mut encoder,
            hir_roles,
            bind_group,
            "codegen.c_tokens.hir_roles",
            hir_node_capacity.div_ceil(256).max(1),
        );
        dispatch_token_blocks(
            &mut encoder,
            function_scan,
            &function_scan_bind_group,
            "codegen.c_tokens.function_scan",
            token_block_count,
        );
        for (_, bind_group) in &function_scan_block_bind_groups {
            dispatch_token_blocks(
                &mut encoder,
                function_scan_blocks_step,
                bind_group,
                "codegen.c_tokens.function_scan_blocks_step",
                token_block_count,
            );
        }
        dispatch_token_blocks(
            &mut encoder,
            function_flags,
            &function_flags_bind_group,
            "codegen.c_tokens.function_flags",
            token_block_count,
        );
        dispatch_token_blocks(
            &mut encoder,
            top_level_bounds,
            &top_level_bounds_bind_group,
            "codegen.c_tokens.top_level_bounds",
            token_block_count,
        );
    }
    dispatch_token_blocks(
        &mut encoder,
        plan,
        &plan_bind_group,
        "codegen.c_tokens.plan",
        token_block_count,
    );
    dispatch_token_blocks(
        &mut encoder,
        scan,
        &scan_bind_group,
        "codegen.c_tokens.scan",
        token_block_count,
    );
    for (_, bind_group) in &block_scan_bind_groups {
        dispatch_token_blocks(
            &mut encoder,
            scan_blocks_step,
            bind_group,
            "codegen.c_tokens.scan_blocks_step",
            token_block_count,
        );
    }
    dispatch_token_blocks(
        &mut encoder,
        emit,
        &emit_bind_group,
        "codegen.c_tokens.emit",
        token_block_count,
    );
    encoder.copy_buffer_to_buffer(&out_buf, 0, &out_readback, 0, (output_capacity * 4) as u64);
    encoder.copy_buffer_to_buffer(&status_buf, 0, &status_readback, 0, 8);
    queue.submit(Some(encoder.finish()));

    map_buffer(device, &status_readback);
    map_buffer(device, &out_readback);
    let _ = device.poll(wgpu::PollType::Wait);

    let status = {
        let data = status_readback.slice(..).get_mapped_range();
        let len = u32::from_le_bytes(data[0..4].try_into().unwrap()) as usize;
        let ok = u32::from_le_bytes(data[4..8].try_into().unwrap()) != 0;
        drop(data);
        status_readback.unmap();
        if !ok {
            return Err(anyhow::anyhow!(
                "GPU token C emitter produced {} bytes for capacity {} with {} tokens",
                len,
                output_capacity,
                token_capacity
            )
            .into());
        }
        len
    };

    let bytes = {
        let data = out_readback.slice(..).get_mapped_range();
        let mut bytes = Vec::with_capacity(status);
        for chunk in data.chunks_exact(4).take(status) {
            bytes.push(u32::from_le_bytes(chunk.try_into().unwrap()) as u8);
        }
        drop(data);
        out_readback.unmap();
        bytes
    };
    String::from_utf8(bytes).map_err(Into::into)
}

struct CodegenTokenPasses {
    clear_roles: PassData,
    hir_roles: PassData,
    function_scan: PassData,
    function_scan_blocks_step: PassData,
    function_flags: PassData,
    top_level_bounds: PassData,
    plan: PassData,
    scan: PassData,
    scan_blocks_step: PassData,
    emit: PassData,
}

impl CodegenTokenPasses {
    fn new(device: &wgpu::Device) -> Result<Self> {
        let clear_roles = make_pass_data(
            device,
            "codegen_c_tokens_00_clear_roles",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_00_clear_roles.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_00_clear_roles.reflect.json"
            )),
        )?;
        let hir_roles = make_pass_data(
            device,
            "codegen_c_tokens_01_hir_roles",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_01_hir_roles.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_01_hir_roles.reflect.json"
            )),
        )?;
        let function_scan = make_pass_data(
            device,
            "codegen_c_tokens_02_function_scan",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_scan.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_scan.reflect.json"
            )),
        )?;
        let function_scan_blocks_step = make_pass_data(
            device,
            "codegen_c_tokens_02_function_scan_blocks_step",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_scan_blocks_step.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_scan_blocks_step.reflect.json"
            )),
        )?;
        let function_flags = make_pass_data(
            device,
            "codegen_c_tokens_02_function_flags",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_flags.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_function_flags.reflect.json"
            )),
        )?;
        let top_level_bounds = make_pass_data(
            device,
            "codegen_c_tokens_02_top_level_bounds",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_top_level_bounds.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_top_level_bounds.reflect.json"
            )),
        )?;
        let plan = make_pass_data(
            device,
            "codegen_c_tokens_01_plan",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/c_tokens_01_plan.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_01_plan.reflect.json"
            )),
        )?;
        let scan = make_pass_data(
            device,
            "codegen_c_tokens_02_scan",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/c_tokens_02_scan.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_02_scan.reflect.json"
            )),
        )?;
        let scan_blocks_step = make_pass_data(
            device,
            "codegen_c_tokens_03_scan_blocks_step",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_03_scan_blocks_step.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_03_scan_blocks_step.reflect.json"
            )),
        )?;
        let emit = make_pass_data(
            device,
            "codegen_c_tokens_03_emit",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/c_tokens_03_emit.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/c_tokens_03_emit.reflect.json"
            )),
        )?;
        Ok(CodegenTokenPasses {
            clear_roles,
            hir_roles,
            function_scan,
            function_scan_blocks_step,
            function_flags,
            top_level_bounds,
            plan,
            scan,
            scan_blocks_step,
            emit,
        })
    }
}

fn codegen_token_passes(device: &wgpu::Device) -> Result<&'static CodegenTokenPasses> {
    static PASSES: OnceLock<Result<CodegenTokenPasses, String>> = OnceLock::new();
    PASSES
        .get_or_init(|| CodegenTokenPasses::new(device).map_err(|err| err.to_string()))
        .as_ref()
        .map_err(|err| anyhow::anyhow!("{err}"))
}

fn dispatch_token_blocks(
    encoder: &mut wgpu::CommandEncoder,
    pass: &crate::gpu::passes_core::PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    block_count: u32,
) {
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(block_count.max(1), 1, 1);
}

fn token_emit_params_bytes(params: &TokenEmitParams) -> Vec<u8> {
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(params)
        .expect("failed to encode C token emit params");
    ub.as_ref().to_vec()
}

fn read_codegen_output(
    device: &wgpu::Device,
    status_readback: &wgpu::Buffer,
    out_readback: &wgpu::Buffer,
    output_capacity: usize,
    token_capacity: u32,
) -> Result<String, GpuCCodegenError> {
    let output_bytes = (output_capacity * 4) as u64;
    status_readback
        .slice(..)
        .map_async(wgpu::MapMode::Read, |_| {});
    out_readback
        .slice(0..output_bytes)
        .map_async(wgpu::MapMode::Read, |_| {});
    let _ = device.poll(wgpu::PollType::Wait);

    let status = {
        let data = status_readback.slice(..).get_mapped_range();
        let len = u32::from_le_bytes(data[0..4].try_into().unwrap()) as usize;
        let ok = u32::from_le_bytes(data[4..8].try_into().unwrap()) != 0;
        drop(data);
        status_readback.unmap();
        if !ok {
            out_readback.unmap();
            return Err(anyhow::anyhow!(
                "GPU token C emitter produced {} bytes for capacity {} with {} tokens",
                len,
                output_capacity,
                token_capacity
            )
            .into());
        }
        len
    };

    let bytes = {
        let data = out_readback.slice(0..output_bytes).get_mapped_range();
        let mut bytes = Vec::with_capacity(status);
        for chunk in data.chunks_exact(4).take(status) {
            bytes.push(u32::from_le_bytes(chunk.try_into().unwrap()) as u8);
        }
        drop(data);
        out_readback.unmap();
        bytes
    };
    String::from_utf8(bytes).map_err(Into::into)
}

fn buffer_fingerprint(buffers: &[&wgpu::Buffer]) -> u64 {
    let mut hasher = std::collections::hash_map::DefaultHasher::new();
    for buffer in buffers {
        buffer.hash(&mut hasher);
    }
    hasher.finish()
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
        usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST | extra_usage,
        mapped_at_creation: false,
    })
}

fn readback_u32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: (count.max(1) * 4) as u64,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    })
}

fn pack_segments(segments: &[&str]) -> (Vec<u32>, Vec<u32>) {
    let mut words = Vec::new();
    let mut meta = Vec::with_capacity(segments.len() * 2);
    for segment in segments {
        meta.push(words.len() as u32);
        meta.push(segment.len() as u32);
        words.extend(segment.bytes().map(|byte| byte as u32));
    }
    (
        nonempty_u32s(words.into_iter()),
        nonempty_u32s(meta.into_iter()),
    )
}

fn nonempty_u32s(values: impl IntoIterator<Item = u32>) -> Vec<u32> {
    let mut out = values.into_iter().collect::<Vec<_>>();
    if out.is_empty() {
        out.push(0);
    }
    out
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

fn estimate_output_capacity_from_counts(
    source_len: usize,
    token_capacity: usize,
    segment_bytes: usize,
) -> usize {
    let rough = segment_bytes
        .saturating_add(source_len.saturating_mul(4))
        .saturating_add(token_capacity.saturating_mul(128))
        .saturating_add(1024);
    rough.max(4096)
}
