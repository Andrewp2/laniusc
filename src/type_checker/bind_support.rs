use super::*;

fn reflected_bind_group_from_resources(
    device: &wgpu::Device,
    label: &'static str,
    pass: &PassData,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<wgpu::BindGroup> {
    bind_group::create_bind_group_from_reflection(
        device,
        Some(label),
        &pass.bind_group_layouts[0],
        &pass.reflection,
        0,
        resources,
    )
}

pub(super) fn create_visible_bind_groups(
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<VisibleBindGroups> {
    let clear_pass = type_check_visible_clear_pass(device)?;
    let scope_blocks_pass = type_check_visible_scope_blocks_pass(device)?;
    let scatter_pass = type_check_visible_scatter_pass(device)?;
    let decode_pass = type_check_visible_decode_pass(device)?;
    create_visible_bind_groups_from_passes(
        device,
        resources,
        clear_pass,
        scope_blocks_pass,
        scatter_pass,
        decode_pass,
    )
}

pub(super) fn create_visible_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
) -> Result<VisibleBindGroups> {
    create_visible_bind_groups_from_passes(
        device,
        resources,
        &passes.visible_clear,
        &passes.visible_scope_blocks,
        &passes.visible_scatter,
        &passes.visible_decode,
    )
}

pub(super) fn create_visible_bind_groups_from_passes(
    device: &wgpu::Device,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    clear_pass: &PassData,
    scope_blocks_pass: &PassData,
    scatter_pass: &PassData,
    decode_pass: &PassData,
) -> Result<VisibleBindGroups> {
    let clear = reflected_bind_group_from_resources(
        device,
        "type_check_visible_01_clear",
        clear_pass,
        resources,
    )?;
    let scope_blocks = reflected_bind_group_from_resources(
        device,
        "type_check_visible_02_scope_blocks",
        scope_blocks_pass,
        resources,
    )?;
    let scatter = reflected_bind_group_from_resources(
        device,
        "type_check_visible_02_scatter",
        scatter_pass,
        resources,
    )?;
    let decode = reflected_bind_group_from_resources(
        device,
        "type_check_visible_03_decode",
        decode_pass,
        resources,
    )?;

    Ok(VisibleBindGroups {
        clear,
        scope_blocks,
        scatter,
        decode,
    })
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_name_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<TypeCheckParams>,
    source_len: u32,
    name_capacity: u32,
    token_scan_n_blocks: u32,
    name_n_blocks: u32,
    scan_steps: &[NameScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    source_buf: &wgpu::Buffer,
    status_buf: &wgpu::Buffer,
    name_lexeme_flag: &wgpu::Buffer,
    name_lexeme_kind: &wgpu::Buffer,
    name_lexeme_prefix: &wgpu::Buffer,
    name_scan_local_prefix: &wgpu::Buffer,
    name_scan_block_sum: &wgpu::Buffer,
    name_scan_prefix_a: &wgpu::Buffer,
    name_scan_prefix_b: &wgpu::Buffer,
    name_scan_total: &wgpu::Buffer,
    name_spans: &wgpu::Buffer,
    name_order_in: &wgpu::Buffer,
    name_order_tmp: &wgpu::Buffer,
    language_symbol_bytes: &wgpu::Buffer,
    language_symbol_start: &wgpu::Buffer,
    language_symbol_len: &wgpu::Buffer,
    name_id_by_token: &wgpu::Buffer,
    language_name_id: &wgpu::Buffer,
    radix_block_histogram: &wgpu::Buffer,
    radix_block_bucket_prefix: &wgpu::Buffer,
    radix_bucket_total: &wgpu::Buffer,
    radix_bucket_base: &wgpu::Buffer,
    run_head_mask: &wgpu::Buffer,
    adjacent_equal_mask: &wgpu::Buffer,
    run_head_prefix: &wgpu::Buffer,
    sorted_name_id: &wgpu::Buffer,
    name_id_by_input: &wgpu::Buffer,
    unique_name_count: &wgpu::Buffer,
) -> Result<NameBindGroups> {
    let run_head_scan_params = NameScanParams {
        n_items: name_capacity,
        n_blocks: name_n_blocks,
        scan_step: 0,
    };
    let run_head_scan_steps = make_name_scan_steps(device, run_head_scan_params);

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("token_count".into(), token_count_buf.as_entire_binding()),
        (
            "name_lexeme_flag".into(),
            name_lexeme_flag.as_entire_binding(),
        ),
        (
            "name_lexeme_kind".into(),
            name_lexeme_kind.as_entire_binding(),
        ),
    ]);
    let mark = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_00_mark_lexemes"),
        &passes.names_mark_lexemes.bind_group_layouts[0],
        &passes.names_mark_lexemes.reflection,
        0,
        &mark_resources,
    )?;

    let scan_local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        ("scan_input".into(), name_lexeme_flag.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            name_scan_local_prefix.as_entire_binding(),
        ),
        (
            "scan_block_sum".into(),
            name_scan_block_sum.as_entire_binding(),
        ),
    ]);
    let scan_local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_scan_00_local"),
        &passes.names_scan_local.bind_group_layouts[0],
        &passes.names_scan_local.reflection,
        0,
        &scan_local_resources,
    )?;

    let mut scan_blocks = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            name_scan_prefix_a
        } else {
            name_scan_prefix_b
        };
        let prefix_out = if step.write_to_a {
            name_scan_prefix_a
        } else {
            name_scan_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gScan".into(), step.params.as_entire_binding()),
            (
                "scan_block_sum".into(),
                name_scan_block_sum.as_entire_binding(),
            ),
            ("scan_block_prefix_in".into(), prefix_in.as_entire_binding()),
            (
                "scan_block_prefix_out".into(),
                prefix_out.as_entire_binding(),
            ),
        ]);
        scan_blocks.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_scan_01_blocks"),
            &passes.names_scan_blocks.bind_group_layouts[0],
            &passes.names_scan_blocks.reflection,
            0,
            &scan_resources,
        )?);
    }

    let final_prefix = if scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        name_scan_prefix_a
    } else {
        name_scan_prefix_b
    };
    let scan_apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            name_scan_local_prefix.as_entire_binding(),
        ),
        ("scan_block_prefix".into(), final_prefix.as_entire_binding()),
        (
            "scan_output_prefix".into(),
            name_lexeme_prefix.as_entire_binding(),
        ),
        ("scan_total".into(), name_scan_total.as_entire_binding()),
    ]);
    let scan_apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_scan_02_apply"),
        &passes.names_scan_apply.bind_group_layouts[0],
        &passes.names_scan_apply.reflection,
        0,
        &scan_apply_resources,
    )?;

    let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("token_count".into(), token_count_buf.as_entire_binding()),
        (
            "name_lexeme_flag".into(),
            name_lexeme_flag.as_entire_binding(),
        ),
        (
            "name_lexeme_kind".into(),
            name_lexeme_kind.as_entire_binding(),
        ),
        (
            "name_lexeme_prefix".into(),
            name_lexeme_prefix.as_entire_binding(),
        ),
        (
            "language_symbol_start".into(),
            language_symbol_start.as_entire_binding(),
        ),
        (
            "language_symbol_len".into(),
            language_symbol_len.as_entire_binding(),
        ),
        ("name_spans".into(), name_spans.as_entire_binding()),
        ("name_order_in".into(), name_order_in.as_entire_binding()),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        ("name_count_out".into(), name_scan_total.as_entire_binding()),
        ("status".into(), status_buf.as_entire_binding()),
    ]);
    let scatter = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_01_scatter_lexemes"),
        &passes.names_scatter_lexemes.bind_group_layouts[0],
        &passes.names_scatter_lexemes.reflection,
        0,
        &scatter_resources,
    )?;

    let mut radix_steps = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_histogram = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_bucket_prefix = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_bucket_bases = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    let mut radix_scatter = Vec::with_capacity(NAME_RADIX_MAX_BYTES as usize);
    for pass_i in 0..NAME_RADIX_MAX_BYTES {
        let byte_offset = NAME_RADIX_MAX_BYTES - 1 - pass_i;
        let step_params = uniform_from_val(
            device,
            &format!("type_check.names.radix.params.{byte_offset}"),
            &NameRadixParams {
                name_count: name_capacity,
                source_len,
                n_blocks: name_n_blocks,
                radix_byte_offset: byte_offset,
            },
        );
        let read_order = if pass_i % 2 == 0 {
            name_order_in
        } else {
            name_order_tmp
        };
        let write_order = if pass_i % 2 == 0 {
            name_order_tmp
        } else {
            name_order_in
        };

        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            ("name_spans".into(), name_spans.as_entire_binding()),
            ("name_count_in".into(), name_scan_total.as_entire_binding()),
            ("name_order_in".into(), read_order.as_entire_binding()),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            (
                "language_symbol_bytes".into(),
                language_symbol_bytes.as_entire_binding(),
            ),
            (
                "radix_block_histogram".into(),
                radix_block_histogram.as_entire_binding(),
            ),
        ]);
        radix_histogram.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_radix_00_histogram"),
            &passes.names_radix_histogram.bind_group_layouts[0],
            &passes.names_radix_histogram.reflection,
            0,
            &histogram_resources,
        )?);

        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                radix_bucket_total.as_entire_binding(),
            ),
        ]);
        radix_bucket_prefix.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_radix_00b_bucket_prefix"),
            &passes.names_radix_bucket_prefix.bind_group_layouts[0],
            &passes.names_radix_bucket_prefix.reflection,
            0,
            &bucket_prefix_resources,
        )?);

        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                radix_bucket_base.as_entire_binding(),
            ),
        ]);
        radix_bucket_bases.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_radix_00c_bucket_bases"),
            &passes.names_radix_bucket_bases.bind_group_layouts[0],
            &passes.names_radix_bucket_bases.reflection,
            0,
            &bucket_bases_resources,
        )?);

        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            ("name_spans".into(), name_spans.as_entire_binding()),
            ("name_count_in".into(), name_scan_total.as_entire_binding()),
            ("name_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_bucket_base".into(),
                radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                radix_block_bucket_prefix.as_entire_binding(),
            ),
            ("source_bytes".into(), source_buf.as_entire_binding()),
            (
                "language_symbol_bytes".into(),
                language_symbol_bytes.as_entire_binding(),
            ),
            ("name_order_out".into(), write_order.as_entire_binding()),
        ]);
        radix_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_radix_01_scatter"),
            &passes.names_radix_scatter.bind_group_layouts[0],
            &passes.names_radix_scatter.reflection,
            0,
            &scatter_resources,
        )?);

        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        radix_steps.push(NameRadixStep {
            _params: step_params,
        });
    }

    let sorted_name_order = if NAME_RADIX_MAX_BYTES % 2 == 0 {
        name_order_in
    } else {
        name_order_tmp
    };
    let final_params = uniform_from_val(
        device,
        "type_check.names.radix.params.final",
        &NameRadixParams {
            name_count: name_capacity,
            source_len,
            n_blocks: name_n_blocks,
            radix_byte_offset: 0,
        },
    );
    let dedup_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), final_params.as_entire_binding()),
        ("name_spans".into(), name_spans.as_entire_binding()),
        ("name_count_in".into(), name_scan_total.as_entire_binding()),
        (
            "sorted_name_order".into(),
            sorted_name_order.as_entire_binding(),
        ),
        ("source_bytes".into(), source_buf.as_entire_binding()),
        (
            "language_symbol_bytes".into(),
            language_symbol_bytes.as_entire_binding(),
        ),
        ("run_head_mask".into(), run_head_mask.as_entire_binding()),
        (
            "adjacent_equal_mask".into(),
            adjacent_equal_mask.as_entire_binding(),
        ),
    ]);
    let dedup = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_radix_02_adjacent_dedup"),
        &passes.names_radix_dedup.bind_group_layouts[0],
        &passes.names_radix_dedup.reflection,
        0,
        &dedup_resources,
    )?;

    let run_head_scan_local_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gScan".into(),
                run_head_scan_steps[0].params.as_entire_binding(),
            ),
            ("scan_input".into(), run_head_mask.as_entire_binding()),
            (
                "scan_local_prefix".into(),
                name_scan_local_prefix.as_entire_binding(),
            ),
            (
                "scan_block_sum".into(),
                name_scan_block_sum.as_entire_binding(),
            ),
        ]);
    let run_head_scan_local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_run_heads_scan_00_local"),
        &passes.names_scan_local.bind_group_layouts[0],
        &passes.names_scan_local.reflection,
        0,
        &run_head_scan_local_resources,
    )?;

    let mut run_head_scan_blocks = Vec::with_capacity(run_head_scan_steps.len());
    for step in &run_head_scan_steps {
        let prefix_in = if step.read_from_a {
            name_scan_prefix_a
        } else {
            name_scan_prefix_b
        };
        let prefix_out = if step.write_to_a {
            name_scan_prefix_a
        } else {
            name_scan_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gScan".into(), step.params.as_entire_binding()),
            (
                "scan_block_sum".into(),
                name_scan_block_sum.as_entire_binding(),
            ),
            ("scan_block_prefix_in".into(), prefix_in.as_entire_binding()),
            (
                "scan_block_prefix_out".into(),
                prefix_out.as_entire_binding(),
            ),
        ]);
        run_head_scan_blocks.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_names_run_heads_scan_01_blocks"),
            &passes.names_scan_blocks.bind_group_layouts[0],
            &passes.names_scan_blocks.reflection,
            0,
            &scan_resources,
        )?);
    }

    let run_head_scan_apply_resources: HashMap<String, wgpu::BindingResource<'_>> =
        HashMap::from([
            (
                "gScan".into(),
                run_head_scan_steps[0].params.as_entire_binding(),
            ),
            (
                "scan_local_prefix".into(),
                name_scan_local_prefix.as_entire_binding(),
            ),
            ("scan_block_prefix".into(), final_prefix.as_entire_binding()),
            (
                "scan_output_prefix".into(),
                run_head_prefix.as_entire_binding(),
            ),
            ("scan_total".into(), unique_name_count.as_entire_binding()),
        ]);
    let run_head_scan_apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_run_heads_scan_02_apply"),
        &passes.names_scan_apply.bind_group_layouts[0],
        &passes.names_scan_apply.reflection,
        0,
        &run_head_scan_apply_resources,
    )?;

    let assign_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), final_params.as_entire_binding()),
        ("name_spans".into(), name_spans.as_entire_binding()),
        ("name_count_in".into(), name_scan_total.as_entire_binding()),
        (
            "sorted_name_order".into(),
            sorted_name_order.as_entire_binding(),
        ),
        ("run_head_mask".into(), run_head_mask.as_entire_binding()),
        (
            "run_head_prefix".into(),
            run_head_prefix.as_entire_binding(),
        ),
        ("sorted_name_id".into(), sorted_name_id.as_entire_binding()),
        (
            "name_id_by_input".into(),
            name_id_by_input.as_entire_binding(),
        ),
        (
            "name_id_by_token".into(),
            name_id_by_token.as_entire_binding(),
        ),
        (
            "language_name_id".into(),
            language_name_id.as_entire_binding(),
        ),
        (
            "unique_name_count".into(),
            unique_name_count.as_entire_binding(),
        ),
    ]);
    let assign_ids = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_names_radix_03_assign_ids"),
        &passes.names_radix_assign_ids.bind_group_layouts[0],
        &passes.names_radix_assign_ids.reflection,
        0,
        &assign_resources,
    )?;
    drop(dedup_resources);
    drop(assign_resources);
    radix_steps.push(NameRadixStep {
        _params: final_params,
    });

    Ok(NameBindGroups {
        token_scan_n_blocks,
        radix_n_blocks: name_n_blocks,
        mark,
        scan_local,
        scan_blocks,
        scan_apply,
        scatter,
        _radix_steps: radix_steps,
        radix_histogram,
        radix_bucket_prefix,
        radix_bucket_bases,
        radix_scatter,
        dedup,
        _run_head_scan_steps: run_head_scan_steps,
        run_head_scan_local,
        run_head_scan_blocks,
        run_head_scan_apply,
        assign_ids,
    })
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_u32_scan_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    label: &'static str,
    scan_steps: &[NameScanStep],
    scan_input: &wgpu::Buffer,
    scan_output_prefix: &wgpu::Buffer,
    scan_total: &wgpu::Buffer,
    scan_local_prefix: &wgpu::Buffer,
    scan_block_sum: &wgpu::Buffer,
    scan_prefix_a: &wgpu::Buffer,
    scan_prefix_b: &wgpu::Buffer,
) -> Result<U32ScanBindGroups> {
    let scan_local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        ("scan_input".into(), scan_input.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            scan_local_prefix.as_entire_binding(),
        ),
        ("scan_block_sum".into(), scan_block_sum.as_entire_binding()),
    ]);
    let local = bind_group::create_bind_group_from_reflection(
        device,
        Some(&format!("{label}.scan_local")),
        &passes.names_scan_local.bind_group_layouts[0],
        &passes.names_scan_local.reflection,
        0,
        &scan_local_resources,
    )?;

    let mut blocks = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            scan_prefix_a
        } else {
            scan_prefix_b
        };
        let prefix_out = if step.write_to_a {
            scan_prefix_a
        } else {
            scan_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gScan".into(), step.params.as_entire_binding()),
            ("scan_block_sum".into(), scan_block_sum.as_entire_binding()),
            ("scan_block_prefix_in".into(), prefix_in.as_entire_binding()),
            (
                "scan_block_prefix_out".into(),
                prefix_out.as_entire_binding(),
            ),
        ]);
        blocks.push(bind_group::create_bind_group_from_reflection(
            device,
            Some(&format!("{label}.scan_blocks")),
            &passes.names_scan_blocks.bind_group_layouts[0],
            &passes.names_scan_blocks.reflection,
            0,
            &scan_resources,
        )?);
    }

    let final_prefix = if scan_steps
        .last()
        .map(|step| step.write_to_a)
        .unwrap_or(true)
    {
        scan_prefix_a
    } else {
        scan_prefix_b
    };
    let scan_apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gScan".into(), scan_steps[0].params.as_entire_binding()),
        (
            "scan_local_prefix".into(),
            scan_local_prefix.as_entire_binding(),
        ),
        ("scan_block_prefix".into(), final_prefix.as_entire_binding()),
        (
            "scan_output_prefix".into(),
            scan_output_prefix.as_entire_binding(),
        ),
        ("scan_total".into(), scan_total.as_entire_binding()),
    ]);
    let apply = bind_group::create_bind_group_from_reflection(
        device,
        Some(&format!("{label}.scan_apply")),
        &passes.names_scan_apply.bind_group_layouts[0],
        &passes.names_scan_apply.reflection,
        0,
        &scan_apply_resources,
    )?;
    Ok(U32ScanBindGroups {
        local,
        blocks,
        apply,
    })
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_method_key_bind_groups_with_passes(
    device: &wgpu::Device,
    label: &'static str,
    seed_pass: &PassData,
    sort_pass: &PassData,
    bucket_prefix_pass: &PassData,
    bucket_bases_pass: &PassData,
    scatter_pass: &PassData,
    validate_pass: &PassData,
    method_capacity: u32,
    n_blocks: u32,
    module_count_out: &wgpu::Buffer,
    method_decl_impl_node: &wgpu::Buffer,
    method_decl_receiver_ref_tag: &wgpu::Buffer,
    method_decl_receiver_ref_payload: &wgpu::Buffer,
    method_decl_module_id: &wgpu::Buffer,
    method_decl_name_token: &wgpu::Buffer,
    method_decl_name_id: &wgpu::Buffer,
    method_decl_visibility: &wgpu::Buffer,
    module_type_path_type: &wgpu::Buffer,
    type_instance_decl_token: &wgpu::Buffer,
    method_key_to_fn_token: &wgpu::Buffer,
    method_key_order_tmp: &wgpu::Buffer,
    method_key_status: &wgpu::Buffer,
    method_key_duplicate_of: &wgpu::Buffer,
    method_key_radix_block_histogram: &wgpu::Buffer,
    method_key_radix_block_bucket_prefix: &wgpu::Buffer,
    method_key_radix_bucket_total: &wgpu::Buffer,
    method_key_radix_bucket_base: &wgpu::Buffer,
    status: &wgpu::Buffer,
) -> Result<MethodKeyBindGroups> {
    let seed_params = uniform_from_val(
        device,
        &format!("{label}.method_key.params.seed"),
        &ModuleKeyRadixParams {
            module_capacity: method_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let seed_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), seed_params.as_entire_binding()),
        (
            "method_key_to_fn_token".into(),
            method_key_to_fn_token.as_entire_binding(),
        ),
        (
            "method_key_status".into(),
            method_key_status.as_entire_binding(),
        ),
        (
            "method_key_duplicate_of".into(),
            method_key_duplicate_of.as_entire_binding(),
        ),
    ]);
    let seed_key_order = bind_group::create_bind_group_from_reflection(
        device,
        Some(&format!("{label}.seed_key_order")),
        &seed_pass.bind_group_layouts[0],
        &seed_pass.reflection,
        0,
        &seed_resources,
    )?;
    drop(seed_resources);

    let mut key_radix_steps = Vec::with_capacity(METHOD_KEY_RADIX_STEPS as usize + 2);
    key_radix_steps.push(ModuleKeyRadixStep {
        _params: seed_params,
    });
    let mut sort_key_histogram = Vec::with_capacity(METHOD_KEY_RADIX_STEPS as usize);
    let mut sort_key_bucket_prefix = Vec::with_capacity(METHOD_KEY_RADIX_STEPS as usize);
    let mut sort_key_bucket_bases = Vec::with_capacity(METHOD_KEY_RADIX_STEPS as usize);
    let mut sort_key_scatter = Vec::with_capacity(METHOD_KEY_RADIX_STEPS as usize);
    for key_step in 0..METHOD_KEY_RADIX_STEPS {
        let step_params = uniform_from_val(
            device,
            &format!("{label}.method_key.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: method_capacity,
                reserved: 0,
                n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            method_key_to_fn_token
        } else {
            method_key_order_tmp
        };
        let write_order = if key_step % 2 == 0 {
            method_key_order_tmp
        } else {
            method_key_to_fn_token
        };

        let histogram_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "method_decl_impl_node".into(),
                method_decl_impl_node.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_tag".into(),
                method_decl_receiver_ref_tag.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_payload".into(),
                method_decl_receiver_ref_payload.as_entire_binding(),
            ),
            (
                "method_decl_module_id".into(),
                method_decl_module_id.as_entire_binding(),
            ),
            (
                "method_decl_name_id".into(),
                method_decl_name_id.as_entire_binding(),
            ),
            (
                "module_type_path_type".into(),
                module_type_path_type.as_entire_binding(),
            ),
            (
                "type_instance_decl_token".into(),
                type_instance_decl_token.as_entire_binding(),
            ),
            ("method_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                method_key_radix_block_histogram.as_entire_binding(),
            ),
        ]);
        sort_key_histogram.push(bind_group::create_bind_group_from_reflection(
            device,
            Some(&format!("{label}.sort_keys_histogram")),
            &sort_pass.bind_group_layouts[0],
            &sort_pass.reflection,
            0,
            &histogram_resources,
        )?);

        let bucket_prefix_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_block_histogram".into(),
                method_key_radix_block_histogram.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                method_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "radix_bucket_total".into(),
                method_key_radix_bucket_total.as_entire_binding(),
            ),
        ]);
        sort_key_bucket_prefix.push(bind_group::create_bind_group_from_reflection(
            device,
            Some(&format!("{label}.sort_keys_bucket_prefix")),
            &bucket_prefix_pass.bind_group_layouts[0],
            &bucket_prefix_pass.reflection,
            0,
            &bucket_prefix_resources,
        )?);

        let bucket_bases_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "radix_bucket_total".into(),
                method_key_radix_bucket_total.as_entire_binding(),
            ),
            (
                "radix_bucket_base".into(),
                method_key_radix_bucket_base.as_entire_binding(),
            ),
        ]);
        sort_key_bucket_bases.push(bind_group::create_bind_group_from_reflection(
            device,
            Some(&format!("{label}.sort_keys_bucket_bases")),
            &bucket_bases_pass.bind_group_layouts[0],
            &bucket_bases_pass.reflection,
            0,
            &bucket_bases_resources,
        )?);

        let scatter_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step_params.as_entire_binding()),
            (
                "method_decl_impl_node".into(),
                method_decl_impl_node.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_tag".into(),
                method_decl_receiver_ref_tag.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_payload".into(),
                method_decl_receiver_ref_payload.as_entire_binding(),
            ),
            (
                "method_decl_module_id".into(),
                method_decl_module_id.as_entire_binding(),
            ),
            (
                "method_decl_name_id".into(),
                method_decl_name_id.as_entire_binding(),
            ),
            (
                "module_type_path_type".into(),
                module_type_path_type.as_entire_binding(),
            ),
            (
                "type_instance_decl_token".into(),
                type_instance_decl_token.as_entire_binding(),
            ),
            ("method_key_order_in".into(), read_order.as_entire_binding()),
            (
                "radix_bucket_base".into(),
                method_key_radix_bucket_base.as_entire_binding(),
            ),
            (
                "radix_block_bucket_prefix".into(),
                method_key_radix_block_bucket_prefix.as_entire_binding(),
            ),
            (
                "method_key_order_out".into(),
                write_order.as_entire_binding(),
            ),
        ]);
        sort_key_scatter.push(bind_group::create_bind_group_from_reflection(
            device,
            Some(&format!("{label}.sort_keys_scatter")),
            &scatter_pass.bind_group_layouts[0],
            &scatter_pass.reflection,
            0,
            &scatter_resources,
        )?);

        drop(histogram_resources);
        drop(bucket_prefix_resources);
        drop(bucket_bases_resources);
        drop(scatter_resources);
        key_radix_steps.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let validate_params = uniform_from_val(
        device,
        &format!("{label}.method_key.params.validate"),
        &ModuleKeyRadixParams {
            module_capacity: method_capacity,
            reserved: 0,
            n_blocks,
            key_step: 0,
        },
    );
    let validate_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), validate_params.as_entire_binding()),
        (
            "module_count_out".into(),
            module_count_out.as_entire_binding(),
        ),
        (
            "sorted_method_key_order".into(),
            method_key_to_fn_token.as_entire_binding(),
        ),
        (
            "method_decl_impl_node".into(),
            method_decl_impl_node.as_entire_binding(),
        ),
        (
            "method_decl_receiver_ref_tag".into(),
            method_decl_receiver_ref_tag.as_entire_binding(),
        ),
        (
            "method_decl_receiver_ref_payload".into(),
            method_decl_receiver_ref_payload.as_entire_binding(),
        ),
        (
            "method_decl_module_id".into(),
            method_decl_module_id.as_entire_binding(),
        ),
        (
            "method_decl_name_token".into(),
            method_decl_name_token.as_entire_binding(),
        ),
        (
            "method_decl_name_id".into(),
            method_decl_name_id.as_entire_binding(),
        ),
        (
            "method_decl_visibility".into(),
            method_decl_visibility.as_entire_binding(),
        ),
        (
            "module_type_path_type".into(),
            module_type_path_type.as_entire_binding(),
        ),
        (
            "type_instance_decl_token".into(),
            type_instance_decl_token.as_entire_binding(),
        ),
        (
            "method_key_status".into(),
            method_key_status.as_entire_binding(),
        ),
        (
            "method_key_duplicate_of".into(),
            method_key_duplicate_of.as_entire_binding(),
        ),
        ("status".into(), status.as_entire_binding()),
    ]);
    let validate_keys = bind_group::create_bind_group_from_reflection(
        device,
        Some(&format!("{label}.validate_keys")),
        &validate_pass.bind_group_layouts[0],
        &validate_pass.reflection,
        0,
        &validate_resources,
    )?;
    drop(validate_resources);
    key_radix_steps.push(ModuleKeyRadixStep {
        _params: validate_params,
    });

    Ok(MethodKeyBindGroups {
        _key_radix_steps: key_radix_steps,
        seed_key_order,
        sort_key_histogram,
        sort_key_bucket_prefix,
        sort_key_bucket_bases,
        sort_key_scatter,
        validate_keys,
    })
}

