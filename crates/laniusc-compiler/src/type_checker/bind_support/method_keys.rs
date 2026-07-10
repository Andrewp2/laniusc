use super::super::*;

/// Builds method-key bind groups from the typed method-key input model.
pub(in crate::type_checker) fn create_method_key_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    input: MethodKeyInput<'_>,
) -> Result<MethodKeyBindGroups> {
    create_method_key_bind_groups_from_passes(
        device,
        input.label,
        &passes.methods_seed_key_order,
        &passes.methods_sort_keys_small,
        &passes.methods_sort_keys,
        &passes.names_radix_bucket_prefix,
        &passes.names_radix_bucket_bases,
        &passes.methods_sort_keys_scatter,
        &passes.methods_validate_keys,
        input.cap,
        input.blocks,
        input.token_count,
        input.module_count,
        input.decl.impl_node,
        input.decl.recv_tag,
        input.decl.recv_payload,
        input.decl.module_id,
        input.decl.name_token,
        input.decl.name_id,
        input.decl.visibility,
        input.module_type_path_type,
        input.type_instance_decl_token,
        input.type_instance_arg_start,
        input.type_instance_arg_count,
        input.type_instance_arg_ref_tag,
        input.type_instance_arg_ref_payload,
        input.type_instance_arg_hash,
        input.type_instance_arg_row_start,
        input.type_instance_arg_row_count_out,
        input.type_instance_arg_row_ref_tag,
        input.type_instance_arg_row_ref_payload,
        input.keys.to_fn_token,
        input.keys.order_tmp,
        input.keys.status,
        input.keys.duplicate_of,
        input.radix.histogram,
        input.radix.bucket_prefix,
        input.radix.bucket_total,
        input.radix.bucket_base,
        input.status,
    )
}

