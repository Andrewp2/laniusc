//! Reusable GPU-parallel operations used by compiler phases.

use anyhow::Result;

use super::passes_core::{
    DispatchDim,
    InputElements,
    PassData,
    count_recorded_compute_pass,
    defer_compute_direct,
    defer_compute_indirect,
    plan_workgroups,
};

mod hierarchical_radix_sort;
mod prefix_scan;
mod radix_sort;

pub(crate) use hierarchical_radix_sort::{
    HierarchicalRadixSortDefinition,
    HierarchicalRadixSortDispatch,
    HierarchicalRadixSortKernels,
};
pub(crate) use prefix_scan::PrefixScanOperation;
pub(crate) use radix_sort::{
    RadixDispatchDomain,
    RadixSortBatchItem,
    RadixSortDefinition,
    RadixSortDispatch,
    RadixSortKernels,
    RadixSortOperation,
    RadixSortPairDefinition,
    RadixSortPlan,
    RadixSortResources,
    record_radix_sort_batch,
};

fn record_direct(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    n_elements: u32,
) -> Result<()> {
    count_recorded_compute_pass();
    let [x, y, _] = pass.thread_group_size;
    let groups = plan_workgroups(
        DispatchDim::D1,
        InputElements::Elements1D(n_elements),
        [x, y, 1],
    )?;
    if defer_compute_direct(pass, bind_group, groups) {
        return Ok(());
    }
    let mut compute = encoder.begin_compute_pass(&wgpu::ComputePassDescriptor {
        label: Some(label),
        timestamp_writes: None,
    });
    compute.set_pipeline(&pass.pipeline);
    compute.set_bind_group(0, Some(bind_group), &[]);
    compute.dispatch_workgroups(groups.0, groups.1, groups.2);
    Ok(())
}

fn record_indirect(
    encoder: &mut wgpu::CommandEncoder,
    pass: &PassData,
    bind_group: &wgpu::BindGroup,
    label: &str,
    dispatch_args: &wgpu::Buffer,
) -> Result<()> {
    count_recorded_compute_pass();
    if defer_compute_indirect(pass, bind_group, dispatch_args, 0, &[]) {
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
