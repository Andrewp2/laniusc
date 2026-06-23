//! Standalone GPU syntax checks over lexer token buffers.

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
        passes_core::{DispatchDim, InputElements, PassData, bind_group, plan_workgroups},
    },
    lexer::types::Token,
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

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct MinTreeParams {
    n_blocks: u32,
    leaf_base: u32,
    start_node: u32,
    node_count: u32,
    mode: u32,
    _pad0: u32,
    _pad1: u32,
    _pad2: u32,
}

struct DelimiterScanStep {
    params: LaniusBuffer<DelimiterParams>,
    read_from_a: bool,
    write_to_a: bool,
}

struct MinTreeBuildStep {
    params: LaniusBuffer<MinTreeParams>,
    work_items: u32,
}

/// Reusable GPU syntax checker with a resident buffer cache.
pub struct GpuSyntaxChecker {
    buffers: Mutex<Option<SyntaxBufferCache>>,
}

/// Deferred syntax-check status readback.
pub struct RecordedSyntaxCheck {
    readback: wgpu::Buffer,
}

impl GpuSyntaxChecker {
    /// Creates a syntax checker with an empty resident buffer cache.
    pub fn new() -> Self {
        Self {
            buffers: Mutex::new(None),
        }
    }

    /// Checks a token buffer on the GPU and reads status before returning.
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

    /// Checks a token buffer with source-file ids on the GPU.
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

    /// Records a syntax check into an existing command encoder.
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

    /// Records a syntax check with source-file ids into an existing command encoder.
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

