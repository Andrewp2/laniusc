use std::collections::HashMap;

use super::*;

pub(super) struct StandaloneGenericParamBindGroups {
    _key_radix_steps: Vec<ModuleKeyRadixStep>,
    mark_generic_param_records: wgpu::BindGroup,
    propagate_generic_decl_owner: Vec<wgpu::BindGroup>,
    generic_param_scan: U32ScanBindGroups,
    decl_generic_params: wgpu::BindGroup,
    generic_param_key_radix_dispatch_args: wgpu::Buffer,
    generic_param_key_radix_dispatch: wgpu::BindGroup,
    sort_generic_param_key_histogram: Vec<wgpu::BindGroup>,
    sort_generic_param_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_generic_param_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_generic_param_key_scatter: Vec<wgpu::BindGroup>,
    generic_param_use_slots: wgpu::BindGroup,
    seed_struct_field_keys: wgpu::BindGroup,
    struct_field_key_radix_dispatch_args: wgpu::Buffer,
    struct_field_key_radix_dispatch: wgpu::BindGroup,
    sort_struct_field_key_histogram: Vec<wgpu::BindGroup>,
    sort_struct_field_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_struct_field_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_struct_field_key_scatter: Vec<wgpu::BindGroup>,
}

pub(super) fn create_standalone_generic_param_bind_groups(
    device: &wgpu::Device,
    passes: &TokenTypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    token_capacity: u32,
    hir_node_capacity: u32,
    hir_scan_steps: &[NameScanStep],
    generic_param_key_radix_dispatch_args: &wgpu::Buffer,
    struct_field_key_radix_dispatch_args: &wgpu::Buffer,
) -> Result<StandaloneGenericParamBindGroups, GpuTypeCheckError> {
    let param_capacity = token_capacity.max(1);
    let param_n_blocks = param_capacity.div_ceil(256).max(1);
    let radix_bytes = generic_param_key_radix_bytes(param_capacity, hir_node_capacity);
    let radix_steps = generic_param_key_radix_steps(param_capacity, hir_node_capacity);
    let owner_steps = generic_decl_owner_step_count(hir_node_capacity);
    let struct_field_capacity = hir_node_capacity.max(1);
    let struct_field_n_blocks = struct_field_capacity.div_ceil(256).max(1);
    let struct_field_radix_bytes =
        struct_field_key_radix_bytes(struct_field_capacity, token_capacity);
    let struct_field_radix_steps =
        struct_field_key_radix_steps(struct_field_capacity, token_capacity);
    let seed_params = uniform_from_val(
        device,
        "type_check.tokens.generic_param_key_radix.params.seed",
        &ModuleKeyRadixParams {
            module_capacity: param_capacity,
            reserved: radix_bytes,
            n_blocks: param_n_blocks,
            key_step: 0,
        },
    );

    let mark_generic_param_records = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens_type_instances_mark_generic_param_records"),
        &passes
            .type_instances_mark_generic_param_records
            .bind_group_layouts[0],
        &passes.type_instances_mark_generic_param_records.reflection,
        0,
        resources,
    )?;
    let mut propagate_generic_decl_owner = Vec::with_capacity(owner_steps as usize);
    for step in 0..owner_steps {
        let read_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_a"].clone()
        } else {
            resources["generic_decl_owner_by_node_b"].clone()
        };
        let read_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_a"].clone()
        } else {
            resources["generic_decl_parent_jump_b"].clone()
        };
        let write_owner = if step % 2 == 0 {
            resources["generic_decl_owner_by_node_b"].clone()
        } else {
            resources["generic_decl_owner_by_node_a"].clone()
        };
        let write_jump = if step % 2 == 0 {
            resources["generic_decl_parent_jump_b"].clone()
        } else {
            resources["generic_decl_parent_jump_a"].clone()
        };
        propagate_generic_decl_owner.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_tokens_type_instances_propagate_generic_decl_owner"),
            passes.type_instances_propagate_generic_decl_owner,
            0,
            &[
                ("gParams", resources["gParams"].clone()),
                ("hir_status", resources["hir_status"].clone()),
                ("generic_decl_owner_by_node_in", read_owner),
                ("generic_decl_parent_jump_in", read_jump),
                ("generic_decl_owner_by_node_out", write_owner),
                ("generic_decl_parent_jump_out", write_jump),
            ],
        )?);
    }
    let generic_param_scan = create_counted_u32_scan_bind_groups_from_passes(
        passes.counted_scan_local,
        passes.counted_scan_blocks,
        passes.counted_scan_apply,
        device,
        "type_check.tokens.generic_param_scan",
        hir_scan_steps,
        resource_buffer(resources, "hir_active_count"),
        resource_buffer(resources, "generic_param_flag"),
        resource_buffer(resources, "generic_param_prefix"),
        resource_buffer(resources, "generic_param_count_out"),
        resource_buffer(resources, "generic_param_scan_local_prefix"),
        resource_buffer(resources, "generic_param_scan_block_sum"),
        resource_buffer(resources, "generic_param_scan_prefix_a"),
        resource_buffer(resources, "generic_param_scan_prefix_b"),
    )?;
    let decl_generic_params = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens_type_instances_decl_generic_params"),
        &passes.type_instances_decl_generic_params.bind_group_layouts[0],
        &passes.type_instances_decl_generic_params.reflection,
        0,
        resources,
    )?;
    let generic_param_key_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.tokens.generic_param_key_radix_dispatch"),
        passes.names_radix_dispatch_args,
        0,
        &[
            ("gParams", seed_params.as_entire_binding()),
            (
                "name_count_in",
                resources["generic_param_count_out"].clone(),
            ),
            (
                "radix_dispatch_args",
                resources["generic_param_key_radix_dispatch_args"].clone(),
            ),
        ],
    )?;
    let mut key_radix_steps = Vec::with_capacity(radix_steps as usize + 1);
    let mut sort_generic_param_key_histogram = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_bucket_prefix = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_bucket_bases = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_scatter = Vec::with_capacity(radix_steps as usize);
    for key_step in 0..radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.tokens.generic_param_key_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: param_capacity,
                reserved: radix_bytes,
                n_blocks: param_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            resources["generic_param_key_order"].clone()
        } else {
            resources["generic_param_key_order_tmp"].clone()
        };
        let write_order = if key_step % 2 == 0 {
            resources["generic_param_key_order_tmp"].clone()
        } else {
            resources["generic_param_key_order"].clone()
        };

        sort_generic_param_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_tokens_type_instances_sort_generic_param_keys"),
            passes.type_instances_sort_generic_param_keys,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "generic_param_count_out",
                    resources["generic_param_count_out"].clone(),
                ),
                (
                    "generic_param_owner_node",
                    resources["generic_param_owner_node"].clone(),
                ),
                (
                    "generic_param_name_id",
                    resources["generic_param_name_id"].clone(),
                ),
                (
                    "generic_param_node",
                    resources["generic_param_node"].clone(),
                ),
                ("generic_param_key_order_in", read_order.clone()),
                (
                    "radix_block_histogram",
                    resources["generic_param_key_radix_block_histogram"].clone(),
                ),
            ],
        )?);
        sort_generic_param_key_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.tokens.generic_param_key_radix_bucket_prefix"),
            passes.names_radix_bucket_prefix,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "name_count_in",
                    resources["generic_param_count_out"].clone(),
                ),
                (
                    "radix_block_histogram",
                    resources["generic_param_key_radix_block_histogram"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["generic_param_key_radix_block_bucket_prefix"].clone(),
                ),
                (
                    "radix_bucket_total",
                    resources["generic_param_key_radix_bucket_total"].clone(),
                ),
            ],
        )?);
        sort_generic_param_key_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.tokens.generic_param_key_radix_bucket_bases"),
            passes.names_radix_bucket_bases,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    resources["generic_param_key_radix_bucket_total"].clone(),
                ),
                (
                    "radix_bucket_base",
                    resources["generic_param_key_radix_bucket_base"].clone(),
                ),
            ],
        )?);
        sort_generic_param_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_tokens_type_instances_sort_generic_param_keys_scatter"),
            passes.type_instances_sort_generic_param_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "generic_param_count_out",
                    resources["generic_param_count_out"].clone(),
                ),
                (
                    "generic_param_owner_node",
                    resources["generic_param_owner_node"].clone(),
                ),
                (
                    "generic_param_name_id",
                    resources["generic_param_name_id"].clone(),
                ),
                (
                    "generic_param_node",
                    resources["generic_param_node"].clone(),
                ),
                ("generic_param_key_order_in", read_order),
                (
                    "radix_bucket_base",
                    resources["generic_param_key_radix_bucket_base"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["generic_param_key_radix_block_bucket_prefix"].clone(),
                ),
                ("generic_param_key_order_out", write_order),
            ],
        )?);
        key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let generic_param_use_slots = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens_type_instances_generic_param_use_slots"),
        &passes
            .type_instances_generic_param_use_slots
            .bind_group_layouts[0],
        &passes.type_instances_generic_param_use_slots.reflection,
        0,
        resources,
    )?;

    let seed_struct_field_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_tokens_type_instances_seed_struct_field_keys"),
        &passes
            .type_instances_seed_struct_field_keys
            .bind_group_layouts[0],
        &passes.type_instances_seed_struct_field_keys.reflection,
        0,
        resources,
    )?;
    let struct_field_seed_params = uniform_from_val(
        device,
        "type_check.tokens.struct_field_key_radix.params.seed",
        &ModuleKeyRadixParams {
            module_capacity: struct_field_capacity,
            reserved: struct_field_radix_bytes,
            n_blocks: struct_field_n_blocks,
            key_step: 0,
        },
    );
    let struct_field_key_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.tokens.struct_field_key_radix_dispatch"),
        passes.names_radix_dispatch_args,
        0,
        &[
            ("gParams", struct_field_seed_params.as_entire_binding()),
            ("name_count_in", resources["hir_active_count"].clone()),
            (
                "radix_dispatch_args",
                resources["struct_field_key_radix_dispatch_args"].clone(),
            ),
        ],
    )?;
    let mut sort_struct_field_key_histogram = Vec::with_capacity(struct_field_radix_steps as usize);
    let mut sort_struct_field_key_bucket_prefix =
        Vec::with_capacity(struct_field_radix_steps as usize);
    let mut sort_struct_field_key_bucket_bases =
        Vec::with_capacity(struct_field_radix_steps as usize);
    let mut sort_struct_field_key_scatter = Vec::with_capacity(struct_field_radix_steps as usize);
    for key_step in 0..struct_field_radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.tokens.struct_field_key_radix.params.{key_step}"),
            &StructFieldKeyRadixParams {
                hir_node_capacity: struct_field_capacity,
                token_capacity,
                n_blocks: struct_field_n_blocks,
                key_step,
                radix_bytes: struct_field_radix_bytes,
                reserved0: 0,
                reserved1: 0,
                reserved2: 0,
            },
        );
        let read_order = if key_step % 2 == 0 {
            resources["struct_field_key_order"].clone()
        } else {
            resources["struct_field_key_order_tmp"].clone()
        };
        let write_order = if key_step % 2 == 0 {
            resources["struct_field_key_order_tmp"].clone()
        } else {
            resources["struct_field_key_order"].clone()
        };

        sort_struct_field_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_tokens_type_instances_sort_struct_field_keys"),
            passes.type_instances_sort_struct_field_keys,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("hir_active_count", resources["hir_active_count"].clone()),
                ("hir_token_pos", resources["hir_token_pos"].clone()),
                (
                    "hir_struct_field_parent_struct",
                    resources["hir_struct_field_parent_struct"].clone(),
                ),
                ("name_id_by_token", resources["name_id_by_token"].clone()),
                ("struct_field_key_order_in", read_order.clone()),
                (
                    "radix_block_histogram",
                    resources["struct_field_key_radix_block_histogram"].clone(),
                ),
            ],
        )?);
        sort_struct_field_key_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.tokens.struct_field_key_radix_bucket_prefix"),
            passes.names_radix_bucket_prefix,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_count_in", resources["hir_active_count"].clone()),
                (
                    "radix_block_histogram",
                    resources["struct_field_key_radix_block_histogram"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["struct_field_key_radix_block_bucket_prefix"].clone(),
                ),
                (
                    "radix_bucket_total",
                    resources["struct_field_key_radix_bucket_total"].clone(),
                ),
            ],
        )?);
        sort_struct_field_key_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.tokens.struct_field_key_radix_bucket_bases"),
            passes.names_radix_bucket_bases,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    resources["struct_field_key_radix_bucket_total"].clone(),
                ),
                (
                    "radix_bucket_base",
                    resources["struct_field_key_radix_bucket_base"].clone(),
                ),
            ],
        )?);
        sort_struct_field_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_tokens_type_instances_sort_struct_field_keys_scatter"),
            passes.type_instances_sort_struct_field_keys_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("hir_active_count", resources["hir_active_count"].clone()),
                ("hir_token_pos", resources["hir_token_pos"].clone()),
                (
                    "hir_struct_field_parent_struct",
                    resources["hir_struct_field_parent_struct"].clone(),
                ),
                ("name_id_by_token", resources["name_id_by_token"].clone()),
                ("struct_field_key_order_in", read_order),
                (
                    "radix_bucket_base",
                    resources["struct_field_key_radix_bucket_base"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["struct_field_key_radix_block_bucket_prefix"].clone(),
                ),
                ("struct_field_key_order_out", write_order),
            ],
        )?);
    }

    key_radix_steps.push(ModuleKeyRadixStep {
        _params: seed_params,
    });
    key_radix_steps.push(ModuleKeyRadixStep {
        _params: struct_field_seed_params,
    });

    Ok(StandaloneGenericParamBindGroups {
        _key_radix_steps: key_radix_steps,
        mark_generic_param_records,
        propagate_generic_decl_owner,
        generic_param_scan,
        decl_generic_params,
        generic_param_key_radix_dispatch_args: generic_param_key_radix_dispatch_args.clone(),
        generic_param_key_radix_dispatch,
        sort_generic_param_key_histogram,
        sort_generic_param_key_bucket_prefix,
        sort_generic_param_key_bucket_bases,
        sort_generic_param_key_scatter,
        generic_param_use_slots,
        seed_struct_field_keys,
        struct_field_key_radix_dispatch_args: struct_field_key_radix_dispatch_args.clone(),
        struct_field_key_radix_dispatch,
        sort_struct_field_key_histogram,
        sort_struct_field_key_bucket_prefix,
        sort_struct_field_key_bucket_bases,
        sort_struct_field_key_scatter,
    })
}

