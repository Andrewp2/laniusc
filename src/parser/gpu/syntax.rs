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
struct SyntaxParams {
    n_tokens: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct DelimiterParams {
    n_tokens: u32,
    n_blocks: u32,
    scan_step: u32,
}

struct DelimiterScanStep {
    params: LaniusBuffer<DelimiterParams>,
    read_from_a: bool,
    write_to_a: bool,
}

pub struct GpuSyntaxChecker {
    buffers: Mutex<Option<SyntaxBufferCache>>,
}

pub struct RecordedSyntaxCheck {
    status_readback: wgpu::Buffer,
    counters_readback: wgpu::Buffer,
}

impl GpuSyntaxChecker {
    pub fn new() -> Self {
        Self {
            buffers: Mutex::new(None),
        }
    }

    pub fn check_token_buffer_on_gpu(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
    ) -> Result<(), GpuSyntaxError> {
        let mut guard = self.buffers.lock().expect("syntax checker cache poisoned");
        check_token_buffer_with_cache(
            device,
            queue,
            token_capacity,
            token_buf,
            token_count_buf,
            &mut guard,
        )
    }

    pub fn check_token_buffer_on_gpu_with_file_ids(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
    ) -> Result<(), GpuSyntaxError> {
        let mut guard = self.buffers.lock().expect("syntax checker cache poisoned");
        check_token_buffer_with_cache_and_file_ids(
            device,
            queue,
            token_capacity,
            token_buf,
            token_count_buf,
            Some(token_file_id_buf),
            &mut guard,
        )
    }

    pub fn record_token_buffer_check(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
    ) -> Result<RecordedSyntaxCheck, GpuSyntaxError> {
        let mut guard = self.buffers.lock().expect("syntax checker cache poisoned");
        record_token_buffer_check_with_cache(
            device,
            queue,
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            &mut guard,
        )
    }

    pub fn record_token_buffer_check_with_file_ids(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        encoder: &mut wgpu::CommandEncoder,
        token_capacity: u32,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        token_file_id_buf: &wgpu::Buffer,
    ) -> Result<RecordedSyntaxCheck, GpuSyntaxError> {
        let mut guard = self.buffers.lock().expect("syntax checker cache poisoned");
        record_token_buffer_check_with_cache_and_file_ids(
            device,
            queue,
            encoder,
            token_capacity,
            token_buf,
            token_count_buf,
            Some(token_file_id_buf),
            &mut guard,
        )
    }

