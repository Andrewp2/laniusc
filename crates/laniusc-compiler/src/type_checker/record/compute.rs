// src/type_checker/record/compute.rs

use super::*;

/// Emits a GPU timer stamp when type-check timing is enabled.
pub(in crate::type_checker) fn stamp_typecheck_timer(
    timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &str,
) {
    if crate::gpu::env::env_bool_truthy("LANIUS_GPU_COMPILE_HOST_TIMING", false) {
        eprintln!(
            "[gpu_compile_host_timer] typecheck.pass_checkpoint: label={label} total_compute_passes={}",
            recorded_compute_pass_count(),
        );
    }
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}