pub(super) fn create_fn_context_bind_groups(
    device: &wgpu::Device,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    let clear_pass = type_check_fn_context_clear_pass(device)?;
    let mark_pass = type_check_fn_context_mark_pass(device)?;
    let local_pass = type_check_fn_context_local_pass(device)?;
    let scan_pass = type_check_fn_context_scan_pass(device)?;
    let apply_pass = type_check_fn_context_apply_pass(device)?;
    create_fn_context_bind_groups_from_passes(
        device,
        &clear_pass,
        &mark_pass,
        &local_pass,
        &scan_pass,
        &apply_pass,
        params,
        scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        enclosing_fn,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_fn_context_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    create_fn_context_bind_groups_from_passes(
        device,
        &passes.fn_context_clear,
        &passes.fn_context_mark,
        &passes.fn_context_local,
        &passes.fn_context_scan,
        &passes.fn_context_apply,
        params,
        scan_steps,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        enclosing_fn,
        enclosing_fn_end,
        fn_event_value,
        fn_event_end,
        fn_event_index,
        fn_event_inblock,
        fn_block_sum,
        fn_prefix_a,
        fn_prefix_b,
        fn_block_prefix,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_fn_context_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    scan_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<FnContextParams>,
    scan_steps: &[FnContextScanStep],
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    enclosing_fn: &wgpu::Buffer,
    enclosing_fn_end: &wgpu::Buffer,
    fn_event_value: &wgpu::Buffer,
    fn_event_end: &wgpu::Buffer,
    fn_event_index: &wgpu::Buffer,
    fn_event_inblock: &wgpu::Buffer,
    fn_block_sum: &wgpu::Buffer,
    fn_prefix_a: &wgpu::Buffer,
    fn_prefix_b: &wgpu::Buffer,
    fn_block_prefix: &wgpu::Buffer,
) -> Result<FnContextBindGroups> {
    let clear_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("enclosing_fn".into(), enclosing_fn.as_entire_binding()),
        (
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        ),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), fn_block_sum.as_entire_binding()),
        ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
    ]);
    let clear = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_01_clear"),
        &clear_pass.bind_group_layouts[0],
        &clear_pass.reflection,
        0,
        &clear_resources,
    )?;

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
    ]);
    let mark = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_02_mark"),
        &mark_pass.bind_group_layouts[0],
        &mark_pass.reflection,
        0,
        &mark_resources,
    )?;

    let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("fn_event_index".into(), fn_event_index.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), fn_block_sum.as_entire_binding()),
    ]);
    let local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_03_local"),
        &local_pass.bind_group_layouts[0],
        &local_pass.reflection,
        0,
        &local_resources,
    )?;

    let mut scan = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            fn_prefix_a
        } else {
            fn_prefix_b
        };
        let prefix_out = if step.write_to_a {
            fn_prefix_a
        } else {
            fn_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("block_sum".into(), fn_block_sum.as_entire_binding()),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
        ]);
        scan.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_fn_context_04_scan_blocks"),
            &scan_pass.bind_group_layouts[0],
            &scan_pass.reflection,
            0,
            &scan_resources,
        )?);
    }

    let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("fn_event_value".into(), fn_event_value.as_entire_binding()),
        ("fn_event_end".into(), fn_event_end.as_entire_binding()),
        (
            "fn_event_inblock".into(),
            fn_event_inblock.as_entire_binding(),
        ),
        ("block_prefix".into(), fn_block_prefix.as_entire_binding()),
        ("enclosing_fn".into(), enclosing_fn.as_entire_binding()),
        (
            "enclosing_fn_end".into(),
            enclosing_fn_end.as_entire_binding(),
        ),
    ]);
    let apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_fn_context_05_apply"),
        &apply_pass.bind_group_layouts[0],
        &apply_pass.reflection,
        0,
        &apply_resources,
    )?;

    Ok(FnContextBindGroups {
        clear,
        mark,
        local,
        scan,
        apply,
    })
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_loop_depth_bind_groups(
    device: &wgpu::Device,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    let clear_pass = loop_depth_01_clear_pass(device)?;
    let mark_pass = loop_depth_02_mark_pass(device)?;
    let local_pass = loop_depth_03_local_pass(device)?;
    let scan_pass = loop_depth_04_scan_pass(device)?;
    let apply_pass = loop_depth_05_apply_pass(device)?;
    create_loop_depth_bind_groups_from_passes(
        device,
        &clear_pass,
        &mark_pass,
        &local_pass,
        &scan_pass,
        &apply_pass,
        params,
        scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        loop_delta,
        loop_depth_inblock,
        loop_block_sum,
        loop_prefix_a,
        loop_prefix_b,
        loop_block_prefix,
        loop_depth,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_loop_depth_bind_groups_with_passes(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    create_loop_depth_bind_groups_from_passes(
        device,
        &passes.loop_depth_clear,
        &passes.loop_depth_mark,
        &passes.loop_depth_local,
        &passes.loop_depth_scan,
        &passes.loop_depth_apply,
        params,
        scan_steps,
        token_buf,
        token_count_buf,
        hir_kind_buf,
        hir_token_pos_buf,
        hir_token_end_buf,
        hir_status_buf,
        loop_delta,
        loop_depth_inblock,
        loop_block_sum,
        loop_prefix_a,
        loop_prefix_b,
        loop_block_prefix,
        loop_depth,
    )
}

#[allow(clippy::too_many_arguments)]
pub(super) fn create_loop_depth_bind_groups_from_passes(
    device: &wgpu::Device,
    clear_pass: &PassData,
    mark_pass: &PassData,
    local_pass: &PassData,
    scan_pass: &PassData,
    apply_pass: &PassData,
    params: &LaniusBuffer<LoopDepthParams>,
    scan_steps: &[LoopDepthScanStep],
    token_buf: &wgpu::Buffer,
    token_count_buf: &wgpu::Buffer,
    hir_kind_buf: &wgpu::Buffer,
    hir_token_pos_buf: &wgpu::Buffer,
    hir_token_end_buf: &wgpu::Buffer,
    hir_status_buf: &wgpu::Buffer,
    loop_delta: &wgpu::Buffer,
    loop_depth_inblock: &wgpu::Buffer,
    loop_block_sum: &wgpu::Buffer,
    loop_prefix_a: &wgpu::Buffer,
    loop_prefix_b: &wgpu::Buffer,
    loop_block_prefix: &wgpu::Buffer,
    loop_depth: &wgpu::Buffer,
) -> Result<LoopDepthBindGroups> {
    let clear_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
    ]);
    let clear = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_01_clear"),
        &clear_pass.bind_group_layouts[0],
        &clear_pass.reflection,
        0,
        &clear_resources,
    )?;

    let mark_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("hir_kind".into(), hir_kind_buf.as_entire_binding()),
        (
            "hir_token_pos".into(),
            hir_token_pos_buf.as_entire_binding(),
        ),
        (
            "hir_token_end".into(),
            hir_token_end_buf.as_entire_binding(),
        ),
        ("hir_status".into(), hir_status_buf.as_entire_binding()),
        ("token_words".into(), token_buf.as_entire_binding()),
        ("token_count".into(), token_count_buf.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
    ]);
    let mark = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_02_mark"),
        &mark_pass.bind_group_layouts[0],
        &mark_pass.reflection,
        0,
        &mark_resources,
    )?;

    let local_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        ("loop_delta".into(), loop_delta.as_entire_binding()),
        (
            "loop_depth_inblock".into(),
            loop_depth_inblock.as_entire_binding(),
        ),
        ("block_sum".into(), loop_block_sum.as_entire_binding()),
    ]);
    let local = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_03_local"),
        &local_pass.bind_group_layouts[0],
        &local_pass.reflection,
        0,
        &local_resources,
    )?;

    let mut scan = Vec::with_capacity(scan_steps.len());
    for step in scan_steps {
        let prefix_in = if step.read_from_a {
            loop_prefix_a
        } else {
            loop_prefix_b
        };
        let prefix_out = if step.write_to_a {
            loop_prefix_a
        } else {
            loop_prefix_b
        };
        let scan_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
            ("gParams".into(), step.params.as_entire_binding()),
            ("block_sum".into(), loop_block_sum.as_entire_binding()),
            ("prefix_in".into(), prefix_in.as_entire_binding()),
            ("prefix_out".into(), prefix_out.as_entire_binding()),
            ("block_prefix".into(), loop_block_prefix.as_entire_binding()),
        ]);
        scan.push(bind_group::create_bind_group_from_reflection(
            device,
            Some("type_check_loop_depth_04_scan_blocks"),
            &scan_pass.bind_group_layouts[0],
            &scan_pass.reflection,
            0,
            &scan_resources,
        )?);
    }

    let apply_resources: HashMap<String, wgpu::BindingResource<'_>> = HashMap::from([
        ("gParams".into(), params.as_entire_binding()),
        (
            "loop_depth_inblock".into(),
            loop_depth_inblock.as_entire_binding(),
        ),
        ("block_prefix".into(), loop_block_prefix.as_entire_binding()),
        ("loop_depth".into(), loop_depth.as_entire_binding()),
    ]);
    let apply = bind_group::create_bind_group_from_reflection(
        device,
        Some("type_check_loop_depth_05_apply"),
        &apply_pass.bind_group_layouts[0],
        &apply_pass.reflection,
        0,
        &apply_resources,
    )?;

    Ok(LoopDepthBindGroups {
        clear,
        mark,
        local,
        scan,
        apply,
    })
}

