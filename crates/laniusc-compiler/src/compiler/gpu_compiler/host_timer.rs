use super::*;

/// Host-side timing helper for GPU compiler orchestration.
pub(super) struct CompilerHostTimer {
    /// Prefix used for emitted timing labels.
    pub(super) label: &'static str,
    /// Whether timing should be printed to stdout.
    pub(super) print_enabled: bool,
    /// Whether timing spans should be written to the GPU trace recorder.
    pub(super) trace_enabled: bool,
    /// Start time for total elapsed duration.
    pub(super) start: std::time::Instant,
    /// Timestamp of the previous stage marker.
    pub(super) last: std::time::Instant,
}

impl CompilerHostTimer {
    /// Creates a timer whose output is controlled by compiler tracing environment variables.
    pub(super) fn new(label: &'static str) -> Self {
        let now = std::time::Instant::now();
        Self {
            label,
            print_enabled: crate::gpu::env::env_bool_truthy(
                "LANIUS_GPU_COMPILE_HOST_TIMING",
                false,
            ),
            trace_enabled: crate::gpu::trace::enabled(),
            start: now,
            last: now,
        }
    }

    /// Records elapsed time for one named compiler stage.
    pub(super) fn stamp(&mut self, stage: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let name = format!("{}.{stage}", self.label);
        if self.print_enabled {
            eprintln!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.compiler", &name, self.last, now);
        }
        self.last = now;
    }

    /// Samples and optionally traces the backend pipeline-cache byte size.
    pub(super) fn pipeline_cache_size(&self, gpu: &GpuDevice, stage: &str) {
        if !crate::gpu::env::env_bool_truthy("LANIUS_PIPELINE_CACHE_BREAKDOWN", false) {
            return;
        }
        let start = std::time::Instant::now();
        let size = gpu.pipeline_cache_data_len();
        let end = std::time::Instant::now();
        let sample_ms = end.duration_since(start).as_secs_f64() * 1000.0;
        match size {
            Some(bytes) => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes={bytes} sample_ms={sample_ms:.3}"
                );
                if self.trace_enabled {
                    crate::gpu::trace::record_host_span(
                        "host.pipeline_cache",
                        &format!("pipeline_cache.sample.{stage}"),
                        start,
                        end,
                    );
                    crate::gpu::trace::record_counter(
                        "host.pipeline_cache.size",
                        "pipeline_cache_bytes",
                        end,
                        bytes as f64,
                    );
                }
            }
            None => {
                eprintln!(
                    "[pipeline_cache_breakdown] stage={stage} bytes=unavailable sample_ms={sample_ms:.3}"
                );
            }
        }
    }
}