    pub fn finish_recorded_check(
        device: &wgpu::Device,
        recorded: &RecordedSyntaxCheck,
    ) -> Result<(), GpuSyntaxError> {
        finish_recorded_check(device, recorded)
    }
}

impl Default for GpuSyntaxChecker {
    fn default() -> Self {
        Self::new()
    }
}

struct SyntaxBufferCache {
    token_capacity: u32,
    n_blocks_capacity: u32,
    params_buf: LaniusBuffer<SyntaxParams>,
    delimiter_params: LaniusBuffer<DelimiterParams>,
    delimiter_scan_steps: Vec<DelimiterScanStep>,
    depth_paren_inblock: wgpu::Buffer,
    depth_bracket_inblock: wgpu::Buffer,
    depth_brace_inblock: wgpu::Buffer,
    block_sum_paren: wgpu::Buffer,
    block_sum_bracket: wgpu::Buffer,
    block_sum_brace: wgpu::Buffer,
    prefix_paren_a: wgpu::Buffer,
    prefix_paren_b: wgpu::Buffer,
    prefix_bracket_a: wgpu::Buffer,
    prefix_bracket_b: wgpu::Buffer,
    prefix_brace_a: wgpu::Buffer,
    prefix_brace_b: wgpu::Buffer,
    block_prefix_paren: wgpu::Buffer,
    block_prefix_bracket: wgpu::Buffer,
    block_prefix_brace: wgpu::Buffer,
    default_token_file_id: LaniusBuffer<u32>,
    status_buf: wgpu::Buffer,
    counters_buf: wgpu::Buffer,
}

impl SyntaxBufferCache {
    fn new(device: &wgpu::Device, token_capacity: u32, n_blocks_capacity: u32) -> Self {
        let token_capacity = token_capacity.max(1);
        let n_blocks_capacity = n_blocks_capacity.max(1);
        let params = SyntaxParams {
            n_tokens: token_capacity,
        };
        let delimiter_params_value = DelimiterParams {
            n_tokens: token_capacity,
            n_blocks: n_blocks_capacity,
            scan_step: 0,
        };
        Self {
            token_capacity,
            n_blocks_capacity,
            params_buf: uniform_from_val(device, "parser.syntax.params", &params),
            delimiter_params: uniform_from_val(
                device,
                "parser.syntax.delimiters.params",
                &delimiter_params_value,
            ),
            delimiter_scan_steps: make_delimiter_scan_steps(
                device,
                token_capacity,
                n_blocks_capacity,
            ),
            depth_paren_inblock: storage_i32_rw(
                device,
                "parser.syntax.depth_paren_inblock",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            depth_bracket_inblock: storage_i32_rw(
                device,
                "parser.syntax.depth_bracket_inblock",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            depth_brace_inblock: storage_i32_rw(
                device,
                "parser.syntax.depth_brace_inblock",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_sum_paren: storage_i32_rw(
                device,
                "parser.syntax.block_sum_paren",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_sum_bracket: storage_i32_rw(
                device,
                "parser.syntax.block_sum_bracket",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_sum_brace: storage_i32_rw(
                device,
                "parser.syntax.block_sum_brace",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_paren_a: storage_i32_rw(
                device,
                "parser.syntax.prefix_paren_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_paren_b: storage_i32_rw(
                device,
                "parser.syntax.prefix_paren_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_bracket_a: storage_i32_rw(
                device,
                "parser.syntax.prefix_bracket_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_bracket_b: storage_i32_rw(
                device,
                "parser.syntax.prefix_bracket_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_brace_a: storage_i32_rw(
                device,
                "parser.syntax.prefix_brace_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_brace_b: storage_i32_rw(
                device,
                "parser.syntax.prefix_brace_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_prefix_paren: storage_i32_rw(
                device,
                "parser.syntax.block_prefix_paren",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_prefix_bracket: storage_i32_rw(
                device,
                "parser.syntax.block_prefix_bracket",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_prefix_brace: storage_i32_rw(
                device,
                "parser.syntax.block_prefix_brace",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            default_token_file_id: storage_ro_from_u32s(
                device,
                "parser.syntax.default_token_file_id",
                &vec![0u32; token_capacity as usize],
            ),
            status_buf: storage_u32_rw(
                device,
                "parser.syntax.status",
                4,
                wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            ),
            counters_buf: storage_i32_rw(
                device,
                "parser.syntax.counters",
                3,
                wgpu::BufferUsages::COPY_SRC | wgpu::BufferUsages::COPY_DST,
            ),
        }
    }

    fn prepare<'a>(
        cache: &'a mut Option<Self>,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        token_capacity: u32,
        n_blocks: u32,
    ) -> &'a mut Self {
        let required_tokens = token_capacity.max(1);
        let required_blocks = n_blocks.max(1);
        let needs_recreate = cache.as_ref().is_none_or(|buffers| {
            buffers.token_capacity < required_tokens || buffers.n_blocks_capacity < required_blocks
        });
        if needs_recreate {
            *cache = Some(Self::new(device, required_tokens, required_blocks));
        }
        let buffers = cache.as_mut().expect("syntax cache must be initialized");
        buffers.update_run_params(device, queue, token_capacity, n_blocks);
        buffers
    }

    fn update_run_params(
        &mut self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        token_capacity: u32,
        n_blocks: u32,
    ) {
        let syntax_params = SyntaxParams {
            n_tokens: token_capacity,
        };
        write_uniform(queue, &self.params_buf, &syntax_params);

        let delimiter_params = DelimiterParams {
            n_tokens: token_capacity,
            n_blocks,
            scan_step: 0,
        };
        write_uniform(queue, &self.delimiter_params, &delimiter_params);
        self.delimiter_scan_steps = make_delimiter_scan_steps(device, token_capacity, n_blocks);

        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());
        queue.write_buffer(&self.counters_buf, 0, &zero_i32_bytes(3));
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GpuSyntaxCode {
    UnexpectedToken,
    ExpectedToken,
    MissingSemicolon,
    StatementOverlap,
    UnbalancedDelimiter,
    Unknown(u32),
}

impl GpuSyntaxCode {
    fn from_u32(value: u32) -> Self {
        match value {
            1 => Self::UnexpectedToken,
            2 => Self::ExpectedToken,
            3 => Self::MissingSemicolon,
            4 => Self::StatementOverlap,
            5 => Self::UnbalancedDelimiter,
            other => Self::Unknown(other),
        }
    }
}

#[derive(Debug)]
pub enum GpuSyntaxError {
    Rejected {
        token: u32,
        code: GpuSyntaxCode,
        detail: u32,
    },
    Gpu(anyhow::Error),
}

impl std::fmt::Display for GpuSyntaxError {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        match self {
            GpuSyntaxError::Rejected {
                token,
                code,
                detail,
            } => {
                let compatibility = if matches!(code, GpuSyntaxCode::ExpectedToken) && *detail == 80
                {
                    " (LL(1) parser compatibility)"
                } else {
                    ""
                };
                write!(
                    f,
                    "GPU syntax parser rejected token {token}: {code:?} ({detail}){compatibility}"
                )
            }
            GpuSyntaxError::Gpu(err) => write!(f, "GPU syntax parser failed: {err}"),
        }
    }
}

impl std::error::Error for GpuSyntaxError {}

impl From<anyhow::Error> for GpuSyntaxError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

pub async fn check_tokens_on_gpu(tokens: &[Token]) -> Result<(), GpuSyntaxError> {
    check_tokens_on_gpu_inner(tokens).await
}

async fn check_tokens_on_gpu_inner(tokens: &[Token]) -> Result<(), GpuSyntaxError> {
    let ctx = device::global();
    let device = &ctx.device;
    let queue = &ctx.queue;

    let token_bytes = token_bytes(tokens);

    let token_buf =
        storage_ro_from_bytes::<u32>(device, "parser.syntax.tokens", &token_bytes, tokens.len());
    let token_count_buf =
        storage_ro_from_u32s(device, "parser.syntax.token_count", &[tokens.len() as u32]);
    check_token_buffer_on_gpu(
        device,
        queue,
        tokens.len() as u32,
        &token_buf,
        &token_count_buf,
    )
}

pub fn check_token_buffer_on_gpu(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
) -> Result<(), GpuSyntaxError> {
    let mut cache = None;
    check_token_buffer_with_cache(
        device,
        queue,
        token_capacity,
        token_buf,
        token_count_buf,
        &mut cache,
    )
}

pub fn check_token_buffer_on_gpu_with_file_ids(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    token_file_id_buf: &wgpu::Buffer,
) -> Result<(), GpuSyntaxError> {
    let mut cache = None;
    check_token_buffer_with_cache_and_file_ids(
        device,
        queue,
        token_capacity,
        token_buf,
        token_count_buf,
        Some(token_file_id_buf),
        &mut cache,
    )
}

fn check_token_buffer_with_cache(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    cache: &mut Option<SyntaxBufferCache>,
) -> Result<(), GpuSyntaxError> {
    check_token_buffer_with_cache_and_file_ids(
        device,
        queue,
        token_capacity,
        token_buf,
        token_count_buf,
        None,
        cache,
    )
}

fn check_token_buffer_with_cache_and_file_ids(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    token_file_id_buf: Option<&wgpu::Buffer>,
    cache: &mut Option<SyntaxBufferCache>,
) -> Result<(), GpuSyntaxError> {
    let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
        label: Some("parser.syntax.encoder"),
    });
    let recorded = record_token_buffer_check_with_cache_and_file_ids(
        device,
        queue,
        &mut encoder,
        token_capacity,
        token_buf,
        token_count_buf,
        token_file_id_buf,
        cache,
    )?;
    crate::gpu::passes_core::submit_with_progress(queue, "parser.syntax.batch", encoder.finish());
    finish_recorded_check(device, &recorded)
}

fn record_token_buffer_check_with_cache(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    cache: &mut Option<SyntaxBufferCache>,
) -> Result<RecordedSyntaxCheck, GpuSyntaxError> {
    record_token_buffer_check_with_cache_and_file_ids(
        device,
        queue,
        encoder,
        token_capacity,
        token_buf,
        token_count_buf,
        None,
        cache,
    )
}

fn record_token_buffer_check_with_cache_and_file_ids(
    device: &wgpu::Device,
    queue: &wgpu::Queue,
    encoder: &mut wgpu::CommandEncoder,
    token_capacity: u32,
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    token_file_id_buf: Option<&wgpu::Buffer>,
    cache: &mut Option<SyntaxBufferCache>,
) -> Result<RecordedSyntaxCheck, GpuSyntaxError> {
    let n_blocks = token_capacity.div_ceil(256).max(1);
    let buffers = SyntaxBufferCache::prepare(cache, device, queue, token_capacity, n_blocks);
    let default_token_file_id: &wgpu::Buffer = &buffers.default_token_file_id;
    let token_file_id_buf = token_file_id_buf.unwrap_or(default_token_file_id);

    let delimiter_local_pass = syntax_delimiters_01_pass(device)?;
    let delimiter_scan_pass = syntax_delimiters_02_pass(device)?;
    let pass = syntax_tokens_pass(device)?;

    let mut resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::new();
    resources.insert("gParams".into(), buffers.params_buf.as_entire_binding());
    resources.insert("token_words".into(), token_buf.as_entire_binding());
    resources.insert("token_count".into(), token_count_buf.as_entire_binding());
    resources.insert(
        "token_file_id".into(),
        token_file_id_buf.as_entire_binding(),
    );
    resources.insert("status".into(), buffers.status_buf.as_entire_binding());
    resources.insert(
        "depth_paren_inblock".into(),
        buffers.depth_paren_inblock.as_entire_binding(),
    );
    resources.insert(
        "depth_bracket_inblock".into(),
        buffers.depth_bracket_inblock.as_entire_binding(),
    );
    resources.insert(
        "depth_brace_inblock".into(),
        buffers.depth_brace_inblock.as_entire_binding(),
    );
    resources.insert(
        "block_prefix_paren".into(),
        buffers.block_prefix_paren.as_entire_binding(),
    );
    resources.insert(
        "block_prefix_bracket".into(),
        buffers.block_prefix_bracket.as_entire_binding(),
    );
    resources.insert(
        "block_prefix_brace".into(),
        buffers.block_prefix_brace.as_entire_binding(),
    );
    let bind_group = bind_group::create_bind_group_from_reflection(
        device,
        Some("parser_syntax_tokens"),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        &resources,
    )?;

    {
        let delimiter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "depth_paren_inblock".into(),
                buffers.depth_paren_inblock.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                buffers.depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "depth_brace_inblock".into(),
                buffers.depth_brace_inblock.as_entire_binding(),
            ),
            (
                "block_sum_paren".into(),
                buffers.block_sum_paren.as_entire_binding(),
            ),
            (
                "block_sum_bracket".into(),
                buffers.block_sum_bracket.as_entire_binding(),
            ),
            (
                "block_sum_brace".into(),
                buffers.block_sum_brace.as_entire_binding(),
            ),
        ]);
        let delimiter_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_delimiters_01_local"),
            &delimiter_local_pass.bind_group_layouts[0],
            &delimiter_local_pass.reflection,
            0,
            &delimiter_resources,
        )?;
        record_compute(
            encoder,
            delimiter_local_pass,
            &delimiter_bind_group,
            "parser.syntax.delimiters.local",
            n_blocks.saturating_mul(256),
        )?;
    }
    for step in &buffers.delimiter_scan_steps {
        let prefix_paren_in = if step.read_from_a {
            &buffers.prefix_paren_a
        } else {
            &buffers.prefix_paren_b
        };
        let prefix_bracket_in = if step.read_from_a {
            &buffers.prefix_bracket_a
        } else {
            &buffers.prefix_bracket_b
        };
        let prefix_brace_in = if step.read_from_a {
            &buffers.prefix_brace_a
        } else {
            &buffers.prefix_brace_b
        };
        let prefix_paren_out = if step.write_to_a {
            &buffers.prefix_paren_a
        } else {
            &buffers.prefix_paren_b
        };
        let prefix_bracket_out = if step.write_to_a {
            &buffers.prefix_bracket_a
        } else {
            &buffers.prefix_bracket_b
        };
        let prefix_brace_out = if step.write_to_a {
            &buffers.prefix_brace_a
        } else {
            &buffers.prefix_brace_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            (
                "block_sum_paren".into(),
                buffers.block_sum_paren.as_entire_binding(),
            ),
            (
                "block_sum_bracket".into(),
                buffers.block_sum_bracket.as_entire_binding(),
            ),
            (
                "block_sum_brace".into(),
                buffers.block_sum_brace.as_entire_binding(),
            ),
            (
                "prefix_paren_in".into(),
                prefix_paren_in.as_entire_binding(),
            ),
            (
                "prefix_bracket_in".into(),
                prefix_bracket_in.as_entire_binding(),
            ),
            (
                "prefix_brace_in".into(),
                prefix_brace_in.as_entire_binding(),
            ),
            (
                "prefix_paren_out".into(),
                prefix_paren_out.as_entire_binding(),
            ),
            (
                "prefix_bracket_out".into(),
                prefix_bracket_out.as_entire_binding(),
            ),
            (
                "prefix_brace_out".into(),
                prefix_brace_out.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                buffers.block_prefix_paren.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                buffers.block_prefix_bracket.as_entire_binding(),
            ),
            (
                "block_prefix_brace".into(),
                buffers.block_prefix_brace.as_entire_binding(),
            ),
            ("counters".into(), buffers.counters_buf.as_entire_binding()),
        ]);
        let scan_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_delimiters_02_scan_blocks"),
            &delimiter_scan_pass.bind_group_layouts[0],
            &delimiter_scan_pass.reflection,
            0,
            &scan_resources,
        )?;
        record_compute(
            encoder,
            delimiter_scan_pass,
            &scan_bind_group,
            "parser.syntax.delimiters.scan",
            n_blocks,
        )?;
    }
    {
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("parser.syntax.pass"),
            timestamp_writes: None,
        });
        compute.set_pipeline(&pass.pipeline);
        compute.set_bind_group(0, Some(&bind_group), &[]);
        let (gx, gy, gz) = plan_compute(pass, token_capacity.max(512))?;
        compute.dispatch_workgroups(gx, gy, gz);
    }
    let status_readback = readback_u32s(device, "rb.parser.syntax.status", 4);
    let counters_readback = readback_i32s(device, "rb.parser.syntax.counters", 3);
    encoder.copy_buffer_to_buffer(&buffers.status_buf, 0, &status_readback, 0, 16);
    encoder.copy_buffer_to_buffer(&buffers.counters_buf, 0, &counters_readback, 0, 12);
    Ok(RecordedSyntaxCheck {
        status_readback,
        counters_readback,
    })
}

