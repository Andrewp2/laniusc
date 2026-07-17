use super::{super::*, buffers::Buffers, inputs::CreateInputs};

/// Bind groups for exact, arbitrary-depth path-prefix canonicalization.
pub(in crate::type_checker) struct PathSequences {
    pub(in crate::type_checker) clear_state: wgpu::BindGroup,
    pub(in crate::type_checker) dispatch_params: LaniusBuffer<PathPrefixDispatchParams>,
    pub(in crate::type_checker) dispatch_args: wgpu::BindGroup,
    pub(in crate::type_checker) rounds: Vec<PathPrefixRound>,
    pub(in crate::type_checker) finalize: wgpu::BindGroup,
}

/// One pre-bound prefix-doubling round. Every round reuses the same three
/// pipelines; only immutable uniforms and ping/pong buffer roles differ.
pub(in crate::type_checker) struct PathPrefixRound {
    pub(in crate::type_checker) _params: LaniusBuffer<PathPrefixRoundParams>,
    pub(in crate::type_checker) clear: wgpu::BindGroup,
    pub(in crate::type_checker) insert: wgpu::BindGroup,
    pub(in crate::type_checker) lookup: wgpu::BindGroup,
}

pub(in crate::type_checker) fn create_path_sequences(
    passes: &TypeCheckPasses,
    device: &wgpu::Device,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
) -> Result<PathSequences> {
    let segment_capacity = inputs.token_capacity.max(1);
    let round_count = u32::BITS - segment_capacity.saturating_sub(1).leading_zeros();
    let dispatch_params = uniform_from_val(
        device,
        "type_check.modules.path_prefix.dispatch_params",
        &PathPrefixDispatchParams {
            segment_capacity,
            round_count,
            reserved0: 0,
            reserved1: 0,
        },
    );

    let clear_state = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01a_clear_path_state"),
        &passes.modules_clear_path_state,
        0,
        &[
            ("gParams", inputs.params.as_entire_binding()),
            (
                "path_id_by_owner_hir",
                buffers.path_id_by_owner_hir.as_entire_binding(),
            ),
            (
                "path_max_segment_count",
                buffers.path_max_segment_count.as_entire_binding(),
            ),
        ],
    )?;
    let dispatch_args = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01c_path_prefix_dispatch_args"),
        &passes.modules_path_prefix_dispatch_args,
        0,
        &[
            ("gParams", dispatch_params.as_entire_binding()),
            (
                "path_segment_count_out",
                buffers.path_segment_count_out.as_entire_binding(),
            ),
            (
                "path_max_segment_count",
                buffers.path_max_segment_count.as_entire_binding(),
            ),
            (
                "path_prefix_row_dispatch_args",
                buffers.path_prefix_row_dispatch_args.as_entire_binding(),
            ),
            (
                "path_prefix_round_dispatch_args",
                buffers.path_prefix_round_dispatch_args.as_entire_binding(),
            ),
        ],
    )?;

    let mut rounds = Vec::with_capacity(round_count as usize);
    for round_i in 0..round_count {
        let params = uniform_from_val(
            device,
            &format!("type_check.modules.path_prefix.round.{round_i}.params"),
            &PathPrefixRoundParams {
                segment_capacity,
                step: 1u32 << round_i,
                reserved0: 0,
                reserved1: 0,
            },
        );
        let (read_ids, write_ids) = if round_i & 1 == 0 {
            (&buffers.path_prefix_id_a, &buffers.path_prefix_id_b)
        } else {
            (&buffers.path_prefix_id_b, &buffers.path_prefix_id_a)
        };
        let clear = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_01c_path_prefix_table_clear"),
            &passes.modules_path_prefix_table_clear,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "path_segment_count_out",
                    buffers.path_segment_count_out.as_entire_binding(),
                ),
                (
                    "path_prefix_table_state",
                    buffers.path_prefix_table_state.as_entire_binding(),
                ),
            ],
        )?;
        let insert = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_01c_path_prefix_table_insert"),
            &passes.modules_path_prefix_table_insert,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "path_segment_count_out",
                    buffers.path_segment_count_out.as_entire_binding(),
                ),
                (
                    "path_prefix_base",
                    buffers.path_prefix_base.as_entire_binding(),
                ),
                ("path_prefix_id_in", read_ids.as_entire_binding()),
                (
                    "path_prefix_table_state",
                    buffers.path_prefix_table_state.as_entire_binding(),
                ),
                (
                    "path_prefix_table_left",
                    buffers.path_prefix_table_left.as_entire_binding(),
                ),
                (
                    "path_prefix_table_right",
                    buffers.path_prefix_table_right.as_entire_binding(),
                ),
            ],
        )?;
        let lookup = bind_group::create_bind_group_from_bindings(
            device,
            Some("type_check_modules_01c_path_prefix_table_lookup"),
            &passes.modules_path_prefix_table_lookup,
            0,
            &[
                ("gParams", params.as_entire_binding()),
                (
                    "path_segment_count_out",
                    buffers.path_segment_count_out.as_entire_binding(),
                ),
                (
                    "path_prefix_base",
                    buffers.path_prefix_base.as_entire_binding(),
                ),
                ("path_prefix_id_in", read_ids.as_entire_binding()),
                (
                    "path_prefix_table_state",
                    buffers.path_prefix_table_state.as_entire_binding(),
                ),
                (
                    "path_prefix_table_left",
                    buffers.path_prefix_table_left.as_entire_binding(),
                ),
                (
                    "path_prefix_table_right",
                    buffers.path_prefix_table_right.as_entire_binding(),
                ),
                ("path_prefix_id_out", write_ids.as_entire_binding()),
                ("status", inputs.status_buf.as_entire_binding()),
            ],
        )?;
        rounds.push(PathPrefixRound {
            _params: params,
            clear,
            insert,
            lookup,
        });
    }

    let finalize = bind_group::create_bind_group_from_bindings(
        device,
        Some("type_check_modules_01c_path_prefix_finalize"),
        &passes.modules_path_prefix_finalize,
        0,
        &[
            ("gParams", dispatch_params.as_entire_binding()),
            (
                "path_segment_count_out",
                buffers.path_segment_count_out.as_entire_binding(),
            ),
            (
                "path_max_segment_count",
                buffers.path_max_segment_count.as_entire_binding(),
            ),
            (
                "path_prefix_id_b",
                buffers.path_prefix_id_b.as_entire_binding(),
            ),
            (
                "path_prefix_id_a",
                buffers.path_prefix_id_a.as_entire_binding(),
            ),
        ],
    )?;

    Ok(PathSequences {
        clear_state,
        dispatch_params,
        dispatch_args,
        rounds,
        finalize,
    })
}
