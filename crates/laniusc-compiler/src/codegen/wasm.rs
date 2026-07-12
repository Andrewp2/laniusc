//! GPU WASM backend boundary.
//!
//! The WASM backend consumes the same parser HIR and retained type-check
//! metadata shape as other backends. It records target-specific GPU passes and
//! reports fail-closed backend status for unsupported shapes.

use std::{
    collections::HashMap,
    fmt,
    sync::{
        Arc,
        Mutex,
        atomic::{AtomicBool, Ordering},
    },
    time::{Duration, Instant},
};

use anyhow::{Context, Result, anyhow};
use encase::ShaderType;

mod support;
use support::*;

use crate::{
    gpu::{
        buffers::LaniusBuffer,
        device,
        passes_core::{bgls_from_reflection, bind_group, pipeline_from_spirv_and_bgls},
    },
    reflection::{SlangReflection, parse_reflection_from_bytes},
};

const WASM_ASSERT_OUTPUT_TARGET_LIMIT: u32 = 512;
const WASM_FUNCTION_REACHABILITY_ITERATIONS: u32 = 64;
const WASM_BODY_PLAN_FINALIZE_GROUPS: u32 = 1;
const WASM_BODY_STATUS_GROUPS: u32 = 1;
const WASM_MODULE_STATUS_GROUPS: u32 = 1;
const WASM_BODY_PLAN_WORDS: usize = 40;
const ERR_UNSUPPORTED_SOURCE_SHAPE: u32 = 1;
const WASM_BODY_PLAN_FEATURE_MASK: usize = 35;
const WASM_BODY_FEATURE_EXPR_CONTROL: u32 = 1 << 0;
const WASM_BODY_FEATURE_DIRECT: u32 = 1 << 1;
const WASM_BODY_FEATURE_HOST: u32 = 1 << 2;
const WASM_BODY_FEATURE_ARRAYS: u32 = 1 << 3;
const WASM_BODY_FEATURE_MEMBER_EXPR: u32 = 1 << 4;
const WASM_BODY_FEATURE_BINARY_DIRECT: u32 = 1 << 5;
const WASM_BODY_FEATURE_LET_DIRECT: u32 = 1 << 6;
const WASM_BODY_FEATURE_RETURN_NESTED_DIRECT: u32 = 1 << 7;
const WASM_BODY_FEATURE_RETURN_DIRECT: u32 = 1 << 8;
const WASM_BODY_FEATURE_LET_AGG_DIRECT: u32 = 1 << 9;
const WASM_BODY_FEATURE_RETURN_AGG_DIRECT: u32 = 1 << 10;
const WASM_BODY_FEATURE_AGG_COPY: u32 = 1 << 11;
const WASM_BODY_FEATURE_ARRAY_ALLOC: u32 = 1 << 12;
const WASM_BODY_FEATURE_ASSIGN: u32 = 1 << 13;
const WASM_BODY_FEATURE_CONTROL: u32 = 1 << 14;
const WASM_BODY_FEATURE_STMT_CALL: u32 = 1 << 15;
const WASM_BODY_FEATURE_HOST_BASIC: u32 = 1 << 16;
const WASM_BODY_FEATURE_HOST_ENV: u32 = 1 << 17;
const WASM_BODY_FEATURE_HOST_IO: u32 = 1 << 18;
const WASM_BODY_FEATURE_HOST_VOID: u32 = 1 << 19;
const WASM_BODY_FEATURE_STMT_PRINT: u32 = 1 << 20;
const WASM_BODY_FEATURE_STMT_HOST_VOID: u32 = 1 << 21;
const WASM_BODY_FEATURE_STMT_PRINT_DIRECT: u32 = 1 << 22;
const WASM_BODY_FEATURE_CONTROL_IF_SIMPLE: u32 = 1 << 23;
const WASM_BODY_FEATURE_HOST_IO_I32: u32 = 1 << 24;
const WASM_BODY_FEATURE_HOST_IO_STRING: u32 = 1 << 25;
const WASM_BODY_FEATURE_HOST_IO_RETURN: u32 = 1 << 26;
const WASM_BODY_FEATURE_RETURN_SCALAR: u32 = 1 << 27;
const WASM_BODY_FEATURE_LET_CONST: u32 = 1 << 28;
const WASM_BODY_FEATURE_RETURN_MEMBER_EXPR: u32 = 1 << 29;
const WASM_BODY_FEATURE_MEMBER_EXPR_SCATTER: u32 = 1 << 30;
const WASM_BODY_FEATURE_RETURN_EXPR: u32 = 1u32 << 31;

#[derive(Clone, Copy, Debug, Default)]
struct WasmBodyFeatures {
    mask: u32,
}

impl WasmBodyFeatures {
    fn from_body_plan(words: &[u32; WASM_BODY_PLAN_WORDS]) -> Self {
        Self {
            mask: words[WASM_BODY_PLAN_FEATURE_MASK],
        }
    }

    fn has(self, bit: u32) -> bool {
        self.mask & bit != 0
    }
}

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

fn wasm_output_error_from_status(error_code: u32, error_detail: u32) -> WasmOutputError {
    let error_name = match error_code {
        2 => "unsupported for loop",
        3 => "unsupported WASM body HIR-node budget",
        830 => "unsupported array-helper body token budget",
        831 => "unsupported array-helper body HIR-node budget",
        800..=899 => "unsupported array-helper body shape",
        902 => "retired enum-match module token budget",
        903 => "retired enum-match module HIR-node budget",
        900..=999 => "unsupported retired enum-match module shape",
        _ => "unsupported source shape",
    };
    WasmOutputError::new(error_name, error_code, error_detail)
}

struct LazyWasmPass {
    stage: &'static str,
    label: &'static str,
    entry: &'static str,
    spirv: Arc<Vec<u8>>,
    bind_group_layouts: Vec<Arc<wgpu::BindGroupLayout>>,
    reflection: Arc<SlangReflection>,
    pipeline: Mutex<Option<Arc<wgpu::ComputePipeline>>>,
    pipeline_cache_dirty: Arc<AtomicBool>,
    device: Arc<wgpu::Device>,
}

impl LazyWasmPass {
    fn from_artifacts(
        device: &Arc<wgpu::Device>,
        stage: &'static str,
        label: &'static str,
        spv: &'static str,
        reflection: &'static str,
        pipeline_cache_dirty: Arc<AtomicBool>,
    ) -> Result<Self> {
        let spv_path = crate::shader_artifacts::artifact_path(spv);
        let reflection_path = crate::shader_artifacts::artifact_path(reflection);
        let spirv = std::fs::read(&spv_path)
            .map_err(|err| anyhow!("read shader SPIR-V {}: {err}", spv_path.display()))?;
        let reflection_json = std::fs::read(&reflection_path).map_err(|err| {
            anyhow!(
                "read shader reflection {}: {err}",
                reflection_path.display()
            )
        })?;
        let reflection: SlangReflection =
            parse_reflection_from_bytes(&reflection_json).map_err(anyhow::Error::msg)?;
        let bind_group_layouts = bgls_from_reflection(device, &reflection)?
            .into_iter()
            .map(Arc::new)
            .collect();
        Ok(Self {
            stage,
            label,
            entry: "main",
            spirv: Arc::new(spirv),
            bind_group_layouts,
            reflection: Arc::new(reflection),
            pipeline: Mutex::new(None),
            pipeline_cache_dirty,
            device: device.clone(),
        })
    }

    fn pipeline(&self) -> Result<Arc<wgpu::ComputePipeline>> {
        let mut pipeline = self
            .pipeline
            .lock()
            .map_err(|_| anyhow!("WASM pass {} pipeline lock poisoned", self.stage))?;
        if let Some(pipeline) = pipeline.as_ref() {
            return Ok(pipeline.clone());
        }

        trace_wasm_codegen(&format!("{}.pipeline.start", self.stage));
        let start = Instant::now();
        let bgl_refs: Vec<&wgpu::BindGroupLayout> = self
            .bind_group_layouts
            .iter()
            .map(|layout| layout.as_ref())
            .collect();
        let created = pipeline_from_spirv_and_bgls(
            &self.device,
            self.label,
            self.entry,
            &self.spirv,
            &bgl_refs,
        );
        let end = Instant::now();
        let dt_ms = end.duration_since(start).as_secs_f64() * 1000.0;
        if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
            eprintln!(
                "[gpu_compile_host_timer] codegen.wasm.pipeline.{}: {:.3}ms",
                self.stage, dt_ms
            );
        }
        if crate::gpu::trace::enabled() {
            crate::gpu::trace::record_host_span(
                "host.wasm.pipeline",
                &format!("codegen.wasm.pipeline.{}", self.stage),
                start,
                end,
            );
        }
        trace_wasm_codegen(&format!("{}.pipeline.done", self.stage));
        let created = Arc::new(created);
        *pipeline = Some(created.clone());
        self.pipeline_cache_dirty.store(true, Ordering::Release);
        // A single complex driver pipeline can take longer than the compile
        // timeout. Checkpoint expensive creations immediately so a later
        // pipeline timeout does not discard all cold-start progress. Keep
        // cheap pipelines batched behind the normal phase boundary.
        if end.duration_since(start) >= Duration::from_secs(1) {
            device::persist_pipeline_cache_for_device(&self.device);
            self.pipeline_cache_dirty.store(false, Ordering::Release);
        }
        Ok(created)
    }
}

fn create_wasm_bind_group<'a>(
    device: &wgpu::Device,
    label: Option<&str>,
    pass: &LazyWasmPass,
    set_index: usize,
    bindings: &[(&str, wgpu::BindingResource<'a>)],
) -> Result<wgpu::BindGroup> {
    let resources: HashMap<String, wgpu::BindingResource<'a>> = bindings
        .iter()
        .map(|(name, resource)| ((*name).to_string(), resource.clone()))
        .collect();
    bind_group::create_bind_group_from_reflection(
        device,
        label,
        &pass.bind_group_layouts[set_index],
        &pass.reflection,
        set_index,
        &resources,
    )
    .with_context(|| {
        format!(
            "create WASM bind group {} for pass {}",
            label.unwrap_or("<unnamed>"),
            pass.stage
        )
    })
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmParams {
    n_tokens: u32,
    source_len: u32,
    out_capacity: u32,
    n_hir_nodes: u32,
}

#[repr(C)]
#[derive(Clone, Copy, ShaderType)]
struct WasmScanParams {
    n_items: u32,
    n_blocks: u32,
    scan_step: u32,
    out_capacity: u32,
}

/// Recorded WASM backend work and retained capacity metadata for readback.
pub struct RecordedWasmCodegen {
    output_capacity: usize,
    token_capacity: u32,
}

#[derive(Clone, Copy, Debug, Eq, PartialEq)]
/// Declared read/write boundary for one WASM recording stage.
pub struct WasmRecordBoundary {
    pub stage: &'static str,
    pub reads: &'static [&'static str],
    pub writes: &'static [&'static str],
}