fn finish_recorded_check(
    device: &wgpu::Device,
    recorded: &RecordedSyntaxCheck,
) -> Result<(), GpuSyntaxError> {
    let status_slice = recorded.status_readback.slice(..);
    let counters_slice = recorded.counters_readback.slice(..);
    crate::gpu::passes_core::map_readback_for_progress(&status_slice, "parser.syntax.status");
    crate::gpu::passes_core::map_readback_for_progress(&counters_slice, "parser.syntax.counters");
    crate::gpu::passes_core::wait_for_map_progress(
        device,
        "parser.syntax.recorded-check",
        wgpu::PollType::Wait,
    );

    let status_words = {
        let mapped = status_slice.get_mapped_range();
        let words = read_status_words(&mapped)?;
        drop(mapped);
        recorded.status_readback.unmap();
        words
    };
    let counters = {
        let mapped = counters_slice.get_mapped_range();
        let words = read_counter_words(&mapped)?;
        drop(mapped);
        recorded.counters_readback.unmap();
        words
    };

    if status_words[0] == 0 {
        return Err(GpuSyntaxError::Rejected {
            token: status_words[1],
            code: GpuSyntaxCode::from_u32(status_words[2]),
            detail: status_words[3],
        });
    }
    if let Some((idx, value)) = counters
        .into_iter()
        .enumerate()
        .find(|(_, value)| *value != 0)
    {
        return Err(GpuSyntaxError::Rejected {
            token: 0,
            code: GpuSyntaxCode::UnbalancedDelimiter,
            detail: ((idx as u32) << 16) | (value as u32 & 0xffff),
        });
    }
    Ok(())
}

