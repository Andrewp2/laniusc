/// Host-side timer for optional x86 recording trace and console timing output.
pub(super) struct HostTimer {
    print_enabled: bool,
    trace_enabled: bool,
    start: std::time::Instant,
    last: std::time::Instant,
}

impl HostTimer {
    /// Creates a timer using the current environment-controlled timing and tracing settings.
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

    /// Records a named host stage boundary when host timing or tracing is enabled.
    pub(super) fn stamp(&mut self, stage: &str) {
        if !self.print_enabled && !self.trace_enabled {
            return;
        }
        let now = std::time::Instant::now();
        let dt_ms = now.duration_since(self.last).as_secs_f64() * 1000.0;
        let total_ms = now.duration_since(self.start).as_secs_f64() * 1000.0;
        let name = format!("codegen.x86.record.{stage}");
        if self.print_enabled {
            println!("[gpu_compile_host_timer] {name}: {dt_ms:.3}ms (total {total_ms:.3}ms)");
        }
        if self.trace_enabled {
            crate::gpu::trace::record_host_span("host.x86.record", &name, self.last, now);
        }
        self.last = now;
    }
}

/// Emits a GPU timer stamp when the caller provided a timer for the current recording run.
pub(super) fn stamp_timer(
    timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}
