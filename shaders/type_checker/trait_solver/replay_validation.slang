// Replay consumes an earlier GPU-accepted result in this exact retained arena.
// It rechecks semantic goal equality in the selected body's environment; neither
// matching integer slots nor a copied predicate ID grants proof.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.goal_operations;
import type_checker.trait_solver.proof_goal_equality;

public SolverStatus ts_validate_retained_evidence(uint evidence)
{
    uint4 low; uint4 high;
    if (!ts_read4(17u, evidence, 0u, low) || !ts_read4(17u, evidence, 4u, high))
        return ts_invalid(1u, evidence, 17u);
    uint obligation_state; uint evidence_slot; uint call_state;
    if (!ts_output_read(3u, high.z, 0u, obligation_state) ||
        !ts_output_read(3u, high.z, 2u, evidence_slot) || evidence_slot != high.z ||
        !ts_output_read(4u, high.y, 0u, call_state) || (call_state != 1u && call_state != 2u) ||
        (low.x == 1u ? obligation_state != 1u : (low.x != 2u || obligation_state != 2u)))
        return ts_invalid(13u, evidence, high.z);
    // Prior output rows are retained across submissions and are never reset by
    // appended-row initialization. This exact copy is the GPU proof provenance.
    // A concrete obligation may come from a CHECKED_SYMBOLIC call; its entire
    // source call need not be concrete merely to retain that one valid witness.
    for (uint field = 0u; field < 8u; field++)
    {
        uint supplied; uint selected;
        if (!ts_word(17u, evidence, field, supplied) ||
            !ts_output_read(5u, high.z, field, selected) || supplied != selected)
            return ts_invalid(13u, evidence, high.z);
    }
    uint proof_context; uint4 source_call;
    if (!pps_retained_proof_reference(low.w, high.x, low.x, proof_context) ||
        !ts_read4(15u, high.y, 0u, source_call) || source_call.x != proof_context)
        return ts_invalid(13u, evidence, low.w);
    return ts_ok();
}

public SolverStatus ts_validate_context(uint context)
{
    uint4 low; uint4 high;
    if (!ts_read4(13u, context, 0u, low) || !ts_read4(13u, context, 4u, high))
        return ts_invalid(1u, context, 13u);
    if (high.y != 1u) return ts_ok(); // Full representation/owner admission ran first.
    uint origin_state;
    if (!ts_output_read(4u, high.z, 0u, origin_state) || origin_state != 1u)
        return ts_invalid(13u, context, high.z);
    for (uint i = 0u; i < high.x; i++)
    {
        uint assumption = low.w + i; uint4 offered;
        if (!ts_read4(14u, assumption, 0u, offered)) return ts_invalid(1u, context, assumption);
        SolverStatus status = ts_validate_retained_evidence(offered.w);
        if (status.state != TS_VALID) return status;
        uint4 source;
        if (!ts_read4(17u, offered.w, 0u, source) || source.x != 1u)
            return ts_invalid(13u, context, offered.w);
        // The accepted proof's conclusion is the normalized selected goal.
        // Generic implementation heads may still contain owned parameters and
        // are never compared directly against this new concrete body goal.
        uint conclusion;
        if (!ts_word(17u, offered.w, 4u, conclusion))
            return ts_invalid(1u, context, offered.w);
        bool equal;
        status = pps_predicate_equals_goal(offered.y, offered.z, low.y,
            conclusion, true, equal);
        if (status.state != TS_VALID) return status;
        if (!equal) return ts_invalid(13u, context, offered.w);
    }
    return ts_ok();
}
