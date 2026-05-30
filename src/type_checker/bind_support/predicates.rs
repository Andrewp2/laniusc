use super::{super::*, common::reflected_bind_group_from_resources};

pub(in crate::type_checker) fn create_predicate_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    input: PredicateInput<'_>,
    resident_resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<PredicateBindGroups> {
    let items = input.hir_items;
    let path = input.module_path;
    let rows = input.rows;

    let clear_bound_arg_facts = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_predicates_clear_bound_arg_facts"),
        &passes.predicates_clear_bound_arg_facts,
        0,
        &[
            ("gParams", input.params.as_entire_binding()),
            ("hir_status", input.hir_status.as_entire_binding()),
            (
                "predicate_bound_arg_count",
                rows.bound_arg_count.as_entire_binding(),
            ),
            (
                "predicate_bound_first_arg_token",
                rows.first_arg_token.as_entire_binding(),
            ),
            (
                "predicate_bound_second_arg_token",
                rows.second_arg_token.as_entire_binding(),
            ),
            ("predicate_status", rows.status.as_entire_binding()),
            (
                "predicate_method_contract_owner_node",
                rows.method_contract_owner_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_token",
                rows.method_contract_name_token.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_id",
                rows.method_contract_name_id.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_count",
                rows.method_contract_param_count.as_entire_binding(),
            ),
            (
                "predicate_method_contract_first_param_node",
                rows.method_contract_first_param_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_return_type_node",
                rows.method_contract_return_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_visibility",
                rows.method_contract_visibility.as_entire_binding(),
            ),
            (
                "predicate_method_contract_status",
                rows.method_contract_status.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_next_node",
                rows.method_contract_param_next_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_type_node",
                rows.method_contract_param_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_first",
                rows.method_contract_owner_range_first.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_count",
                rows.method_contract_owner_range_count.as_entire_binding(),
            ),
        ],
    )?;

    let collect_bound_arg_facts = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_predicates_collect_bound_arg_facts"),
        &passes.predicates_collect_bound_arg_facts,
        0,
        &[
            ("gParams", input.params.as_entire_binding()),
            ("hir_status", input.hir_status.as_entire_binding()),
            ("node_kind", items.node_kind.as_entire_binding()),
            ("parent", items.parent.as_entire_binding()),
            ("first_child", items.first_child.as_entire_binding()),
            ("next_sibling", items.next_sibling.as_entire_binding()),
            (
                "predicate_bound_arg_count",
                rows.bound_arg_count.as_entire_binding(),
            ),
            (
                "predicate_bound_first_arg_token",
                rows.first_arg_token.as_entire_binding(),
            ),
            (
                "predicate_bound_second_arg_token",
                rows.second_arg_token.as_entire_binding(),
            ),
            ("predicate_status", rows.status.as_entire_binding()),
        ],
    )?;

    let collect_method_contracts = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_predicates_collect_method_contracts"),
        &passes.predicates_collect_method_contracts,
        0,
        &[
            ("gParams", input.params.as_entire_binding()),
            ("hir_status", input.hir_status.as_entire_binding()),
            ("node_kind", items.node_kind.as_entire_binding()),
            ("parent", items.parent.as_entire_binding()),
            ("first_child", items.first_child.as_entire_binding()),
            (
                "hir_method_owner_node",
                items.method_owner_node.as_entire_binding(),
            ),
            (
                "hir_method_name_token",
                items.method_name_token.as_entire_binding(),
            ),
            (
                "hir_method_visibility",
                items.method_visibility.as_entire_binding(),
            ),
            (
                "hir_method_signature_flags",
                items.method_signature_flags.as_entire_binding(),
            ),
            (
                "hir_fn_return_type_node",
                items.fn_return_type_node.as_entire_binding(),
            ),
            (
                "name_id_by_token",
                input.name_id_by_token.as_entire_binding(),
            ),
            ("hir_param_record", items.param_record.as_entire_binding()),
            (
                "hir_param_type_node",
                items.param_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_node",
                rows.method_contract_owner_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_token",
                rows.method_contract_name_token.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_id",
                rows.method_contract_name_id.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_count",
                rows.method_contract_param_count.as_entire_binding(),
            ),
            (
                "predicate_method_contract_first_param_node",
                rows.method_contract_first_param_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_return_type_node",
                rows.method_contract_return_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_visibility",
                rows.method_contract_visibility.as_entire_binding(),
            ),
            (
                "predicate_method_contract_status",
                rows.method_contract_status.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_next_node",
                rows.method_contract_param_next_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_type_node",
                rows.method_contract_param_type_node.as_entire_binding(),
            ),
        ],
    )?;

    let collect = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_predicates_collect"),
        &passes.predicates_collect,
        0,
        &[
            ("gParams", input.params.as_entire_binding()),
            ("hir_status", input.hir_status.as_entire_binding()),
            ("node_kind", items.node_kind.as_entire_binding()),
            ("parent", items.parent.as_entire_binding()),
            ("first_child", items.first_child.as_entire_binding()),
            ("next_sibling", items.next_sibling.as_entire_binding()),
            ("subtree_end", items.subtree_end.as_entire_binding()),
            ("hir_token_pos", input.hir_token_pos.as_entire_binding()),
            (
                "hir_type_len_value",
                items.type_len_value.as_entire_binding(),
            ),
            (
                "hir_type_arg_start",
                items.type_arg_start.as_entire_binding(),
            ),
            (
                "hir_type_arg_count",
                items.type_arg_count.as_entire_binding(),
            ),
            ("hir_type_arg_next", items.type_arg_next.as_entire_binding()),
            ("hir_item_kind", items.kind.as_entire_binding()),
            ("hir_item_name_token", items.name_token.as_entire_binding()),
            (
                "hir_method_impl_receiver_type_node",
                items.method_impl_receiver_type_node.as_entire_binding(),
            ),
            (
                "name_id_by_token",
                input.name_id_by_token.as_entire_binding(),
            ),
            (
                "type_decl_generic_param_count_by_node",
                input.generic_param_count_by_node.as_entire_binding(),
            ),
            (
                "type_generic_param_slot_by_token",
                input.generic_param_slot_by_token.as_entire_binding(),
            ),
            (
                "generic_decl_owner_by_node",
                resident_resources["generic_decl_owner_by_node"].clone(),
            ),
            (
                "generic_param_count_out",
                resident_resources["generic_param_count_out"].clone(),
            ),
            (
                "generic_param_owner_node",
                resident_resources["generic_param_owner_node"].clone(),
            ),
            (
                "generic_param_name_id",
                resident_resources["generic_param_name_id"].clone(),
            ),
            (
                "generic_param_token",
                resident_resources["generic_param_token"].clone(),
            ),
            (
                "generic_param_kind",
                resident_resources["generic_param_kind"].clone(),
            ),
            (
                "generic_param_key_order",
                resident_resources["generic_param_key_order"].clone(),
            ),
            (
                "type_expr_ref_tag",
                input.type_expr_ref_tag.as_entire_binding(),
            ),
            (
                "language_type_code_by_name_id",
                input.type_code_by_name.as_entire_binding(),
            ),
            ("decl_count_out", path.decl_count_out.as_entire_binding()),
            ("decl_name_id", path.decl_name_id.as_entire_binding()),
            ("decl_kind", path.decl_kind.as_entire_binding()),
            ("decl_namespace", path.decl_namespace.as_entire_binding()),
            ("decl_hir_node", path.decl_hir_node.as_entire_binding()),
            ("decl_visibility", path.decl_visibility.as_entire_binding()),
            (
                "module_count_out",
                path.module_count_out.as_entire_binding(),
            ),
            (
                "sorted_module_key_order",
                path.module_key_to_module_id.as_entire_binding(),
            ),
            (
                "module_key_segment_count",
                path.module_key_segment_count.as_entire_binding(),
            ),
            (
                "module_key_segment_base",
                path.module_key_segment_base.as_entire_binding(),
            ),
            (
                "module_key_segment_name_id",
                path.module_key_segment_name_id.as_entire_binding(),
            ),
            (
                "decl_type_key_count_out",
                path.decl_type_key_count_out.as_entire_binding(),
            ),
            (
                "decl_type_key_to_decl_id",
                path.decl_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "decl_id_by_name_token",
                path.decl_id_by_name_token.as_entire_binding(),
            ),
            ("decl_module_id", path.decl_module_id.as_entire_binding()),
            ("path_count_out", path.path_count_out.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                path.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "path_owner_module_id",
                path.path_owner_module_id.as_entire_binding(),
            ),
            (
                "import_visible_type_count_out",
                path.import_visible_type_count_out.as_entire_binding(),
            ),
            (
                "import_visible_type_key_module_id",
                path.import_visible_type_key_module_id.as_entire_binding(),
            ),
            (
                "import_visible_type_key_name_id",
                path.import_visible_type_key_name_id.as_entire_binding(),
            ),
            (
                "import_visible_type_key_to_decl_id",
                path.import_visible_type_key_to_decl_id.as_entire_binding(),
            ),
            (
                "import_visible_type_status",
                path.import_visible_type_status.as_entire_binding(),
            ),
            ("predicate_owner_node", rows.owner_node.as_entire_binding()),
            (
                "predicate_subject_token",
                rows.subject_token.as_entire_binding(),
            ),
            (
                "predicate_bound_token",
                rows.bound_token.as_entire_binding(),
            ),
            (
                "predicate_bound_decl_id",
                rows.bound_decl_id.as_entire_binding(),
            ),
            (
                "predicate_bound_arg_count",
                rows.bound_arg_count.as_entire_binding(),
            ),
            (
                "predicate_bound_first_arg_token",
                rows.first_arg_token.as_entire_binding(),
            ),
            (
                "predicate_bound_second_arg_token",
                rows.second_arg_token.as_entire_binding(),
            ),
            ("predicate_status", rows.status.as_entire_binding()),
            (
                "predicate_method_contract_owner_node",
                rows.method_contract_owner_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_token",
                rows.method_contract_name_token.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_id",
                rows.method_contract_name_id.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_count",
                rows.method_contract_param_count.as_entire_binding(),
            ),
            (
                "predicate_method_contract_first_param_node",
                rows.method_contract_first_param_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_return_type_node",
                rows.method_contract_return_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_visibility",
                rows.method_contract_visibility.as_entire_binding(),
            ),
            (
                "predicate_method_contract_status",
                rows.method_contract_status.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_next_node",
                rows.method_contract_param_next_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_param_type_node",
                rows.method_contract_param_type_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_key_order",
                rows.method_contract_order.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_first",
                rows.method_contract_owner_range_first.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_count",
                rows.method_contract_owner_range_count.as_entire_binding(),
            ),
        ],
    )?;

    let method_contract_keys = create_predicate_key_bind_groups(
        device,
        passes,
        "method_contract",
        input.token_capacity,
        input.predicate_capacity,
        input.predicate_blocks,
        PREDICATE_KEY_MODE_METHOD_CONTRACT,
        PREDICATE_METHOD_CONTRACT_KEY_RADIX_STEPS,
        input.hir_token_pos,
        input.name_id_by_token,
        resident_resources,
        rows.method_contract_order,
        rows.method_contract_order_tmp,
        rows.radix,
    )?;
    let build_method_contract_owner_ranges = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_predicates_build_method_contract_owner_ranges"),
        &passes.predicates_build_method_owner_ranges,
        0,
        &[
            ("gParams", input.params.as_entire_binding()),
            ("hir_status", input.hir_status.as_entire_binding()),
            (
                "predicate_method_contract_owner_node",
                rows.method_contract_owner_node.as_entire_binding(),
            ),
            (
                "predicate_method_contract_name_id",
                rows.method_contract_name_id.as_entire_binding(),
            ),
            (
                "predicate_method_contract_key_order",
                rows.method_contract_order.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_first",
                rows.method_contract_owner_range_first.as_entire_binding(),
            ),
            (
                "predicate_method_contract_owner_range_count",
                rows.method_contract_owner_range_count.as_entire_binding(),
            ),
        ],
    )?;
    let owner_keys = create_predicate_key_bind_groups(
        device,
        passes,
        "owner",
        input.token_capacity,
        input.predicate_capacity,
        input.predicate_blocks,
        PREDICATE_KEY_MODE_OWNER,
        PREDICATE_OWNER_KEY_RADIX_STEPS,
        input.hir_token_pos,
        input.name_id_by_token,
        resident_resources,
        rows.owner_order,
        rows.owner_order_tmp,
        rows.radix,
    )?;
    let impl_keys = create_predicate_key_bind_groups(
        device,
        passes,
        "impl",
        input.token_capacity,
        input.predicate_capacity,
        input.predicate_blocks,
        PREDICATE_KEY_MODE_IMPL,
        PREDICATE_IMPL_KEY_RADIX_STEPS,
        input.hir_token_pos,
        input.name_id_by_token,
        resident_resources,
        rows.impl_order,
        rows.impl_order_tmp,
        rows.radix,
    )?;

    Ok(PredicateBindGroups {
        clear_bound_arg_facts,
        collect_bound_arg_facts,
        collect_method_contracts,
        collect,
        _method_contract_key_radix_steps: method_contract_keys.steps,
        seed_method_contract_key_order: method_contract_keys.seed_key_order,
        sort_method_contract_key_histogram: method_contract_keys.sort_key_histogram,
        sort_method_contract_key_bucket_prefix: method_contract_keys.sort_key_bucket_prefix,
        sort_method_contract_key_bucket_bases: method_contract_keys.sort_key_bucket_bases,
        sort_method_contract_key_scatter: method_contract_keys.sort_key_scatter,
        build_method_contract_owner_ranges,
        _owner_key_radix_steps: owner_keys.steps,
        seed_owner_key_order: owner_keys.seed_key_order,
        sort_owner_key_histogram: owner_keys.sort_key_histogram,
        sort_owner_key_bucket_prefix: owner_keys.sort_key_bucket_prefix,
        sort_owner_key_bucket_bases: owner_keys.sort_key_bucket_bases,
        sort_owner_key_scatter: owner_keys.sort_key_scatter,
        _impl_key_radix_steps: impl_keys.steps,
        seed_impl_key_order: impl_keys.seed_key_order,
        sort_impl_key_histogram: impl_keys.sort_key_histogram,
        sort_impl_key_bucket_prefix: impl_keys.sort_key_bucket_prefix,
        sort_impl_key_bucket_bases: impl_keys.sort_key_bucket_bases,
        sort_impl_key_scatter: impl_keys.sort_key_scatter,
        obligations: reflected_bind_group_from_resources(
            device,
            "type_check_resident_predicates_obligations",
            &passes.predicates_obligations,
            resident_resources,
        )?,
    })
}