    /// Finishes a recorded syntax check and returns an error on rejection.
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
    depth_paren_inblock: LaniusBuffer<i32>,
    depth_bracket_inblock: LaniusBuffer<i32>,
    depth_brace_inblock: LaniusBuffer<i32>,
    depth_angle_inblock: LaniusBuffer<i32>,
    block_sum_paren: LaniusBuffer<i32>,
    block_sum_bracket: LaniusBuffer<i32>,
    block_sum_brace: LaniusBuffer<i32>,
    block_sum_angle: LaniusBuffer<i32>,
    prefix_paren_a: LaniusBuffer<i32>,
    prefix_paren_b: LaniusBuffer<i32>,
    prefix_bracket_a: LaniusBuffer<i32>,
    prefix_bracket_b: LaniusBuffer<i32>,
    prefix_brace_a: LaniusBuffer<i32>,
    prefix_brace_b: LaniusBuffer<i32>,
    prefix_angle_a: LaniusBuffer<i32>,
    prefix_angle_b: LaniusBuffer<i32>,
    block_prefix_paren: LaniusBuffer<i32>,
    block_prefix_bracket: LaniusBuffer<i32>,
    block_prefix_brace: LaniusBuffer<i32>,
    block_prefix_angle: LaniusBuffer<i32>,
    statement_context_event_block: LaniusBuffer<u32>,
    statement_context_event_prefix_a: LaniusBuffer<u32>,
    statement_context_event_prefix_b: LaniusBuffer<u32>,
    statement_context_event_block_prefix: LaniusBuffer<u32>,
    statement_context_kind: LaniusBuffer<u32>,
    statement_context_scan_steps: Vec<DelimiterScanStep>,
    impl_context_event_block: LaniusBuffer<u32>,
    impl_context_event_prefix_a: LaniusBuffer<u32>,
    impl_context_event_prefix_b: LaniusBuffer<u32>,
    impl_context_event_block_prefix: LaniusBuffer<u32>,
    token_impl_header_kind: LaniusBuffer<u32>,
    token_impl_context_event: LaniusBuffer<u32>,
    impl_context_scan_steps: Vec<DelimiterScanStep>,
    trait_context_event_block: LaniusBuffer<u32>,
    trait_context_event_prefix_a: LaniusBuffer<u32>,
    trait_context_event_prefix_b: LaniusBuffer<u32>,
    trait_context_event_block_prefix: LaniusBuffer<u32>,
    trait_context_event: LaniusBuffer<u32>,
    trait_context_scan_steps: Vec<DelimiterScanStep>,
    paren_match_depth: LaniusBuffer<i32>,
    paren_match_block_min: LaniusBuffer<i32>,
    paren_match_min_tree: LaniusBuffer<i32>,
    angle_match_depth: LaniusBuffer<i32>,
    angle_match_block_min: LaniusBuffer<i32>,
    angle_match_min_tree: LaniusBuffer<i32>,
    paren_match_min_tree_steps: Vec<MinTreeBuildStep>,
    default_token_file_id: LaniusBuffer<u32>,
    status_buf: LaniusBuffer<u32>,
    counters_buf: LaniusBuffer<i32>,
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
        let paren_match_min_tree_leaf_base = next_power_of_two_u32(n_blocks_capacity).max(1);
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
            depth_angle_inblock: storage_i32_rw(
                device,
                "parser.syntax.depth_angle_inblock",
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
            block_sum_angle: storage_i32_rw(
                device,
                "parser.syntax.block_sum_angle",
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
            prefix_angle_a: storage_i32_rw(
                device,
                "parser.syntax.prefix_angle_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            prefix_angle_b: storage_i32_rw(
                device,
                "parser.syntax.prefix_angle_b",
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
            block_prefix_angle: storage_i32_rw(
                device,
                "parser.syntax.block_prefix_angle",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            block_prefix_brace: storage_i32_rw(
                device,
                "parser.syntax.block_prefix_brace",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            statement_context_event_block: storage_u32_rw(
                device,
                "parser.syntax.statement_context_event_block",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            statement_context_event_prefix_a: storage_u32_rw(
                device,
                "parser.syntax.statement_context_event_prefix_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            statement_context_event_prefix_b: storage_u32_rw(
                device,
                "parser.syntax.statement_context_event_prefix_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            statement_context_event_block_prefix: storage_u32_rw(
                device,
                "parser.syntax.statement_context_event_block_prefix",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            statement_context_kind: storage_u32_rw(
                device,
                "parser.syntax.statement_context_kind",
                token_capacity as usize,
                wgpu::BufferUsages::COPY_DST,
            ),
            statement_context_scan_steps: make_delimiter_scan_steps(
                device,
                token_capacity,
                n_blocks_capacity,
            ),
            impl_context_event_block: storage_u32_rw(
                device,
                "parser.syntax.impl_context_event_block",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            impl_context_event_prefix_a: storage_u32_rw(
                device,
                "parser.syntax.impl_context_event_prefix_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            impl_context_event_prefix_b: storage_u32_rw(
                device,
                "parser.syntax.impl_context_event_prefix_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            impl_context_event_block_prefix: storage_u32_rw(
                device,
                "parser.syntax.impl_context_event_block_prefix",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            token_impl_header_kind: storage_u32_rw(
                device,
                "parser.syntax.token_impl_header_kind",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            token_impl_context_event: storage_u32_rw(
                device,
                "parser.syntax.token_impl_context_event",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            impl_context_scan_steps: make_delimiter_scan_steps(
                device,
                token_capacity,
                n_blocks_capacity,
            ),
            trait_context_event_block: storage_u32_rw(
                device,
                "parser.syntax.trait_context_event_block",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            trait_context_event_prefix_a: storage_u32_rw(
                device,
                "parser.syntax.trait_context_event_prefix_a",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            trait_context_event_prefix_b: storage_u32_rw(
                device,
                "parser.syntax.trait_context_event_prefix_b",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            trait_context_event_block_prefix: storage_u32_rw(
                device,
                "parser.syntax.trait_context_event_block_prefix",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            trait_context_event: storage_u32_rw(
                device,
                "parser.syntax.trait_context_event",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            trait_context_scan_steps: make_delimiter_scan_steps(
                device,
                token_capacity,
                n_blocks_capacity,
            ),
            paren_match_depth: storage_i32_rw(
                device,
                "parser.syntax.paren_match_depth",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            paren_match_block_min: storage_i32_rw(
                device,
                "parser.syntax.paren_match_block_min",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            paren_match_min_tree: storage_i32_rw(
                device,
                "parser.syntax.paren_match_min_tree",
                paren_match_min_tree_leaf_base.saturating_mul(2) as usize,
                wgpu::BufferUsages::empty(),
            ),
            angle_match_depth: storage_i32_rw(
                device,
                "parser.syntax.angle_match_depth",
                token_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            angle_match_block_min: storage_i32_rw(
                device,
                "parser.syntax.angle_match_block_min",
                n_blocks_capacity as usize,
                wgpu::BufferUsages::empty(),
            ),
            angle_match_min_tree: storage_i32_rw(
                device,
                "parser.syntax.angle_match_min_tree",
                paren_match_min_tree_leaf_base.saturating_mul(2) as usize,
                wgpu::BufferUsages::empty(),
            ),
            paren_match_min_tree_steps: make_min_tree_build_steps(
                device,
                n_blocks_capacity,
                paren_match_min_tree_leaf_base,
            ),
            default_token_file_id: storage_u32_rw(
                device,
                "parser.syntax.default_token_file_id",
                token_capacity as usize,
                wgpu::BufferUsages::COPY_DST,
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
        self.statement_context_scan_steps =
            make_delimiter_scan_steps(device, token_capacity, n_blocks);
        self.impl_context_scan_steps = make_delimiter_scan_steps(device, token_capacity, n_blocks);
        self.trait_context_scan_steps = make_delimiter_scan_steps(device, token_capacity, n_blocks);
        self.paren_match_min_tree_steps =
            make_min_tree_build_steps(device, n_blocks, next_power_of_two_u32(n_blocks).max(1));

        queue.write_buffer(&self.status_buf, 0, &status_init_bytes());
        queue.write_buffer(&self.counters_buf, 0, &zero_i32_bytes(3));
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
/// GPU syntax status code decoded from the syntax status buffer.
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

    fn description(self) -> String {
        match self {
            Self::UnexpectedToken => "unexpected token".to_string(),
            Self::ExpectedToken => "expected another token".to_string(),
            Self::MissingSemicolon => "missing semicolon".to_string(),
            Self::StatementOverlap => "statement boundaries overlap".to_string(),
            Self::UnbalancedDelimiter => "unbalanced delimiter".to_string(),
            Self::Unknown(code) => format!("unknown syntax error (code {code})"),
        }
    }
}

#[derive(Debug)]
/// Error returned by standalone GPU syntax checking.
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
            GpuSyntaxError::Rejected { code, .. } => {
                write!(f, "syntax error: {}", code.description())
            }
            GpuSyntaxError::Gpu(_) => {
                f.write_str("syntax analysis failed before syntax status could be decoded")
            }
        }
    }
}

impl std::error::Error for GpuSyntaxError {}

#[cfg(test)]
mod tests {
    use super::{GpuSyntaxCode, GpuSyntaxError};

    #[test]
    fn gpu_syntax_error_display_is_user_facing() {
        let error = GpuSyntaxError::Rejected {
            token: 4,
            code: GpuSyntaxCode::MissingSemicolon,
            detail: 9,
        };

        let message = error.to_string();
        assert_eq!(message, "syntax error: missing semicolon");
        assert!(!message.contains("GPU"));
        assert!(!message.contains("near token"));
        assert!(!message.contains("status token"));
    }

    #[test]
    fn gpu_syntax_backend_error_display_omits_internal_detail() {
        let error = GpuSyntaxError::Gpu(anyhow::anyhow!(
            "parser.syntax.status readback failed"
        ));

        let message = error.to_string();
        assert_eq!(
            message,
            "syntax analysis failed before syntax status could be decoded"
        );
        assert!(!message.contains("GPU"));
        assert!(!message.contains("readback"));
        assert!(!message.contains("parser.syntax.status"));
    }
}

impl From<anyhow::Error> for GpuSyntaxError {
    fn from(err: anyhow::Error) -> Self {
        Self::Gpu(err)
    }
}

/// Checks an in-memory token slice with the global GPU device.
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

/// Checks an existing token buffer without reusing a checker cache.
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

/// Checks an existing token buffer plus source-file ids without reusing a checker cache.
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
    let token_file_id_buf = if let Some(token_file_id_buf) = token_file_id_buf {
        token_file_id_buf
    } else {
        encoder.clear_buffer(&buffers.default_token_file_id, 0, None);
        &buffers.default_token_file_id
    };

    let delimiter_local_pass = syntax_delimiters_01_pass(device)?;
    let delimiter_scan_pass = syntax_delimiters_02_pass(device)?;
    let statement_context_local_pass = syntax_statement_context_01_pass(device)?;
    let statement_context_scan_pass = syntax_statement_context_02_pass(device)?;
    let statement_context_apply_pass = syntax_statement_context_03_pass(device)?;
    let impl_context_local_pass = syntax_impl_context_01_pass(device)?;
    let impl_context_scan_pass = syntax_impl_context_02_pass(device)?;
    let impl_context_apply_pass = syntax_impl_context_03_pass(device)?;
    let trait_context_local_pass = syntax_trait_context_01_pass(device)?;
    let trait_context_scan_pass = syntax_trait_context_02_pass(device)?;
    let trait_context_apply_pass = syntax_trait_context_03_pass(device)?;
    let paren_match_pass = syntax_paren_match_01_pass(device)?;
    let angle_match_pass = syntax_angle_match_01_pass(device)?;
    let min_tree_pass = syntax_match_min_tree_pass(device)?;
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
        "depth_angle_inblock".into(),
        buffers.depth_angle_inblock.as_entire_binding(),
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
    resources.insert(
        "block_prefix_angle".into(),
        buffers.block_prefix_angle.as_entire_binding(),
    );
    resources.insert(
        "paren_match_depth".into(),
        buffers.paren_match_depth.as_entire_binding(),
    );
    resources.insert(
        "paren_match_block_min".into(),
        buffers.paren_match_block_min.as_entire_binding(),
    );
    resources.insert(
        "paren_match_min_tree".into(),
        buffers.paren_match_min_tree.as_entire_binding(),
    );
    resources.insert(
        "angle_match_depth".into(),
        buffers.angle_match_depth.as_entire_binding(),
    );
    resources.insert(
        "angle_match_block_min".into(),
        buffers.angle_match_block_min.as_entire_binding(),
    );
    resources.insert(
        "angle_match_min_tree".into(),
        buffers.angle_match_min_tree.as_entire_binding(),
    );
    resources.insert(
        "statement_context_kind".into(),
        buffers.statement_context_kind.as_entire_binding(),
    );
    resources.insert(
        "token_impl_context_event".into(),
        buffers.token_impl_context_event.as_entire_binding(),
    );
    resources.insert(
        "trait_context_event".into(),
        buffers.trait_context_event.as_entire_binding(),
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
                "depth_angle_inblock".into(),
                buffers.depth_angle_inblock.as_entire_binding(),
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
            (
                "block_sum_angle".into(),
                buffers.block_sum_angle.as_entire_binding(),
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
        let prefix_angle_in = if step.read_from_a {
            &buffers.prefix_angle_a
        } else {
            &buffers.prefix_angle_b
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
        let prefix_angle_out = if step.write_to_a {
            &buffers.prefix_angle_a
        } else {
            &buffers.prefix_angle_b
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
                "block_sum_angle".into(),
                buffers.block_sum_angle.as_entire_binding(),
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
                "prefix_angle_in".into(),
                prefix_angle_in.as_entire_binding(),
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
                "prefix_angle_out".into(),
                prefix_angle_out.as_entire_binding(),
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
            (
                "block_prefix_angle".into(),
                buffers.block_prefix_angle.as_entire_binding(),
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
    encoder.clear_buffer(&buffers.statement_context_kind, 0, None);
    {
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                buffers.depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                buffers.block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                buffers.statement_context_kind.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                buffers.statement_context_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_statement_context_01_local"),
            &statement_context_local_pass.bind_group_layouts[0],
            &statement_context_local_pass.reflection,
            0,
            &local_resources,
        )?;
        record_compute(
            encoder,
            statement_context_local_pass,
            &local_bind_group,
            "parser.syntax.statement_context.local",
            n_blocks.saturating_mul(256),
        )?;

        for step in &buffers.statement_context_scan_steps {
            let prefix_in = if step.read_from_a {
                &buffers.statement_context_event_prefix_a
            } else {
                &buffers.statement_context_event_prefix_b
            };
            let prefix_out = if step.write_to_a {
                &buffers.statement_context_event_prefix_a
            } else {
                &buffers.statement_context_event_prefix_b
            };
            let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "trait_context_event_block".into(),
                    buffers.statement_context_event_block.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_in".into(),
                    prefix_in.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_out".into(),
                    prefix_out.as_entire_binding(),
                ),
                (
                    "trait_context_event_block_prefix".into(),
                    buffers
                        .statement_context_event_block_prefix
                        .as_entire_binding(),
                ),
            ]);
            let scan_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("parser_syntax_statement_context_02_scan"),
                &statement_context_scan_pass.bind_group_layouts[0],
                &statement_context_scan_pass.reflection,
                0,
                &scan_resources,
            )?;
            record_compute(
                encoder,
                statement_context_scan_pass,
                &scan_bind_group,
                "parser.syntax.statement_context.scan",
                n_blocks,
            )?;
        }

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_bracket_inblock".into(),
                buffers.depth_bracket_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_bracket".into(),
                buffers.block_prefix_bracket.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                buffers
                    .statement_context_event_block_prefix
                    .as_entire_binding(),
            ),
            (
                "statement_context_kind".into(),
                buffers.statement_context_kind.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_statement_context_03_apply"),
            &statement_context_apply_pass.bind_group_layouts[0],
            &statement_context_apply_pass.reflection,
            0,
            &apply_resources,
        )?;
        record_compute(
            encoder,
            statement_context_apply_pass,
            &apply_bind_group,
            "parser.syntax.statement_context.apply",
            n_blocks.saturating_mul(256),
        )?;
    }
    {
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block".into(),
                buffers.impl_context_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_impl_context_01_local"),
            &impl_context_local_pass.bind_group_layouts[0],
            &impl_context_local_pass.reflection,
            0,
            &local_resources,
        )?;
        record_compute(
            encoder,
            impl_context_local_pass,
            &local_bind_group,
            "parser.syntax.impl_context.local",
            n_blocks.saturating_mul(256),
        )?;

        for step in &buffers.impl_context_scan_steps {
            let prefix_in = if step.read_from_a {
                &buffers.impl_context_event_prefix_a
            } else {
                &buffers.impl_context_event_prefix_b
            };
            let prefix_out = if step.write_to_a {
                &buffers.impl_context_event_prefix_a
            } else {
                &buffers.impl_context_event_prefix_b
            };
            let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "trait_context_event_block".into(),
                    buffers.impl_context_event_block.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_in".into(),
                    prefix_in.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_out".into(),
                    prefix_out.as_entire_binding(),
                ),
                (
                    "trait_context_event_block_prefix".into(),
                    buffers.impl_context_event_block_prefix.as_entire_binding(),
                ),
            ]);
            let scan_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("parser_syntax_impl_context_02_scan"),
                &impl_context_scan_pass.bind_group_layouts[0],
                &impl_context_scan_pass.reflection,
                0,
                &scan_resources,
            )?;
            record_compute(
                encoder,
                impl_context_scan_pass,
                &scan_bind_group,
                "parser.syntax.impl_context.scan",
                n_blocks,
            )?;
        }

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "statement_event_block_prefix".into(),
                buffers.impl_context_event_block_prefix.as_entire_binding(),
            ),
            (
                "token_impl_header_kind".into(),
                buffers.token_impl_header_kind.as_entire_binding(),
            ),
            (
                "token_impl_context_event".into(),
                buffers.token_impl_context_event.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_impl_context_03_apply"),
            &impl_context_apply_pass.bind_group_layouts[0],
            &impl_context_apply_pass.reflection,
            0,
            &apply_resources,
        )?;
        record_compute(
            encoder,
            impl_context_apply_pass,
            &apply_bind_group,
            "parser.syntax.impl_context.apply",
            n_blocks.saturating_mul(256),
        )?;
    }
    {
        let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "trait_context_event_block".into(),
                buffers.trait_context_event_block.as_entire_binding(),
            ),
        ]);
        let local_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_trait_context_01_local"),
            &trait_context_local_pass.bind_group_layouts[0],
            &trait_context_local_pass.reflection,
            0,
            &local_resources,
        )?;
        record_compute(
            encoder,
            trait_context_local_pass,
            &local_bind_group,
            "parser.syntax.trait_context.local",
            n_blocks.saturating_mul(256),
        )?;

        for step in &buffers.trait_context_scan_steps {
            let prefix_in = if step.read_from_a {
                &buffers.trait_context_event_prefix_a
            } else {
                &buffers.trait_context_event_prefix_b
            };
            let prefix_out = if step.write_to_a {
                &buffers.trait_context_event_prefix_a
            } else {
                &buffers.trait_context_event_prefix_b
            };
            let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gParams".into(), step.params.as_entire_binding()),
                (
                    "trait_context_event_block".into(),
                    buffers.trait_context_event_block.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_in".into(),
                    prefix_in.as_entire_binding(),
                ),
                (
                    "trait_context_event_prefix_out".into(),
                    prefix_out.as_entire_binding(),
                ),
                (
                    "trait_context_event_block_prefix".into(),
                    buffers.trait_context_event_block_prefix.as_entire_binding(),
                ),
            ]);
            let scan_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("parser_syntax_trait_context_02_scan"),
                &trait_context_scan_pass.bind_group_layouts[0],
                &trait_context_scan_pass.reflection,
                0,
                &scan_resources,
            )?;
            record_compute(
                encoder,
                trait_context_scan_pass,
                &scan_bind_group,
                "parser.syntax.trait_context.scan",
                n_blocks,
            )?;
        }

        let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            (
                "gParams".into(),
                buffers.delimiter_params.as_entire_binding(),
            ),
            ("token_words".into(), token_buf.as_entire_binding()),
            ("token_count".into(), token_count_buf.as_entire_binding()),
            (
                "trait_context_event_block_prefix".into(),
                buffers.trait_context_event_block_prefix.as_entire_binding(),
            ),
            (
                "trait_context_event".into(),
                buffers.trait_context_event.as_entire_binding(),
            ),
        ]);
        let apply_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_trait_context_03_apply"),
            &trait_context_apply_pass.bind_group_layouts[0],
            &trait_context_apply_pass.reflection,
            0,
            &apply_resources,
        )?;
        record_compute(
            encoder,
            trait_context_apply_pass,
            &apply_bind_group,
            "parser.syntax.trait_context.apply",
            n_blocks.saturating_mul(256),
        )?;
    }
    {
        let paren_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), buffers.params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_paren_inblock".into(),
                buffers.depth_paren_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_paren".into(),
                buffers.block_prefix_paren.as_entire_binding(),
            ),
            (
                "paren_match_depth".into(),
                buffers.paren_match_depth.as_entire_binding(),
            ),
            (
                "paren_match_block_min".into(),
                buffers.paren_match_block_min.as_entire_binding(),
            ),
        ]);
        let paren_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_paren_match_01_depth_blocks"),
            &paren_match_pass.bind_group_layouts[0],
            &paren_match_pass.reflection,
            0,
            &paren_resources,
        )?;
        record_compute(
            encoder,
            paren_match_pass,
            &paren_bind_group,
            "parser.syntax.paren_match.depth_blocks",
            n_blocks.saturating_mul(256),
        )?;

        for step in &buffers.paren_match_min_tree_steps {
            let tree_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    buffers.paren_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    buffers.paren_match_min_tree.as_entire_binding(),
                ),
            ]);
            let tree_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("parser_syntax_paren_match_02_build_min_tree"),
                &min_tree_pass.bind_group_layouts[0],
                &min_tree_pass.reflection,
                0,
                &tree_resources,
            )?;
            record_compute(
                encoder,
                min_tree_pass,
                &tree_bind_group,
                "parser.syntax.paren_match.build_min_tree",
                step.work_items,
            )?;
        }
    }
    {
        let angle_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), buffers.params_buf.as_entire_binding()),
            ("token_words".into(), token_buf.as_entire_binding()),
            (
                "lexer_token_count".into(),
                token_count_buf.as_entire_binding(),
            ),
            (
                "depth_angle_inblock".into(),
                buffers.depth_angle_inblock.as_entire_binding(),
            ),
            (
                "block_prefix_angle".into(),
                buffers.block_prefix_angle.as_entire_binding(),
            ),
            (
                "angle_match_depth".into(),
                buffers.angle_match_depth.as_entire_binding(),
            ),
            (
                "angle_match_block_min".into(),
                buffers.angle_match_block_min.as_entire_binding(),
            ),
        ]);
        let angle_bind_group = bind_group::create_bind_group_from_reflection(
            device,
            Some("parser_syntax_angle_match_01_depth_blocks"),
            &angle_match_pass.bind_group_layouts[0],
            &angle_match_pass.reflection,
            0,
            &angle_resources,
        )?;
        record_compute(
            encoder,
            angle_match_pass,
            &angle_bind_group,
            "parser.syntax.angle_match.depth_blocks",
            n_blocks.saturating_mul(256),
        )?;

        for step in &buffers.paren_match_min_tree_steps {
            let tree_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
                ("gMinTree".into(), step.params.as_entire_binding()),
                (
                    "brace_match_block_min".into(),
                    buffers.angle_match_block_min.as_entire_binding(),
                ),
                (
                    "brace_match_min_tree".into(),
                    buffers.angle_match_min_tree.as_entire_binding(),
                ),
            ]);
            let tree_bind_group = bind_group::create_bind_group_from_reflection(
                device,
                Some("parser_syntax_angle_match_02_build_min_tree"),
                &min_tree_pass.bind_group_layouts[0],
                &min_tree_pass.reflection,
                0,
                &tree_resources,
            )?;
            record_compute(
                encoder,
                min_tree_pass,
                &tree_bind_group,
                "parser.syntax.angle_match.build_min_tree",
                step.work_items,
            )?;
        }
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
    let readback = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some("rb.parser.syntax.status_counters"),
        size: 28,
        usage: wgpu::BufferUsages::COPY_DST | wgpu::BufferUsages::MAP_READ,
        mapped_at_creation: false,
    });
    encoder.copy_buffer_to_buffer(&buffers.status_buf, 0, &readback, 0, 16);
    encoder.copy_buffer_to_buffer(&buffers.counters_buf, 0, &readback, 16, 12);
    Ok(RecordedSyntaxCheck { readback })
}

