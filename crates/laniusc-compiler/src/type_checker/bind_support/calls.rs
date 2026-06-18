use super::{
    super::*,
    common::reflected_bind_group_from_resources,
    scan::create_counted_u32_scan_bind_groups_with_passes,
};

const GENERIC_CLAIM_KEY_FIELD_COUNT: u32 = 3;
const GENERIC_CLAIM_KEY_MAX_RADIX_STEPS: u32 = 12;

fn generic_claim_radix_bytes(token_capacity: u32, claim_capacity: u32) -> u32 {
    let max_key = token_capacity
        .max(claim_capacity)
        .saturating_add(8192)
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

fn generic_claim_radix_steps(token_capacity: u32, claim_capacity: u32) -> u32 {
    let steps =
        generic_claim_radix_bytes(token_capacity, claim_capacity) * GENERIC_CLAIM_KEY_FIELD_COUNT;
    let even_steps = if steps % 2 == 0 { steps } else { steps + 1 };
    even_steps.min(GENERIC_CLAIM_KEY_MAX_RADIX_STEPS)
}

fn even_list_match_steps(capacity: u32) -> u32 {
    let steps = if capacity <= 1 {
        0
    } else {
        u32::BITS - (capacity - 1).leading_zeros()
    };

    if steps % 2 == 0 { steps } else { steps + 1 }
}

#[cfg(test)]
mod tests {
    use super::even_list_match_steps;

    const INVALID: u32 = u32::MAX;

    fn next_row(row: usize, capacity: usize) -> u32 {
        let next = row + 1;
        if next < capacity {
            next as u32
        } else {
            INVALID
        }
    }

    fn propagate_linear_list_match(capacity: usize) -> Vec<u32> {
        let steps = even_list_match_steps(capacity as u32);
        let mut friend = vec![INVALID; capacity];
        let mut arg_jump = (0..capacity)
            .map(|row| next_row(row, capacity))
            .collect::<Vec<_>>();
        let mut param_jump = arg_jump.clone();
        if capacity > 0 {
            friend[0] = 0;
        }

        for _ in 0..steps {
            let mut next_friend = friend.clone();
            let mut next_arg_jump = vec![INVALID; capacity];
            let mut next_param_jump = vec![INVALID; capacity];

            for row in 0..capacity {
                let next_arg = arg_jump[row];
                if next_arg != INVALID {
                    next_arg_jump[row] = arg_jump[next_arg as usize];
                }

                let matched_param = friend[row];
                if matched_param != INVALID && next_arg != INVALID {
                    let next_param = param_jump[matched_param as usize];
                    if next_param != INVALID {
                        next_friend[next_arg as usize] = next_param;
                    }
                }

                let next_param = param_jump[row];
                if next_param != INVALID {
                    next_param_jump[row] = param_jump[next_param as usize];
                }
            }

            friend = next_friend;
            arg_jump = next_arg_jump;
            param_jump = next_param_jump;
        }

        friend
    }

    #[test]
    fn list_match_steps_cover_65k_rows_and_land_in_main_buffer() {
        for capacity in [0u32, 1, 2, 3, 4, 5, 257, 65_535, 65_536, 65_537] {
            let steps = even_list_match_steps(capacity);
            assert_eq!(
                steps % 2,
                0,
                "capacity {capacity} should finish in the main relation buffer"
            );

            if capacity <= 1 {
                assert_eq!(steps, 0);
                continue;
            }

            let covered_distance = 1u128 << steps;
            assert!(
                covered_distance >= u128::from(capacity - 1),
                "capacity {capacity} should cover every row in one linked list"
            );
        }

        assert_eq!(
            even_list_match_steps(65_535),
            16,
            "65,535 rows should require 16 logarithmic propagation dispatches"
        );
    }

    #[test]
    fn list_match_propagates_65k_linear_argument_parameter_rows() {
        let matched = propagate_linear_list_match(65_535);
        assert_eq!(
            matched.len(),
            65_535,
            "test fixture should model the requested row limit"
        );

        for (arg_row, param_row) in matched.iter().copied().enumerate() {
            assert_eq!(
                param_row, arg_row as u32,
                "argument row {arg_row} should match parameter row {arg_row}"
            );
        }
    }
}

/// Scan wiring for compact call-row families such as params, args, and claims.
pub(in crate::type_checker) struct CompactCallRowScanInput<'a> {
    pub(in crate::type_checker) scan_steps: &'a [NameScanStep],
    pub(in crate::type_checker) scan_count: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_input: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_output_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_total: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_local_prefix: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_block_sum: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_prefix_a: &'a wgpu::Buffer,
    pub(in crate::type_checker) scan_prefix_b: &'a wgpu::Buffer,
    pub(in crate::type_checker) n_blocks: u32,
}

