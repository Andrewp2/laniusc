use crate::gpu::timer::MINIMUM_TIME_TO_NOT_ELIDE_MS;

pub(super) fn print_timer_trace(
    stamps: &[(String, u64)],
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
    let mut last = stamps[0].1;
    let mut total = 0.0f64;
    for (label, value) in stamps.iter().skip(1) {
        let dt_ms = value.saturating_sub(last) as f64 * period_ns as f64 / 1_000_000.0;
        let start_ms = total;
        total += dt_ms;
        if print_enabled && dt_ms >= min_ms {
            println!("[gpu_compile_timer] {label}: {dt_ms:.3}ms (total {total:.3}ms)");
        }
        let lane = if label.starts_with("x86.") {
            "gpu.x86"
        } else {
            "gpu.frontend"
        };
        crate::gpu::trace::record_gpu_span(lane, label, gpu_anchor, start_ms, dt_ms);
        last = *value;
    }
}

pub(super) struct HostCompileTimer {
    print_enabled: bool,
    trace_enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl HostCompileTimer {
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

    pub(super) fn stamp(&mut self, label: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        if self.print_enabled {
            println!("[gpu_compile_host_timer] {label}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.lexer", label, self.last, now);
        }
        self.last = now;
    }
}
