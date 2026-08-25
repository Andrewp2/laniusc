use crate::gpu::timer::{GpuTimestampSample, MINIMUM_TIME_TO_NOT_ELIDE_MS};

/// Prints and records GPU timing spans for combined lexer/compile submissions.
pub(crate) fn print_timer_trace(
    stamps: &[GpuTimestampSample],
    period_ns: f32,
    gpu_anchor: std::time::Instant,
) {
    if stamps.len() < 2 {
        return;
    }
    let min_ms = std::env::var("LANIUS_GPU_COMPILE_TIMING_MIN_MS")
        .ok()
        .and_then(|value| value.parse::<f64>().ok())
        .unwrap_or(MINIMUM_TIME_TO_NOT_ELIDE_MS);
    let print_enabled = crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_TIMING", false)
        || crate::gpu::env::env_bool_truthy("LANIUS_GPU_TIMING", false);
    let mut last = stamps[0].ticks;
    let mut total = 0.0f64;
    for sample in stamps.iter().skip(1) {
        let label = &sample.label;
        let value = sample.ticks;
        let dt_ms = value.saturating_sub(last) as f64 * period_ns as f64 / 1_000_000.0;
        let start_ms = total;
        total += dt_ms;
        let submission_gap = is_submission_begin(label);
        if print_enabled && dt_ms >= min_ms {
            let timer_kind = if submission_gap {
                "gpu_compile_submission_gap"
            } else {
                "gpu_compile_timer"
            };
            eprintln!("[{timer_kind}] {label}: {dt_ms:.3}ms (total {total:.3}ms)");
        }
        if submission_gap {
            crate::gpu::trace::record_gpu_submission_gap(
                "Between Lanius GPU submissions",
                gpu_anchor,
                start_ms,
                dt_ms,
            );
        } else {
            let lane = if label.starts_with("x86.") {
                "gpu.x86"
            } else {
                "gpu.frontend"
            };
            crate::gpu::trace::record_gpu_span(
                lane,
                label,
                sample.phase,
                gpu_anchor,
                start_ms,
                dt_ms,
            );
        }
        last = value;
    }
}

fn is_submission_begin(label: &str) -> bool {
    label.ends_with(".submission.begin")
}

#[cfg(test)]
mod tests {
    use super::is_submission_begin;

    #[test]
    fn recognizes_submission_boundaries_without_classifying_shader_markers() {
        assert!(is_submission_begin(
            "compile.source_pack.parser.submission.begin"
        ));
        assert!(!is_submission_begin("parser.tokens.impl_header.local.done"));
    }
}

/// Host-side timer used around lexer count-boundary compile paths.
pub(super) struct HostCompileTimer {
    print_enabled: bool,
    trace_enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl HostCompileTimer {
    /// Starts a host timer for compile paths that cross a lexer count boundary.
    pub(super) fn new() -> Self {
        let now = std::time::Instant::now();
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

    /// Records a labeled host timing span.
    pub(super) fn stamp(&mut self, label: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        if self.print_enabled {
            eprintln!("[gpu_compile_host_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.lexer", label, self.last, now);
        }
        self.last = now;
    }
}