/// Builds bind groups for call collection, argument matching, and claim validation.
pub(in crate::type_checker) fn create_call_bind_groups(
    device: &wgpu::Device,
    passes: &TypeCheckPasses,
    resources: &HashMap<String, wgpu::BindingResource<'_>>,
    token_capacity: u32,
    call_arg_row_capacity: u32,
    call_generic_claim_radix_dispatch_args: &LaniusBuffer<u32>,
    call_const_claim_radix_dispatch_args: &LaniusBuffer<u32>,
    call_required_generic_dispatch_args: &LaniusBuffer<u32>,
    compact_param_scan: CompactCallRowScanInput<'_>,
    compact_arg_scan: CompactCallRowScanInput<'_>,
    generic_claim_scan: CompactCallRowScanInput<'_>,
    required_generic_scan: CompactCallRowScanInput<'_>,
) -> Result<CallBindGroups> {
    let claim_capacity = token_capacity
        .max(call_arg_row_capacity)
        .saturating_mul(GENERIC_CLAIM_CAPACITY_MULTIPLIER)
        .max(call_arg_row_capacity)
        .max(1);
    let claim_n_blocks = claim_capacity.div_ceil(256).max(1);
    let claim_radix_bytes = generic_claim_radix_bytes(token_capacity, claim_capacity);
    let claim_radix_steps = generic_claim_radix_steps(token_capacity, claim_capacity);
    let required_generic_dispatch_params = uniform_from_val(
        device,
        "type_check.calls.required_generic_dispatch.params",
        &CountDispatchParams {
            capacity: u32::MAX,
            multiplier: 1,
            reserved0: 0,
            reserved1: 0,
        },
    );
    let claim_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.calls.generic_claim_radix.dispatch.params",
        &ModuleKeyRadixParams {
            module_capacity: claim_capacity,
            reserved: claim_radix_bytes,
            n_blocks: claim_n_blocks,
            key_step: 0,
        },
    );
    let generic_claim_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.calls.generic_claim_radix_dispatch"),
        &passes.names_radix_dispatch_args,
        0,
        &[
            ("gParams", claim_radix_dispatch_params.as_entire_binding()),
            (
                "name_count_in",
                resources["call_generic_claim_count_out"].clone(),
            ),
            (
                "radix_dispatch_args",
                resources["call_generic_claim_radix_dispatch_args"].clone(),
            ),
        ],
    )?;
    let required_generic_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.calls.required_generic_dispatch"),
        &passes.count_dispatch_args,
        0,
        &[
            (
                "gParams",
                required_generic_dispatch_params.as_entire_binding(),
            ),
            (
                "count_in",
                resources["call_required_generic_count_out"].clone(),
            ),
            (
                "dispatch_args",
                call_required_generic_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;

    let mut generic_claim_radix_step_params = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_generic_claim_histogram = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_generic_claim_bucket_prefix = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_generic_claim_bucket_bases = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_generic_claim_scatter = Vec::with_capacity(claim_radix_steps as usize);
    for key_step in 0..claim_radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.calls.generic_claim_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: claim_capacity,
                reserved: claim_radix_bytes,
                n_blocks: claim_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            resources["call_generic_claim_order"].clone()
        } else {
            resources["call_generic_claim_order_tmp"].clone()
        };
        let write_order = if key_step % 2 == 0 {
            resources["call_generic_claim_order_tmp"].clone()
        } else {
            resources["call_generic_claim_order"].clone()
        };

        sort_generic_claim_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_calls_03a2_sort_generic_claims"),
            &passes.calls_sort_generic_claims,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "call_generic_claim_count_out",
                    resources["call_generic_claim_count_out"].clone(),
                ),
                (
                    "call_generic_claim_callee",
                    resources["call_generic_claim_callee"].clone(),
                ),
                (
                    "call_generic_claim_slot",
                    resources["call_generic_claim_slot"].clone(),
                ),
                (
                    "call_generic_claim_type",
                    resources["call_generic_claim_type"].clone(),
                ),
                ("call_generic_claim_order_in", read_order.clone()),
                (
                    "radix_block_histogram",
                    resources["call_generic_claim_radix_block_histogram"].clone(),
                ),
            ],
        )?);

        sort_generic_claim_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.calls.generic_claim_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "name_count_in",
                    resources["call_generic_claim_count_out"].clone(),
                ),
                (
                    "radix_block_histogram",
                    resources["call_generic_claim_radix_block_histogram"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["call_generic_claim_radix_block_bucket_prefix"].clone(),
                ),
                (
                    "radix_bucket_total",
                    resources["call_generic_claim_radix_bucket_total"].clone(),
                ),
            ],
        )?);

        sort_generic_claim_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.calls.generic_claim_radix_bucket_bases"),
            &passes.names_radix_bucket_bases,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    resources["call_generic_claim_radix_bucket_total"].clone(),
                ),
                (
                    "radix_bucket_base",
                    resources["call_generic_claim_radix_bucket_base"].clone(),
                ),
            ],
        )?);

        sort_generic_claim_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_calls_03a3_sort_generic_claims_scatter"),
            &passes.calls_sort_generic_claims_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "call_generic_claim_count_out",
                    resources["call_generic_claim_count_out"].clone(),
                ),
                (
                    "call_generic_claim_callee",
                    resources["call_generic_claim_callee"].clone(),
                ),
                (
                    "call_generic_claim_slot",
                    resources["call_generic_claim_slot"].clone(),
                ),
                (
                    "call_generic_claim_type",
                    resources["call_generic_claim_type"].clone(),
                ),
                ("call_generic_claim_order_in", read_order),
                (
                    "radix_bucket_base",
                    resources["call_generic_claim_radix_bucket_base"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["call_generic_claim_radix_block_bucket_prefix"].clone(),
                ),
                ("call_generic_claim_order_out", write_order),
            ],
        )?);

        generic_claim_radix_step_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let const_claim_radix_dispatch_params = uniform_from_val(
        device,
        "type_check.calls.const_claim_radix.dispatch.params",
        &ModuleKeyRadixParams {
            module_capacity: claim_capacity,
            reserved: claim_radix_bytes,
            n_blocks: claim_n_blocks,
            key_step: 0,
        },
    );
    let const_claim_radix_dispatch = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check.calls.const_claim_radix_dispatch"),
        &passes.names_radix_dispatch_args,
        0,
        &[
            (
                "gParams",
                const_claim_radix_dispatch_params.as_entire_binding(),
            ),
            ("name_count_in", resources["call_arg_row_count_out"].clone()),
            (
                "radix_dispatch_args",
                resources["call_const_claim_radix_dispatch_args"].clone(),
            ),
        ],
    )?;

    let mut const_claim_radix_step_params = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_const_claim_histogram = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_const_claim_bucket_prefix = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_const_claim_bucket_bases = Vec::with_capacity(claim_radix_steps as usize);
    let mut sort_const_claim_scatter = Vec::with_capacity(claim_radix_steps as usize);
    for key_step in 0..claim_radix_steps {
        let step_params = uniform_from_val(
            device,
            &format!("type_check.calls.const_claim_radix.params.{key_step}"),
            &ModuleKeyRadixParams {
                module_capacity: claim_capacity,
                reserved: claim_radix_bytes,
                n_blocks: claim_n_blocks,
                key_step,
            },
        );
        let read_order = if key_step % 2 == 0 {
            resources["call_const_claim_order"].clone()
        } else {
            resources["call_const_claim_order_tmp"].clone()
        };
        let write_order = if key_step % 2 == 0 {
            resources["call_const_claim_order_tmp"].clone()
        } else {
            resources["call_const_claim_order"].clone()
        };

        sort_const_claim_histogram.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_calls_03a2_sort_const_claims"),
            &passes.calls_sort_generic_claims,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "call_generic_claim_count_out",
                    resources["call_arg_row_count_out"].clone(),
                ),
                (
                    "call_generic_claim_callee",
                    resources["call_const_claim_callee"].clone(),
                ),
                (
                    "call_generic_claim_slot",
                    resources["call_const_claim_slot"].clone(),
                ),
                (
                    "call_generic_claim_type",
                    resources["call_const_claim_len"].clone(),
                ),
                ("call_generic_claim_order_in", read_order.clone()),
                (
                    "radix_block_histogram",
                    resources["call_const_claim_radix_block_histogram"].clone(),
                ),
            ],
        )?);

        sort_const_claim_bucket_prefix.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.calls.const_claim_radix_bucket_prefix"),
            &passes.names_radix_bucket_prefix,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                ("name_count_in", resources["call_arg_row_count_out"].clone()),
                (
                    "radix_block_histogram",
                    resources["call_const_claim_radix_block_histogram"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["call_const_claim_radix_block_bucket_prefix"].clone(),
                ),
                (
                    "radix_bucket_total",
                    resources["call_const_claim_radix_bucket_total"].clone(),
                ),
            ],
        )?);

        sort_const_claim_bucket_bases.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check.calls.const_claim_radix_bucket_bases"),
            &passes.names_radix_bucket_bases,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "radix_bucket_total",
                    resources["call_const_claim_radix_bucket_total"].clone(),
                ),
                (
                    "radix_bucket_base",
                    resources["call_const_claim_radix_bucket_base"].clone(),
                ),
            ],
        )?);

        sort_const_claim_scatter.push(bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_calls_03a3_sort_const_claims_scatter"),
            &passes.calls_sort_generic_claims_scatter,
            0,
            &[
                ("gParams", step_params.as_entire_binding()),
                (
                    "call_generic_claim_count_out",
                    resources["call_arg_row_count_out"].clone(),
                ),
                (
                    "call_generic_claim_callee",
                    resources["call_const_claim_callee"].clone(),
                ),
                (
                    "call_generic_claim_slot",
                    resources["call_const_claim_slot"].clone(),
                ),
                (
                    "call_generic_claim_type",
                    resources["call_const_claim_len"].clone(),
                ),
                ("call_generic_claim_order_in", read_order),
                (
                    "radix_bucket_base",
                    resources["call_const_claim_radix_bucket_base"].clone(),
                ),
                (
                    "radix_block_bucket_prefix",
                    resources["call_const_claim_radix_block_bucket_prefix"].clone(),
                ),
                ("call_generic_claim_order_out", write_order),
            ],
        )?);

        const_claim_radix_step_params.push(ModuleKeyRadixStep {
            _params: step_params,
        });
    }

    let match_arg_param_steps = even_list_match_steps(call_arg_row_capacity);
    let match_arg_params_init = reflected_bind_group_from_resources(
        device,
        "type_check_resident_calls_match_arg_params_init",
        &passes.calls_match_arg_params_init,
        resources,
    )?;
    let match_arg_params_copy_main_to_tmp = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_calls_match_arg_params_copy_main_to_tmp"),
        &passes.calls_match_arg_params_copy,
        0,
        &[
            ("gParams", resources["gParams"].clone()),
            ("hir_status", resources["hir_status"].clone()),
            (
                "call_arg_row_count_out",
                resources["call_arg_row_count_out"].clone(),
            ),
            (
                "call_arg_param_row_in",
                resources["call_arg_param_row"].clone(),
            ),
            (
                "call_arg_param_row_out",
                resources["call_arg_param_row_tmp"].clone(),
            ),
        ],
    )?;
    let match_arg_params_copy_tmp_to_main = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_calls_match_arg_params_copy_tmp_to_main"),
        &passes.calls_match_arg_params_copy,
        0,
        &[
            ("gParams", resources["gParams"].clone()),
            ("hir_status", resources["hir_status"].clone()),
            (
                "call_arg_row_count_out",
                resources["call_arg_row_count_out"].clone(),
            ),
            (
                "call_arg_param_row_in",
                resources["call_arg_param_row_tmp"].clone(),
            ),
            (
                "call_arg_param_row_out",
                resources["call_arg_param_row"].clone(),
            ),
        ],
    )?;
    let match_arg_params_step_main_to_tmp = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_calls_match_arg_params_step_main_to_tmp"),
        &passes.calls_match_arg_params_step,
        0,
        &[
            ("gParams", resources["gParams"].clone()),
            ("hir_status", resources["hir_status"].clone()),
            (
                "call_arg_row_count_out",
                resources["call_arg_row_count_out"].clone(),
            ),
            (
                "call_param_row_count_out",
                resources["call_param_row_count_out"].clone(),
            ),
            (
                "call_arg_param_row_in",
                resources["call_arg_param_row"].clone(),
            ),
            (
                "call_arg_match_jump_in",
                resources["call_arg_match_jump_a"].clone(),
            ),
            (
                "call_param_match_jump_in",
                resources["call_param_match_jump_a"].clone(),
            ),
            (
                "call_arg_param_row_out",
                resources["call_arg_param_row_tmp"].clone(),
            ),
            (
                "call_arg_match_jump_out",
                resources["call_arg_match_jump_b"].clone(),
            ),
            (
                "call_param_match_jump_out",
                resources["call_param_match_jump_b"].clone(),
            ),
        ],
    )?;
    let match_arg_params_step_tmp_to_main = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_resident_calls_match_arg_params_step_tmp_to_main"),
        &passes.calls_match_arg_params_step,
        0,
        &[
            ("gParams", resources["gParams"].clone()),
            ("hir_status", resources["hir_status"].clone()),
            (
                "call_arg_row_count_out",
                resources["call_arg_row_count_out"].clone(),
            ),
            (
                "call_param_row_count_out",
                resources["call_param_row_count_out"].clone(),
            ),
            (
                "call_arg_param_row_in",
                resources["call_arg_param_row_tmp"].clone(),
            ),
            (
                "call_arg_match_jump_in",
                resources["call_arg_match_jump_b"].clone(),
            ),
            (
                "call_param_match_jump_in",
                resources["call_param_match_jump_b"].clone(),
            ),
            (
                "call_arg_param_row_out",
                resources["call_arg_param_row"].clone(),
            ),
            (
                "call_arg_match_jump_out",
                resources["call_arg_match_jump_a"].clone(),
            ),
            (
                "call_param_match_jump_out",
                resources["call_param_match_jump_a"].clone(),
            ),
        ],
    )?;

    Ok(CallBindGroups {
        clear: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_clear",
            &passes.calls_clear,
            resources,
        )?,
        return_refs: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_return_refs",
            &passes.calls_return_refs,
            resources,
        )?,
        entrypoints: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_entrypoints",
            &passes.calls_entrypoints,
            resources,
        )?,
        functions: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_functions",
            &passes.calls_functions,
            resources,
        )?,
        param_types: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_param_types",
            &passes.calls_param_types,
            resources,
        )?,
        intrinsics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_intrinsics",
            &passes.calls_intrinsics,
            resources,
        )?,
        clear_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_clear_hir_call_args",
            &passes.calls_clear_hir_call_args,
            resources,
        )?,
        pack_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_pack_hir_call_args",
            &passes.calls_pack_hir_call_args,
            resources,
        )?,
        mark_compact_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_mark_compact_hir_call_args",
            &passes.calls_mark_compact_hir_call_args,
            resources,
        )?,
        compact_hir_call_arg_scan: create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.calls.compact_hir_call_arg_scan",
            compact_arg_scan.scan_steps,
            compact_arg_scan.scan_count,
            compact_arg_scan.scan_input,
            compact_arg_scan.scan_output_prefix,
            compact_arg_scan.scan_total,
            compact_arg_scan.scan_local_prefix,
            compact_arg_scan.scan_block_sum,
            compact_arg_scan.scan_prefix_a,
            compact_arg_scan.scan_prefix_b,
        )?,
        compact_hir_call_arg_scan_n_blocks: compact_arg_scan.n_blocks,
        scatter_compact_hir_call_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_scatter_compact_hir_call_args",
            &passes.calls_scatter_compact_hir_call_args,
            resources,
        )?,
        call_param_segment_scan: create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.calls.call_param_segment_scan",
            compact_param_scan.scan_steps,
            compact_param_scan.scan_count,
            compact_param_scan.scan_input,
            compact_param_scan.scan_output_prefix,
            compact_param_scan.scan_total,
            compact_param_scan.scan_local_prefix,
            compact_param_scan.scan_block_sum,
            compact_param_scan.scan_prefix_a,
            compact_param_scan.scan_prefix_b,
        )?,
        call_param_segment_scan_n_blocks: compact_param_scan.n_blocks,
        scatter_compact_hir_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_scatter_compact_hir_params",
            &passes.calls_scatter_compact_hir_params,
            resources,
        )?,
        resolve: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_resolve",
            &passes.calls_resolve,
            resources,
        )?,
        match_arg_params_init,
        match_arg_params_copy_main_to_tmp,
        match_arg_params_copy_tmp_to_main,
        match_arg_params_step_main_to_tmp,
        match_arg_params_step_tmp_to_main,
        match_arg_param_steps,
        collect_row_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_collect_row_args",
            &passes.calls_collect_row_args,
            resources,
        )?,
        generic_claim_scan: create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.calls.generic_claim_scan",
            generic_claim_scan.scan_steps,
            generic_claim_scan.scan_count,
            generic_claim_scan.scan_input,
            generic_claim_scan.scan_output_prefix,
            generic_claim_scan.scan_total,
            generic_claim_scan.scan_local_prefix,
            generic_claim_scan.scan_block_sum,
            generic_claim_scan.scan_prefix_a,
            generic_claim_scan.scan_prefix_b,
        )?,
        generic_claim_scan_n_blocks: generic_claim_scan.n_blocks,
        emit_generic_claims: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_emit_generic_claims",
            &passes.calls_emit_generic_claims,
            resources,
        )?,
        generic_claim_capacity: claim_capacity,
        generic_claim_radix_dispatch,
        generic_claim_radix_dispatch_args: call_generic_claim_radix_dispatch_args.clone(),
        _generic_claim_radix_steps: generic_claim_radix_step_params,
        sort_generic_claim_histogram,
        sort_generic_claim_bucket_prefix,
        sort_generic_claim_bucket_bases,
        sort_generic_claim_scatter,
        validate_generic_claims: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_validate_generic_claims",
            &passes.calls_validate_generic_claims,
            resources,
        )?,
        mark_required_generics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_mark_required_generics",
            &passes.calls_mark_required_generics,
            resources,
        )?,
        required_generic_scan: create_counted_u32_scan_bind_groups_with_passes(
            passes,
            device,
            "type_check.calls.required_generic_scan",
            required_generic_scan.scan_steps,
            required_generic_scan.scan_count,
            required_generic_scan.scan_input,
            required_generic_scan.scan_output_prefix,
            required_generic_scan.scan_total,
            required_generic_scan.scan_local_prefix,
            required_generic_scan.scan_block_sum,
            required_generic_scan.scan_prefix_a,
            required_generic_scan.scan_prefix_b,
        )?,
        required_generic_scan_n_blocks: required_generic_scan.n_blocks,
        required_generic_dispatch,
        required_generic_dispatch_args: call_required_generic_dispatch_args.clone(),
        _required_generic_dispatch_params: required_generic_dispatch_params,
        validate_required_generics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_validate_required_generics",
            &passes.calls_validate_required_generics,
            resources,
        )?,
        const_claim_radix_dispatch,
        const_claim_radix_dispatch_args: call_const_claim_radix_dispatch_args.clone(),
        _const_claim_radix_steps: const_claim_radix_step_params,
        sort_const_claim_histogram,
        sort_const_claim_bucket_prefix,
        sort_const_claim_bucket_bases,
        sort_const_claim_scatter,
        validate_const_claims: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_validate_const_claims",
            &passes.calls_validate_const_claims,
            resources,
        )?,
        apply_row_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_apply_row_args",
            &passes.calls_apply_row_args,
            resources,
        )?,
        infer_array_generics: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_infer_array_generics",
            &passes.calls_infer_array_generics,
            resources,
        )?,
        validate_array_results: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_validate_array_results",
            &passes.calls_validate_array_results,
            resources,
        )?,
        mark_array_args: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_mark_array_args",
            &passes.calls_mark_array_args,
            resources,
        )?,
        erase_generic_params: reflected_bind_group_from_resources(
            device,
            "type_check_resident_calls_erase_generic_params",
            &passes.calls_erase_generic_params,
            resources,
        )?,
    })
}
