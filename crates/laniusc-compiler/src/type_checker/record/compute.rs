// src/type_checker/record/compute.rs

use super::*;

pub(in crate::type_checker) fn record_typecheck_clear_buffer(
    encoder: &mut wgpu::CommandEncoder,
    buffer: &wgpu::Buffer,
    offset: u64,
    size: Option<u64>,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    encoder.clear_buffer(buffer, offset, size);
}

pub(in crate::type_checker) fn record_typecheck_copy_buffer_to_buffer(
    encoder: &mut wgpu::CommandEncoder,
    source: &wgpu::Buffer,
    source_offset: u64,
    destination: &wgpu::Buffer,
    destination_offset: u64,
    size: u64,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    encoder.copy_buffer_to_buffer(source, source_offset, destination, destination_offset, size);
}

/// Emits a GPU timer stamp when type-check timing is enabled.
pub(in crate::type_checker) fn stamp_typecheck_timer(
    timer: &mut Option<&mut crate::gpu::timer::GpuTimer>,
    encoder: &mut wgpu::CommandEncoder,
    label: &'static str,
) {
    if let Some(timer) = timer.as_deref_mut() {
        timer.stamp(encoder, label);
    }
}

/// Records a direct one-dimensional compute dispatch for a type-check pass.
pub(in crate::type_checker) fn record_compute(
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
    if crate::gpu::passes_core::defer_compute_direct(pass, bind_group, (gx, gy, gz)) {
        return Ok(());
    }
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(gx, gy, gz);
    Ok(())
}

/// Records an indirect compute dispatch whose workgroup count lives in a buffer.
pub(in crate::type_checker) fn record_compute_indirect(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    dispatch_args: &wgpu::Buffer,
) -> Result<()> {
    if crate::gpu::passes_core::defer_compute_indirect(pass, bind_group, dispatch_args, 0, &[]) {
        return Ok(());
    }
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups_indirect(dispatch_args, 0);
    Ok(())
}