fn finish_recorded_check(
    device: &wgpu::Device,
    recorded: &RecordedSyntaxCheck,
) -> Result<(), GpuSyntaxError> {
    let slice = recorded.readback.slice(..);
    crate::gpu::passes_core::map_readback_blocking(
        device,
        &slice,
        "parser.syntax.status_counters",
    )?;

    let mapped = slice.get_mapped_range();
    let result = finish_recorded_check_mapped(&mapped);
    drop(mapped);
    recorded.readback.unmap();
    result
}

fn finish_recorded_check_mapped(bytes: &[u8]) -> Result<(), GpuSyntaxError> {
    if bytes.len() < 28 {
        return Err(GpuSyntaxError::Gpu(anyhow::anyhow!(
            "syntax parser readback was truncated: expected at least 28 bytes, got {}",
            bytes.len()
        )));
    }

    let status_words = read_status_words(&bytes[0..16])?;
    let counters = read_counter_words(&bytes[16..28])?;

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
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_tokens",
            shader: "parser/syntax/tokens"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_delimiters_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_delimiters_01_local",
            shader: "parser/syntax/delimiters/01_local"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_delimiters_02_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_delimiters_02_scan_blocks",
            shader: "parser/syntax/delimiters/02_scan_blocks"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_statement_context_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_statement_context_01_local",
            shader: "parser/tokens/statement/phase/01_local"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_statement_context_02_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_statement_context_02_scan",
            shader: "parser/tokens/trait/context/02_scan"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_statement_context_03_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_statement_context_03_apply",
            shader: "parser/tokens/statement/phase/02_apply"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_impl_context_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_impl_context_01_local",
            shader: "parser/tokens/impl/header/01_local"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_impl_context_02_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_impl_context_02_scan",
            shader: "parser/tokens/trait/context/02_scan"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_impl_context_03_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_impl_context_03_apply",
            shader: "parser/tokens/impl/header/02_apply"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_trait_context_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_trait_context_01_local",
            shader: "parser/tokens/trait/context/01_local"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_trait_context_02_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_trait_context_02_scan",
            shader: "parser/tokens/trait/context/02_scan"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_trait_context_03_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_trait_context_03_apply",
            shader: "parser/tokens/trait/context/03_apply"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_paren_match_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_paren_match_01_depth_blocks",
            shader: "parser/tokens/paren_match_01_depth_blocks"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_angle_match_01_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_angle_match_01_depth_blocks",
            shader: "parser/tokens/angle_match_01_depth_blocks"
        )
        .map_err(|err| err.to_string())
    })
    .as_ref()
    .map_err(|err| anyhow!("{err}"))
}

