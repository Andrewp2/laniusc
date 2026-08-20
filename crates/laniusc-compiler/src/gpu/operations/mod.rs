//! Reusable GPU-parallel operations used by compiler phases.

use anyhow::Result;

use super::{
    buffers::LaniusBuffer,
    passes_core::{
        DispatchDim,
        InputElements,
        PassData,
        begin_counted_compute_pass,
        defer_compute_direct_with_offsets,
        defer_compute_indirect,
        plan_workgroups,
        record_compiler_operation,
    },
};

mod buffer;
mod compute;
mod exact_lookup;
mod inclusive_block_scan;
mod prefix_scan;
mod radix_sort;

pub(crate) use buffer::{
    ClearBufferOperation,
    ClearBuffersOperation,
    CopyBufferOperation,
    CopyBuffersOperation,
    EmptyRelationsOperation,
    ResetGraphAllocationsOperation,
};
pub(crate) use compute::{ComputeGraph, ComputeInvocation, ComputeKernels, ComputeOperation};
pub(crate) use exact_lookup::ExactLookupOperation;
pub(crate) use inclusive_block_scan::{InclusiveBlockScanKernels, InclusiveBlockScanPlan};
pub(crate) use prefix_scan::{PrefixScanOperation, PrefixScanPairOperation};
pub(super) use radix_sort::uses_dynamic_uniform_kernel;
pub(crate) use radix_sort::{
    RadixDispatchDomain,
    RadixSortDefinition,
    RadixSortDispatch,
    RadixSortKernels,
    RadixSortOperation,
    RadixSortResources,
};

fn record_direct(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    n_elements: u32,
) -> Result<()> {
    record_direct_with_offsets(encoder, pass, bind_group, label, n_elements, &[])
}

fn record_direct_with_offsets(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    n_elements: u32,
    dynamic_offsets: &[u32],
) -> Result<()> {
    record_compiler_operation(label);
    let [x, y, _] = pass.thread_group_size;
    let groups = plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [x, y, 1],
    )?;
    if defer_compute_direct_with_offsets(pass, bind_group, groups, dynamic_offsets) {
        return Ok(());
    }
    let mut compute = begin_counted_compute_pass(
        encoder,
        &wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        },
    );
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), dynamic_offsets);
    crate::gpu::passes_core::record_compute_dispatch();
    compute.dispatch_workgroups(groups.0, groups.1, groups.2);
    Ok(())
}

fn record_indirect(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    dispatch_args: &LaniusBuffer<u32>,
) -> Result<()> {
    record_indirect_at(encoder, pass, bind_group, label, dispatch_args, 0)
}

fn record_indirect_at(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    dispatch_args: &LaniusBuffer<u32>,
    dispatch_offset: u64,
) -> Result<()> {
    let absolute_offset = dispatch_args.absolute_offset(dispatch_offset);
    record_compiler_operation(label);
    if defer_compute_indirect(
        pass,
        bind_group,
        &dispatch_args.buffer,
        absolute_offset,
        &[],
    ) {
        return Ok(());
    }
    let mut compute = begin_counted_compute_pass(
        encoder,
        &wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        },
    );
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    crate::gpu::passes_core::record_compute_dispatch();
    compute.dispatch_workgroups_indirect(&dispatch_args.buffer, absolute_offset);
    Ok(())
}

fn record_indirect_with_offsets(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    dispatch_args: &LaniusBuffer<u32>,
    dynamic_offsets: &[u32],
) -> Result<()> {
    record_compiler_operation(label);
    if defer_compute_indirect(
        pass,
        bind_group,
        &dispatch_args.buffer,
        dispatch_args.byte_offset,
        dynamic_offsets,
    ) {
        return Ok(());
    }
    let mut compute = begin_counted_compute_pass(
        encoder,
        &wgpu::ComputePassDescriptor {
            label: Some(label),
            timestamp_writes: None,
        },
    );
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), dynamic_offsets);
    crate::gpu::passes_core::record_compute_dispatch();
    compute.dispatch_workgroups_indirect(&dispatch_args.buffer, dispatch_args.byte_offset);
    Ok(())
}
