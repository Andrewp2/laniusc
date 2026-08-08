// src/type_checker/record/compute.rs

use super::*;

pub(in crate::type_checker) fn record_typecheck_clear_buffer<'a>(
    encoder: &mut wgpu::CommandEncoder,
    buffer: impl Into<TrackedBufferView<'a>>,
    offset: u64,
    size: Option<u64>,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    buffer.into().clear(encoder, offset, size);
}

pub(in crate::type_checker) fn record_typecheck_copy_buffer_to_buffer<'a, 'b>(
    encoder: &mut wgpu::CommandEncoder,
    source: impl Into<TrackedBufferView<'a>>,
    source_offset: u64,
    destination: impl Into<TrackedBufferView<'b>>,
    destination_offset: u64,
    size: u64,
) {
    crate::gpu::passes_core::flush_deferred_compute(encoder);
    source.into().copy_to(
        encoder,
        source_offset,
        destination.into(),
        destination_offset,
        size,
    );
}

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

/// Records a direct one-dimensional compute dispatch for a type-check pass.
pub(in crate::type_checker) fn record_compute(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    n_elements: u32,
) -> Result<()> {
    count_recorded_compute_pass();
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
    label: &str,
    dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    count_recorded_compute_pass();
    if crate::gpu::passes_core::defer_compute_indirect(
        pass,
        bind_group,
        &dispatch_args.buffer,
        dispatch_args.byte_offset,
        &[],
    ) {
        return Ok(());
    }
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups_indirect(&dispatch_args.buffer, dispatch_args.byte_offset);
    Ok(())
}

/// Records an indirect compute dispatch at a byte offset in a packed argument
/// buffer. This is used when the GPU activates a source-dependent subset of a
/// fully pre-recorded pass family.
pub(in crate::type_checker) fn record_compute_indirect_offset(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &'static str,
    dispatch_args: &LaniusBuffer<u32>,
    dispatch_offset: u64,
) -> Result<()> {
    count_recorded_compute_pass();
    crate::gpu::passes_core::record_or_defer_compute_indirect_offset(
        encoder,
        pass,
        bind_group,
        label,
        &dispatch_args.buffer,
        dispatch_args.absolute_offset(dispatch_offset),
    );
    Ok(())
}