struct PredicateKeyBindGroups {
    steps: Vec<PredicateKeyStep>,
    seed_key_order: wgpu::BindGroup,
    sort_key_histogram: Vec<wgpu::BindGroup>,
    sort_key_bucket_prefix: Vec<wgpu::BindGroup>,
    sort_key_bucket_bases: Vec<wgpu::BindGroup>,
    sort_key_scatter: Vec<wgpu::BindGroup>,
}

#[allow(clippy::too_many_arguments)]
fn create_predicate_key_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    label: &'static str,
    token_capacity: u32,
    predicate_capacity: u32,
    predicate_blocks: u32,
    mode: u32,
    radix_steps: u32,
    hir_token_pos: &wgpu::Buffer,
    name_id_by_token: &wgpu::Buffer,
    resident_resources: &HashMap<String, wgpu::BindingResource<'_>>,
    key_order: &wgpu::Buffer,
    key_order_tmp: &wgpu::Buffer,
    radix: RadixRows<'_>,
) -> Result<PredicateKeyBindGroups> {
    let seed_params = uniform_from_val(
        device,
        &format!("type_check.predicates.{label}.key.params.seed"),
        &PredicateKeyParams {
            predicate_capacity,
            token_capacity,
            mode,
            n_blocks: predicate_blocks,
            key_step: 0,
            reserved: 0,
        },
    );
    let seed_key_order = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("type_check.predicates.{label}.seed_key_order")),
        &passes.predicates_seed_key_order,
        0,
        &[
            ("gParams", seed_params.as_entire_binding()),
            (
                "predicate_count_in",
                resident_resources["hir_active_count"].clone(),
            ),
            ("predicate_key_order", key_order.as_entire_binding()),
        ],
    )?;

    let mut steps = Vec::with_capacity(radix_steps as usize + 1);
    steps.push(PredicateKeyStep {
        _params: seed_params,
    });
    let mut sort_key_histogram = Vec::with_capacity(radix_steps as usize);
    let mut sort_key_bucket_prefix = Vec::with_capacity(radix_steps as usize);
    let mut sort_key_bucket_bases = Vec::with_capacity(radix_steps as usize);
    let mut sort_key_scatter = Vec::with_capacity(radix_steps as usize);

    for key_step in 0..radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.predicates.{label}.key.params.{key_step}"),
            &PredicateKeyParams {
                predicate_capacity,
                token_capacity,
                mode,
                n_blocks: predicate_blocks,
                key_step,
                reserved: 0,
            },
        );
        let read_order = if key_step % 2 == 0 {
            key_order
        } else {
            key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            key_order_tmp
        } else {
            key_order
        };

        sort_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!(
                "type_check.predicates.{label}.sort_keys_histogram"
            )),
            &passes.predicates_sort_keys,
            0,
            &predicate_key_sort_bindings(
                &step_params,
                hir_token_pos,
                name_id_by_token,
                resident_resources,
                read_order,
                None,
                radix,
            ),
        )?);

        sort_key_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!(
                "type_check.predicates.{label}.sort_keys_bucket_prefix"
            )),
            &passes.names_radix_bucket_prefix,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "name_count_in",
                    resident_resources["hir_active_count"].clone(),
                ),
                ("radix_block_histogram", radix.histogram.as_entire_binding()),
                (
                    "radix_block_bucket_prefix",
                    radix.bucket_prefix.as_entire_binding(),
                ),
                ("radix_bucket_total", radix.bucket_total.as_entire_binding()),
            ],
        )?);

        sort_key_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!(
                "type_check.predicates.{label}.sort_keys_bucket_bases"
            )),
            &passes.names_radix_bucket_bases,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("radix_bucket_total", radix.bucket_total.as_entire_binding()),
                ("radix_bucket_base", radix.bucket_base.as_entire_binding()),
            ],
        )?);

        sort_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("type_check.predicates.{label}.sort_keys_scatter")),
            &passes.predicates_sort_keys_scatter,
            0,
            &predicate_key_sort_bindings(
                &step_params,
                hir_token_pos,
                name_id_by_token,
                resident_resources,
                read_order,
                Some(write_order),
                radix,
            ),
        )?);

        steps.push(PredicateKeyStep {
            _params: step_params,
        });
    }

    Ok(PredicateKeyBindGroups {
        steps,
        seed_key_order,
        sort_key_histogram,
        sort_key_bucket_prefix,
        sort_key_bucket_bases,
        sort_key_scatter,
    })
}

