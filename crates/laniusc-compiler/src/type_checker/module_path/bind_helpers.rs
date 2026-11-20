use super::super::*;

pub(super) fn create_count_dispatch(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
    param_label: &str,
    capacity: u32,
    multiplier: u32,
) -> Result<(LaniusBuffer<CountDispatchParams>, ComputeOperation)> {
    let params = uniform_from_val(
        device,
        param_label,
        &CountDispatchParams {
            capacity,
            multiplier,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let mut resources = resources.clone();
    resources.buffer("gParams", &params);
    let operation = ComputeOperation::direct_spec(device, graph, &resources, passes, spec, 1)?;
    Ok((params, operation))
}

/// Creates a dispatch-argument bind group sized by the larger of two counts.
pub(super) fn create_pair_max_dispatch(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    resources: &ResourceMap<'_>,
    spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
    param_label: &str,
    left_capacity: u32,
    right_capacity: u32,
) -> Result<(LaniusBuffer<CountPairMaxDispatchParams>, ComputeOperation)> {
    let params = uniform_from_val(
        device,
        param_label,
        &CountPairMaxDispatchParams {
            left_capacity,
            right_capacity,
            multiplier: 1,
            reserved: 0,
        },
    );
    let mut resources = resources.clone();
    resources.buffer("gParams", &params);
    let operation = ComputeOperation::direct_spec(device, graph, &resources, passes, spec, 1)?;
    Ok((params, operation))
}