pub(super) fn make_loop_depth_scan_steps(
    device: &wgpu::Device,
    base: LoopDepthParams,
) -> Vec<LoopDepthScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(
        base.n_blocks,
        crate::gpu::scan::ScanFinalize::Always(base.n_blocks),
    )
    .into_iter()
    .map(|plan| {
        let label = if plan.scan_step == 0 {
            "type_check.loop_depth.scan.params.init"
        } else if plan.scan_step == base.n_blocks {
            "type_check.loop_depth.scan.params.finalize"
        } else {
            "type_check.loop_depth.scan.params.step"
        };
        LoopDepthScanStep {
            params: uniform_from_val(
                device,
                label,
                &LoopDepthParams {
                    scan_step: plan.scan_step,
                    ..base
                },
            ),
            read_from_a: plan.read_from_a,
            write_to_a: plan.write_to_a,
        }
    })
    .collect()
}

pub(super) fn make_name_scan_steps(
    device: &wgpu::Device,
    base: NameScanParams,
) -> Vec<NameScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(base.n_blocks, crate::gpu::scan::ScanFinalize::None)
        .into_iter()
        .map(|plan| {
            let label = if plan.scan_step == 0 {
                "type_check.names.scan.params.init"
            } else {
                "type_check.names.scan.params.step"
            };
            NameScanStep {
                params: uniform_from_val(
                    device,
                    label,
                    &NameScanParams {
                        scan_step: plan.scan_step,
                        ..base
                    },
                ),
                read_from_a: plan.read_from_a,
                write_to_a: plan.write_to_a,
            }
        })
        .collect()
}

pub(super) fn make_fn_context_scan_steps(
    device: &wgpu::Device,
    base: FnContextParams,
) -> Vec<FnContextScanStep> {
    crate::gpu::scan::ping_pong_scan_steps(
        base.n_blocks,
        crate::gpu::scan::ScanFinalize::Always(base.n_blocks),
    )
    .into_iter()
    .map(|plan| {
        let label = if plan.scan_step == 0 {
            "type_check.fn_context.scan.params.init"
        } else if plan.scan_step == base.n_blocks {
            "type_check.fn_context.scan.params.finalize"
        } else {
            "type_check.fn_context.scan.params.step"
        };
        FnContextScanStep {
            params: uniform_from_val(
                device,
                label,
                &FnContextParams {
                    scan_step: plan.scan_step,
                    ..base
                },
            ),
            read_from_a: plan.read_from_a,
            write_to_a: plan.write_to_a,
        }
    })
    .collect()
}
