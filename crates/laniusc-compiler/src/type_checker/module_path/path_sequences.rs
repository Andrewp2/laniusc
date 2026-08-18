use super::{super::*, buffers::Buffers, inputs::CreateInputs};

/// Bind groups for exact, arbitrary-depth path-prefix canonicalization.
pub(in crate::type_checker) struct PathSequences {
    pub(in crate::type_checker) clear_state: ComputeOperation,
    pub(in crate::type_checker) dispatch_params: LaniusBuffer<PathPrefixDispatchParams>,
    pub(in crate::type_checker) dispatch_args: ComputeOperation,
    pub(in crate::type_checker) initial_table_clear: ComputeOperation,
    pub(in crate::type_checker) rounds: Vec<PathPrefixRound>,
    pub(in crate::type_checker) finalize: ComputeOperation,
}

/// One pre-bound prefix-doubling round. Every round reuses the insert and
/// lookup pipelines; only immutable uniforms and ping/pong buffer roles differ.
pub(in crate::type_checker) struct PathPrefixRound {
    pub(in crate::type_checker) _params: LaniusBuffer<PathPrefixRoundParams>,
    pub(in crate::type_checker) intern: ComputeOperation,
}

pub(in crate::type_checker) fn create_path_sequences(
    passes: &TypeCheckPasses,
    graph: &compiler_graph::TypeCheckCompilerGraph,
    device: &wgpu::Device,
    inputs: &CreateInputs<'_>,
    buffers: &Buffers,
    resources: &ResourceMap<'_>,
) -> Result<PathSequences> {
    let segment_capacity = inputs.token_capacity.max(1);
    assert!(
        segment_capacity <= 0x07ff_ffff,
        "path-prefix row capacity exceeds the round-tagged table encoding",
    );
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

    let hir_work = inputs
        .hir_node_capacity
        .div_ceil(256)
        .saturating_mul(256)
        .max(1);
    let clear_state = ComputeOperation::direct_spec(
        device,
        graph,
        resources,
        passes,
        PATH_STATE_CLEAR,
        hir_work.max(segment_capacity),
    )?;
    let mut dispatch_resources = resources.clone();
    dispatch_resources.buffer("gParams", &dispatch_params);
    let dispatch_args = ComputeOperation::direct_spec(
        device,
        graph,
        &dispatch_resources,
        passes,
        PATH_PREFIX_DISPATCH,
        32,
    )?;
    let initial_table_clear = ComputeOperation::indirect_spec(
        device,
        graph,
        &dispatch_resources,
        passes,
        PATH_PREFIX_TABLE_CLEAR,
        &buffers.path_prefix_row_dispatch_args,
    )?;

    let mut rounds = Vec::with_capacity(round_count as usize);
    for round_i in 0..round_count {
        let params = uniform_from_val(
            device,
            &format!("type_check.modules.path_prefix.round.{round_i}.params"),
            &PathPrefixRoundParams {
                segment_capacity,
                step: 1u32 << round_i,
                reserved0: round_i + 1,
                reserved1: 0,
            },
        );
        let spec = if round_i & 1 == 0 {
            PATH_PREFIX_INTERN_A_TO_B
        } else {
            PATH_PREFIX_INTERN_B_TO_A
        };
        let mut round_resources = resources.clone();
        round_resources.buffer("gParams", &params);
        let offset = u64::from(round_i) * 3 * std::mem::size_of::<u32>() as u64;
        let intern = ComputeOperation::indirect_spec_at(
            device,
            graph,
            &round_resources,
            passes,
            spec,
            &buffers.path_prefix_round_dispatch_args,
            offset,
        )?;
        rounds.push(PathPrefixRound {
            _params: params,
            intern,
        });
    }

    let finalize = ComputeOperation::indirect_spec(
        device,
        graph,
        &dispatch_resources,
        passes,
        PATH_PREFIX_FINALIZE,
        &buffers.path_prefix_row_dispatch_args,
    )?;

    Ok(PathSequences {
        clear_state,
        dispatch_params,
        dispatch_args,
        initial_table_clear,
        rounds,
        finalize,
    })
}