fn predicate_key_sort_bindings<'a>(
    params: &'a LaniusBuffer<PredicateKeyParams>,
    hir_token_pos: &'a wgpu::Buffer,
    _name_id_by_token: &'a wgpu::Buffer,
    resources: &'a HashMap<String, wgpu::BindingResource<'a>>,
    key_order_in: &'a wgpu::Buffer,
    key_order_out: Option<&'a wgpu::Buffer>,
    radix: RadixRows<'a>,
) -> Vec<(&'static str, wgpu::BindingResource<'a>)> {
    let mut bindings = vec![
        ("gParams", params.as_entire_binding()),
        ("predicate_count_in", resources["hir_active_count"].clone()),
        ("hir_token_pos", hir_token_pos.as_entire_binding()),
        ("visible_type", resources["visible_type"].clone()),
        ("type_expr_ref_tag", resources["type_expr_ref_tag"].clone()),
        (
            "type_expr_ref_payload",
            resources["type_expr_ref_payload"].clone(),
        ),
        (
            "type_generic_param_slot_by_token",
            resources["type_generic_param_slot_by_token"].clone(),
        ),
        (
            "predicate_owner_node",
            resources["predicate_owner_node"].clone(),
        ),
        (
            "predicate_subject_token",
            resources["predicate_subject_token"].clone(),
        ),
        (
            "predicate_bound_decl_id",
            resources["predicate_bound_decl_id"].clone(),
        ),
        (
            "predicate_bound_arg_count",
            resources["predicate_bound_arg_count"].clone(),
        ),
        (
            "predicate_bound_first_arg_token",
            resources["predicate_bound_first_arg_token"].clone(),
        ),
        (
            "predicate_bound_second_arg_token",
            resources["predicate_bound_second_arg_token"].clone(),
        ),
        ("predicate_status", resources["predicate_status"].clone()),
        (
            "predicate_method_contract_owner_node",
            resources["predicate_method_contract_owner_node"].clone(),
        ),
        (
            "predicate_method_contract_name_id",
            resources["predicate_method_contract_name_id"].clone(),
        ),
        ("predicate_key_order_in", key_order_in.as_entire_binding()),
        ("radix_block_histogram", radix.histogram.as_entire_binding()),
    ];
    if let Some(order_out) = key_order_out {
        bindings.push(("radix_bucket_base", radix.bucket_base.as_entire_binding()));
        bindings.push((
            "radix_block_bucket_prefix",
            radix.bucket_prefix.as_entire_binding(),
        ));
        bindings.push(("predicate_key_order_out", order_out.as_entire_binding()));
    }
    bindings
}
