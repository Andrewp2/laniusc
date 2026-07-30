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
    dispatch_args: &wgpu::Buffer,
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

/// Creates a one-dispatch bind group that writes radix dispatch arguments.
pub(super) fn create_radix_dispatch(
    device: &wgpu::Device,
    pass: &PassData,
    label: &'static str,
    params: &LaniusBuffer<ModuleKeyRadixParams>,
    item_count: &wgpu::Buffer,
    dispatch_args: &wgpu::Buffer,
) -> Result<wgpu::BindGroup> {
    let mut resources = ResourceMap::new();
    resources.buffer("gParams", params);
    resources.buffer("name_count_in", item_count);
    resources.buffer("radix_dispatch_args", dispatch_args);
    resources.reflected_bind_group_with_overrides(device, label, pass, &[])
}

/// Creates a one-dispatch bind group that expands a count into dispatch args.
pub(super) fn create_count_dispatch(
    device: &wgpu::Device,
    pass: &PassData,
    param_label: &str,
    bind_label: &'static str,
    capacity: u32,
    multiplier: u32,
    count_in: &wgpu::Buffer,
    dispatch_args: &wgpu::Buffer,
) -> Result<(LaniusBuffer<CountDispatchParams>, wgpu::BindGroup)> {
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
    let mut resources = ResourceMap::new();
    resources.buffer("gParams", &params);
    resources.buffer("count_in", count_in);
    resources.buffer("dispatch_args", dispatch_args);
    let bind_group =
        resources.reflected_bind_group_with_overrides(device, bind_label, pass, &[])?;
    Ok((params, bind_group))
}

/// Creates a dispatch-argument bind group sized by the larger of two counts.
pub(super) fn create_pair_max_dispatch(
    device: &wgpu::Device,
    pass: &PassData,
    param_label: &str,
    bind_label: &'static str,
    left_capacity: u32,
    right_capacity: u32,
    left_count_in: &wgpu::Buffer,
    right_count_in: &wgpu::Buffer,
    dispatch_args: &wgpu::Buffer,
) -> Result<(LaniusBuffer<CountPairMaxDispatchParams>, wgpu::BindGroup)> {
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
    let mut resources = ResourceMap::new();
    resources.buffer("gParams", &params);
    resources.buffer("left_count_in", left_count_in);
    resources.buffer("right_count_in", right_count_in);
    resources.buffer("dispatch_args", dispatch_args);
    let bind_group =
        resources.reflected_bind_group_with_overrides(device, bind_label, pass, &[])?;
    Ok((params, bind_group))
}
