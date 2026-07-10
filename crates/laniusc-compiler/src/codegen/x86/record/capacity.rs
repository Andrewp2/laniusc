use log::warn;

use super::super::{
    X86_REGALLOC_ROWS_PER_CHUNK,
    X86FeatureSummary,
    X86Params,
    regalloc_recorded_step_count,
    support::{pointer_jump_steps_for_items, scan_steps_for_blocks, workgroup_grid_1d},
    x86_capacity_estimate_for_hir_tokens_inst_basis_and_feature_summary,
    x86_control_flow_bridge_pass_contract,
    x86_encode_pass_contract,
    x86_function_slot_capacity,
    x86_initial_output_readback_bytes,
    x86_lowering_pass_contract,
    x86_node_inst_order_rows,
    x86_regalloc_pass_contract,
};

const X86_SYSV_INTEGER_REGISTER_SLOTS: usize = 6;
const X86_AGGREGATE_RETURN_POINTER_REGISTER_SLOTS: usize = 1;
const X86_REGALLOC_DISPATCH_PHASES: usize = 2;

/// Capacity plan for x86 recording buffers derived from HIR size and feature counts.
pub(super) struct RecordCapacity {
    pub(super) hir_words: usize,
    pub(super) inst_capacity: usize,
    pub(super) output_capacity: usize,
    pub(super) output_words: usize,
    pub(super) output_readback_bytes: u64,
    pub(super) node_inst_scan_words: usize,
    pub(super) node_inst_scan_blocks: usize,
    pub(super) node_func_owner_steps: Vec<u32>,
    pub(super) expr_resolve_steps: Vec<u32>,
    pub(super) expr_semantic_type_steps: Vec<u32>,
    pub(super) enclosing_return_steps: Vec<u32>,
    pub(super) enclosing_let_steps: Vec<u32>,
    pub(super) enclosing_stmt_steps: Vec<u32>,
    pub(super) call_callee_owner_steps: Vec<u32>,
    pub(super) match_result_owner_steps: Vec<u32>,
    pub(super) match_pattern_owner_steps: Vec<u32>,
    pub(super) node_inst_same_end_rank_steps: Vec<u32>,
    pub(super) enclosing_loop_steps: Vec<u32>,
    pub(super) short_circuit_rhs_steps: Vec<u32>,
    pub(super) index_source_owner_steps: Vec<u32>,
    pub(super) func_owner_scan_blocks: usize,
    pub(super) node_inst_order_rows: usize,
    pub(super) virtual_next_call_steps: Vec<u32>,
    pub(super) virtual_regalloc_chunk_count: usize,
    pub(super) token_words: usize,
    pub(super) function_slot_capacity: usize,
    pub(super) virtual_dispatch_arg_groups: (u32, u32),
    pub(super) params: X86Params,
}

