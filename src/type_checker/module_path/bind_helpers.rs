use super::super::*;

pub(super) fn create_record_flag_extract(
    device: &wgpu::Device,
    pass: &PassData,
    param_label: &'static str,
    bind_label: &'static str,
    hir_node_capacity: u32,
    family_bit: u32,
    record_family_bits: &wgpu::Buffer,
    record_family_flag: &wgpu::Buffer,
) -> Result<(LaniusBuffer<RecordFamilyFlagParams>, wgpu::BindGroup)> {
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
    let bind_group = bind_group::create_bind_group_from_bindings(
        device,
        Some(bind_label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("record_family_bits", record_family_bits.as_entire_binding()),
            ("record_family_flag", record_family_flag.as_entire_binding()),
        ],
    )?;
    Ok((params, bind_group))
}

pub(super) fn create_radix_dispatch(
    device: &wgpu::Device,
    pass: &PassData,
    label: &'static str,
    params: &LaniusBuffer<ModuleKeyRadixParams>,
    item_count: &wgpu::Buffer,
    dispatch_args: &wgpu::Buffer,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(
        device,
        Some(label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("name_count_in", item_count.as_entire_binding()),
            ("radix_dispatch_args", dispatch_args.as_entire_binding()),
        ],
    )
}

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
    let bind_group = bind_group::create_bind_group_from_bindings(
        device,
        Some(bind_label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("count_in", count_in.as_entire_binding()),
            ("dispatch_args", dispatch_args.as_entire_binding()),
        ],
    )?;
    Ok((params, bind_group))
}

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
    let bind_group = bind_group::create_bind_group_from_bindings(
        device,
        Some(bind_label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("left_count_in", left_count_in.as_entire_binding()),
            ("right_count_in", right_count_in.as_entire_binding()),
            ("dispatch_args", dispatch_args.as_entire_binding()),
        ],
    )?;
    Ok((params, bind_group))
}

pub(super) fn create_radix_bucket_prefix(
    device: &wgpu::Device,
    pass: &PassData,
    label: &'static str,
    params: &LaniusBuffer<ModuleKeyRadixParams>,
    item_count: &wgpu::Buffer,
    block_histogram: &wgpu::Buffer,
    block_bucket_prefix: &wgpu::Buffer,
    bucket_total: &wgpu::Buffer,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(
        device,
        Some(label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("name_count_in", item_count.as_entire_binding()),
            ("radix_block_histogram", block_histogram.as_entire_binding()),
            (
                "radix_block_bucket_prefix",
                block_bucket_prefix.as_entire_binding(),
            ),
            ("radix_bucket_total", bucket_total.as_entire_binding()),
        ],
    )
}

pub(super) fn create_radix_bucket_bases(
    device: &wgpu::Device,
    pass: &PassData,
    label: &'static str,
    params: &LaniusBuffer<ModuleKeyRadixParams>,
    bucket_total: &wgpu::Buffer,
    bucket_base: &wgpu::Buffer,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_bindings(
        device,
        Some(label),
        pass,
        0,
        &[
            ("gParams", params.as_entire_binding()),
            ("radix_bucket_total", bucket_total.as_entire_binding()),
            ("radix_bucket_base", bucket_base.as_entire_binding()),
        ],
    )
}
