use super::{super::*, common::reflected_bind_group_from_resources};

const GENERIC_PARAM_KEY_FIELD_COUNT: u32 = 3;
const GENERIC_PARAM_KEY_MAX_RADIX_STEPS: u32 = 12;
const STRUCT_FIELD_KEY_FIELD_COUNT: u32 = 3;
const STRUCT_FIELD_KEY_MAX_RADIX_STEPS: u32 = 12;

/// Returns the byte width needed for each generic-parameter key field.
pub(in crate::type_checker) fn generic_param_key_radix_bytes(
    param_capacity: u32,
    hir_node_capacity: u32,
) -> u32 {
    let max_key = param_capacity
        .max(hir_node_capacity)
        .saturating_add(LANGUAGE_SYMBOL_COUNT)
        .saturating_add(1)
        .max(1);
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

/// Returns the even radix step count for sorting generic-parameter keys.
pub(in crate::type_checker) fn generic_param_key_radix_steps(
    param_capacity: u32,
    hir_node_capacity: u32,
) -> u32 {
    let steps = generic_param_key_radix_bytes(param_capacity, hir_node_capacity)
        * GENERIC_PARAM_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(GENERIC_PARAM_KEY_MAX_RADIX_STEPS)
}

/// Returns the byte width needed for each struct-field key field.
pub(in crate::type_checker) fn struct_field_key_radix_bytes(
    hir_node_capacity: u32,
    token_capacity: u32,
) -> u32 {
    let max_key = hir_node_capacity
        .max(token_capacity.saturating_add(LANGUAGE_SYMBOL_COUNT))
        .saturating_add(1)
        .max(1);
    if max_key <= 0xff {
        1
    } else if max_key <= 0xffff {
        2
    } else if max_key <= 0x00ff_ffff {
        3
    } else {
        4
    }
}

/// Returns the even radix step count for sorting struct-field keys.
pub(in crate::type_checker) fn struct_field_key_radix_steps(
    hir_node_capacity: u32,
    token_capacity: u32,
) -> u32 {
    let steps = struct_field_key_radix_bytes(hir_node_capacity, token_capacity)
        * STRUCT_FIELD_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(STRUCT_FIELD_KEY_MAX_RADIX_STEPS)
}

/// Returns the propagation passes needed to attach generic params to owners.
pub(in crate::type_checker) fn generic_decl_owner_step_count(hir_node_capacity: u32) -> u32 {
    let mut covered_depth = 1u32;
    let mut steps = 0u32;
    let target = hir_node_capacity.max(1);
    while covered_depth < target {
        covered_depth = covered_depth.saturating_mul(2);
        steps = steps.saturating_add(1);
    }
    if steps % 2 == 0 {
        steps
    } else {
        steps.saturating_add(1)
    }
}

/// Builds bind groups for collecting, sorting, and projecting type instances.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_type_instance_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    token_capacity: u32,
    hir_node_capacity: u32,
    generic_param_key_radix_dispatch_args: &LaniusBuffer<u32>,
    struct_field_key_radix_dispatch_args: &LaniusBuffer<u32>,
    _hir_scan_n_blocks: u32,
    hir_scan_steps: &[NameScanStep],
) -> Result<TypeInstanceBindGroups> {
    let param_capacity = token_capacity.max(1);
    let param_n_blocks = param_capacity.div_ceil(256).max(1);
    let radix_bytes = generic_param_key_radix_bytes(param_capacity, hir_node_capacity);
    let radix_steps = generic_param_key_radix_steps(param_capacity, hir_node_capacity);
    let owner_steps = generic_decl_owner_step_count(hir_node_capacity);
    let struct_field_capacity = hir_node_capacity.max(1);
    let struct_field_n_blocks = struct_field_capacity.div_ceil(256).max(1);
    let arg_row_scan_n_blocks = token_capacity.div_ceil(256).max(1);
    let arg_row_scan_steps = make_name_scan_steps(
        device,
        NameScanParams {
            n_items: token_capacity,
            n_blocks: arg_row_scan_n_blocks,
            scan_step: 0,
        },
    );
    let struct_field_radix_bytes =
        struct_field_key_radix_bytes(struct_field_capacity, token_capacity);
    let struct_field_radix_steps =
        struct_field_key_radix_steps(struct_field_capacity, token_capacity);
    let radix_params = uniform_from_val(
        device,
        "type_check.type_instances.generic_param_key_radix.dispatch.params",
        &ModuleKeyRadixParams {
            module_capacity: param_capacity,
            reserved: radix_bytes,
            n_blocks: param_n_blocks,
            key_step: 0,
        },
    );
    let generic_param_key_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.generic_param_key_radix_dispatch"),
        &passes.names_radix_dispatch_args,
        0,
        &[
            ("gParams", radix_params.as_entire_binding()),
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

    let mut sort_generic_param_key_histogram = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_bucket_prefix = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_bucket_bases = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_key_scatter = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_slot_histogram = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_slot_bucket_prefix = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_slot_bucket_bases = Vec::with_capacity(radix_steps as usize);
    let mut sort_generic_param_slot_scatter = Vec::with_capacity(radix_steps as usize);
    for key_step in 0..radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.type_instances.generic_param_key_radix.params.{key_step}"),
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
            Some("type_check_type_instances_00c_sort_generic_param_keys"),
            &passes.type_instances_sort_generic_param_keys,
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
            Some("type_check.type_instances.generic_param_key_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix,
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
            Some("type_check.type_instances.generic_param_key_radix_bucket_bases"),
            &passes.names_radix_bucket_bases,
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
            Some("type_check_type_instances_00d_sort_generic_param_keys_scatter"),
            &passes.type_instances_sort_generic_param_keys_scatter,
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
    }

    for key_step in 0..radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.type_instances.generic_param_slot_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: param_capacity,
                reserved: radix_bytes,
                n_blocks: param_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            resources["generic_param_slot_order"].clone()
        } else {
            resources["generic_param_slot_order_tmp"].clone()
        };
        let write_order = if key_step % 2 == 0 {
            resources["generic_param_slot_order_tmp"].clone()
        } else {
            resources["generic_param_slot_order"].clone()
        };

        sort_generic_param_slot_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_type_instances_00c2_sort_generic_param_slots"),
            &passes.type_instances_sort_generic_param_slots,
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
                    "generic_param_node",
                    resources["generic_param_node"].clone(),
                ),
                (
                    "generic_param_kind",
                    resources["generic_param_kind"].clone(),
                ),
                ("generic_param_slot_order_in", read_order.clone()),
                (
                    "radix_block_histogram",
                    resources["generic_param_key_radix_block_histogram"].clone(),
                ),
            ],
        )?);

        sort_generic_param_slot_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.type_instances.generic_param_slot_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix,
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

        sort_generic_param_slot_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.type_instances.generic_param_slot_radix_bucket_bases"),
            &passes.names_radix_bucket_bases,
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

        sort_generic_param_slot_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_type_instances_00d2_sort_generic_param_slots_scatter"),
            &passes.type_instances_sort_generic_param_slots_scatter,
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
                    "generic_param_node",
                    resources["generic_param_node"].clone(),
                ),
                (
                    "generic_param_kind",
                    resources["generic_param_kind"].clone(),
                ),
                ("generic_param_slot_order_in", read_order),
                (
                    "radix_bucket_base",
                    resources["generic_param_key_radix_bucket_base"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["generic_param_key_radix_block_bucket_prefix"].clone(),
                ),
                ("generic_param_slot_order_out", write_order),
            ],
        )?);
    }

    let struct_field_radix_params = uniform_from_val(
        device,
        "type_check.type_instances.struct_field_key_radix.dispatch.params",
        &ModuleKeyRadixParams {
            module_capacity: struct_field_capacity,
            reserved: struct_field_radix_bytes,
            n_blocks: struct_field_n_blocks,
            key_step: 0,
        },
    );
    let struct_field_key_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.struct_field_key_radix_dispatch"),
        &passes.names_radix_dispatch_args,
        0,
        &[
            ("gParams", struct_field_radix_params.as_entire_binding()),
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
            &format!("type_check.type_instances.struct_field_key_radix.params.{key_step}"),
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
            Some("type_check_type_instances_02b_sort_struct_field_keys"),
            &passes.type_instances_sort_struct_field_keys,
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
            Some("type_check.type_instances.struct_field_key_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix,
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
            Some("type_check.type_instances.struct_field_key_radix_bucket_bases"),
            &passes.names_radix_bucket_bases,
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
            Some("type_check_type_instances_02c_sort_struct_field_keys_scatter"),
            &passes.type_instances_sort_struct_field_keys_scatter,
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
            Some("type_check_type_instances_00a1_propagate_generic_decl_owner"),
            &passes.type_instances_propagate_generic_decl_owner,
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

    let generic_param_scan_local = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.generic_param_scan.counted_scan_local"),
        &passes.counted_scan_local,
        0,
        &[
            ("gScan", hir_scan_steps[0].params.as_entire_binding()),
            ("scan_count", resources["hir_active_count"].clone()),
            ("scan_input", resources["generic_param_flag"].clone()),
            (
                "scan_local_prefix",
                resources["generic_param_scan_local_prefix"].clone(),
            ),
            (
                "scan_block_sum",
                resources["generic_param_scan_block_sum"].clone(),
            ),
        ],
    )?;
    let mut generic_param_scan_blocks = Vec::with_capacity(hir_scan_steps.len());
    for step in hir_scan_steps {
        let prefix_in = if step.read_from_a {
            resources["generic_param_scan_prefix_a"].clone()
        } else {
            resources["generic_param_scan_prefix_b"].clone()
        };
        let prefix_out = if step.write_to_a {
            resources["generic_param_scan_prefix_a"].clone()
        } else {
            resources["generic_param_scan_prefix_b"].clone()
        };
        generic_param_scan_blocks.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.type_instances.generic_param_scan.counted_scan_blocks"),
            &passes.counted_scan_blocks,
            0,
            &[
                ("gScan", step.params.as_entire_binding()),
                ("scan_count", resources["hir_active_count"].clone()),
                (
                    "scan_block_sum",
                    resources["generic_param_scan_block_sum"].clone(),
                ),
                ("scan_block_prefix_in", prefix_in),
                ("scan_block_prefix_out", prefix_out),
            ],
        )?);
    }
    let final_prefix = if hir_scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        resources["generic_param_scan_prefix_a"].clone()
    } else {
        resources["generic_param_scan_prefix_b"].clone()
    };
    let generic_param_scan_apply = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.generic_param_scan.counted_scan_apply"),
        &passes.counted_scan_apply,
        0,
        &[
            ("gScan", hir_scan_steps[0].params.as_entire_binding()),
            ("scan_count", resources["hir_active_count"].clone()),
            (
                "scan_local_prefix",
                resources["generic_param_scan_local_prefix"].clone(),
            ),
            ("scan_block_prefix", final_prefix),
            (
                "scan_output_prefix",
                resources["generic_param_prefix"].clone(),
            ),
            ("scan_total", resources["generic_param_count_out"].clone()),
        ],
    )?;

    let type_instance_arg_row_scan_local = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.arg_row_scan.counted_scan_local"),
        &passes.counted_scan_local,
        0,
        &[
            ("gScan", arg_row_scan_steps[0].params.as_entire_binding()),
            ("scan_count", resources["token_count"].clone()),
            ("scan_input", resources["type_instance_arg_count"].clone()),
            (
                "scan_local_prefix",
                resources["type_instance_arg_row_scan_local_prefix"].clone(),
            ),
            (
                "scan_block_sum",
                resources["type_instance_arg_row_scan_block_sum"].clone(),
            ),
        ],
    )?;
    let mut type_instance_arg_row_scan_blocks = Vec::with_capacity(arg_row_scan_steps.len());
    for step in &arg_row_scan_steps {
        let prefix_in = if step.read_from_a {
            resources["type_instance_arg_row_scan_prefix_a"].clone()
        } else {
            resources["type_instance_arg_row_scan_prefix_b"].clone()
        };
        let prefix_out = if step.write_to_a {
            resources["type_instance_arg_row_scan_prefix_a"].clone()
        } else {
            resources["type_instance_arg_row_scan_prefix_b"].clone()
        };
        type_instance_arg_row_scan_blocks.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.type_instances.arg_row_scan.counted_scan_blocks"),
            &passes.counted_scan_blocks,
            0,
            &[
                ("gScan", step.params.as_entire_binding()),
                ("scan_count", resources["token_count"].clone()),
                (
                    "scan_block_sum",
                    resources["type_instance_arg_row_scan_block_sum"].clone(),
                ),
                ("scan_block_prefix_in", prefix_in),
                ("scan_block_prefix_out", prefix_out),
            ],
        )?);
    }
    let arg_row_final_prefix = if arg_row_scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        resources["type_instance_arg_row_scan_prefix_a"].clone()
    } else {
        resources["type_instance_arg_row_scan_prefix_b"].clone()
    };
    let type_instance_arg_row_scan_apply = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.type_instances.arg_row_scan.counted_scan_apply"),
        &passes.counted_scan_apply,
        0,
        &[
            ("gScan", arg_row_scan_steps[0].params.as_entire_binding()),
            ("scan_count", resources["token_count"].clone()),
            (
                "scan_local_prefix",
                resources["type_instance_arg_row_scan_local_prefix"].clone(),
            ),
            ("scan_block_prefix", arg_row_final_prefix),
            (
                "scan_output_prefix",
                resources["type_instance_arg_row_start"].clone(),
            ),
            (
                "scan_total",
                resources["type_instance_arg_row_count_out"].clone(),
            ),
        ],
    )?;

    Ok(TypeInstanceBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_clear",
            &passes.type_instances_clear,
            resources,
        )?,
        mark_generic_param_records: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_mark_generic_param_records",
            &passes.type_instances_mark_generic_param_records,
            resources,
        )?,
        propagate_generic_decl_owner,
        generic_param_scan: U32ScanBindGroups {
            local: generic_param_scan_local,
            blocks: generic_param_scan_blocks,
            apply: generic_param_scan_apply,
        },
        type_instance_arg_row_scan: U32ScanBindGroups {
            local: type_instance_arg_row_scan_local,
            blocks: type_instance_arg_row_scan_blocks,
            apply: type_instance_arg_row_scan_apply,
        },
        type_instance_arg_row_scan_n_blocks: arg_row_scan_n_blocks,
        decl_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_generic_params",
            &passes.type_instances_decl_generic_params,
            resources,
        )?,
        generic_param_key_radix_dispatch_args: (*generic_param_key_radix_dispatch_args).clone(),
        generic_param_key_radix_dispatch,
        sort_generic_param_key_histogram,
        sort_generic_param_key_bucket_prefix,
        sort_generic_param_key_bucket_bases,
        sort_generic_param_key_scatter,
        sort_generic_param_slot_histogram,
        sort_generic_param_slot_bucket_prefix,
        sort_generic_param_slot_bucket_bases,
        sort_generic_param_slot_scatter,
        generic_param_use_slots: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_generic_param_use_slots",
            &passes.type_instances_generic_param_use_slots,
            resources,
        )?,
        seed_struct_field_keys: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_seed_struct_field_keys",
            &passes.type_instances_seed_struct_field_keys,
            resources,
        )?,
        struct_field_key_radix_dispatch_args: (*struct_field_key_radix_dispatch_args).clone(),
        struct_field_key_radix_dispatch,
        sort_struct_field_key_histogram,
        sort_struct_field_key_bucket_prefix,
        sort_struct_field_key_bucket_bases,
        sort_struct_field_key_scatter,
        collect: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect",
            &passes.type_instances_collect,
            resources,
        )?,
        collect_named: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named",
            &passes.type_instances_collect_named,
            resources,
        )?,
        collect_aggregate_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_refs",
            &passes.type_instances_collect_aggregate_refs,
            resources,
        )?,
        collect_aggregate_details: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_aggregate_details",
            &passes.type_instances_collect_aggregate_details,
            resources,
        )?,
        collect_named_arg_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_collect_named_arg_refs",
            &passes.type_instances_collect_named_arg_refs,
            resources,
        )?,
        hash_arg_rows: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_hash_arg_rows",
            &passes.type_instances_hash_arg_rows,
            resources,
        )?,
        decl_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_decl_refs",
            &passes.type_instances_decl_refs,
            resources,
        )?,
        member_receivers: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_receivers",
            &passes.type_instances_member_receivers,
            resources,
        )?,
        member_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_results",
            &passes.type_instances_member_results,
            resources,
        )?,
        member_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_member_substitute",
            &passes.type_instances_member_substitute,
            resources,
        )?,
        struct_init_clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_clear",
            &passes.type_instances_struct_init_clear,
            resources,
        )?,
        struct_init_contexts: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_contexts",
            &passes.type_instances_struct_init_contexts,
            resources,
        )?,
        struct_init_fields: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_fields",
            &passes.type_instances_struct_init_fields,
            resources,
        )?,
        struct_init_substitute: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_struct_init_substitute",
            &passes.type_instances_struct_init_substitute,
            resources,
        )?,
        array_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_return_refs",
            &passes.type_instances_array_return_refs,
            resources,
        )?,
        array_literal_return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_literal_return_refs",
            &passes.type_instances_array_literal_return_refs,
            resources,
        )?,
        array_index_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_array_index_results",
            &passes.type_instances_array_index_results,
            resources,
        )?,
        validate_aggregate_access: reflected_bind_group_from_resources(
            device,
            "type_check_resident_type_instances_validate_aggregate_access",
            &passes.type_instances_validate_aggregate_access,
            resources,
        )?,
    })
}