const WASM_RECORD_BOUNDARIES: &[WasmRecordBoundary] = &[
    WasmRecordBoundary {
        stage: "agg_layout_clear",
        reads: &["wasm_params"],
        writes: &["aggregate_layout_records"],
    },
    WasmRecordBoundary {
        stage: "agg_layout",
        reads: &["hir_records", "struct_records", "aggregate_layout_records"],
        writes: &["aggregate_layout_records"],
    },
    WasmRecordBoundary {
        stage: "const_values",
        reads: &["hir_status", "hir_expr_records", "hir_stmt_records"],
        writes: &["wasm_const_value_records"],
    },
    WasmRecordBoundary {
        stage: "hir_body_let_init_clear",
        reads: &["wasm_params"],
        writes: &["wasm_body_let_init_expr_by_decl_token"],
    },
    WasmRecordBoundary {
        stage: "hir_body_let_init",
        reads: &["hir_status", "hir_records", "hir_stmt_records"],
        writes: &["wasm_body_let_init_expr_by_decl_token"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_clear",
        reads: &["wasm_params"],
        writes: &["wasm_function_records"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_mark",
        reads: &["hir_records", "hir_param_records", "typecheck_records"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_reach",
        reads: &[
            "hir_records",
            "call_records",
            "path_records",
            "typecheck_records",
            "wasm_function_records",
        ],
        writes: &["wasm_function_records"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_count",
        reads: &["wasm_function_records"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_func_scan_local",
        reads: &["wasm_function_flags"],
        writes: &[
            "wasm_function_scan_local_prefix",
            "wasm_function_scan_block_sum",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_func_scan_blocks",
        reads: &[
            "wasm_function_scan_block_sum",
            "wasm_function_scan_prefix_a",
            "wasm_function_scan_prefix_b",
        ],
        writes: &["wasm_function_scan_prefix_a", "wasm_function_scan_prefix_b"],
    },
    WasmRecordBoundary {
        stage: "hir_functions_scatter",
        reads: &["wasm_function_flags", "wasm_function_scan_prefixes"],
        writes: &["wasm_function_slots"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_collect",
        reads: &[
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
        ],
        writes: &["wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_validate",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_agg_direct_call",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_agg_struct",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_arrays",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_functions",
        reads: &["wasm_function_records", "wasm_body_plan"],
        writes: &["wasm_function_records", "wasm_body_plan"],
    },
    WasmRecordBoundary {
        stage: "hir_body_plan_finalize",
        reads: &["wasm_body_plan"],
        writes: &["wasm_body_plan", "wasm_body_status", "wasm_status"],
    },
    WasmRecordBoundary {
        stage: "hir_body_clear",
        reads: &["wasm_params"],
        writes: &[
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_plan",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_body_counts",
        reads: &[
            "wasm_body_plan",
            "hir_records",
            "typecheck_records",
            "call_records",
            "wasm_const_value_records",
            "wasm_body_let_init_expr_by_decl_token",
        ],
        writes: &[
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
        ],
    },
    WasmRecordBoundary {
        stage: "hir_body_scan_local",
        reads: &["wasm_body_fragment_len"],
        writes: &["wasm_body_scan_local_prefix", "wasm_body_scan_block_sum"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scan_blocks",
        reads: &[
            "wasm_body_scan_block_sum",
            "wasm_body_scan_prefix_a",
            "wasm_body_scan_prefix_b",
        ],
        writes: &["wasm_body_scan_prefix_a", "wasm_body_scan_prefix_b"],
    },
    WasmRecordBoundary {
        stage: "hir_body_status",
        reads: &["wasm_body_scan_block_prefix", "wasm_status"],
        writes: &["wasm_body_status", "wasm_status"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_expr_control",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_range_control",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_let_direct",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_direct_nested_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_host_io",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_host",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_arrays",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_copy",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_array_lean",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_agg_direct_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_body_scatter_binary_direct_call",
        reads: &[
            "wasm_params",
            "wasm_body_fragment_len",
            "wasm_body_fragment_meta",
            "wasm_body_fragment_aux",
            "wasm_body_scan_local_prefix",
            "wasm_body_scan_block_prefix",
            "wasm_status",
        ],
        writes: &["wasm_body_words"],
    },
    WasmRecordBoundary {
        stage: "hir_agg_body",
        reads: &["wasm_status"],
        writes: &[],
    },
    WasmRecordBoundary {
        stage: "hir_enum_match_records",
        reads: &["hir_match_records"],
        writes: &["wasm_enum_match_records"],
    },
    WasmRecordBoundary {
        stage: "module_status",
        reads: &["wasm_params", "wasm_body_status", "wasm_status"],
        writes: &["wasm_status"],
    },
    WasmRecordBoundary {
        stage: "module",
        reads: &[
            "wasm_params",
            "wasm_body_words",
            "wasm_body_status",
            "wasm_status",
        ],
        writes: &["wasm_module_words"],
    },
    WasmRecordBoundary {
        stage: "hir_assert_module",
        reads: &["wasm_status"],
        writes: &[],
    },
    WasmRecordBoundary {
        stage: "pack_output",
        reads: &["wasm_module_words", "wasm_status"],
        writes: &["wasm_packed_words", "wasm_status"],
    },
];

/// Returns the current WASM recording stages and their buffer read/write roles.
pub fn wasm_record_boundaries() -> &'static [WasmRecordBoundary] {
    WASM_RECORD_BOUNDARIES
}

#[derive(Debug)]
/// Target-level error reported by the GPU WASM emitter.
pub struct WasmOutputError {
    error_name: &'static str,
    error_code: u32,
    error_detail: u32,
}

impl WasmOutputError {
    /// Creates a target-level WASM output error from backend status fields.
    pub(super) fn new(error_name: &'static str, error_code: u32, error_detail: u32) -> Self {
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

    /// Returns whether `error_detail` should be interpreted as a token index.
    pub fn detail_is_token(&self) -> bool {
        self.error_detail != u32::MAX
            && (self.error_code == 1
                || self.error_code == 2
                || ((800..=899).contains(&self.error_code)
                    && !matches!(self.error_code, 830 | 831)))
    }
}

impl fmt::Display for WasmOutputError {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.write_str("WASM code generation reached an unsupported backend boundary")
    }
}

impl std::error::Error for WasmOutputError {}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn wasm_output_error_display_is_user_facing() {
        let error = WasmOutputError::new("unsupported_struct_literal", 830, 27);
        let rendered = error.to_string();

        assert_eq!(
            rendered,
            "WASM code generation reached an unsupported backend boundary"
        );
        assert!(!rendered.contains("GPU"));
        assert!(!rendered.contains("emitter rejected"));
        assert!(!rendered.contains("unsupported_struct_literal"));
        assert!(!rendered.contains("code 830"));
        assert!(!rendered.contains("detail 27"));
    }

    #[test]
    fn wasm_output_error_public_message_humanizes_backend_status() {
        let error = WasmOutputError::new("unsupported_struct_literal", 830, 27);

        let message = error.public_message();
        assert_eq!(message, "unsupported struct literal");
        assert!(!message.contains("unsupported_struct_literal"));
        assert!(!message.contains("830"));
        assert!(!message.contains("27"));
    }

    #[test]
    fn wasm_output_error_marks_unsupported_shape_detail_as_token() {
        let error = WasmOutputError::new("unsupported source shape", 1, 5);
        assert!(error.detail_is_token());

        let missing = WasmOutputError::new("unsupported source shape", 1, u32::MAX);
        assert!(!missing.detail_is_token());
    }
}

#[derive(Clone, Copy)]
/// Struct declaration/member metadata buffers needed by WASM lowering.
pub struct GpuWasmStructMetadataBuffers<'a> {
    pub member_receiver_node: &'a wgpu::Buffer,
    pub struct_decl_field_count: &'a wgpu::Buffer,
    pub lit_field_parent_lit: &'a wgpu::Buffer,
    pub lit_context_stmt_node: &'a wgpu::Buffer,
    pub lit_field_start: &'a wgpu::Buffer,
    pub lit_field_count: &'a wgpu::Buffer,
    pub lit_field_value_node: &'a wgpu::Buffer,
    pub lit_field_next: &'a wgpu::Buffer,
    pub member_name_token: &'a wgpu::Buffer,
    pub member_result_field_ordinal: &'a wgpu::Buffer,
    pub member_result_field_node: &'a wgpu::Buffer,
    pub struct_init_field_ordinal_by_node: &'a wgpu::Buffer,
    pub struct_init_field_decl_node_by_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Enum-match metadata buffers needed by WASM lowering.
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
/// Call and call-argument metadata buffers needed by WASM lowering.
pub struct GpuWasmCallMetadataBuffers<'a> {
    pub callee_node: &'a wgpu::Buffer,
    pub context_stmt: &'a wgpu::Buffer,
    pub arg_start: &'a wgpu::Buffer,
    pub arg_parent_call: &'a wgpu::Buffer,
    pub arg_end: &'a wgpu::Buffer,
    pub arg_count: &'a wgpu::Buffer,
    pub arg_ordinal: &'a wgpu::Buffer,
    pub param_row_count_out: &'a wgpu::Buffer,
    pub param_row_fn_token: &'a wgpu::Buffer,
    pub param_row_ordinal: &'a wgpu::Buffer,
    pub param_row_type: &'a wgpu::Buffer,
    pub param_row_start: &'a wgpu::Buffer,
    pub param_row_count: &'a wgpu::Buffer,
    pub arg_row_node: &'a wgpu::Buffer,
    pub arg_row_call_node: &'a wgpu::Buffer,
    pub arg_row_ordinal: &'a wgpu::Buffer,
    pub arg_row_start: &'a wgpu::Buffer,
    pub arg_row_count: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Expression and statement metadata buffers needed by WASM lowering.
pub struct GpuWasmExprMetadataBuffers<'a> {
    pub record: &'a wgpu::Buffer,
    pub result_root_node: &'a wgpu::Buffer,
    pub int_value: &'a wgpu::Buffer,
    pub float_bits: &'a wgpu::Buffer,
    pub string_start: &'a wgpu::Buffer,
    pub string_len: &'a wgpu::Buffer,
    pub stmt_record: &'a wgpu::Buffer,
    pub nearest_stmt_node: &'a wgpu::Buffer,
    pub nearest_block_node: &'a wgpu::Buffer,
    pub nearest_enclosing_control_node: &'a wgpu::Buffer,
    pub nearest_loop_node: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Parser-owned array metadata buffers needed by WASM lowering.
pub struct GpuWasmArrayMetadataBuffers<'a> {
    pub lit_first_element: &'a wgpu::Buffer,
    pub lit_element_count: &'a wgpu::Buffer,
    pub lit_context_stmt_node: &'a wgpu::Buffer,
    pub element_parent_lit: &'a wgpu::Buffer,
    pub element_ordinal: &'a wgpu::Buffer,
    pub element_next: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Qualified path metadata buffers needed by WASM lowering.
pub struct GpuWasmPathMetadataBuffers<'a> {
    pub count_out: &'a wgpu::Buffer,
    pub segment_count: &'a wgpu::Buffer,
    pub segment_base: &'a wgpu::Buffer,
    pub segment_token: &'a wgpu::Buffer,
    pub id_by_owner_hir: &'a wgpu::Buffer,
}

#[derive(Clone, Copy)]
/// Dense semantic-HIR tree buffers needed by WASM lowering.
pub struct GpuWasmSemanticHirBuffers<'a> {
    pub count: &'a wgpu::Buffer,
    pub prefix_before_node: &'a wgpu::Buffer,
    pub dense_node: &'a wgpu::Buffer,
    pub subtree_end: &'a wgpu::Buffer,
    pub parent: &'a wgpu::Buffer,
    pub first_child: &'a wgpu::Buffer,
    pub next_sibling: &'a wgpu::Buffer,
    pub depth: &'a wgpu::Buffer,
    pub child_index: &'a wgpu::Buffer,
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
    _hir_enum_match_record_buf: LaniusBuffer<u32>,
    wasm_const_value_record_buf: LaniusBuffer<u32>,
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
    hir_body_plan_validate_if_simple_bind_group: wgpu::BindGroup,
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
    hir_body_scatter_if_simple_bind_group: wgpu::BindGroup,
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
    hir_body_scatter_arrays_bind_group: wgpu::BindGroup,
    hir_body_scatter_array_lean_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_copy_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_call_args_bind_group: wgpu::BindGroup,
    hir_body_scatter_nested_call_args_bind_group: wgpu::BindGroup,
    hir_body_scatter_agg_direct_call_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_agg_direct_call_bind_group: wgpu::BindGroup,
    hir_body_scatter_return_member_bind_group: wgpu::BindGroup,
    hir_body_scatter_member_expr_bind_group: wgpu::BindGroup,
    hir_body_scatter_binary_direct_call_bind_group: wgpu::BindGroup,
    hir_agg_body_bind_group: wgpu::BindGroup,
    hir_assert_module_bind_group: wgpu::BindGroup,
    hir_enum_match_records_bind_group: wgpu::BindGroup,
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
    hir_body_plan_validate_pass: LazyWasmPass,
    hir_body_plan_validate_return_pass: LazyWasmPass,
    hir_body_plan_validate_return_call_pass: LazyWasmPass,
    hir_body_plan_validate_return_agg_call_pass: LazyWasmPass,
    hir_body_plan_validate_return_nested_call_pass: LazyWasmPass,
    hir_body_plan_validate_assign_pass: LazyWasmPass,
    hir_body_plan_validate_control_pass: LazyWasmPass,
    hir_body_plan_validate_agg_range_control_pass: LazyWasmPass,
    hir_body_plan_validate_if_simple_pass: LazyWasmPass,
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
    hir_body_scatter_if_simple_pass: LazyWasmPass,
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
    hir_body_scatter_arrays_pass: LazyWasmPass,
    hir_body_scatter_array_lean_pass: LazyWasmPass,
    hir_body_scatter_agg_copy_pass: LazyWasmPass,
    hir_body_scatter_agg_direct_call_pass: LazyWasmPass,
    hir_body_scatter_nested_call_args_pass: LazyWasmPass,
    hir_body_scatter_return_agg_direct_call_pass: LazyWasmPass,
    hir_body_scatter_return_member_pass: LazyWasmPass,
    hir_body_scatter_member_expr_pass: LazyWasmPass,
    hir_body_scatter_binary_direct_call_pass: LazyWasmPass,
    hir_agg_body_pass: LazyWasmPass,
    hir_assert_module_pass: LazyWasmPass,
    hir_enum_match_records_pass: LazyWasmPass,
    wasm_const_values_pass: LazyWasmPass,
    module_type_lengths_pass: LazyWasmPass,
    module_type_dispatch_args_pass: LazyWasmPass,
    module_type_bytes_pass: LazyWasmPass,
    module_status_pass: LazyWasmPass,
    pass: LazyWasmPass,
    pack_pass: LazyWasmPass,
    pipeline_cache_dirty: Arc<AtomicBool>,
    buffers: Mutex<Option<ResidentWasmBuffers>>,
}

impl GpuWasmCodeGenerator {
    /// Loads all WASM backend compute passes for a GPU device.
    pub fn new_with_device(gpu: &device::GpuDevice) -> Result<Self> {
        let pipeline_cache_dirty = Arc::new(AtomicBool::new(false));
        macro_rules! wasm_pass {
            ($stage:literal, $label:literal, $spv:literal, $reflection:literal) => {{
                let device = gpu.device.clone();
                let pipeline_cache_dirty = pipeline_cache_dirty.clone();
                std::thread::spawn(move || {
                    LazyWasmPass::from_artifacts(
                        &device,
                        $stage,
                        $label,
                        $spv,
                        $reflection,
                        pipeline_cache_dirty,
                    )
                })
            }};
        }
        macro_rules! join_wasm_pass {
            ($handle:ident, $stage:literal) => {{
                let pass = $handle
                    .join()
                    .map_err(|_| anyhow!("WASM pass {} initialization panicked", $stage))??;
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
        let hir_body_plan_validate_if_simple_pass = wasm_pass!(
            "hir_body_plan_validate_if_simple",
            "codegen_wasm_hir_body_plan_validate_if_simple",
            "codegen/wasm/hir/body_plan_validate_if_simple.spv",
            "codegen/wasm/hir/body_plan_validate_if_simple.reflect.json"
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
        let hir_body_scatter_if_simple_pass = wasm_pass!(
            "hir_body_scatter_if_simple",
            "codegen_wasm_hir_body_scatter_if_simple",
            "codegen/wasm/hir/body_scatter_if_simple.spv",
            "codegen/wasm/hir/body_scatter_if_simple.reflect.json"
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
        let hir_body_scatter_arrays_pass = wasm_pass!(
            "hir_body_scatter_arrays",
            "codegen_wasm_hir_body_scatter_arrays",
            "codegen/wasm/hir/body_scatter_arrays.spv",
            "codegen/wasm/hir/body_scatter_arrays.reflect.json"
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
        let hir_body_scatter_member_expr_pass = wasm_pass!(
            "hir_body_scatter_member_expr",
            "codegen_wasm_hir_body_scatter_member_expr",
            "codegen/wasm/hir/body_scatter_member_expr.spv",
            "codegen/wasm/hir/body_scatter_member_expr.reflect.json"
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
        let hir_enum_match_records_pass = wasm_pass!(
            "hir_enum_match_records",
            "codegen_wasm_hir_enum_match_records",
            "codegen/wasm/hir/enum_match_records.spv",
            "codegen/wasm/hir/enum_match_records.reflect.json"
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
            hir_body_plan_validate_if_simple_pass: join_wasm_pass!(
                hir_body_plan_validate_if_simple_pass,
                "hir_body_plan_validate_if_simple"
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
            hir_body_scatter_if_simple_pass: join_wasm_pass!(
                hir_body_scatter_if_simple_pass,
                "hir_body_scatter_if_simple"
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
            hir_body_scatter_arrays_pass: join_wasm_pass!(
                hir_body_scatter_arrays_pass,
                "hir_body_scatter_arrays"
            ),
            hir_body_scatter_array_lean_pass: join_wasm_pass!(
                hir_body_scatter_array_lean_pass,
                "hir_body_scatter_array_lean"
            ),
            hir_body_scatter_agg_copy_pass: join_wasm_pass!(
                hir_body_scatter_agg_copy_pass,
                "hir_body_scatter_agg_copy"
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
            hir_body_scatter_member_expr_pass: join_wasm_pass!(
                hir_body_scatter_member_expr_pass,
                "hir_body_scatter_member_expr"
            ),
            hir_body_scatter_binary_direct_call_pass: join_wasm_pass!(
                hir_body_scatter_binary_direct_call_pass,
                "hir_body_scatter_binary_direct_call"
            ),
            hir_agg_body_pass: join_wasm_pass!(hir_agg_body_pass, "hir_agg_body"),
            hir_assert_module_pass: join_wasm_pass!(hir_assert_module_pass, "hir_assert_module"),
            hir_enum_match_records_pass: join_wasm_pass!(
                hir_enum_match_records_pass,
                "hir_enum_match_records"
            ),
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
            pipeline_cache_dirty,
            buffers: Mutex::new(None),
        };
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_PREWARM_PIPELINES", false) {
            generator.prewarm_pipelines(gpu)?;
        }
        {
            gpu.persist_pipeline_cache();
        }
        Ok(generator)
    }

    fn persist_pipeline_cache_if_dirty(&self, device: &wgpu::Device) {
        if self.pipeline_cache_dirty.swap(false, Ordering::AcqRel) {
            device::persist_pipeline_cache_for_device(device);
        }
    }

    fn prewarm_pipelines(&self, gpu: &device::GpuDevice) -> Result<()> {
        trace_wasm_codegen("prewarm_pipelines.start");
        let passes = [
            &self.agg_layout_clear_pass,
            &self.agg_layout_pass,
            &self.hir_body_let_init_clear_pass,
            &self.hir_body_let_init_pass,
            &self.hir_functions_clear_pass,
            &self.hir_functions_mark_pass,
            &self.hir_functions_reach_pass,
            &self.hir_functions_count_pass,
            &self.hir_functions_scatter_pass,
            &self.hir_body_plan_collect_pass,
            &self.hir_body_plan_validate_pass,
            &self.hir_body_plan_validate_return_pass,
            &self.hir_body_plan_validate_return_call_pass,
            &self.hir_body_plan_validate_return_agg_call_pass,
            &self.hir_body_plan_validate_return_nested_call_pass,
            &self.hir_body_plan_validate_assign_pass,
            &self.hir_body_plan_validate_control_pass,
            &self.hir_body_plan_validate_agg_range_control_pass,
            &self.hir_body_plan_validate_if_simple_pass,
            &self.hir_body_plan_validate_print_simple_pass,
            &self.hir_body_plan_validate_call_pass,
            &self.hir_body_plan_validate_host_void_call_pass,
            &self.hir_body_plan_validate_let_host_pass,
            &self.hir_body_plan_validate_let_host_env_pass,
            &self.hir_body_plan_validate_let_host_io_pass,
            &self.hir_body_plan_validate_let_host_string_pass,
            &self.hir_body_plan_validate_return_host_io_pass,
            &self.hir_body_plan_validate_return_host_string_pass,
            &self.hir_body_plan_validate_let_direct_call_pass,
            &self.hir_body_plan_validate_let_call_pass,
            &self.hir_body_plan_validate_let_call_status_pass,
            &self.hir_body_plan_agg_direct_call_pass,
            &self.hir_body_plan_agg_struct_pass,
            &self.hir_body_plan_arrays_pass,
            &self.hir_body_plan_functions_pass,
            &self.hir_body_plan_finalize_pass,
            &self.hir_body_clear_pass,
            &self.hir_body_counts_pass,
            &self.hir_body_scan_local_pass,
            &self.hir_body_scan_blocks_pass,
            &self.hir_body_agg_call_arg_counts_pass,
            &self.hir_body_agg_call_arg_records_pass,
            &self.hir_body_agg_call_finalize_pass,
            &self.hir_body_direct_call_arg_records_pass,
            &self.hir_body_direct_call_finalize_pass,
            &self.hir_body_status_pass,
            &self.hir_body_scatter_pass,
            &self.hir_body_scatter_frame_pass,
            &self.hir_body_scatter_if_simple_pass,
            &self.hir_body_scatter_return_scalar_pass,
            &self.hir_body_scatter_return_expr_pass,
            &self.hir_body_scatter_conversion_expr_pass,
            &self.hir_body_scatter_let_const_pass,
            &self.hir_body_scatter_expr_control_pass,
            &self.hir_body_scatter_agg_range_control_pass,
            &self.hir_body_scatter_let_direct_pass,
            &self.hir_body_scatter_direct_nested_call_pass,
            &self.hir_body_scatter_host_io_pass,
            &self.hir_body_scatter_host_pass,
            &self.hir_body_scatter_arrays_pass,
            &self.hir_body_scatter_array_lean_pass,
            &self.hir_body_scatter_agg_copy_pass,
            &self.hir_body_scatter_agg_direct_call_pass,
            &self.hir_body_scatter_agg_call_args_pass,
            &self.hir_body_scatter_nested_call_args_pass,
            &self.hir_body_scatter_return_agg_direct_call_pass,
            &self.hir_body_scatter_return_member_pass,
            &self.hir_body_scatter_member_expr_pass,
            &self.hir_body_scatter_binary_direct_call_pass,
            &self.hir_agg_body_pass,
            &self.hir_assert_module_pass,
            &self.hir_enum_match_records_pass,
            &self.wasm_const_values_pass,
            &self.module_type_lengths_pass,
            &self.module_type_dispatch_args_pass,
            &self.module_type_bytes_pass,
            &self.module_status_pass,
            &self.pass,
            &self.pack_pass,
        ];
        for pass in passes {
            pass.pipeline()?;
            if crate::gpu::env::env_bool_truthy("LANIUS_WASM_PREWARM_PERSIST_INCREMENTAL", true) {
                self.persist_pipeline_cache_if_dirty(&gpu.device);
            }
        }
        trace_wasm_codegen("prewarm_pipelines.done");
        Ok(())
    }

    /// Records WASM backend passes from resident frontend and type-check buffers.
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
        active_hir_dispatch_args_buf: &wgpu::Buffer,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_item_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        parser_feature_flags_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        language_name_id_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        array_metadata: GpuWasmArrayMetadataBuffers<'_>,
        path_metadata: GpuWasmPathMetadataBuffers<'_>,
        semantic_hir: GpuWasmSemanticHirBuffers<'_>,
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
        type_decl_hir_node_by_token_buf: &wgpu::Buffer,
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
            hir_item_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            parser_feature_flags_buf,
            visible_decl_buf,
            visible_type_buf,
            name_id_by_token_buf,
            language_name_id_buf,
            enclosing_fn_buf,
            struct_metadata.lit_field_parent_lit,
            struct_metadata.member_name_token,
            struct_metadata.member_result_field_ordinal,
            struct_metadata.struct_init_field_ordinal_by_node,
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
            call_metadata.arg_row_node,
            call_metadata.arg_row_start,
            call_metadata.arg_row_count,
            expr_metadata.record,
            expr_metadata.result_root_node,
            expr_metadata.int_value,
            expr_metadata.float_bits,
            expr_metadata.string_start,
            expr_metadata.string_len,
            expr_metadata.stmt_record,
            array_metadata.lit_first_element,
            array_metadata.lit_element_count,
            array_metadata.lit_context_stmt_node,
            array_metadata.element_parent_lit,
            array_metadata.element_ordinal,
            array_metadata.element_next,
            path_metadata.count_out,
            path_metadata.segment_count,
            path_metadata.segment_base,
            path_metadata.segment_token,
            path_metadata.id_by_owner_hir,
            semantic_hir.count,
            semantic_hir.prefix_before_node,
            semantic_hir.dense_node,
            semantic_hir.subtree_end,
            semantic_hir.parent,
            semantic_hir.first_child,
            semantic_hir.next_sibling,
            semantic_hir.depth,
            semantic_hir.child_index,
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
            type_decl_hir_node_by_token_buf,
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
        let bufs = match self.resident_buffers_for(
            &mut guard,
            device,
            input_fingerprint,
            output_capacity,
            token_capacity,
            hir_node_capacity,
            active_hir_dispatch_args_buf,
            token_buf,
            token_count_buf,
            source_buf,
            node_kind_buf,
            parent_buf,
            first_child_buf,
            next_sibling_buf,
            hir_kind_buf,
            hir_item_kind_buf,
            hir_token_pos_buf,
            hir_token_end_buf,
            hir_status_buf,
            parser_feature_flags_buf,
            visible_decl_buf,
            visible_type_buf,
            name_id_by_token_buf,
            language_name_id_buf,
            enclosing_fn_buf,
            struct_metadata,
            enum_match_metadata,
            call_metadata,
            expr_metadata,
            array_metadata,
            path_metadata,
            semantic_hir,
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
            type_decl_hir_node_by_token_buf,
            fn_return_ref_tag_buf,
            fn_return_ref_payload_buf,
            member_result_ref_tag_buf,
            member_result_ref_payload_buf,
            struct_init_field_expected_ref_tag_buf,
            struct_init_field_expected_ref_payload_buf,
        ) {
            Ok(bufs) => bufs,
            Err(err) => return Err(err),
        };
        trace_wasm_codegen("record.resident.done");

        let params = WasmParams {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes: hir_node_capacity,
        };
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let (func_scan_local_groups_x, func_scan_local_groups_y) =
            workgroup_grid_1d(bufs.func_scan_blocks);
        let func_scan_block_groups = bufs.func_scan_blocks.div_ceil(256).max(1);
        let (func_scan_block_groups_x, func_scan_block_groups_y) =
            workgroup_grid_1d(func_scan_block_groups);
        let output_word_groups = (output_capacity as u32).div_ceil(4).div_ceil(256).max(1);
        let (output_word_groups_x, output_word_groups_y) = workgroup_grid_1d(output_word_groups);
        trace_wasm_codegen("record.write_params.start");
        queue.write_buffer(&bufs.params_buf, 0, &wasm_params_bytes(&params));
        for (scan_param_buf, scan_step) in bufs
            .body_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.body_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: token_capacity.saturating_mul(2),
                n_blocks: bufs.body_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        for (scan_param_buf, scan_step) in bufs
            .arg_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.arg_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: hir_node_capacity.saturating_mul(2).max(1),
                n_blocks: bufs.arg_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        for (scan_param_buf, scan_step) in bufs
            .func_scan_param_bufs
            .iter()
            .zip(scan_steps_for_blocks(bufs.func_scan_blocks as usize))
        {
            let scan_params = WasmScanParams {
                n_items: token_capacity,
                n_blocks: bufs.func_scan_blocks,
                scan_step,
                out_capacity: output_capacity as u32,
            };
            queue.write_buffer(scan_param_buf, 0, &wasm_scan_params_bytes(&scan_params));
        }
        queue.write_buffer(&bufs.body_status_buf, 0, &body_status_init_bytes());
        queue.write_buffer(&bufs.body_plan_buf, 0, &body_plan_init_bytes());
        queue.write_buffer(&bufs.status_buf, 0, &unsupported_shape_status_init_bytes());
        let const_value_clear = vec![0u8; bufs.token_capacity as usize * 2 * 4];
        queue.write_buffer(&bufs.wasm_const_value_record_buf, 0, &const_value_clear);
        queue.write_buffer(
            &bufs.body_dispatch_buf,
            0,
            &dispatch_args_bytes(output_word_groups_x, output_word_groups_y, 1),
        );
        trace_wasm_codegen("record.write_params.done");

        let agg_layout_groups = token_capacity.max(hir_node_capacity).div_ceil(256).max(1);
        let (agg_layout_groups_x, agg_layout_groups_y) = workgroup_grid_1d(agg_layout_groups);
        let hir_node_groups = hir_node_capacity.div_ceil(256).max(1);
        let (hir_node_groups_x, hir_node_groups_y) = workgroup_grid_1d(hir_node_groups);

        trace_wasm_codegen("record.dispatch.agg_layout_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.agg_layout_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.agg_layout_clear_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout_clear.done");

        trace_wasm_codegen("record.dispatch.agg_layout.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.agg_layout"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.agg_layout_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.agg_layout_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.agg_layout.done");

        trace_wasm_codegen("record.dispatch.hir_agg_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_agg_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_agg_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_agg_scan_local.done");

        for (step_i, bind_group) in bufs.hir_agg_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_agg_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_agg_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_agg_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.const_values.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.const_values"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.wasm_const_values_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.wasm_const_values_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.const_values.done");

        trace_wasm_codegen("record.dispatch.hir_functions_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_clear_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_clear.done");

        trace_wasm_codegen("record.dispatch.hir_functions_mark.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_mark"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_mark_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_mark_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_mark.done");

        for iteration in 0..WASM_FUNCTION_REACHABILITY_ITERATIONS {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_functions_reach.{iteration}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_functions_reach"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_functions_reach_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_functions_reach_bind_group), &[]);
            compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_functions_reach.{iteration}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.hir_functions_count.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_count"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_count_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_count_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_count.done");

        trace_wasm_codegen("record.dispatch.hir_func_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_func_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_func_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_func_scan_local.done");

        for (step_i, bind_group) in bufs.hir_func_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_func_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_func_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.dispatch.hir_func_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.dispatch.hir_functions_scatter.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_functions_scatter"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_functions_scatter_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_functions_scatter_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_functions_scatter.done");

        trace_wasm_codegen("record.dispatch.hir_body_let_init_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_let_init_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_let_init_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_let_init_clear_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_let_init_clear.done");

        trace_wasm_codegen("record.dispatch.hir_body_let_init.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_let_init"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_let_init_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_let_init_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_let_init.done");

        trace_wasm_codegen("record.dispatch.hir_body_plan_collect.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_collect"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_collect_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_collect_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.dispatch.hir_body_plan_collect.done");

        trace_wasm_codegen("record.early_features.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        encoder.copy_buffer_to_buffer(
            &bufs.body_plan_buf,
            0,
            &bufs.body_plan_readback,
            0,
            (WASM_BODY_PLAN_WORDS * 4) as u64,
        );
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_invalid_count_by_token_buf,
                0,
                &bufs.wasm_func_invalid_count_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_detail_by_token_buf,
                0,
                &bufs.wasm_func_detail_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
        }
        trace_wasm_codegen("record.early_features.copy_status.done");

        Ok(RecordedWasmCodegen {
            output_capacity,
            token_capacity,
        })
    }

    fn record_wasm_body_plan_and_status(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
        features: WasmBodyFeatures,
    ) -> Result<()> {
        let token_capacity = recorded.token_capacity;
        let body_item_capacity = token_capacity.saturating_mul(2);
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let body_item_groups = body_item_capacity.div_ceil(256).max(1);
        let (body_item_groups_x, body_item_groups_y) = workgroup_grid_1d(body_item_groups);
        let arg_record_capacity = bufs.hir_node_capacity.saturating_mul(2).max(1);
        let arg_record_groups = arg_record_capacity.div_ceil(256).max(1);
        let (arg_record_groups_x, arg_record_groups_y) = workgroup_grid_1d(arg_record_groups);
        let hir_node_groups = bufs.hir_node_capacity.div_ceil(256).max(1);
        let (hir_node_groups_x, hir_node_groups_y) = workgroup_grid_1d(hir_node_groups);
        let (body_scan_local_groups_x, body_scan_local_groups_y) =
            workgroup_grid_1d(bufs.body_scan_blocks);
        let body_scan_block_groups = bufs.body_scan_blocks.div_ceil(256).max(1);
        let (body_scan_block_groups_x, body_scan_block_groups_y) =
            workgroup_grid_1d(body_scan_block_groups);
        let (arg_scan_local_groups_x, arg_scan_local_groups_y) =
            workgroup_grid_1d(bufs.arg_scan_blocks);
        let arg_scan_block_groups = bufs.arg_scan_blocks.div_ceil(256).max(1);
        let (arg_scan_block_groups_x, arg_scan_block_groups_y) =
            workgroup_grid_1d(arg_scan_block_groups);
        let has_stmt_print_direct = features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT);
        let has_direct_call = features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || has_stmt_print_direct;
        let has_plain_let_direct = features.has(WASM_BODY_FEATURE_LET_DIRECT);
        let has_binary_direct = features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_scalar_return_direct = features.has(WASM_BODY_FEATURE_RETURN_DIRECT);
        let has_return_agg_direct = features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT);
        let has_return_call_planning =
            has_scalar_return_direct || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_assign = features.has(WASM_BODY_FEATURE_ASSIGN);
        let has_control = features.has(WASM_BODY_FEATURE_CONTROL);
        let has_control_if_simple = features.has(WASM_BODY_FEATURE_CONTROL_IF_SIMPLE);
        let has_stmt_print = features.has(WASM_BODY_FEATURE_STMT_PRINT);
        let has_stmt_host_void = features.has(WASM_BODY_FEATURE_STMT_HOST_VOID)
            || (features.has(WASM_BODY_FEATURE_STMT_CALL)
                && features.has(WASM_BODY_FEATURE_HOST_VOID));
        let has_host = features.has(WASM_BODY_FEATURE_HOST);
        let has_host_basic = has_host || features.has(WASM_BODY_FEATURE_HOST_BASIC);
        let has_host_env = has_host || features.has(WASM_BODY_FEATURE_HOST_ENV);
        let has_host_io_bare = features.has(WASM_BODY_FEATURE_HOST_IO)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_I32)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_STRING)
            && !features.has(WASM_BODY_FEATURE_HOST_IO_RETURN);
        let has_host_io_i32 =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_I32) || has_host_io_bare;
        let has_host_io_string =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_STRING) || has_host_io_bare;
        let has_host_io_return =
            has_host || features.has(WASM_BODY_FEATURE_HOST_IO_RETURN) || has_host_io_bare;
        let has_host_io_return_string_only =
            has_host_io_return && has_host_io_string && !has_host_io_i32 && !has_host;
        let has_host_io_return_combined = has_host_io_return && !has_host_io_return_string_only;
        let has_agg_direct_call = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_AGG_COPY);
        let has_agg_or_binary_call_arg_records = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let has_direct_call_arg_records = has_direct_call || has_agg_or_binary_call_arg_records;
        let use_direct_call_arg_record_shaders =
            has_direct_call_arg_records && !has_agg_or_binary_call_arg_records;
        let has_agg_struct = features.has(WASM_BODY_FEATURE_ARRAY_ALLOC)
            || features.has(WASM_BODY_FEATURE_MEMBER_EXPR);
        let has_array_like =
            features.has(WASM_BODY_FEATURE_ARRAYS) || features.has(WASM_BODY_FEATURE_ARRAY_ALLOC);

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_clear.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_clear"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_clear_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_clear_bind_group), &[]);
        compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_clear.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_validate"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_validate_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_validate_return"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_validate_return_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_return_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return.done");

        if has_scalar_return_direct {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_nested_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_nested_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_nested_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_nested_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_nested_call.done",
            );
        }

        if has_return_call_planning {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_return_call.done");
        }

        if has_return_agg_direct {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_agg_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_agg_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_agg_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_agg_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_agg_call.done",
            );
        }

        if has_assign {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_assign.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_assign"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_validate_assign_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_assign_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_assign.done");
        }

        if has_control {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_control.done");

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_agg_range_control.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_agg_range_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_agg_range_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_agg_range_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_agg_range_control.done",
            );
        }

        if has_stmt_print {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_print_simple.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_print_simple"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_print_simple_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_print_simple_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_print_simple.done",
            );
        }

        if has_control_if_simple {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_if_simple.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_if_simple"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_if_simple_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_if_simple_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_if_simple.done");
        }

        if has_stmt_print_direct {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_validate_call_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_validate_call_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_call.done");
        }

        if has_stmt_host_void {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_host_void_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_host_void_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_host_void_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_host_void_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_host_void_call.done",
            );
        }

        if has_host_basic {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host.done");
        }

        if has_host_env {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_env.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_env"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_env_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_env_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_env.done",
            );
        }

        if has_host_io_i32 {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_io.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_io_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_io_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_host_io.done");
        }

        if has_host_io_string {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_string.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_host_string"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_host_string_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_host_string_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_host_string.done",
            );
        }

        if has_host_io_return_string_only {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_string.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_host_string"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_host_string_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_host_string_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_string.done",
            );
        }

        if has_host_io_return_combined {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_io.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_return_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_return_host_io_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_return_host_io_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_return_host_io.done",
            );
        }

        if has_plain_let_direct {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_direct_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_direct_call.done",
            );
        }

        if has_binary_direct {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_validate_let_call.done");
        }

        if has_agg_direct_call {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_agg_direct_call_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_agg_direct_call_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_direct_call.done");
        }

        if has_agg_struct {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_struct.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_agg_struct"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_agg_struct_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_agg_struct_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_agg_struct.done");
        }

        if has_array_like {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_arrays.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_arrays"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_plan_arrays_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_plan_arrays_bind_group), &[]);
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_arrays.done");
        }

        if has_direct_call_arg_records {
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_agg_call_arg_counts.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_counts"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_agg_call_arg_counts_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_agg_call_arg_counts_bind_group), &[]);
            compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.body_plan.dispatch.hir_body_agg_call_arg_counts.done");

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_local.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_count_scan_local"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_agg_call_arg_count_scan_local_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scan_local_groups_x, body_scan_local_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_local.done",
            );

            for (step_i, bind_group) in bufs
                .hir_body_agg_call_arg_count_scan_block_bind_groups
                .iter()
                .enumerate()
            {
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_blocks.{step_i}.start"
                ));
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("codegen.wasm.hir_body_agg_call_arg_count_scan_blocks"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(bind_group), &[]);
                compute.dispatch_workgroups(body_scan_block_groups_x, body_scan_block_groups_y, 1);
                drop(compute);
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_count_scan_blocks.{step_i}.done"
                ));
            }

            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_arg_records.start"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_arg_records.start"
            });
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(if use_direct_call_arg_record_shaders {
                    "codegen.wasm.hir_body_direct_call_arg_records"
                } else {
                    "codegen.wasm.hir_body_agg_call_arg_records"
                }),
                timestamp_writes: None,
            });
            if use_direct_call_arg_record_shaders {
                compute.set_pipeline(
                    self.hir_body_direct_call_arg_records_pass
                        .pipeline()?
                        .as_ref(),
                );
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_direct_call_arg_records_bind_group),
                    &[],
                );
            } else {
                compute.set_pipeline(self.hir_body_agg_call_arg_records_pass.pipeline()?.as_ref());
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_agg_call_arg_records_bind_group),
                    &[],
                );
            }
            compute.dispatch_workgroups(arg_record_groups_x, arg_record_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_arg_records.done"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_arg_records.done"
            });

            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_local.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_agg_call_arg_byte_scan_local"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_agg_call_arg_byte_scan_local_bind_group),
                &[],
            );
            compute.dispatch_workgroups(arg_scan_local_groups_x, arg_scan_local_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_local.done",
            );

            for (step_i, bind_group) in bufs
                .hir_body_agg_call_arg_byte_scan_block_bind_groups
                .iter()
                .enumerate()
            {
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_blocks.{step_i}.start"
                ));
                let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                    label: Some("codegen.wasm.hir_body_agg_call_arg_byte_scan_blocks"),
                    timestamp_writes: None,
                });
                compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(bind_group), &[]);
                compute.dispatch_workgroups(arg_scan_block_groups_x, arg_scan_block_groups_y, 1);
                drop(compute);
                trace_wasm_codegen(&format!(
                    "record.body_plan.dispatch.hir_body_agg_call_arg_byte_scan_blocks.{step_i}.done"
                ));
            }

            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_finalize.start"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_finalize.start"
            });
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some(if use_direct_call_arg_record_shaders {
                    "codegen.wasm.hir_body_direct_call_finalize"
                } else {
                    "codegen.wasm.hir_body_agg_call_finalize"
                }),
                timestamp_writes: None,
            });
            if use_direct_call_arg_record_shaders {
                compute.set_pipeline(self.hir_body_direct_call_finalize_pass.pipeline()?.as_ref());
                compute.set_bind_group(
                    0,
                    Some(&bufs.hir_body_direct_call_finalize_bind_group),
                    &[],
                );
            } else {
                compute.set_pipeline(self.hir_body_agg_call_finalize_pass.pipeline()?.as_ref());
                compute.set_bind_group(0, Some(&bufs.hir_body_agg_call_finalize_bind_group), &[]);
            }
            compute.dispatch_workgroups(body_item_groups_x, body_item_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(if use_direct_call_arg_record_shaders {
                "record.body_plan.dispatch.hir_body_direct_call_finalize.done"
            } else {
                "record.body_plan.dispatch.hir_body_agg_call_finalize.done"
            });
        }

        let skip_non_essential_validations = crate::gpu::env::env_bool_truthy(
            "LANIUS_SHADER_DISABLE_NON_ESSENTIAL_VALIDATIONS",
            true,
        );
        if !skip_non_essential_validations && has_direct_call {
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_call_status.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_plan_validate_let_call_status"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_plan_validate_let_call_status_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_plan_validate_let_call_status_bind_group),
                &[],
            );
            compute.dispatch_workgroups_indirect(&bufs.active_hir_dispatch_args_buf, 0);
            drop(compute);
            trace_wasm_codegen(
                "record.body_plan.dispatch.hir_body_plan_validate_let_call_status.done",
            );
        }

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_functions.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_functions"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_functions_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_functions_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_functions.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_finalize.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_plan_finalize"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_plan_finalize_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_plan_finalize_bind_group), &[]);
        compute.dispatch_workgroups(WASM_BODY_PLAN_FINALIZE_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_plan_finalize.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_counts.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_counts"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_counts_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_counts_bind_group), &[]);
        compute.dispatch_workgroups(hir_node_groups_x, hir_node_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_counts.done");

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_scan_local.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(body_scan_local_groups_x, body_scan_local_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_scan_local.done");

        for (step_i, bind_group) in bufs.hir_body_scan_block_bind_groups.iter().enumerate() {
            trace_wasm_codegen(&format!(
                "record.body_plan.dispatch.hir_body_scan_blocks.{step_i}.start"
            ));
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(body_scan_block_groups_x, body_scan_block_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(&format!(
                "record.body_plan.dispatch.hir_body_scan_blocks.{step_i}.done"
            ));
        }

        trace_wasm_codegen("record.body_plan.dispatch.hir_body_status.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_body_status"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_status_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_body_status_bind_group), &[]);
        compute.dispatch_workgroups(WASM_BODY_STATUS_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.body_plan.dispatch.hir_body_status.done");

        trace_wasm_codegen("record.body_plan.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        encoder.copy_buffer_to_buffer(
            &bufs.body_plan_buf,
            0,
            &bufs.body_plan_readback,
            0,
            (WASM_BODY_PLAN_WORDS * 4) as u64,
        );
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_len_buf,
                0,
                &bufs.body_fragment_len_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_aux_buf,
                0,
                &bufs.body_fragment_aux_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 16) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_meta_buf,
                0,
                &bufs.body_fragment_meta_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 16) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_invalid_count_by_token_buf,
                0,
                &bufs.wasm_func_invalid_count_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_detail_by_token_buf,
                0,
                &bufs.wasm_func_detail_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
        }
        trace_wasm_codegen("record.body_plan.copy_status.done");

        Ok(())
    }

    /// Reads and validates the output bytes produced by a recorded WASM backend run.
    fn record_wasm_scatter_and_pack(
        &self,
        encoder: &mut wgpu::CommandEncoder,
        bufs: &ResidentWasmBuffers,
        recorded: &RecordedWasmCodegen,
        features: WasmBodyFeatures,
    ) -> Result<()> {
        let output_capacity = recorded.output_capacity;
        let token_capacity = recorded.token_capacity;
        let token_groups = token_capacity.div_ceil(256).max(1);
        let (token_groups_x, token_groups_y) = workgroup_grid_1d(token_groups);
        let (func_scan_local_groups_x, func_scan_local_groups_y) =
            workgroup_grid_1d(bufs.func_scan_blocks);
        let func_scan_block_groups = bufs.func_scan_blocks.div_ceil(256).max(1);
        let (func_scan_block_groups_x, func_scan_block_groups_y) =
            workgroup_grid_1d(func_scan_block_groups);
        let body_scatter_items = output_capacity as u32;
        let body_scatter_groups = body_scatter_items.div_ceil(256).max(1);
        let (body_scatter_groups_x, body_scatter_groups_y) = workgroup_grid_1d(body_scatter_groups);
        let agg_layout_groups = token_capacity
            .max(bufs.hir_node_capacity)
            .div_ceil(256)
            .max(1);
        let (agg_layout_groups_x, agg_layout_groups_y) = workgroup_grid_1d(agg_layout_groups);
        let wasm_assert_output_groups = ((output_capacity as u32)
            .min(WASM_ASSERT_OUTPUT_TARGET_LIMIT))
        .div_ceil(256)
        .max(1);
        let (wasm_assert_output_groups_x, wasm_assert_output_groups_y) =
            workgroup_grid_1d(wasm_assert_output_groups);
        let has_direct_arg_scatter = features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT);
        let has_agg_or_binary_arg_scatter = features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT)
            || features.has(WASM_BODY_FEATURE_BINARY_DIRECT);
        let expr_control_has_full_only_shape = features.has(WASM_BODY_FEATURE_ASSIGN)
            || features.has(WASM_BODY_FEATURE_CONTROL)
            || features.has(WASM_BODY_FEATURE_STMT_CALL)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT);
        let needs_expr_control_scatter = features.has(WASM_BODY_FEATURE_EXPR_CONTROL);
        let needs_full_body_scatter = expr_control_has_full_only_shape;
        let body_scatter_stage = if needs_full_body_scatter {
            "hir_body_scatter"
        } else {
            "hir_body_scatter_frame"
        };
        trace_wasm_codegen(&format!(
            "record.phase2.dispatch.{body_scatter_stage}.start"
        ));
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some(if needs_full_body_scatter {
                "codegen.wasm.hir_body_scatter"
            } else {
                "codegen.wasm.hir_body_scatter_frame"
            }),
            timestamp_writes: None,
        });
        if needs_full_body_scatter {
            compute.set_pipeline(self.hir_body_scatter_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_bind_group), &[]);
        } else {
            compute.set_pipeline(self.hir_body_scatter_frame_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_frame_bind_group), &[]);
        }
        compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
        drop(compute);
        trace_wasm_codegen(&format!("record.phase2.dispatch.{body_scatter_stage}.done"));

        if features.has(WASM_BODY_FEATURE_RETURN_SCALAR) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_scalar.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_scalar"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_scalar_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_scalar_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_scalar.done");
        }

        if features.has(WASM_BODY_FEATURE_LET_CONST) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_const.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_let_const"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_let_const_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_let_const_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_const.done");
        }

        if needs_expr_control_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_expr_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_expr_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_expr_control_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_expr_control_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_expr_control.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_range_control.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_range_control"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_range_control_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_range_control_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_range_control.done");
        }

        // The generic expression-control pass also recognizes IF fragments.
        // Run the specialized simple-IF pass afterward so its richer fragment
        // metadata wins instead of being overwritten by the generic emitter.
        if features.has(WASM_BODY_FEATURE_CONTROL_IF_SIMPLE) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_if_simple.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_if_simple"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_if_simple_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_if_simple_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_if_simple.done");
        }

        // The generic expression-control pass also recognizes return-expression
        // fragments, but it does not implement the full aggregate-member atom
        // surface. Let the dedicated return-expression emitter own those bytes.
        if features.has(WASM_BODY_FEATURE_RETURN_EXPR) && !needs_full_body_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_return_expr_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_return_expr_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_expr.done");
        }

        if features.has(WASM_BODY_FEATURE_DIRECT)
            || features.has(WASM_BODY_FEATURE_LET_DIRECT)
            || features.has(WASM_BODY_FEATURE_RETURN_DIRECT)
            || features.has(WASM_BODY_FEATURE_STMT_PRINT_DIRECT)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_direct.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_let_direct"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_let_direct_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_let_direct_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_let_direct.done");
        }

        if features.has(WASM_BODY_FEATURE_HOST_IO) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host_io.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_host_io"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_host_io_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_host_io_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host_io.done");
        }

        if features.has(WASM_BODY_FEATURE_HOST_BASIC)
            || features.has(WASM_BODY_FEATURE_HOST_ENV)
            || features.has(WASM_BODY_FEATURE_HOST_IO)
            || features.has(WASM_BODY_FEATURE_HOST_VOID)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_host"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_host_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_host_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_host.done");
        }

        if features.has(WASM_BODY_FEATURE_ARRAYS) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_arrays.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_arrays"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_arrays_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_arrays_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_arrays.done");
        }

        if features.has(WASM_BODY_FEATURE_ARRAY_ALLOC) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_array_lean.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_array_lean"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_array_lean_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_array_lean_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_array_lean.done");
        }

        if features.has(WASM_BODY_FEATURE_AGG_COPY) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_copy.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_copy"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_agg_copy_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_agg_copy_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_copy.done");
        }

        // Specialized expression bytes must win over generic, host, and array
        // emitters that recognize the same broad fragment families.
        if features.has(WASM_BODY_FEATURE_MEMBER_EXPR_SCATTER) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_conversion_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_conversion_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_conversion_expr_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_conversion_expr_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_conversion_expr.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_NESTED_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_direct_nested_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_direct_nested_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_direct_nested_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_direct_nested_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_direct_nested_call.done");
        }

        if has_direct_arg_scatter || has_agg_or_binary_arg_scatter {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_call_args.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_call_args"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_call_args_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_call_args_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_call_args.done");

            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_nested_call_args.start");
            let (nested_arg_groups_x, nested_arg_groups_y) =
                workgroup_grid_1d(bufs.arg_scan_blocks);
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_nested_call_args"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_nested_call_args_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_nested_call_args_bind_group),
                &[],
            );
            compute.dispatch_workgroups(nested_arg_groups_x, nested_arg_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_nested_call_args.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_AGG_DIRECT) {
            trace_wasm_codegen(
                "record.phase2.dispatch.hir_body_scatter_return_agg_direct_call.start",
            );
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_agg_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_agg_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen(
                "record.phase2.dispatch.hir_body_scatter_return_agg_direct_call.done",
            );
        }

        if features.has(WASM_BODY_FEATURE_LET_AGG_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_agg_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_agg_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_agg_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_agg_direct_call.done");
        }

        if features.has(WASM_BODY_FEATURE_RETURN_MEMBER_EXPR) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_member.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_return_member"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_return_member_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_return_member_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_return_member.done");
        }

        // Keep the retired monolithic scatter available as a diagnostic
        // fallback while specialized member-expression passes replace it.
        // It is opt-in because its driver pipeline can take longer than the
        // complete compile timeout to initialize.
        if features.has(WASM_BODY_FEATURE_MEMBER_EXPR_SCATTER)
            && crate::gpu::env::env_bool_strict("LANIUS_WASM_LEGACY_MEMBER_EXPR_SCATTER", false)
        {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_member_expr.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_member_expr"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scatter_member_expr_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(&bufs.hir_body_scatter_member_expr_bind_group), &[]);
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_member_expr.done");
        }

        if features.has(WASM_BODY_FEATURE_BINARY_DIRECT) {
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_binary_direct_call.start");
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.hir_body_scatter_binary_direct_call"),
                timestamp_writes: None,
            });
            compute.set_pipeline(
                self.hir_body_scatter_binary_direct_call_pass
                    .pipeline()?
                    .as_ref(),
            );
            compute.set_bind_group(
                0,
                Some(&bufs.hir_body_scatter_binary_direct_call_bind_group),
                &[],
            );
            compute.dispatch_workgroups(body_scatter_groups_x, body_scatter_groups_y, 1);
            drop(compute);
            trace_wasm_codegen("record.phase2.dispatch.hir_body_scatter_binary_direct_call.done");
        }

        trace_wasm_codegen("record.phase2.dispatch.hir_agg_body.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_agg_body"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_agg_body_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_agg_body_bind_group), &[]);
        compute.dispatch_workgroups(token_groups_x, token_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.hir_agg_body.done");

        trace_wasm_codegen("record.phase2.dispatch.hir_enum_match_records.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_enum_match_records"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_enum_match_records_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_enum_match_records_bind_group), &[]);
        compute.dispatch_workgroups(agg_layout_groups_x, agg_layout_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.hir_enum_match_records.done");

        trace_wasm_codegen("record.phase2.dispatch.module_type_lengths.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_dispatch_args"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_dispatch_args_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_dispatch_args_bind_group), &[]);
        compute.dispatch_workgroups(1, 1, 1);
        drop(compute);
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_lengths"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_lengths_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_lengths_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs._module_type_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_type_lengths.done");

        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_scan_local"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_body_scan_local_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_func_scan_local_bind_group), &[]);
        compute.dispatch_workgroups(func_scan_local_groups_x, func_scan_local_groups_y, 1);
        drop(compute);
        for bind_group in &bufs.hir_func_scan_block_bind_groups {
            let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
                label: Some("codegen.wasm.module_type_scan_blocks"),
                timestamp_writes: None,
            });
            compute.set_pipeline(self.hir_body_scan_blocks_pass.pipeline()?.as_ref());
            compute.set_bind_group(0, Some(bind_group), &[]);
            compute.dispatch_workgroups(func_scan_block_groups_x, func_scan_block_groups_y, 1);
            drop(compute);
        }

        trace_wasm_codegen("record.phase2.dispatch.module_status.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_status"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_status_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_status_bind_group), &[]);
        compute.dispatch_workgroups(WASM_MODULE_STATUS_GROUPS, 1, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_status.done");

        trace_wasm_codegen("record.phase2.dispatch.module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module.done");

        trace_wasm_codegen("record.phase2.dispatch.module_type_bytes.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.module_type_bytes"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.module_type_bytes_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.module_type_bytes_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs._module_type_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.module_type_bytes.done");

        trace_wasm_codegen("record.phase2.dispatch.hir_assert_module.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.hir_assert_module"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.hir_assert_module_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.hir_assert_module_bind_group), &[]);
        compute.dispatch_workgroups(wasm_assert_output_groups_x, wasm_assert_output_groups_y, 1);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.hir_assert_module.done");

        trace_wasm_codegen("record.phase2.dispatch.pack_output.start");
        let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
            label: Some("codegen.wasm.pack_output"),
            timestamp_writes: None,
        });
        compute.set_pipeline(self.pack_pass.pipeline()?.as_ref());
        compute.set_bind_group(0, Some(&bufs.pack_bind_group), &[]);
        compute.dispatch_workgroups_indirect(&bufs.body_dispatch_buf, 0);
        drop(compute);
        trace_wasm_codegen("record.phase2.dispatch.pack_output.done");

        trace_wasm_codegen("record.phase2.copy_status.start");
        encoder.copy_buffer_to_buffer(&bufs.status_buf, 0, &bufs.status_readback, 0, 16);
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            encoder.copy_buffer_to_buffer(
                &bufs.body_plan_buf,
                0,
                &bufs.body_plan_readback,
                0,
                (WASM_BODY_PLAN_WORDS * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._body_fragment_len_buf,
                0,
                &bufs.body_fragment_len_readback,
                0,
                (bufs.token_capacity.saturating_mul(2).max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_invalid_count_by_token_buf,
                0,
                &bufs.wasm_func_invalid_count_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
            encoder.copy_buffer_to_buffer(
                &bufs._wasm_func_detail_by_token_buf,
                0,
                &bufs.wasm_func_detail_readback,
                0,
                (bufs.token_capacity.max(1) * 4) as u64,
            );
        }
        trace_wasm_codegen("record.phase2.copy_status.done");
        Ok(())
    }

    /// Reads and validates the output bytes produced by a recorded WASM backend run.
    pub fn finish_recorded_wasm(
        &self,
        device: &wgpu::Device,
        queue: &wgpu::Queue,
        recorded: &RecordedWasmCodegen,
    ) -> Result<Vec<u8>> {
        let mut host_timer = WasmFinishHostTimer::new();
        let guard = self
            .buffers
            .lock()
            .expect("GpuWasmCodeGenerator.buffers poisoned");
        let bufs = guard
            .as_ref()
            .ok_or_else(|| anyhow::anyhow!("WASM code generation buffers missing"))?;
        host_timer.stamp("lock_buffers");
        let early_prefix =
            read_wasm_prefix_plan(device, &bufs.status_readback, &bufs.body_plan_readback)?;
        host_timer.stamp("read_early_prefix");
        if early_prefix.status[2] != 0 && early_prefix.status[2] != ERR_UNSUPPORTED_SOURCE_SHAPE {
            return Err(wasm_output_error_from_status(
                early_prefix.status[2],
                early_prefix.status[3],
            )
            .into());
        }
        let early_features = WasmBodyFeatures::from_body_plan(&early_prefix.body_plan);
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] body_plan.features mask=0x{:08x}",
                early_features.mask
            );
            eprintln!("[laniusc][wasm-codegen] readback.early_func_invalid");
            trace_func_invalid_readback(
                device,
                &bufs.wasm_func_invalid_count_readback,
                &bufs.wasm_func_detail_readback,
            )?;
        }

        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.body_plan.encoder"),
        });
        host_timer.stamp("body_plan.create_encoder");
        self.record_wasm_body_plan_and_status(&mut encoder, bufs, recorded, early_features)?;
        host_timer.stamp("body_plan.record");
        self.persist_pipeline_cache_if_dirty(device);
        host_timer.stamp("body_plan.persist_pipeline_cache");
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.body_plan",
            encoder.finish(),
        );
        host_timer.stamp("body_plan.submit");

        let prefix =
            read_wasm_prefix_plan(device, &bufs.status_readback, &bufs.body_plan_readback)?;
        host_timer.stamp("body_plan.read_prefix");
        if prefix.status[2] != 0 {
            if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
                trace_body_fragment_len_readback(
                    device,
                    &bufs.body_fragment_len_readback,
                    recorded.token_capacity,
                )?;
                trace_body_fragment_aux_readback(
                    device,
                    &bufs.body_fragment_aux_readback,
                    recorded.token_capacity,
                )?;
                trace_body_fragment_meta_readback(
                    device,
                    &bufs.body_fragment_meta_readback,
                    recorded.token_capacity,
                )?;
                trace_func_invalid_readback(
                    device,
                    &bufs.wasm_func_invalid_count_readback,
                    &bufs.wasm_func_detail_readback,
                )?;
            }
            return Err(wasm_output_error_from_status(prefix.status[2], prefix.status[3]).into());
        }
        let features = WasmBodyFeatures::from_body_plan(&prefix.body_plan);
        if crate::gpu::env::env_bool_strict("LANIUS_WASM_TRACE", false) {
            eprintln!(
                "[laniusc][wasm-codegen] phase2.features mask=0x{:08x}",
                features.mask
            );
            trace_body_fragment_aux_readback(
                device,
                &bufs.body_fragment_aux_readback,
                recorded.token_capacity,
            )?;
            trace_body_fragment_meta_readback(
                device,
                &bufs.body_fragment_meta_readback,
                recorded.token_capacity,
            )?;
        }
        let mut encoder = device.create_command_encoder(&wgpu::CommandEncoderDescriptor {
            label: Some("codegen.wasm.phase2.encoder"),
        });
        host_timer.stamp("phase2.create_encoder");
        self.record_wasm_scatter_and_pack(&mut encoder, bufs, recorded, features)?;
        host_timer.stamp("phase2.record");
        // Generator initialization persists too early to capture demand-created
        // pipelines. Persist here only when phase-2 recording created one.
        self.persist_pipeline_cache_if_dirty(device);
        host_timer.stamp("phase2.persist_pipeline_cache");
        crate::gpu::passes_core::submit_with_progress(
            queue,
            "codegen.wasm.phase2",
            encoder.finish(),
        );
        host_timer.stamp("phase2.submit");
        let output = read_wasm_output(
            device,
            queue,
            &bufs.out_buf,
            &bufs.packed_out_buf,
            &bufs.status_readback,
            &bufs.body_plan_readback,
            &bufs.body_fragment_len_readback,
            &bufs.wasm_func_invalid_count_readback,
            &bufs.wasm_func_detail_readback,
            &bufs.out_readback,
            recorded.output_capacity,
            recorded.token_capacity,
        )?;
        host_timer.stamp("read_output");
        Ok(output)
    }

    fn resident_buffers_for<'a>(
        &self,
        slot: &'a mut Option<ResidentWasmBuffers>,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        hir_node_capacity: u32,
        active_hir_dispatch_args_buf: &wgpu::Buffer,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_item_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        parser_feature_flags_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        language_name_id_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        array_metadata: GpuWasmArrayMetadataBuffers<'_>,
        path_metadata: GpuWasmPathMetadataBuffers<'_>,
        semantic_hir: GpuWasmSemanticHirBuffers<'_>,
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
        type_decl_hir_node_by_token_buf: &wgpu::Buffer,
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
                active_hir_dispatch_args_buf,
                token_buf,
                token_count_buf,
                source_buf,
                node_kind_buf,
                parent_buf,
                first_child_buf,
                next_sibling_buf,
                hir_kind_buf,
                hir_item_kind_buf,
                hir_token_pos_buf,
                hir_token_end_buf,
                hir_status_buf,
                parser_feature_flags_buf,
                visible_decl_buf,
                visible_type_buf,
                name_id_by_token_buf,
                language_name_id_buf,
                enclosing_fn_buf,
                struct_metadata,
                enum_match_metadata,
                call_metadata,
                expr_metadata,
                array_metadata,
                path_metadata,
                semantic_hir,
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
                type_decl_hir_node_by_token_buf,
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

    #[allow(unused_macros, unused_variables)]
    fn create_resident_buffers(
        &self,
        device: &wgpu::Device,
        input_fingerprint: u64,
        output_capacity: usize,
        token_capacity: u32,
        hir_node_capacity: u32,
        active_hir_dispatch_args_buf: &wgpu::Buffer,
        token_buf: &wgpu::Buffer,
        token_count_buf: &wgpu::Buffer,
        source_buf: &wgpu::Buffer,
        node_kind_buf: &wgpu::Buffer,
        parent_buf: &wgpu::Buffer,
        first_child_buf: &wgpu::Buffer,
        next_sibling_buf: &wgpu::Buffer,
        hir_kind_buf: &wgpu::Buffer,
        hir_item_kind_buf: &wgpu::Buffer,
        hir_token_pos_buf: &wgpu::Buffer,
        hir_token_end_buf: &wgpu::Buffer,
        hir_status_buf: &wgpu::Buffer,
        parser_feature_flags_buf: &wgpu::Buffer,
        visible_decl_buf: &wgpu::Buffer,
        visible_type_buf: &wgpu::Buffer,
        name_id_by_token_buf: &wgpu::Buffer,
        language_name_id_buf: &wgpu::Buffer,
        enclosing_fn_buf: &wgpu::Buffer,
        struct_metadata: GpuWasmStructMetadataBuffers<'_>,
        enum_match_metadata: GpuWasmEnumMatchMetadataBuffers<'_>,
        call_metadata: GpuWasmCallMetadataBuffers<'_>,
        expr_metadata: GpuWasmExprMetadataBuffers<'_>,
        array_metadata: GpuWasmArrayMetadataBuffers<'_>,
        path_metadata: GpuWasmPathMetadataBuffers<'_>,
        semantic_hir: GpuWasmSemanticHirBuffers<'_>,
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
        type_decl_hir_node_by_token_buf: &wgpu::Buffer,
        fn_return_ref_tag_buf: &wgpu::Buffer,
        fn_return_ref_payload_buf: &wgpu::Buffer,
        member_result_ref_tag_buf: &wgpu::Buffer,
        member_result_ref_payload_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_tag_buf: &wgpu::Buffer,
        struct_init_field_expected_ref_payload_buf: &wgpu::Buffer,
    ) -> Result<ResidentWasmBuffers> {
        let params_buf = LaniusBuffer::new(
            (
                device.create_buffer(&wgpu::BufferDescriptor {
                    label: Some("codegen.wasm.params"),
                    size: 16,
                    usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                    mapped_at_creation: false,
                }),
                16,
            ),
            1,
        );
        let body_item_capacity = token_capacity.saturating_mul(2);
        let body_scan_blocks = body_item_capacity.div_ceil(256).max(1);
        let body_scan_steps = scan_steps_for_blocks(body_scan_blocks as usize);
        let arg_record_capacity = hir_node_capacity.saturating_mul(2).max(1);
        let arg_scan_blocks = arg_record_capacity.div_ceil(256).max(1);
        let arg_scan_steps = scan_steps_for_blocks(arg_scan_blocks as usize);
        let func_scan_blocks = token_capacity.div_ceil(256).max(1);
        let func_scan_steps = scan_steps_for_blocks(func_scan_blocks as usize);
        let body_scan_param_bufs = body_scan_steps
            .iter()
            .enumerate()
            .map(|(step_i, _)| {
                LaniusBuffer::new(
                    (
                        device.create_buffer(&wgpu::BufferDescriptor {
                            label: Some(&format!("codegen.wasm.body_scan.params.{step_i}")),
                            size: 16,
                            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                            mapped_at_creation: false,
                        }),
                        16,
                    ),
                    1,
                )
            })
            .collect::<Vec<_>>();
        let arg_scan_param_bufs = arg_scan_steps
            .iter()
            .enumerate()
            .map(|(step_i, _)| {
                LaniusBuffer::new(
                    (
                        device.create_buffer(&wgpu::BufferDescriptor {
                            label: Some(&format!("codegen.wasm.arg_scan.params.{step_i}")),
                            size: 16,
                            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                            mapped_at_creation: false,
                        }),
                        16,
                    ),
                    1,
                )
            })
            .collect::<Vec<_>>();
        let func_scan_param_bufs = func_scan_steps
            .iter()
            .enumerate()
            .map(|(step_i, _)| {
                LaniusBuffer::new(
                    (
                        device.create_buffer(&wgpu::BufferDescriptor {
                            label: Some(&format!("codegen.wasm.func_scan.params.{step_i}")),
                            size: 16,
                            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
                            mapped_at_creation: false,
                        }),
                        16,
                    ),
                    1,
                )
            })
            .collect::<Vec<_>>();
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
        let module_type_dispatch_buf = storage_u32_rw(
            device,
            "codegen.wasm.module_type_dispatch",
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
        let body_plan_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_plan",
            WASM_BODY_PLAN_WORDS,
            wgpu::BufferUsages::COPY_SRC,
        );
        let wasm_func_flag_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_flag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_decl_flag_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_decl_flag",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_slot_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_slot_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_token_by_slot_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_token_by_slot",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_param_ordinal_by_decl_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_param_ordinal_by_decl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_body_len_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_body_len_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_local_max_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_local_max_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_return_count_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_return_count_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_invalid_count_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_invalid_count_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let wasm_func_return_token_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_return_token_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_detail_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_detail_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let wasm_func_scan_local_prefix_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_scan_local_prefix",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_scan_block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_scan_block_sum",
            func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_scan_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_scan_prefix_a",
            func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_func_scan_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.func_scan_prefix_b",
            func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_let_init_expr_by_decl_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_let_init_expr_by_decl_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_fragment_len_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_fragment_len",
            body_item_capacity as usize,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_fragment_meta_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_fragment_meta",
            body_item_capacity as usize * 4,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_fragment_aux_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_fragment_aux",
            body_item_capacity as usize * 4,
            wgpu::BufferUsages::COPY_SRC,
        );
        let body_scan_local_prefix_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_scan_local_prefix",
            body_item_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_scan_block_sum",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_scan_prefix_a",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let body_scan_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.body_scan_prefix_b",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_count_by_fragment_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.count_by_fragment",
            body_item_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_count_local_prefix_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.count_local_prefix",
            body_item_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_count_block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.count_block_sum",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_count_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.count_prefix_a",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_count_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.count_prefix_b",
            body_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_len_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.len",
            arg_record_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_meta_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.meta",
            arg_record_capacity as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_aux_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.aux",
            arg_record_capacity as usize * 4,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_byte_local_prefix_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.byte_local_prefix",
            arg_record_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_byte_block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.byte_block_sum",
            arg_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_byte_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.byte_prefix_a",
            arg_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_call_arg_byte_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg_call_arg.byte_prefix_b",
            arg_scan_blocks as usize,
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
        let wasm_agg_local_width_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.local_width_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_local_base_by_token_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.local_base_by_token",
            token_capacity as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_scan_block_sum_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.scan_block_sum",
            func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_scan_prefix_a_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.scan_prefix_a",
            func_scan_blocks as usize,
            wgpu::BufferUsages::empty(),
        );
        let wasm_agg_scan_prefix_b_buf = storage_u32_rw(
            device,
            "codegen.wasm.agg.scan_prefix_b",
            func_scan_blocks as usize,
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
        let body_plan_readback =
            readback_u32s(device, "rb.codegen.wasm.body_plan", WASM_BODY_PLAN_WORDS);
        let body_fragment_len_readback = readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_len",
            body_item_capacity as usize,
        );
        let body_fragment_aux_readback = readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_aux",
            body_item_capacity as usize * 4,
        );
        let body_fragment_meta_readback = readback_u32s(
            device,
            "rb.codegen.wasm.body_fragment_meta",
            body_item_capacity as usize * 4,
        );
        let wasm_func_invalid_count_readback = readback_u32s(
            device,
            "rb.codegen.wasm.func_invalid_count",
            token_capacity as usize,
        );
        let wasm_func_detail_readback = readback_u32s(
            device,
            "rb.codegen.wasm.func_detail",
            token_capacity as usize,
        );

        let wasm_const_values_bind_group = create_wasm_bind_group(
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
                    "hir_expr_float_bits",
                    expr_metadata.float_bits.as_entire_binding(),
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
                    (
                        "member_result_field_node",
                        struct_metadata.member_result_field_node.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_width_by_token",
                        wasm_agg_local_width_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_base_by_token",
                        wasm_agg_local_base_by_token_buf.as_entire_binding(),
                    ),
                ]);
            }};
        }

        let mut agg_layout_clear_bindings = vec![("gParams", params_buf.as_entire_binding())];
        add_aggregate_layout_output_bindings!(agg_layout_clear_bindings);
        let agg_layout_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_agg_layout_clear"),
            &self.agg_layout_clear_pass,
            0,
            &agg_layout_clear_bindings,
        )?;

        let agg_layout_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("hir_status", hir_status_buf.as_entire_binding()),
            ("hir_kind", hir_kind_buf.as_entire_binding()),
            ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
            (
                "hir_stmt_record",
                expr_metadata.stmt_record.as_entire_binding(),
            ),
            (
                "hir_expr_result_root_node",
                expr_metadata.result_root_node.as_entire_binding(),
            ),
            (
                "hir_struct_decl_field_count",
                struct_metadata.struct_decl_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node",
                struct_metadata.lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_count",
                struct_metadata.lit_field_count.as_entire_binding(),
            ),
            (
                "hir_struct_lit_field_parent_lit",
                struct_metadata.lit_field_parent_lit.as_entire_binding(),
            ),
            (
                "hir_member_name_token",
                struct_metadata.member_name_token.as_entire_binding(),
            ),
            (
                "member_result_field_ordinal",
                struct_metadata
                    .member_result_field_ordinal
                    .as_entire_binding(),
            ),
            (
                "type_decl_hir_node_by_token",
                type_decl_hir_node_by_token_buf.as_entire_binding(),
            ),
            ("visible_type", visible_type_buf.as_entire_binding()),
            ("call_return_type", call_return_type_buf.as_entire_binding()),
            (
                "struct_init_field_ordinal_by_node",
                struct_metadata
                    .struct_init_field_ordinal_by_node
                    .as_entire_binding(),
            ),
            (
                "struct_init_field_index",
                struct_init_field_index_buf.as_entire_binding(),
            ),
            (
                "member_result_field_index",
                member_result_field_index_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_local_width_by_token",
                wasm_agg_local_width_by_token_buf.as_entire_binding(),
            ),
        ];
        let agg_layout_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_agg_layout"),
            &self.agg_layout_pass,
            0,
            &agg_layout_bindings,
        )?;

        macro_rules! add_hir_body_common_bindings {
            ($bindings:expr, $agg_scan_block_prefix:expr) => {{
                $bindings.extend([
                    ("gParams", params_buf.as_entire_binding()),
                    ("hir_status", hir_status_buf.as_entire_binding()),
                    ("parent", parent_buf.as_entire_binding()),
                    ("first_child", first_child_buf.as_entire_binding()),
                    ("hir_kind", hir_kind_buf.as_entire_binding()),
                    ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                    ("hir_token_end", hir_token_end_buf.as_entire_binding()),
                    ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                    ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                    ("language_name_id", language_name_id_buf.as_entire_binding()),
                    (
                        "fn_entrypoint_tag",
                        fn_entrypoint_tag_buf.as_entire_binding(),
                    ),
                    ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                    ("visible_decl", visible_decl_buf.as_entire_binding()),
                    ("visible_type", visible_type_buf.as_entire_binding()),
                    (
                        "wasm_const_value_record",
                        wasm_const_value_record_buf.as_entire_binding(),
                    ),
                    (
                        "body_let_init_expr_by_decl_token",
                        body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_width_by_token",
                        wasm_agg_local_width_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_base_by_token",
                        wasm_agg_local_base_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_block_prefix",
                        $agg_scan_block_prefix.as_entire_binding(),
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
                        "hir_expr_float_bits",
                        expr_metadata.float_bits.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_start",
                        expr_metadata.string_start.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_len",
                        expr_metadata.string_len.as_entire_binding(),
                    ),
                    (
                        "hir_array_lit_first_element",
                        array_metadata.lit_first_element.as_entire_binding(),
                    ),
                    (
                        "hir_array_lit_element_count",
                        array_metadata.lit_element_count.as_entire_binding(),
                    ),
                    (
                        "hir_array_lit_context_stmt_node",
                        array_metadata.lit_context_stmt_node.as_entire_binding(),
                    ),
                    (
                        "hir_array_element_parent_lit",
                        array_metadata.element_parent_lit.as_entire_binding(),
                    ),
                    (
                        "hir_array_element_ordinal",
                        array_metadata.element_ordinal.as_entire_binding(),
                    ),
                    (
                        "hir_array_element_next",
                        array_metadata.element_next.as_entire_binding(),
                    ),
                    (
                        "hir_member_receiver_node",
                        struct_metadata.member_receiver_node.as_entire_binding(),
                    ),
                    (
                        "hir_member_name_token",
                        struct_metadata.member_name_token.as_entire_binding(),
                    ),
                    (
                        "hir_struct_lit_field_parent_lit",
                        struct_metadata.lit_field_parent_lit.as_entire_binding(),
                    ),
                    (
                        "hir_struct_lit_field_start",
                        struct_metadata.lit_field_start.as_entire_binding(),
                    ),
                    (
                        "hir_struct_lit_field_count",
                        struct_metadata.lit_field_count.as_entire_binding(),
                    ),
                    (
                        "hir_struct_lit_field_value_node",
                        struct_metadata.lit_field_value_node.as_entire_binding(),
                    ),
                    (
                        "hir_struct_lit_field_next",
                        struct_metadata.lit_field_next.as_entire_binding(),
                    ),
                    (
                        "struct_init_field_index",
                        struct_init_field_index_buf.as_entire_binding(),
                    ),
                    (
                        "struct_init_field_decl_node_by_node",
                        struct_metadata
                            .struct_init_field_decl_node_by_node
                            .as_entire_binding(),
                    ),
                    (
                        "member_result_field_index",
                        member_result_field_index_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_field_node",
                        struct_metadata.member_result_field_node.as_entire_binding(),
                    ),
                    (
                        "path_count_out",
                        path_metadata.count_out.as_entire_binding(),
                    ),
                    (
                        "path_segment_count",
                        path_metadata.segment_count.as_entire_binding(),
                    ),
                    (
                        "path_segment_base",
                        path_metadata.segment_base.as_entire_binding(),
                    ),
                    (
                        "path_segment_token",
                        path_metadata.segment_token.as_entire_binding(),
                    ),
                    (
                        "path_id_by_owner_hir",
                        path_metadata.id_by_owner_hir.as_entire_binding(),
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
                        "hir_nearest_loop_node",
                        expr_metadata.nearest_loop_node.as_entire_binding(),
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
                        "hir_call_arg_count",
                        call_metadata.arg_count.as_entire_binding(),
                    ),
                    (
                        "hir_call_arg_ordinal",
                        call_metadata.arg_ordinal.as_entire_binding(),
                    ),
                    (
                        "call_arg_row_node",
                        call_metadata.arg_row_node.as_entire_binding(),
                    ),
                    (
                        "call_arg_row_start",
                        call_metadata.arg_row_start.as_entire_binding(),
                    ),
                    (
                        "call_arg_row_count",
                        call_metadata.arg_row_count.as_entire_binding(),
                    ),
                    (
                        "call_intrinsic_tag",
                        call_intrinsic_tag_buf.as_entire_binding(),
                    ),
                    ("call_return_type", call_return_type_buf.as_entire_binding()),
                    (
                        "call_param_row_count_out",
                        call_metadata.param_row_count_out.as_entire_binding(),
                    ),
                    (
                        "call_param_row_fn_token",
                        call_metadata.param_row_fn_token.as_entire_binding(),
                    ),
                    (
                        "call_param_row_ordinal",
                        call_metadata.param_row_ordinal.as_entire_binding(),
                    ),
                    (
                        "call_param_row_type",
                        call_metadata.param_row_type.as_entire_binding(),
                    ),
                    (
                        "call_param_row_start",
                        call_metadata.param_row_start.as_entire_binding(),
                    ),
                    (
                        "call_param_row_count",
                        call_metadata.param_row_count.as_entire_binding(),
                    ),
                    ("call_param_count", call_param_count_buf.as_entire_binding()),
                    ("call_param_type", call_param_type_buf.as_entire_binding()),
                    ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                    (
                        "wasm_func_slot_by_token",
                        wasm_func_slot_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_param_ordinal_by_decl_token",
                        wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_body_len_by_token",
                        wasm_func_body_len_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_local_max_by_token",
                        wasm_func_local_max_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_return_count_by_token",
                        wasm_func_return_count_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_invalid_count_by_token",
                        wasm_func_invalid_count_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_return_token_by_token",
                        wasm_func_return_token_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_detail_by_token",
                        wasm_func_detail_by_token_buf.as_entire_binding(),
                    ),
                ]);
            }};
        }

        let hir_body_let_init_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_let_init_clear"),
            &self.hir_body_let_init_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_body_let_init_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_let_init"),
            &self.hir_body_let_init_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                (
                    "hir_stmt_record",
                    expr_metadata.stmt_record.as_entire_binding(),
                ),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_functions_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_clear"),
            &self.hir_functions_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_body_len_by_token",
                    wasm_func_body_len_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_local_max_by_token",
                    wasm_func_local_max_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_return_count_by_token",
                    wasm_func_return_count_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_invalid_count_by_token",
                    wasm_func_invalid_count_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_return_token_by_token",
                    wasm_func_return_token_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_detail_by_token",
                    wasm_func_detail_by_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_functions_mark_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_mark"),
            &self.hir_functions_mark_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_item_kind", hir_item_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                (
                    "fn_entrypoint_tag",
                    fn_entrypoint_tag_buf.as_entire_binding(),
                ),
                ("hir_param_record", hir_param_record_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_functions_reach_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_reach"),
            &self.hir_functions_reach_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("hir_expr_record", expr_metadata.record.as_entire_binding()),
                (
                    "path_count_out",
                    path_metadata.count_out.as_entire_binding(),
                ),
                (
                    "path_segment_count",
                    path_metadata.segment_count.as_entire_binding(),
                ),
                (
                    "path_segment_base",
                    path_metadata.segment_base.as_entire_binding(),
                ),
                (
                    "path_segment_token",
                    path_metadata.segment_token.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_hir",
                    path_metadata.id_by_owner_hir.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_member_name_token",
                    struct_metadata.member_name_token.as_entire_binding(),
                ),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                (
                    "call_intrinsic_tag",
                    call_intrinsic_tag_buf.as_entire_binding(),
                ),
                ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                ("language_name_id", language_name_id_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
            ],
        )?;

        let hir_functions_count_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_count"),
            &self.hir_functions_count_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_decl_flag",
                    wasm_func_decl_flag_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
            ],
        )?;

        let hir_func_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_func_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", func_scan_param_bufs[0].as_entire_binding()),
                ("body_fragment_len", wasm_func_flag_buf.as_entire_binding()),
                (
                    "body_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_func_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_func_scan_block_bind_groups = (0..func_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_func_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_func_scan_prefix_a_buf
                } else {
                    &wasm_func_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_func_scan_prefix_a_buf
                } else {
                    &wasm_func_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_hir_func_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", func_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_func_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let hir_agg_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_agg_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", func_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_local_width_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_local_base_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_agg_scan_block_bind_groups = (0..func_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_scan_prefix_a_buf
                } else {
                    &wasm_agg_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_scan_prefix_a_buf
                } else {
                    &wasm_agg_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some(&format!("codegen_wasm_hir_agg_scan_blocks.{step_i}")),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", func_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let final_agg_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_agg_scan_prefix_a_buf
        } else {
            &wasm_agg_scan_prefix_b_buf
        };

        let final_func_scan_block_prefix = if (func_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_func_scan_prefix_a_buf
        } else {
            &wasm_func_scan_prefix_b_buf
        };

        let hir_functions_scatter_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_functions_scatter"),
            &self.hir_functions_scatter_pass,
            0,
            &[
                (
                    "gScan",
                    func_scan_param_bufs
                        .last()
                        .expect("function scan has at least one parameter buffer")
                        .as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
            ],
        )?;

        let mut hir_body_plan_collect_bindings = Vec::new();
        add_hir_body_common_bindings!(hir_body_plan_collect_bindings, final_agg_scan_block_prefix);
        hir_body_plan_collect_bindings.extend([
            ("status", status_buf.as_entire_binding()),
            ("hir_semantic_count", semantic_hir.count.as_entire_binding()),
            (
                "hir_semantic_prefix_before_node",
                semantic_hir.prefix_before_node.as_entire_binding(),
            ),
            (
                "hir_semantic_dense_node",
                semantic_hir.dense_node.as_entire_binding(),
            ),
            (
                "hir_semantic_subtree_end",
                semantic_hir.subtree_end.as_entire_binding(),
            ),
            (
                "hir_semantic_parent",
                semantic_hir.parent.as_entire_binding(),
            ),
            (
                "hir_semantic_first_child",
                semantic_hir.first_child.as_entire_binding(),
            ),
            (
                "hir_semantic_next_sibling",
                semantic_hir.next_sibling.as_entire_binding(),
            ),
            ("hir_semantic_depth", semantic_hir.depth.as_entire_binding()),
            (
                "hir_semantic_child_index",
                semantic_hir.child_index.as_entire_binding(),
            ),
            ("body_plan", body_plan_buf.as_entire_binding()),
        ]);
        let hir_body_plan_collect_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_collect"),
            &self.hir_body_plan_collect_pass,
            0,
            &hir_body_plan_collect_bindings,
        )?;

        let mut hir_body_plan_validate_bindings = Vec::new();
        add_hir_body_common_bindings!(hir_body_plan_validate_bindings, final_agg_scan_block_prefix);
        hir_body_plan_validate_bindings.extend([
            (
                "parser_feature_flags",
                parser_feature_flags_buf.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            (
                "hir_struct_lit_context_stmt_node",
                struct_metadata.lit_context_stmt_node.as_entire_binding(),
            ),
            (
                "struct_init_field_ordinal_by_node",
                struct_metadata
                    .struct_init_field_ordinal_by_node
                    .as_entire_binding(),
            ),
        ]);
        let hir_body_plan_validate_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate"),
            &self.hir_body_plan_validate_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return"),
            &self.hir_body_plan_validate_return_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_call"),
            &self.hir_body_plan_validate_return_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_agg_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_agg_call"),
            &self.hir_body_plan_validate_return_agg_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_nested_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_nested_call"),
            &self.hir_body_plan_validate_return_nested_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_assign_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_assign"),
            &self.hir_body_plan_validate_assign_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_control_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_control"),
            &self.hir_body_plan_validate_control_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_agg_range_control_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_agg_range_control"),
            &self.hir_body_plan_validate_agg_range_control_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_if_simple_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_if_simple"),
            &self.hir_body_plan_validate_if_simple_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_print_simple_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_print_simple"),
            &self.hir_body_plan_validate_print_simple_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_call"),
            &self.hir_body_plan_validate_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_host_void_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_host_void_call"),
            &self.hir_body_plan_validate_host_void_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host"),
            &self.hir_body_plan_validate_let_host_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_env_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_env"),
            &self.hir_body_plan_validate_let_host_env_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_io_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_io"),
            &self.hir_body_plan_validate_let_host_io_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_host_string_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_host_string"),
            &self.hir_body_plan_validate_let_host_string_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_host_io_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_host_io"),
            &self.hir_body_plan_validate_return_host_io_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_return_host_string_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_return_host_string"),
            &self.hir_body_plan_validate_return_host_string_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_direct_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_direct_call"),
            &self.hir_body_plan_validate_let_direct_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_call"),
            &self.hir_body_plan_validate_let_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_validate_let_call_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_validate_let_call_status"),
            &self.hir_body_plan_validate_let_call_status_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_agg_direct_call_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_agg_direct_call"),
            &self.hir_body_plan_agg_direct_call_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;
        let hir_body_plan_agg_struct_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_agg_struct"),
            &self.hir_body_plan_agg_struct_pass,
            0,
            &hir_body_plan_validate_bindings,
        )?;

        let hir_body_plan_arrays_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_arrays"),
            &self.hir_body_plan_arrays_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
                ("hir_status", hir_status_buf.as_entire_binding()),
                (
                    "parser_feature_flags",
                    parser_feature_flags_buf.as_entire_binding(),
                ),
                ("parent", parent_buf.as_entire_binding()),
                ("first_child", first_child_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                ("visible_type", visible_type_buf.as_entire_binding()),
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
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
                (
                    "hir_array_lit_context_stmt_node",
                    array_metadata.lit_context_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_array_element_parent_lit",
                    array_metadata.element_parent_lit.as_entire_binding(),
                ),
                (
                    "hir_array_element_ordinal",
                    array_metadata.element_ordinal.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_field_parent_lit",
                    struct_metadata.lit_field_parent_lit.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_context_stmt_node",
                    struct_metadata.lit_context_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_struct_lit_field_value_node",
                    struct_metadata.lit_field_value_node.as_entire_binding(),
                ),
                (
                    "hir_member_receiver_node",
                    struct_metadata.member_receiver_node.as_entire_binding(),
                ),
                (
                    "hir_member_name_token",
                    struct_metadata.member_name_token.as_entire_binding(),
                ),
                (
                    "member_result_field_index",
                    member_result_field_index_buf.as_entire_binding(),
                ),
                (
                    "struct_init_field_index",
                    struct_init_field_index_buf.as_entire_binding(),
                ),
                (
                    "struct_init_field_ordinal_by_node",
                    struct_metadata
                        .struct_init_field_ordinal_by_node
                        .as_entire_binding(),
                ),
                (
                    "wasm_agg_local_width_by_token",
                    wasm_agg_local_width_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_base_by_token",
                    wasm_agg_local_base_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_block_prefix",
                    final_agg_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "path_count_out",
                    path_metadata.count_out.as_entire_binding(),
                ),
                (
                    "path_segment_count",
                    path_metadata.segment_count.as_entire_binding(),
                ),
                (
                    "path_segment_base",
                    path_metadata.segment_base.as_entire_binding(),
                ),
                (
                    "path_segment_token",
                    path_metadata.segment_token.as_entire_binding(),
                ),
                (
                    "path_id_by_owner_hir",
                    path_metadata.id_by_owner_hir.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "call_arg_row_node",
                    call_metadata.arg_row_node.as_entire_binding(),
                ),
                (
                    "call_arg_row_start",
                    call_metadata.arg_row_start.as_entire_binding(),
                ),
                (
                    "call_arg_row_count",
                    call_metadata.arg_row_count.as_entire_binding(),
                ),
                ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                (
                    "call_intrinsic_tag",
                    call_intrinsic_tag_buf.as_entire_binding(),
                ),
                (
                    "method_decl_param_offset",
                    method_decl_param_offset_buf.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_type", call_param_type_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
                ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                (
                    "wasm_func_slot_by_token",
                    wasm_func_slot_by_token_buf.as_entire_binding(),
                ),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_body_len_by_token",
                    wasm_func_body_len_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_local_max_by_token",
                    wasm_func_local_max_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_invalid_count_by_token",
                    wasm_func_invalid_count_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_func_detail_by_token",
                    wasm_func_detail_by_token_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                ("body_plan", body_plan_buf.as_entire_binding()),
            ],
        )?;

        let mut hir_body_plan_functions_bindings = Vec::new();
        add_hir_body_common_bindings!(
            hir_body_plan_functions_bindings,
            final_agg_scan_block_prefix
        );
        hir_body_plan_functions_bindings.extend([
            ("status", status_buf.as_entire_binding()),
            ("body_plan", body_plan_buf.as_entire_binding()),
        ]);
        let hir_body_plan_functions_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_functions"),
            &self.hir_body_plan_functions_pass,
            0,
            &hir_body_plan_functions_bindings,
        )?;

        let mut hir_body_plan_finalize_bindings = Vec::new();
        add_hir_body_common_bindings!(hir_body_plan_finalize_bindings, final_agg_scan_block_prefix);
        hir_body_plan_finalize_bindings.extend([
            ("body_plan", body_plan_buf.as_entire_binding()),
            ("body_status", body_status_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ]);
        let hir_body_plan_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_plan_finalize"),
            &self.hir_body_plan_finalize_pass,
            0,
            &hir_body_plan_finalize_bindings,
        )?;

        let hir_body_clear_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_clear"),
            &self.hir_body_clear_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                ("body_plan", body_plan_buf.as_entire_binding()),
            ],
        )?;

        let mut hir_body_counts_bindings = Vec::new();
        add_hir_body_common_bindings!(hir_body_counts_bindings, final_agg_scan_block_prefix);
        hir_body_counts_bindings.extend([
            ("body_plan", body_plan_buf.as_entire_binding()),
            ("call_return_type", call_return_type_buf.as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
        ]);
        let hir_body_counts_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_counts"),
            &self.hir_body_counts_pass,
            0,
            &hir_body_counts_bindings,
        )?;

        let hir_body_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    body_scan_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;

        let hir_body_scan_block_bind_groups = (0..body_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &body_scan_block_sum_buf
                } else if step_i % 2 == 1 {
                    &body_scan_prefix_a_buf
                } else {
                    &body_scan_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &body_scan_prefix_a_buf
                } else {
                    &body_scan_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", body_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            body_scan_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;

        let final_body_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            &body_scan_prefix_a_buf
        } else {
            &body_scan_prefix_b_buf
        };
        let hir_body_agg_call_arg_counts_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_counts"),
            &self.hir_body_agg_call_arg_counts_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_call_arg_count_by_fragment",
                    wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_count_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_count_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_call_arg_count_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_count_scan_block_bind_groups = (0..body_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_call_arg_count_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_call_arg_count_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_count_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_call_arg_count_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_count_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_agg_call_arg_count_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", body_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_call_arg_count_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_arg_count_scan_block_prefix = if (body_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_agg_call_arg_count_prefix_a_buf
        } else {
            &wasm_agg_call_arg_count_prefix_b_buf
        };

        let mut hir_body_agg_call_arg_records_bindings = Vec::new();
        add_hir_body_common_bindings!(
            hir_body_agg_call_arg_records_bindings,
            final_agg_scan_block_prefix
        );
        hir_body_agg_call_arg_records_bindings.extend([
            ("gScan", body_scan_param_bufs[0].as_entire_binding()),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_scan_local_prefix",
                body_scan_local_prefix_buf.as_entire_binding(),
            ),
            (
                "body_scan_block_prefix",
                final_body_scan_block_prefix.as_entire_binding(),
            ),
            ("status", status_buf.as_entire_binding()),
            ("body_words", body_buf.as_entire_binding()),
            (
                "wasm_agg_call_arg_count_by_fragment",
                wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_local_prefix",
                wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_block_prefix",
                final_arg_count_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_len",
                wasm_agg_call_arg_len_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_meta",
                wasm_agg_call_arg_meta_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_aux",
                wasm_agg_call_arg_aux_buf.as_entire_binding(),
            ),
        ]);
        let hir_body_agg_call_arg_records_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_records"),
            &self.hir_body_agg_call_arg_records_pass,
            0,
            &hir_body_agg_call_arg_records_bindings,
        )?;
        let hir_body_direct_call_arg_records_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_direct_call_arg_records"),
            &self.hir_body_direct_call_arg_records_pass,
            0,
            &hir_body_agg_call_arg_records_bindings,
        )?;

        let hir_body_agg_call_arg_byte_scan_local_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_arg_byte_scan_local"),
            &self.hir_body_scan_local_pass,
            0,
            &[
                ("gScan", arg_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    wasm_agg_call_arg_len_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_sum",
                    wasm_agg_call_arg_byte_block_sum_buf.as_entire_binding(),
                ),
            ],
        )?;
        let hir_body_agg_call_arg_byte_scan_block_bind_groups = (0..arg_scan_param_bufs.len())
            .map(|step_i| {
                let input = if step_i == 0 {
                    &wasm_agg_call_arg_byte_block_sum_buf
                } else if step_i % 2 == 1 {
                    &wasm_agg_call_arg_byte_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_byte_prefix_b_buf
                };
                let output = if step_i % 2 == 0 {
                    &wasm_agg_call_arg_byte_prefix_a_buf
                } else {
                    &wasm_agg_call_arg_byte_prefix_b_buf
                };
                create_wasm_bind_group(
                    device,
                    Some("codegen_wasm_hir_body_agg_call_arg_byte_scan_blocks"),
                    &self.hir_body_scan_blocks_pass,
                    0,
                    &[
                        ("gScan", arg_scan_param_bufs[step_i].as_entire_binding()),
                        (
                            "body_scan_block_sum",
                            wasm_agg_call_arg_byte_block_sum_buf.as_entire_binding(),
                        ),
                        ("body_scan_block_prefix_in", input.as_entire_binding()),
                        ("body_scan_block_prefix_out", output.as_entire_binding()),
                    ],
                )
            })
            .collect::<Result<Vec<_>>>()?;
        let final_arg_byte_scan_block_prefix = if (arg_scan_param_bufs.len() - 1) % 2 == 0 {
            &wasm_agg_call_arg_byte_prefix_a_buf
        } else {
            &wasm_agg_call_arg_byte_prefix_b_buf
        };
        let mut hir_body_agg_call_finalize_bindings = Vec::new();
        add_hir_body_common_bindings!(
            hir_body_agg_call_finalize_bindings,
            final_agg_scan_block_prefix
        );
        hir_body_agg_call_finalize_bindings.extend([
            ("gScan", body_scan_param_bufs[0].as_entire_binding()),
            (
                "wasm_agg_call_arg_count_by_fragment",
                wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_local_prefix",
                wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_block_prefix",
                final_arg_count_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_len",
                wasm_agg_call_arg_len_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_local_prefix",
                wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_block_prefix",
                final_arg_byte_scan_block_prefix.as_entire_binding(),
            ),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
        ]);
        let hir_body_agg_call_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_agg_call_finalize"),
            &self.hir_body_agg_call_finalize_pass,
            0,
            &hir_body_agg_call_finalize_bindings,
        )?;
        let hir_body_direct_call_finalize_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_direct_call_finalize"),
            &self.hir_body_direct_call_finalize_pass,
            0,
            &hir_body_agg_call_finalize_bindings,
        )?;
        let hir_body_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_status"),
            &self.hir_body_status_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("body_status", body_status_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let create_hir_body_scatter_bind_group = |label: &'static str, pass: &LazyWasmPass| {
            create_wasm_bind_group(
                device,
                Some(label),
                pass,
                0,
                &[
                    ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                    ("gParams", params_buf.as_entire_binding()),
                    (
                        "body_fragment_len",
                        body_fragment_len_buf.as_entire_binding(),
                    ),
                    (
                        "body_fragment_meta",
                        body_fragment_meta_buf.as_entire_binding(),
                    ),
                    (
                        "body_fragment_aux",
                        body_fragment_aux_buf.as_entire_binding(),
                    ),
                    (
                        "body_scan_local_prefix",
                        body_scan_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "body_scan_block_prefix",
                        final_body_scan_block_prefix.as_entire_binding(),
                    ),
                    ("status", status_buf.as_entire_binding()),
                    ("hir_status", hir_status_buf.as_entire_binding()),
                    ("first_child", first_child_buf.as_entire_binding()),
                    ("hir_kind", hir_kind_buf.as_entire_binding()),
                    ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                    ("hir_token_end", hir_token_end_buf.as_entire_binding()),
                    ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
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
                        "hir_expr_float_bits",
                        expr_metadata.float_bits.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_start",
                        expr_metadata.string_start.as_entire_binding(),
                    ),
                    (
                        "hir_expr_string_len",
                        expr_metadata.string_len.as_entire_binding(),
                    ),
                    ("visible_type", visible_type_buf.as_entire_binding()),
                    ("visible_decl", visible_decl_buf.as_entire_binding()),
                    (
                        "wasm_const_value_record",
                        wasm_const_value_record_buf.as_entire_binding(),
                    ),
                    ("name_id_by_token", name_id_by_token_buf.as_entire_binding()),
                    ("language_name_id", language_name_id_buf.as_entire_binding()),
                    (
                        "body_let_init_expr_by_decl_token",
                        body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                    ),
                    (
                        "hir_nearest_enclosing_control_node",
                        expr_metadata
                            .nearest_enclosing_control_node
                            .as_entire_binding(),
                    ),
                    (
                        "hir_call_callee_node",
                        call_metadata.callee_node.as_entire_binding(),
                    ),
                    (
                        "hir_call_arg_count",
                        call_metadata.arg_count.as_entire_binding(),
                    ),
                    (
                        "hir_member_receiver_node",
                        struct_metadata.member_receiver_node.as_entire_binding(),
                    ),
                    (
                        "hir_member_name_token",
                        struct_metadata.member_name_token.as_entire_binding(),
                    ),
                    (
                        "path_count_out",
                        path_metadata.count_out.as_entire_binding(),
                    ),
                    (
                        "path_segment_count",
                        path_metadata.segment_count.as_entire_binding(),
                    ),
                    (
                        "path_segment_base",
                        path_metadata.segment_base.as_entire_binding(),
                    ),
                    (
                        "path_segment_token",
                        path_metadata.segment_token.as_entire_binding(),
                    ),
                    (
                        "path_id_by_owner_hir",
                        path_metadata.id_by_owner_hir.as_entire_binding(),
                    ),
                    ("call_fn_index", call_fn_index_buf.as_entire_binding()),
                    (
                        "call_intrinsic_tag",
                        call_intrinsic_tag_buf.as_entire_binding(),
                    ),
                    ("call_return_type", call_return_type_buf.as_entire_binding()),
                    (
                        "call_param_row_count_out",
                        call_metadata.param_row_count_out.as_entire_binding(),
                    ),
                    (
                        "call_param_row_fn_token",
                        call_metadata.param_row_fn_token.as_entire_binding(),
                    ),
                    (
                        "call_param_row_ordinal",
                        call_metadata.param_row_ordinal.as_entire_binding(),
                    ),
                    (
                        "call_param_row_type",
                        call_metadata.param_row_type.as_entire_binding(),
                    ),
                    (
                        "call_param_row_start",
                        call_metadata.param_row_start.as_entire_binding(),
                    ),
                    (
                        "call_param_row_count",
                        call_metadata.param_row_count.as_entire_binding(),
                    ),
                    (
                        "member_result_field_index",
                        member_result_field_index_buf.as_entire_binding(),
                    ),
                    (
                        "member_result_field_node",
                        struct_metadata.member_result_field_node.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_width_by_token",
                        wasm_agg_local_width_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_base_by_token",
                        wasm_agg_local_base_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_local_block_prefix",
                        final_agg_scan_block_prefix.as_entire_binding(),
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
                        "call_arg_row_node",
                        call_metadata.arg_row_node.as_entire_binding(),
                    ),
                    (
                        "call_arg_row_start",
                        call_metadata.arg_row_start.as_entire_binding(),
                    ),
                    (
                        "call_arg_row_count",
                        call_metadata.arg_row_count.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_count_by_fragment",
                        wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_count_local_prefix",
                        wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_count_block_prefix",
                        final_arg_count_scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_len",
                        wasm_agg_call_arg_len_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_byte_local_prefix",
                        wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_agg_call_arg_byte_block_prefix",
                        final_arg_byte_scan_block_prefix.as_entire_binding(),
                    ),
                    (
                        "wasm_func_param_ordinal_by_decl_token",
                        wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                    ),
                    ("call_param_count", call_param_count_buf.as_entire_binding()),
                    ("call_param_type", call_param_type_buf.as_entire_binding()),
                    ("wasm_func_flag", wasm_func_flag_buf.as_entire_binding()),
                    (
                        "wasm_func_slot_by_token",
                        wasm_func_slot_by_token_buf.as_entire_binding(),
                    ),
                    (
                        "wasm_func_local_max_by_token",
                        wasm_func_local_max_by_token_buf.as_entire_binding(),
                    ),
                    ("body_words", body_buf.as_entire_binding()),
                ],
            )
        };
        let hir_body_scatter_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter",
            &self.hir_body_scatter_pass,
        )?;
        let hir_body_scatter_frame_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_frame"),
            &self.hir_body_scatter_frame_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_if_simple_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_if_simple",
            &self.hir_body_scatter_if_simple_pass,
        )?;
        let hir_body_scatter_return_scalar_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_return_scalar"),
            &self.hir_body_scatter_return_scalar_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_return_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_return_expr",
            &self.hir_body_scatter_return_expr_pass,
        )?;
        let hir_body_scatter_conversion_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_conversion_expr",
            &self.hir_body_scatter_conversion_expr_pass,
        )?;
        let hir_body_scatter_let_const_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_let_const"),
            &self.hir_body_scatter_let_const_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_expr_control_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_expr_control",
            &self.hir_body_scatter_expr_control_pass,
        )?;
        let hir_body_scatter_agg_range_control_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_range_control",
            &self.hir_body_scatter_agg_range_control_pass,
        )?;
        let hir_body_scatter_let_direct_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_let_direct",
            &self.hir_body_scatter_let_direct_pass,
        )?;
        let hir_body_scatter_direct_nested_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_direct_nested_call",
            &self.hir_body_scatter_direct_nested_call_pass,
        )?;
        let hir_body_scatter_host_io_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_host_io",
            &self.hir_body_scatter_host_io_pass,
        )?;
        let hir_body_scatter_host_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_host",
            &self.hir_body_scatter_host_pass,
        )?;
        let hir_body_scatter_arrays_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_arrays"),
            &self.hir_body_scatter_arrays_pass,
            0,
            &[
                ("gScan", body_scan_param_bufs[0].as_entire_binding()),
                ("gParams", params_buf.as_entire_binding()),
                (
                    "body_fragment_len",
                    body_fragment_len_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_meta",
                    body_fragment_meta_buf.as_entire_binding(),
                ),
                (
                    "body_fragment_aux",
                    body_fragment_aux_buf.as_entire_binding(),
                ),
                (
                    "body_scan_local_prefix",
                    body_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "body_scan_block_prefix",
                    final_body_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("hir_kind", hir_kind_buf.as_entire_binding()),
                ("hir_token_pos", hir_token_pos_buf.as_entire_binding()),
                ("enclosing_fn", enclosing_fn_buf.as_entire_binding()),
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
                    "hir_expr_float_bits",
                    expr_metadata.float_bits.as_entire_binding(),
                ),
                (
                    "hir_call_callee_node",
                    call_metadata.callee_node.as_entire_binding(),
                ),
                (
                    "hir_call_arg_count",
                    call_metadata.arg_count.as_entire_binding(),
                ),
                (
                    "hir_array_lit_context_stmt_node",
                    array_metadata.lit_context_stmt_node.as_entire_binding(),
                ),
                (
                    "hir_member_receiver_node",
                    struct_metadata.member_receiver_node.as_entire_binding(),
                ),
                (
                    "hir_member_name_token",
                    struct_metadata.member_name_token.as_entire_binding(),
                ),
                ("visible_type", visible_type_buf.as_entire_binding()),
                ("visible_decl", visible_decl_buf.as_entire_binding()),
                (
                    "body_let_init_expr_by_decl_token",
                    body_let_init_expr_by_decl_token_buf.as_entire_binding(),
                ),
                (
                    "member_result_field_index",
                    member_result_field_index_buf.as_entire_binding(),
                ),
                (
                    "member_result_field_node",
                    struct_metadata.member_result_field_node.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_width_by_token",
                    wasm_agg_local_width_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_base_by_token",
                    wasm_agg_local_base_by_token_buf.as_entire_binding(),
                ),
                (
                    "wasm_agg_local_block_prefix",
                    final_agg_scan_block_prefix.as_entire_binding(),
                ),
                (
                    "method_decl_param_offset",
                    method_decl_param_offset_buf.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_type", call_param_type_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                (
                    "call_arg_row_node",
                    call_metadata.arg_row_node.as_entire_binding(),
                ),
                (
                    "call_arg_row_start",
                    call_metadata.arg_row_start.as_entire_binding(),
                ),
                (
                    "call_arg_row_count",
                    call_metadata.arg_row_count.as_entire_binding(),
                ),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                (
                    "wasm_func_param_ordinal_by_decl_token",
                    wasm_func_param_ordinal_by_decl_token_buf.as_entire_binding(),
                ),
                ("body_words", body_buf.as_entire_binding()),
            ],
        )?;
        let hir_body_scatter_agg_copy_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_copy",
            &self.hir_body_scatter_agg_copy_pass,
        )?;
        let hir_body_scatter_array_lean_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_array_lean",
            &self.hir_body_scatter_array_lean_pass,
        )?;
        let hir_body_scatter_return_member_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_return_member",
            &self.hir_body_scatter_return_member_pass,
        )?;
        let mut hir_body_scatter_agg_call_args_bindings = Vec::new();
        add_hir_body_common_bindings!(
            hir_body_scatter_agg_call_args_bindings,
            final_agg_scan_block_prefix
        );
        hir_body_scatter_agg_call_args_bindings.extend([
            ("gBodyScan", body_scan_param_bufs[0].as_entire_binding()),
            ("gArgScan", arg_scan_param_bufs[0].as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
            (
                "body_fragment_len",
                body_fragment_len_buf.as_entire_binding(),
            ),
            (
                "body_fragment_meta",
                body_fragment_meta_buf.as_entire_binding(),
            ),
            (
                "body_fragment_aux",
                body_fragment_aux_buf.as_entire_binding(),
            ),
            (
                "body_scan_local_prefix",
                body_scan_local_prefix_buf.as_entire_binding(),
            ),
            (
                "body_scan_block_prefix",
                final_body_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_by_fragment",
                wasm_agg_call_arg_count_by_fragment_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_local_prefix",
                wasm_agg_call_arg_count_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_count_block_prefix",
                final_arg_count_scan_block_prefix.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_len",
                wasm_agg_call_arg_len_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_meta",
                wasm_agg_call_arg_meta_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_aux",
                wasm_agg_call_arg_aux_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_local_prefix",
                wasm_agg_call_arg_byte_local_prefix_buf.as_entire_binding(),
            ),
            (
                "wasm_agg_call_arg_byte_block_prefix",
                final_arg_byte_scan_block_prefix.as_entire_binding(),
            ),
            ("body_words", body_buf.as_entire_binding()),
        ]);
        let hir_body_scatter_agg_call_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_agg_call_args"),
            &self.hir_body_scatter_agg_call_args_pass,
            0,
            &hir_body_scatter_agg_call_args_bindings,
        )?;
        let hir_body_scatter_nested_call_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_body_scatter_nested_call_args"),
            &self.hir_body_scatter_nested_call_args_pass,
            0,
            &hir_body_scatter_agg_call_args_bindings,
        )?;
        let hir_body_scatter_agg_direct_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_agg_direct_call",
            &self.hir_body_scatter_agg_direct_call_pass,
        )?;
        let hir_body_scatter_return_agg_direct_call_bind_group =
            create_hir_body_scatter_bind_group(
                "codegen_wasm_hir_body_scatter_return_agg_direct_call",
                &self.hir_body_scatter_return_agg_direct_call_pass,
            )?;
        let hir_body_scatter_member_expr_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_member_expr",
            &self.hir_body_scatter_member_expr_pass,
        )?;
        let hir_body_scatter_binary_direct_call_bind_group = create_hir_body_scatter_bind_group(
            "codegen_wasm_hir_body_scatter_binary_direct_call",
            &self.hir_body_scatter_binary_direct_call_pass,
        )?;

        let hir_agg_body_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_agg_body_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_agg_body"),
            &self.hir_agg_body_pass,
            0,
            &hir_agg_body_bindings,
        )?;

        let hir_assert_module_bindings = [
            ("gParams", params_buf.as_entire_binding()),
            ("status", status_buf.as_entire_binding()),
        ];
        let hir_assert_module_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_hir_assert_module"),
            &self.hir_assert_module_pass,
            0,
            &hir_assert_module_bindings,
        )?;

        let hir_enum_match_records_bind_group = create_wasm_bind_group(
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

        let module_type_dispatch_args_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_dispatch_args"),
            &self.module_type_dispatch_args_pass,
            0,
            &[
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "module_type_dispatch_args",
                    module_type_dispatch_buf.as_entire_binding(),
                ),
            ],
        )?;

        let module_type_lengths_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_lengths"),
            &self.module_type_lengths_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
            ],
        )?;

        let module_type_bytes_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_type_bytes"),
            &self.module_type_bytes_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
                ("out_words", out_buf.as_entire_binding()),
            ],
        )?;

        let module_status_bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module_status"),
            &self.module_status_pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let bind_group = create_wasm_bind_group(
            device,
            Some("codegen_wasm_module"),
            &self.pass,
            0,
            &[
                ("gParams", params_buf.as_entire_binding()),
                ("source_bytes", source_buf.as_entire_binding()),
                ("body_words", body_buf.as_entire_binding()),
                ("body_status", body_status_buf.as_entire_binding()),
                ("body_plan", body_plan_buf.as_entire_binding()),
                (
                    "wasm_func_token_by_slot",
                    wasm_func_token_by_slot_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_entry_len_by_slot",
                    wasm_func_flag_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_local_prefix",
                    wasm_func_scan_local_prefix_buf.as_entire_binding(),
                ),
                (
                    "wasm_type_scan_block_prefix",
                    final_func_scan_block_prefix.as_entire_binding(),
                ),
                ("call_return_type", call_return_type_buf.as_entire_binding()),
                ("call_param_count", call_param_count_buf.as_entire_binding()),
                ("call_param_type", call_param_type_buf.as_entire_binding()),
                (
                    "call_param_row_count_out",
                    call_metadata.param_row_count_out.as_entire_binding(),
                ),
                (
                    "call_param_row_fn_token",
                    call_metadata.param_row_fn_token.as_entire_binding(),
                ),
                (
                    "call_param_row_ordinal",
                    call_metadata.param_row_ordinal.as_entire_binding(),
                ),
                (
                    "call_param_row_type",
                    call_metadata.param_row_type.as_entire_binding(),
                ),
                (
                    "call_param_row_start",
                    call_metadata.param_row_start.as_entire_binding(),
                ),
                (
                    "call_param_row_count",
                    call_metadata.param_row_count.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_mode",
                    method_decl_receiver_mode_buf.as_entire_binding(),
                ),
                ("out_words", out_buf.as_entire_binding()),
                ("status", status_buf.as_entire_binding()),
            ],
        )?;

        let pack_bind_group = create_wasm_bind_group(
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
            active_hir_dispatch_args_buf: active_hir_dispatch_args_buf.clone(),
            params_buf,
            body_scan_param_bufs,
            body_scan_blocks,
            arg_scan_param_bufs,
            arg_scan_blocks,
            func_scan_param_bufs,
            func_scan_blocks,
            body_dispatch_buf,
            _module_type_dispatch_buf: module_type_dispatch_buf,
            _body_buf: body_buf,
            body_plan_buf,
            _wasm_func_flag_buf: wasm_func_flag_buf,
            _wasm_func_decl_flag_buf: wasm_func_decl_flag_buf,
            _wasm_func_slot_by_token_buf: wasm_func_slot_by_token_buf,
            _wasm_func_token_by_slot_buf: wasm_func_token_by_slot_buf,
            _wasm_func_param_ordinal_by_decl_token_buf: wasm_func_param_ordinal_by_decl_token_buf,
            _wasm_func_body_len_by_token_buf: wasm_func_body_len_by_token_buf,
            _wasm_func_local_max_by_token_buf: wasm_func_local_max_by_token_buf,
            _wasm_func_return_count_by_token_buf: wasm_func_return_count_by_token_buf,
            _wasm_func_invalid_count_by_token_buf: wasm_func_invalid_count_by_token_buf,
            _wasm_func_return_token_by_token_buf: wasm_func_return_token_by_token_buf,
            _wasm_func_detail_by_token_buf: wasm_func_detail_by_token_buf,
            _wasm_func_scan_local_prefix_buf: wasm_func_scan_local_prefix_buf,
            _wasm_func_scan_block_sum_buf: wasm_func_scan_block_sum_buf,
            _wasm_func_scan_prefix_a_buf: wasm_func_scan_prefix_a_buf,
            _wasm_func_scan_prefix_b_buf: wasm_func_scan_prefix_b_buf,
            _body_let_init_expr_by_decl_token_buf: body_let_init_expr_by_decl_token_buf,
            _body_fragment_len_buf: body_fragment_len_buf,
            _body_fragment_meta_buf: body_fragment_meta_buf,
            _body_fragment_aux_buf: body_fragment_aux_buf,
            _body_scan_local_prefix_buf: body_scan_local_prefix_buf,
            _body_scan_block_sum_buf: body_scan_block_sum_buf,
            _body_scan_prefix_a_buf: body_scan_prefix_a_buf,
            _body_scan_prefix_b_buf: body_scan_prefix_b_buf,
            _wasm_agg_call_arg_count_by_fragment_buf: wasm_agg_call_arg_count_by_fragment_buf,
            _wasm_agg_call_arg_count_local_prefix_buf: wasm_agg_call_arg_count_local_prefix_buf,
            _wasm_agg_call_arg_count_block_sum_buf: wasm_agg_call_arg_count_block_sum_buf,
            _wasm_agg_call_arg_count_prefix_a_buf: wasm_agg_call_arg_count_prefix_a_buf,
            _wasm_agg_call_arg_count_prefix_b_buf: wasm_agg_call_arg_count_prefix_b_buf,
            _wasm_agg_call_arg_len_buf: wasm_agg_call_arg_len_buf,
            _wasm_agg_call_arg_meta_buf: wasm_agg_call_arg_meta_buf,
            _wasm_agg_call_arg_aux_buf: wasm_agg_call_arg_aux_buf,
            _wasm_agg_call_arg_byte_local_prefix_buf: wasm_agg_call_arg_byte_local_prefix_buf,
            _wasm_agg_call_arg_byte_block_sum_buf: wasm_agg_call_arg_byte_block_sum_buf,
            _wasm_agg_call_arg_byte_prefix_a_buf: wasm_agg_call_arg_byte_prefix_a_buf,
            _wasm_agg_call_arg_byte_prefix_b_buf: wasm_agg_call_arg_byte_prefix_b_buf,
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
            _wasm_agg_local_width_by_token_buf: wasm_agg_local_width_by_token_buf,
            _wasm_agg_local_base_by_token_buf: wasm_agg_local_base_by_token_buf,
            _wasm_agg_scan_block_sum_buf: wasm_agg_scan_block_sum_buf,
            _wasm_agg_scan_prefix_a_buf: wasm_agg_scan_prefix_a_buf,
            _wasm_agg_scan_prefix_b_buf: wasm_agg_scan_prefix_b_buf,
            _hir_enum_match_record_buf: hir_enum_match_record_buf,
            wasm_const_value_record_buf,
            out_buf,
            packed_out_buf,
            status_buf,
            out_readback,
            status_readback,
            body_plan_readback,
            body_fragment_len_readback,
            body_fragment_meta_readback,
            body_fragment_aux_readback,
            wasm_func_invalid_count_readback,
            wasm_func_detail_readback,
            agg_layout_clear_bind_group,
            agg_layout_bind_group,
            hir_body_let_init_clear_bind_group,
            hir_body_let_init_bind_group,
            hir_functions_clear_bind_group,
            hir_functions_mark_bind_group,
            hir_functions_reach_bind_group,
            hir_functions_count_bind_group,
            hir_func_scan_local_bind_group,
            hir_func_scan_block_bind_groups,
            hir_agg_scan_local_bind_group,
            hir_agg_scan_block_bind_groups,
            hir_functions_scatter_bind_group,
            hir_body_plan_collect_bind_group,
            hir_body_plan_validate_bind_group,
            hir_body_plan_validate_return_bind_group,
            hir_body_plan_validate_return_call_bind_group,
            hir_body_plan_validate_return_agg_call_bind_group,
            hir_body_plan_validate_return_nested_call_bind_group,
            hir_body_plan_validate_assign_bind_group,
            hir_body_plan_validate_control_bind_group,
            hir_body_plan_validate_agg_range_control_bind_group,
            hir_body_plan_validate_if_simple_bind_group,
            hir_body_plan_validate_print_simple_bind_group,
            hir_body_plan_validate_call_bind_group,
            hir_body_plan_validate_host_void_call_bind_group,
            hir_body_plan_validate_let_host_bind_group,
            hir_body_plan_validate_let_host_env_bind_group,
            hir_body_plan_validate_let_host_io_bind_group,
            hir_body_plan_validate_let_host_string_bind_group,
            hir_body_plan_validate_return_host_io_bind_group,
            hir_body_plan_validate_return_host_string_bind_group,
            hir_body_plan_validate_let_direct_call_bind_group,
            hir_body_plan_validate_let_call_bind_group,
            hir_body_plan_validate_let_call_status_bind_group,
            hir_body_plan_agg_direct_call_bind_group,
            hir_body_plan_agg_struct_bind_group,
            hir_body_plan_arrays_bind_group,
            hir_body_plan_functions_bind_group,
            hir_body_plan_finalize_bind_group,
            hir_body_clear_bind_group,
            hir_body_counts_bind_group,
            hir_body_scan_local_bind_group,
            hir_body_scan_block_bind_groups,
            hir_body_agg_call_arg_counts_bind_group,
            hir_body_agg_call_arg_count_scan_local_bind_group,
            hir_body_agg_call_arg_count_scan_block_bind_groups,
            hir_body_agg_call_arg_records_bind_group,
            hir_body_direct_call_arg_records_bind_group,
            hir_body_agg_call_arg_byte_scan_local_bind_group,
            hir_body_agg_call_arg_byte_scan_block_bind_groups,
            hir_body_agg_call_finalize_bind_group,
            hir_body_direct_call_finalize_bind_group,
            hir_body_status_bind_group,
            hir_body_scatter_bind_group,
            hir_body_scatter_frame_bind_group,
            hir_body_scatter_if_simple_bind_group,
            hir_body_scatter_return_scalar_bind_group,
            hir_body_scatter_return_expr_bind_group,
            hir_body_scatter_conversion_expr_bind_group,
            hir_body_scatter_let_const_bind_group,
            hir_body_scatter_expr_control_bind_group,
            hir_body_scatter_agg_range_control_bind_group,
            hir_body_scatter_let_direct_bind_group,
            hir_body_scatter_direct_nested_call_bind_group,
            hir_body_scatter_host_io_bind_group,
            hir_body_scatter_host_bind_group,
            hir_body_scatter_arrays_bind_group,
            hir_body_scatter_array_lean_bind_group,
            hir_body_scatter_agg_copy_bind_group,
            hir_body_scatter_agg_call_args_bind_group,
            hir_body_scatter_nested_call_args_bind_group,
            hir_body_scatter_agg_direct_call_bind_group,
            hir_body_scatter_return_agg_direct_call_bind_group,
            hir_body_scatter_return_member_bind_group,
            hir_body_scatter_member_expr_bind_group,
            hir_body_scatter_binary_direct_call_bind_group,
            hir_agg_body_bind_group,
            hir_assert_module_bind_group,
            hir_enum_match_records_bind_group,
            wasm_const_values_bind_group,
            module_type_lengths_bind_group,
            module_type_dispatch_args_bind_group,
            module_type_bytes_bind_group,
            module_status_bind_group,
            bind_group,
            pack_bind_group,
        })
    }
}
