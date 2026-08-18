use super::super::*;

/// Creates the bind group that extracts one record-family bit into scan flags.
pub(super) fn create_record_flag_extract(
    device: &wgpu::Device,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    passes: &TypeCheckPasses,
    spec: crate::gpu::compiler_graph::ReflectedComputeSpec,
    param_label: &'static str,
    hir_node_capacity: u32,
    family_bit: u32,
    record_family_bits: &LaniusBuffer<u32>,
    record_family_flag: &LaniusBuffer<u32>,
    dispatch_args: &LaniusBuffer<u32>,
) -> Result<(LaniusBuffer<RecordFamilyFlagParams>, ComputeOperation)> {
    let params = uniform_from_val(
        device,
        param_label,
        &RecordFamilyFlagParams {
            n_hir_nodes: hir_node_capacity,
            family_bit,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let mut resources = ResourceMap::new();
    resources.buffer("gParams", &params);
    resources.buffer("module_record_family_bits", record_family_bits);
    resources.buffer("module_record_family_flag", record_family_flag);
    let operation =
        ComputeOperation::indirect_spec(device, graph, &resources, passes, spec, dispatch_args)?;
    Ok((params, operation))
}

/// Creates a one-dispatch bind group that expands a count into dispatch args.
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