impl RecordCapacity {
    /// Computes buffer capacities, scan steps, and dispatch parameter limits for one x86 record.
    pub(super) fn for_hir(
        source_len: u32,
        token_capacity: u32,
        n_hir_nodes: u32,
        inst_hir_node_count: usize,
        feature_summary: X86FeatureSummary,
    ) -> Self {
        let capacity = x86_capacity_estimate_for_hir_tokens_inst_basis_and_feature_summary(
            n_hir_nodes as usize,
            token_capacity as usize,
            inst_hir_node_count,
            feature_summary,
        );
        let hir_words = capacity.hir_words;
        let inst_capacity = capacity.inst_capacity;
        let output_capacity = capacity.output_capacity;
        if capacity.inst_capacity_capped {
            warn!(
                "x86 instruction capacity estimate hit cap: requested={} cap={} hir_words={} inst_basis_words={} token_capacity={}; exact instruction-count projection is required for larger programs",
                capacity.requested_inst_capacity,
                capacity.inst_capacity,
                capacity.hir_words,
                capacity.inst_basis_words,
                token_capacity
            );
        }
        let output_words = output_capacity.div_ceil(4);
        let output_readback_bytes =
            x86_initial_output_readback_bytes(output_capacity, source_len as usize) as u64;
        let node_inst_scan_words = hir_words + 1;
        let node_inst_scan_blocks = node_inst_scan_words.div_ceil(256).max(1);
        let node_func_owner_steps = pointer_jump_steps_for_items(hir_words);
        let expr_resolve_steps = pointer_jump_steps_for_items(hir_words);
        let expr_semantic_type_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_return_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_let_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_stmt_steps = pointer_jump_steps_for_items(hir_words);
        let call_callee_owner_steps = pointer_jump_steps_for_items(hir_words);
        let match_result_owner_steps = pointer_jump_steps_for_items(hir_words);
        let match_pattern_owner_steps = pointer_jump_steps_for_items(hir_words);
        let node_inst_same_end_rank_steps = pointer_jump_steps_for_items(hir_words);
        let enclosing_loop_steps = pointer_jump_steps_for_items(hir_words);
        let short_circuit_rhs_steps = pointer_jump_steps_for_items(hir_words);
        let index_source_owner_steps = pointer_jump_steps_for_items(hir_words);
        let func_owner_scan_blocks = hir_words.div_ceil(256).max(1);
        let virtual_next_call_steps = scan_steps_for_blocks(inst_capacity);
        let regalloc_recorded_steps = regalloc_recorded_step_count(inst_capacity);
        // Regalloc now has one validation/status phase followed by one
        // function-parallel allocation phase. A GPU lane owns one function's
        // contiguous virtual-row interval, so command count is independent of
        // conservative instruction capacity.
        let virtual_regalloc_chunk_count = X86_REGALLOC_DISPATCH_PHASES;
        let token_words = (token_capacity as usize).max(1);
        let function_slot_capacity =
            x86_function_slot_capacity(inst_hir_node_count, hir_words, token_words);
        let virtual_dispatch_arg_task_count = virtual_next_call_steps
            .len()
            .max(virtual_regalloc_chunk_count)
            .max(1);
        let virtual_dispatch_arg_groups = workgroup_grid_1d(
            (virtual_dispatch_arg_task_count as u32)
                .div_ceil(256)
                .max(1),
        );
        let node_inst_order_rows = x86_node_inst_order_rows(hir_words, inst_capacity);
        let params = X86Params {
            n_tokens: token_capacity,
            source_len,
            out_capacity: output_capacity as u32,
            n_hir_nodes,
            inst_capacity: inst_capacity as u32,
            virtual_next_call_step_count: virtual_next_call_steps.len().min(u32::MAX as usize)
                as u32,
            regalloc_rows_per_chunk: X86_REGALLOC_ROWS_PER_CHUNK as u32,
            regalloc_chunk_count: virtual_regalloc_chunk_count.min(u32::MAX as usize) as u32,
            function_slot_capacity: function_slot_capacity.min(u32::MAX as usize) as u32,
        };
        trace_capacity(
            &capacity,
            output_readback_bytes,
            &virtual_next_call_steps,
            regalloc_recorded_steps,
            virtual_regalloc_chunk_count,
            function_slot_capacity,
            node_inst_order_rows,
            &node_inst_same_end_rank_steps,
            &enclosing_loop_steps,
            &short_circuit_rhs_steps,
            &index_source_owner_steps,
            feature_summary,
        );

        Self {
            hir_words,
            inst_capacity,
            output_capacity,
            output_words,
            output_readback_bytes,
            node_inst_scan_words,
            node_inst_scan_blocks,
            node_func_owner_steps,
            expr_resolve_steps,
            expr_semantic_type_steps,
            enclosing_return_steps,
            enclosing_let_steps,
            enclosing_stmt_steps,
            call_callee_owner_steps,
            match_result_owner_steps,
            match_pattern_owner_steps,
            node_inst_same_end_rank_steps,
            enclosing_loop_steps,
            short_circuit_rhs_steps,
            index_source_owner_steps,
            func_owner_scan_blocks,
            node_inst_order_rows,
            virtual_next_call_steps,
            virtual_regalloc_chunk_count,
            token_words,
            function_slot_capacity,
            virtual_dispatch_arg_groups,
            params,
        }
    }
}