/// Builds method-key bind groups from explicit pass handles and relation buffers.
#[allow(clippy::too_many_arguments)]
pub(in crate::type_checker) fn create_method_key_bind_groups_from_passes(
    device: &wgpu::Device,
    label: &'static str,
    seed_pass: &PassData,
    small_sort_pass: &PassData,
    sort_pass: &PassData,
    bucket_prefix_pass: &PassData,
    bucket_bases_pass: &PassData,
    scatter_pass: &PassData,
    validate_pass: &PassData,
    method_capacity: u32,
    n_blocks: u32,
    token_count: &wgpu::Buffer,
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
    type_instance_arg_start: &wgpu::Buffer,
    type_instance_arg_count: &wgpu::Buffer,
    type_instance_arg_ref_tag: &wgpu::Buffer,
    type_instance_arg_ref_payload: &wgpu::Buffer,
    type_instance_arg_hash: &wgpu::Buffer,
    type_instance_arg_row_start: &wgpu::Buffer,
    type_instance_arg_row_count_out: &wgpu::Buffer,
    type_instance_arg_row_ref_tag: &wgpu::Buffer,
    type_instance_arg_row_ref_payload: &wgpu::Buffer,
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
    let seed_key_order = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("{label}.seed_key_order")),
        seed_pass,
        0,
        &[
            ("gParams", seed_params.as_entire_binding()),
            ("token_count", token_count.as_entire_binding()),
            (
                "method_key_to_fn_token",
                method_key_to_fn_token.as_entire_binding(),
            ),
            ("method_key_status", method_key_status.as_entire_binding()),
            (
                "method_key_duplicate_of",
                method_key_duplicate_of.as_entire_binding(),
            ),
        ],
    )?;

    let sort_key_small = if method_capacity <= METHOD_KEY_SMALL_SORT_CAPACITY {
        Some(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.sort_key_small")),
            small_sort_pass,
            0,
            &[
                ("gParams", seed_params.as_entire_binding()),
                ("token_count", token_count.as_entire_binding()),
                (
                    "method_decl_impl_node",
                    method_decl_impl_node.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_tag",
                    method_decl_receiver_ref_tag.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_payload",
                    method_decl_receiver_ref_payload.as_entire_binding(),
                ),
                (
                    "method_decl_module_id",
                    method_decl_module_id.as_entire_binding(),
                ),
                (
                    "method_decl_name_id",
                    method_decl_name_id.as_entire_binding(),
                ),
                (
                    "module_type_path_type",
                    module_type_path_type.as_entire_binding(),
                ),
                (
                    "type_instance_decl_token",
                    type_instance_decl_token.as_entire_binding(),
                ),
                (
                    "type_instance_arg_count",
                    type_instance_arg_count.as_entire_binding(),
                ),
                (
                    "type_instance_arg_hash",
                    type_instance_arg_hash.as_entire_binding(),
                ),
                (
                    "method_key_order",
                    method_key_to_fn_token.as_entire_binding(),
                ),
            ],
        )?)
    } else {
        None
    };

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

        sort_key_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.sort_keys_histogram")),
            sort_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("token_count", token_count.as_entire_binding()),
                (
                    "method_decl_impl_node",
                    method_decl_impl_node.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_tag",
                    method_decl_receiver_ref_tag.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_payload",
                    method_decl_receiver_ref_payload.as_entire_binding(),
                ),
                (
                    "method_decl_module_id",
                    method_decl_module_id.as_entire_binding(),
                ),
                (
                    "method_decl_name_id",
                    method_decl_name_id.as_entire_binding(),
                ),
                (
                    "module_type_path_type",
                    module_type_path_type.as_entire_binding(),
                ),
                (
                    "type_instance_decl_token",
                    type_instance_decl_token.as_entire_binding(),
                ),
                (
                    "type_instance_arg_start",
                    type_instance_arg_start.as_entire_binding(),
                ),
                (
                    "type_instance_arg_count",
                    type_instance_arg_count.as_entire_binding(),
                ),
                (
                    "type_instance_arg_ref_tag",
                    type_instance_arg_ref_tag.as_entire_binding(),
                ),
                (
                    "type_instance_arg_ref_payload",
                    type_instance_arg_ref_payload.as_entire_binding(),
                ),
                (
                    "type_instance_arg_hash",
                    type_instance_arg_hash.as_entire_binding(),
                ),
                ("method_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_block_histogram",
                    method_key_radix_block_histogram.as_entire_binding(),
                ),
            ],
        )?);

        sort_key_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.sort_keys_bucket_prefix")),
            bucket_prefix_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_count_in", token_count.as_entire_binding()),
                (
                    "radix_block_histogram",
                    method_key_radix_block_histogram.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    method_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                (
                    "radix_bucket_total",
                    method_key_radix_bucket_total.as_entire_binding(),
                ),
            ],
        )?);

        sort_key_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.sort_keys_bucket_bases")),
            bucket_bases_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    method_key_radix_bucket_total.as_entire_binding(),
                ),
                (
                    "radix_bucket_base",
                    method_key_radix_bucket_base.as_entire_binding(),
                ),
            ],
        )?);

        sort_key_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some(&format!("{label}.sort_keys_scatter")),
            scatter_pass,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("token_count", token_count.as_entire_binding()),
                (
                    "method_decl_impl_node",
                    method_decl_impl_node.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_tag",
                    method_decl_receiver_ref_tag.as_entire_binding(),
                ),
                (
                    "method_decl_receiver_ref_payload",
                    method_decl_receiver_ref_payload.as_entire_binding(),
                ),
                (
                    "method_decl_module_id",
                    method_decl_module_id.as_entire_binding(),
                ),
                (
                    "method_decl_name_id",
                    method_decl_name_id.as_entire_binding(),
                ),
                (
                    "module_type_path_type",
                    module_type_path_type.as_entire_binding(),
                ),
                (
                    "type_instance_decl_token",
                    type_instance_decl_token.as_entire_binding(),
                ),
                (
                    "type_instance_arg_start",
                    type_instance_arg_start.as_entire_binding(),
                ),
                (
                    "type_instance_arg_count",
                    type_instance_arg_count.as_entire_binding(),
                ),
                (
                    "type_instance_arg_ref_tag",
                    type_instance_arg_ref_tag.as_entire_binding(),
                ),
                (
                    "type_instance_arg_ref_payload",
                    type_instance_arg_ref_payload.as_entire_binding(),
                ),
                (
                    "type_instance_arg_hash",
                    type_instance_arg_hash.as_entire_binding(),
                ),
                ("method_key_order_in", read_order.as_entire_binding()),
                (
                    "radix_bucket_base",
                    method_key_radix_bucket_base.as_entire_binding(),
                ),
                (
                    "radix_block_bucket_prefix",
                    method_key_radix_block_bucket_prefix.as_entire_binding(),
                ),
                ("method_key_order_out", write_order.as_entire_binding()),
            ],
        )?);
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
    let validate_keys = bind_group::create_bind_group_from_bindings(
        device,
        Some(&format!("{label}.validate_keys")),
        validate_pass,
        0,
        &[
            ("gParams", validate_params.as_entire_binding()),
            ("token_count", token_count.as_entire_binding()),
            ("module_count_out", module_count_out.as_entire_binding()),
            (
                "sorted_method_key_order",
                method_key_to_fn_token.as_entire_binding(),
            ),
            (
                "method_decl_impl_node",
                method_decl_impl_node.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_tag",
                method_decl_receiver_ref_tag.as_entire_binding(),
            ),
            (
                "method_decl_receiver_ref_payload",
                method_decl_receiver_ref_payload.as_entire_binding(),
            ),
            (
                "method_decl_module_id",
                method_decl_module_id.as_entire_binding(),
            ),
            (
                "method_decl_name_token",
                method_decl_name_token.as_entire_binding(),
            ),
            (
                "method_decl_name_id",
                method_decl_name_id.as_entire_binding(),
            ),
            (
                "method_decl_visibility",
                method_decl_visibility.as_entire_binding(),
            ),
            (
                "module_type_path_type",
                module_type_path_type.as_entire_binding(),
            ),
            (
                "type_instance_decl_token",
                type_instance_decl_token.as_entire_binding(),
            ),
            (
                "type_instance_arg_start",
                type_instance_arg_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_count",
                type_instance_arg_count.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_tag",
                type_instance_arg_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_ref_payload",
                type_instance_arg_ref_payload.as_entire_binding(),
            ),
            (
                "type_instance_arg_hash",
                type_instance_arg_hash.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_start",
                type_instance_arg_row_start.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_count_out",
                type_instance_arg_row_count_out.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_tag",
                type_instance_arg_row_ref_tag.as_entire_binding(),
            ),
            (
                "type_instance_arg_row_ref_payload",
                type_instance_arg_row_ref_payload.as_entire_binding(),
            ),
            ("method_key_status", method_key_status.as_entire_binding()),
            (
                "method_key_duplicate_of",
                method_key_duplicate_of.as_entire_binding(),
            ),
            ("status", status.as_entire_binding()),
        ],
    )?;
    key_radix_steps.push(ModuleKeyRadixStep {
        _params: validate_params,
    });

    Ok(MethodKeyBindGroups {
        _key_radix_steps: key_radix_steps,
        seed_key_order,
        sort_key_small,
        sort_key_histogram,
        sort_key_bucket_prefix,
        sort_key_bucket_bases,
        sort_key_scatter,
        validate_keys,
    })
}