fn syntax_match_min_tree_pass(device: &wgpu::Device) -> Result<&'static PassData> {
    static PASS: OnceLock<Result<PassData, String>> = OnceLock::new();
    PASS.get_or_init(|| {
        crate::gpu::passes_core::make_main_pass!(
            device,
            "parser_syntax_paren_match_02_build_min_tree",
            shader: "parser/tokens/brace/match/02_build_min_tree"
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

fn make_min_tree_build_steps(
    device: &wgpu::Device,
    n_blocks: u32,
    leaf_base: u32,
) -> Vec<MinTreeBuildStep> {
    let mut steps = Vec::new();
    steps.push(MinTreeBuildStep {
        params: uniform_from_val(
            device,
            "parser.syntax.paren_match_min_tree.params.leaves",
            &MinTreeParams {
                n_blocks,
                leaf_base,
                start_node: 0,
                node_count: leaf_base,
                mode: 0,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0,
            },
        ),
        work_items: leaf_base,
    });

    let mut start_node = leaf_base / 2;
    while start_node > 0 {
        steps.push(MinTreeBuildStep {
            params: uniform_from_val(
                device,
                "parser.syntax.paren_match_min_tree.params.combine",
                &MinTreeParams {
                    n_blocks,
                    leaf_base,
                    start_node,
                    node_count: start_node,
                    mode: 1,
                    _pad0: 0,
                    _pad1: 0,
                    _pad2: 0,
                },
            ),
            work_items: start_node,
        });

        if start_node == 1 {
            break;
        }
        start_node >>= 1;
    }
    steps
}

fn next_power_of_two_u32(value: u32) -> u32 {
    value.max(1).next_power_of_two()
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
    crate::gpu::readback::read_u32_words(bytes, "syntax parser status")
}

fn read_counter_words(bytes: &[u8]) -> Result<[i32; 3]> {
    crate::gpu::readback::read_i32_words(bytes, "syntax parser counter")
}

fn storage_u32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<u32> {
    let byte_size = (count.max(1) * 4) as u64;
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size,
        usage: wgpu::BufferUsages::STORAGE | extra_usage,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((raw, byte_size), count)
}

fn storage_i32_rw(
    device: &wgpu::Device,
    label: &str,
    count: usize,
    extra_usage: wgpu::BufferUsages,
) -> LaniusBuffer<i32> {
    let byte_size = (count.max(1) * 4) as u64;
    let raw = device.create_buffer(&wgpu::BufferDescriptor {
        label: Some(label),
        size: byte_size,
        usage: wgpu::BufferUsages::STORAGE | extra_usage,
        mapped_at_creation: false,
    });
    LaniusBuffer::new((raw, byte_size), count)
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