fn trace_capacity(
    capacity: &super::super::X86CapacityEstimate,
    output_readback_bytes: u64,
    virtual_next_call_steps: &[u32],
    regalloc_recorded_steps: usize,
    virtual_regalloc_chunk_count: usize,
    function_slot_capacity: usize,
    node_inst_order_rows: usize,
    node_inst_same_end_rank_steps: &[u32],
    enclosing_loop_steps: &[u32],
    short_circuit_rhs_steps: &[u32],
    index_source_owner_steps: &[u32],
    feature_summary: X86FeatureSummary,
) {
    if !crate::gpu::trace::enabled() {
        return;
    }

    let now = std::time::Instant::now();
    let regalloc_contract = x86_regalloc_pass_contract();
    let regalloc_recorded_span_rows =
        virtual_regalloc_chunk_count.saturating_mul(X86_REGALLOC_ROWS_PER_CHUNK);
    let regalloc_readiness_blocked = regalloc_contract.loop_status == "bounded"
        && regalloc_contract.fallback_status == "fail-closed"
        && regalloc_contract.claim_status == "blocked";
    let control_bridge_contract = x86_control_flow_bridge_pass_contract();
    let control_bridge_readiness_blocked = control_bridge_contract.loop_status == "bounded"
        && control_bridge_contract.fallback_status == "fail-closed"
        && control_bridge_contract.claim_status == "blocked";
    let lowering_contract = x86_lowering_pass_contract();
    let lowering_readiness_blocked = lowering_contract.loop_status == "bounded"
        && lowering_contract.fallback_status == "fail-closed"
        && lowering_contract.claim_status == "blocked";
    let encode_contract = x86_encode_pass_contract();
    let encode_local_byte_loop_not_blocking = encode_contract.loop_status == "bounded-local"
        && encode_contract.fallback_status == "fail-closed"
        && encode_contract.claim_status == "not-blocking"
        && encode_contract.source_text_status == "not-consumed";
    let control_bridge_max_steps = [
        node_inst_same_end_rank_steps.len(),
        enclosing_loop_steps.len(),
        short_circuit_rhs_steps.len(),
        index_source_owner_steps.len(),
    ]
    .into_iter()
    .max()
    .unwrap_or(0);
    let control_bridge_relation_words = capacity
        .hir_words
        .saturating_mul(control_bridge_contract.relation_count);
    for (name, value) in [
        ("x86.hir_words", capacity.hir_words),
        ("x86.inst_basis_words", capacity.inst_basis_words),
        (
            "x86.requested_inst_capacity",
            capacity.requested_inst_capacity,
        ),
        ("x86.inst_capacity", capacity.inst_capacity),
        ("x86.output_capacity_bytes", capacity.output_capacity),
        (
            "x86.initial_output_readback_bytes",
            output_readback_bytes as usize,
        ),
        ("x86.function_slot_capacity", function_slot_capacity),
        ("x86.virtual_next_call_steps", virtual_next_call_steps.len()),
        ("x86.regalloc_recorded_chunks", virtual_regalloc_chunk_count),
        (
            "x86.regalloc_recorded_span_rows",
            regalloc_recorded_span_rows,
        ),
        (
            "x86.regalloc_recorded_span_covers_inst_capacity",
            usize::from(regalloc_recorded_span_rows >= capacity.inst_capacity.max(1)),
        ),
        ("x86.regalloc_recorded_steps", regalloc_recorded_steps),
        ("x86.regalloc_rows_per_chunk", X86_REGALLOC_ROWS_PER_CHUNK),
        (
            "x86.regalloc_contract_rows_per_chunk",
            regalloc_contract.rows_per_chunk,
        ),
        (
            "x86.regalloc_contract_loop_status_bounded",
            usize::from(regalloc_contract.loop_status == "bounded"),
        ),
        (
            "x86.regalloc_contract_fallback_status_fail_closed",
            usize::from(regalloc_contract.fallback_status == "fail-closed"),
        ),
        (
            "x86.regalloc_contract_claim_status_blocked",
            usize::from(regalloc_contract.claim_status == "blocked"),
        ),
        (
            "x86.regalloc_contract_readiness_status_blocked",
            usize::from(regalloc_readiness_blocked),
        ),
        (
            "x86.control_bridge_contract_loop_status_bounded",
            usize::from(control_bridge_contract.loop_status == "bounded"),
        ),
        (
            "x86.control_bridge_contract_fallback_status_fail_closed",
            usize::from(control_bridge_contract.fallback_status == "fail-closed"),
        ),
        (
            "x86.control_bridge_contract_claim_status_blocked",
            usize::from(control_bridge_contract.claim_status == "blocked"),
        ),
        (
            "x86.control_bridge_contract_readiness_status_blocked",
            usize::from(control_bridge_readiness_blocked),
        ),
        (
            "x86.control_bridge_relation_count",
            control_bridge_contract.relation_count,
        ),
        (
            "x86.control_bridge_relation_words",
            control_bridge_relation_words,
        ),
        (
            "x86.lowering_contract_loop_status_bounded",
            usize::from(lowering_contract.loop_status == "bounded"),
        ),
        (
            "x86.lowering_contract_fallback_status_fail_closed",
            usize::from(lowering_contract.fallback_status == "fail-closed"),
        ),
        (
            "x86.lowering_contract_claim_status_blocked",
            usize::from(lowering_contract.claim_status == "blocked"),
        ),
        (
            "x86.lowering_contract_source_text_status_not_consumed",
            usize::from(lowering_contract.source_text_status == "not-consumed"),
        ),
        (
            "x86.lowering_contract_function_body_recognizers_forbidden",
            usize::from(lowering_contract.function_body_recognizer_status == "forbidden"),
        ),
        (
            "x86.lowering_contract_readiness_status_blocked",
            usize::from(lowering_readiness_blocked),
        ),
        (
            "x86.lowering_contract_relation_count",
            lowering_contract.relation_count,
        ),
        (
            "x86.encode_contract_loop_status_bounded_local",
            usize::from(encode_contract.loop_status == "bounded-local"),
        ),
        (
            "x86.encode_contract_fallback_status_fail_closed",
            usize::from(encode_contract.fallback_status == "fail-closed"),
        ),
        (
            "x86.encode_contract_claim_status_not_blocking",
            usize::from(encode_contract.claim_status == "not-blocking"),
        ),
        (
            "x86.encode_contract_source_text_status_not_consumed",
            usize::from(encode_contract.source_text_status == "not-consumed"),
        ),
        (
            "x86.encode_contract_local_byte_loop_not_blocking",
            usize::from(encode_local_byte_loop_not_blocking),
        ),
        (
            "x86.encode_contract_max_bytes_per_instruction",
            encode_contract.max_bytes_per_instruction,
        ),
        (
            "x86.control_bridge_node_inst_same_end_rank_steps",
            node_inst_same_end_rank_steps.len(),
        ),
        (
            "x86.control_bridge_enclosing_loop_steps",
            enclosing_loop_steps.len(),
        ),
        (
            "x86.control_bridge_short_circuit_rhs_steps",
            short_circuit_rhs_steps.len(),
        ),
        (
            "x86.control_bridge_index_source_owner_steps",
            index_source_owner_steps.len(),
        ),
        (
            "x86.control_bridge_max_pointer_jump_steps",
            control_bridge_max_steps,
        ),
        ("x86.node_inst_order_rows", node_inst_order_rows),
        ("x86.feature_mask", feature_summary.mask as usize),
        (
            "x86.feature_scalar_inst_capacity",
            feature_summary.scalar_inst_capacity as usize,
        ),
        (
            "x86.feature_call_count",
            feature_summary.call_count as usize,
        ),
        (
            "x86.feature_param_count",
            feature_summary.param_count as usize,
        ),
        (
            "x86.sysv_integer_register_slots",
            X86_SYSV_INTEGER_REGISTER_SLOTS,
        ),
        (
            "x86.aggregate_return_pointer_register_slots",
            X86_AGGREGATE_RETURN_POINTER_REGISTER_SLOTS,
        ),
        (
            "x86.max_explicit_args_with_aggregate_return",
            X86_SYSV_INTEGER_REGISTER_SLOTS
                .saturating_sub(X86_AGGREGATE_RETURN_POINTER_REGISTER_SLOTS),
        ),
    ] {
        crate::gpu::trace::record_counter("host.x86.capacity", name, now, value as f64);
    }
}
