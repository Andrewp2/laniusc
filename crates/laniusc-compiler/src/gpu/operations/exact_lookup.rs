//! Exact GPU lookup construction as one compiler operation.

use anyhow::Result;

use super::{ComputeGraph, ComputeKernels, ComputeOperation};
use crate::gpu::{
    buffers::LaniusBuffer,
    compiler_graph::ReflectedComputeSpec,
    resource_registry::ResourceMap,
};

/// Clear and parallel-build passes for an exact GPU lookup table.
pub(crate) struct ExactLookupOperation {
    clear: ComputeOperation,
    build: ComputeOperation,
}

impl ExactLookupOperation {
    pub(crate) fn new(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        kernels: &impl ComputeKernels,
        clear: ReflectedComputeSpec,
        build: ReflectedComputeSpec,
        table_capacity: u32,
        build_dispatch: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            clear: ComputeOperation::direct_spec(
                device,
                graph,
                resources,
                kernels,
                clear,
                table_capacity,
            )?,
            build: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                build,
                build_dispatch,
            )?,
        })
    }

    /// Builds a lookup whose clear domain is GPU-generated. This is preferable
    /// for compact families whose physical table reserves frontend capacity but
    /// whose active table is sized from a GPU-produced row count.
    pub(crate) fn new_with_indirect_clear(
        device: &wgpu::Device,
        graph: &impl ComputeGraph,
        resources: &ResourceMap<'_>,
        kernels: &impl ComputeKernels,
        clear: ReflectedComputeSpec,
        build: ReflectedComputeSpec,
        clear_dispatch: &LaniusBuffer<u32>,
        build_dispatch: &LaniusBuffer<u32>,
    ) -> Result<Self> {
        Ok(Self {
            clear: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                clear,
                clear_dispatch,
            )?,
            build: ComputeOperation::indirect_spec(
                device,
                graph,
                resources,
                kernels,
                build,
                build_dispatch,
            )?,
        })
    }

    pub(crate) fn record(&self, encoder: &mut wgpu::CommandEncoder) -> Result<()> {
        self.clear.record(encoder)?;
        self.build.record(encoder)
    }
}