fn syntax_tokens_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "parser_syntax_tokens",
            "main",
            include_bytes!(concat!(env!("OUT_DIR"), "/shaders/syntax_tokens.spv")),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/syntax_tokens.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_delimiters_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "parser_syntax_delimiters_01_local",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/syntax_delimiters_01_local.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/syntax_delimiters_01_local.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_delimiters_02_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        make_pass_data(
            device,
            "parser_syntax_delimiters_02_scan_blocks",
            "main",
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/syntax_delimiters_02_scan_blocks.spv"
            )),
            include_bytes!(concat!(
                env!("OUT_DIR"),
                "/shaders/syntax_delimiters_02_scan_blocks.reflect.json"
            )),
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn make_delimiter_scan_steps(
    device: &wgpu::Device,
    n_tokens: u32,
    n_blocks: u32,
) -> Vec<DelimiterScanStep> {
    let mut steps = Vec::new();
    let base = DelimiterParams {
        n_tokens,
        n_blocks,
        scan_step: 0,
    };
    steps.push(DelimiterScanStep {
        params: uniform_from_val(device, "parser.syntax.delimiter_scan.params.init", &base),
        read_from_a: false,
        write_to_a: true,
    });

    let mut step = 1u32;
    let mut step_count = 0u32;
    while step < n_blocks {
        let read_from_a = step_count % 2 == 0;
        steps.push(DelimiterScanStep {
            params: uniform_from_val(
                device,
                "parser.syntax.delimiter_scan.params.step",
                &DelimiterParams {
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
    steps.push(DelimiterScanStep {
        params: uniform_from_val(
            device,
            "parser.syntax.delimiter_scan.params.finalize",
            &DelimiterParams {
                scan_step: n_blocks,
                ..base
            },
        ),
        read_from_a,
        write_to_a: !read_from_a,
    });
    steps
}

fn plan_compute(pass: &PassData, n_elements: u32) -> Result<(u32, u32, u32)> {
    let [tgsx, tgsy, _] = pass.thread_group_size;
    plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [tgsx, tgsy, 1],
    )
}

fn record_compute(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    n_elements: u32,
) -> Result<()> {
    let (gx, gy, gz) = plan_compute(pass, n_elements)?;
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

fn zero_i32_bytes(count: usize) -> Vec<u8> {
    std::iter::repeat_n(0i32, count)
        .flat_map(i32::to_le_bytes)
        .collect()
}

fn write_uniform<T>(queue: &wgpu::Queue, buffer: &LaniusBuffer<T>, value: &T)
where
    T: encase::ShaderType + encase::internal::WriteInto,
{
    let mut ub = encase::UniformBuffer::new(Vec::<u8>::new());
    ub.write(value)
        .expect("failed to write syntax uniform buffer");
    queue.write_buffer(buffer, 0, ub.as_ref());
}

fn read_status_words(bytes: &[u8]) -> Result<[u32; 4]> {
    if bytes.len() < 16 {
        return Err(anyhow!("syntax parser status readback was truncated"));
    }
    Ok([
        u32::from_le_bytes(bytes[0..4].try_into().unwrap()),
        u32::from_le_bytes(bytes[4..8].try_into().unwrap()),
        u32::from_le_bytes(bytes[8..12].try_into().unwrap()),
        u32::from_le_bytes(bytes[12..16].try_into().unwrap()),
    ])
}

fn read_counter_words(bytes: &[u8]) -> Result<[i32; 3]> {
    if bytes.len() < 12 {
        return Err(anyhow!("syntax parser counter readback was truncated"));
    }
    Ok([
        i32::from_le_bytes(bytes[0..4].try_into().unwrap()),
        i32::from_le_bytes(bytes[4..8].try_into().unwrap()),
        i32::from_le_bytes(bytes[8..12].try_into().unwrap()),
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

fn readback_i32s(device: &wgpu::Device, label: &str, count: usize) -> wgpu::Buffer {
    readback_u32s(device, label, count)
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