pub(super) fn record_standalone_generic_param_passes(
    encoder: &mut wgpu::CommandEncoder,
    passes: &TokenTypeCheckPasses,
    groups: &StandaloneGenericParamBindGroups,
    hir_node_capacity: u32,
    hir_scan_n_blocks: u32,
) -> Result<(), GpuTypeCheckError> {
    let hir_work = hir_node_capacity.max(1);
    record_compute(
        encoder,
        passes.type_instances_mark_generic_param_records,
        &groups.mark_generic_param_records,
        "type_check.type_instances_mark_generic_param_records.pass",
        hir_work,
    )?;
    for bind_group in &groups.propagate_generic_decl_owner {
        record_compute(
            encoder,
            passes.type_instances_propagate_generic_decl_owner,
            bind_group,
            "type_check.type_instances_propagate_generic_decl_owner.pass",
            hir_work,
        )?;
    }
    record_compute(
        encoder,
        passes.counted_scan_local,
        &groups.generic_param_scan.local,
        "type_check.generic_param_record_scan.local",
        hir_work,
    )?;
    for bind_group in &groups.generic_param_scan.blocks {
        record_compute(
            encoder,
            passes.counted_scan_blocks,
            bind_group,
            "type_check.generic_param_record_scan.blocks",
            hir_scan_n_blocks.max(1),
        )?;
    }
    record_compute(
        encoder,
        passes.counted_scan_apply,
        &groups.generic_param_scan.apply,
        "type_check.generic_param_record_scan.apply",
        hir_work,
    )?;
    record_compute(
        encoder,
        passes.type_instances_decl_generic_params,
        &groups.decl_generic_params,
        "type_check.type_instances_decl_generic_params.pass",
        hir_work,
    )?;
    record_compute(
        encoder,
        passes.names_radix_dispatch_args,
        &groups.generic_param_key_radix_dispatch,
        "type_check.generic_param_key_radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.sort_generic_param_key_scatter.len() {
        record_compute_indirect(
            encoder,
            passes.type_instances_sort_generic_param_keys,
            &groups.sort_generic_param_key_histogram[i],
            "type_check.type_instances_sort_generic_param_keys.pass",
            &groups.generic_param_key_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            passes.names_radix_bucket_prefix,
            &groups.sort_generic_param_key_bucket_prefix[i],
            "type_check.generic_param_key_radix_bucket_prefix.pass",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            passes.names_radix_bucket_bases,
            &groups.sort_generic_param_key_bucket_bases[i],
            "type_check.generic_param_key_radix_bucket_bases.pass",
            256,
        )?;
        record_compute_indirect(
            encoder,
            passes.type_instances_sort_generic_param_keys_scatter,
            &groups.sort_generic_param_key_scatter[i],
            "type_check.type_instances_sort_generic_param_keys_scatter.pass",
            &groups.generic_param_key_radix_dispatch_args,
        )?;
    }
    record_compute(
        encoder,
        passes.type_instances_generic_param_use_slots,
        &groups.generic_param_use_slots,
        "type_check.type_instances_generic_param_use_slots.pass",
        hir_work,
    )?;
    record_compute(
        encoder,
        passes.type_instances_seed_struct_field_keys,
        &groups.seed_struct_field_keys,
        "type_check.type_instances_seed_struct_field_keys.pass",
        hir_work,
    )?;
    record_compute(
        encoder,
        passes.names_radix_dispatch_args,
        &groups.struct_field_key_radix_dispatch,
        "type_check.struct_field_key_radix_dispatch_args",
        1,
    )?;
    for i in 0..groups.sort_struct_field_key_scatter.len() {
        record_compute_indirect(
            encoder,
            passes.type_instances_sort_struct_field_keys,
            &groups.sort_struct_field_key_histogram[i],
            "type_check.type_instances_sort_struct_field_keys.pass",
            &groups.struct_field_key_radix_dispatch_args,
        )?;
        record_compute(
            encoder,
            passes.names_radix_bucket_prefix,
            &groups.sort_struct_field_key_bucket_prefix[i],
            "type_check.struct_field_key_radix_bucket_prefix.pass",
            NAME_RADIX_BUCKETS.saturating_mul(256),
        )?;
        record_compute(
            encoder,
            passes.names_radix_bucket_bases,
            &groups.sort_struct_field_key_bucket_bases[i],
            "type_check.struct_field_key_radix_bucket_bases.pass",
            256,
        )?;
        record_compute_indirect(
            encoder,
            passes.type_instances_sort_struct_field_keys_scatter,
            &groups.sort_struct_field_key_scatter[i],
            "type_check.type_instances_sort_struct_field_keys_scatter.pass",
            &groups.struct_field_key_radix_dispatch_args,
        )?;
    }
    Ok(())
}

fn resource_buffer<'a>(
    resources: &'a HashMap<String, wgpu::BindingResource<'a>>,
    name: &str,
) -> &'a wgpu::Buffer {
    match resources.get(name).expect("missing reflected resource") {
        wgpu::BindingResource::Buffer(binding) => binding.buffer,
        _ => panic!("resource {name} is not a buffer binding"),
    }
}
