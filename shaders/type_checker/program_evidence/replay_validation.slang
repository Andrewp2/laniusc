// Replay consumes an earlier GPU-accepted result in this exact retained arena.
// It rechecks semantic goal equality in the selected body's environment; neither
// matching integer slots nor a copied predicate ID grants proof.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.goal_operations;
import type_checker.program_evidence.proof_goal_equality;

public EvidenceStatus pev_validate_retained_evidence(uint evidence)
{
    uint4 low; uint4 high;
    if (!pev_read4(17u, evidence, 0u, low) || !pev_read4(17u, evidence, 4u, high))
        return pev_invalid(1u, evidence, 17u);
    uint obligation_state; uint evidence_slot; uint call_state;
    if (!pev_output_read(3u, high.z, 0u, obligation_state) ||
        !pev_output_read(3u, high.z, 2u, evidence_slot) || evidence_slot != high.z ||
        !pev_output_read(4u, high.y, 0u, call_state) || (call_state != 1u && call_state != 2u) ||
        (low.x == 1u ? obligation_state != 1u : (low.x != 2u || obligation_state != 2u)))
        return pev_invalid(13u, evidence, high.z);
    // Prior output rows are retained across submissions and are never reset by
    // appended-row initialization. This exact copy is the GPU proof provenance.
    // A concrete obligation may come from a CHECKED_SYMBOLIC call; its entire
    // source call need not be concrete merely to retain that one valid witness.
    for (uint field = 0u; field < 8u; field++)
    {
        uint supplied; uint selected;
        if (!pev_word(17u, evidence, field, supplied) ||
            !pev_output_read(5u, high.z, field, selected) || supplied != selected)
            return pev_invalid(13u, evidence, high.z);
    }
    uint proof_context; uint4 source_call;
    if (!pps_retained_proof_reference(low.w, high.x, low.x, proof_context) ||
        !pev_read4(15u, high.y, 0u, source_call) || source_call.x != proof_context)
        return pev_invalid(13u, evidence, low.w);
    return pev_ok();
}

public EvidenceStatus pev_validate_context(uint context)
{
    uint4 low; uint4 high;
    if (!pev_read4(13u, context, 0u, low) || !pev_read4(13u, context, 4u, high))
        return pev_invalid(1u, context, 13u);
    if (high.y != 1u) return pev_ok(); // Full representation/owner admission ran first.
    uint origin_state;
    if (!pev_output_read(4u, high.z, 0u, origin_state) || origin_state != 1u)
        return pev_invalid(13u, context, high.z);
    for (uint i = 0u; i < high.x; i++)
    {
        uint assumption = low.w + i; uint4 offered;
        if (!pev_read4(14u, assumption, 0u, offered)) return pev_invalid(1u, context, assumption);
        EvidenceStatus status = pev_validate_retained_evidence(offered.w);
        if (status.state != PEV_VALID) return status;
        uint4 source;
        if (!pev_read4(17u, offered.w, 0u, source) || source.x != 1u)
            return pev_invalid(13u, context, offered.w);
        // The accepted proof's conclusion is the normalized selected goal.
        // Generic implementation heads may still contain owned parameters and
        // are never compared directly against this new concrete body goal.
        uint conclusion;
        if (!pev_word(17u, offered.w, 4u, conclusion))
            return pev_invalid(1u, context, offered.w);
        bool equal;
        status = pps_predicate_equals_goal(offered.y, offered.z, low.y,
            conclusion, true, equal);
        if (status.state != PEV_VALID) return status;
        if (!equal) return pev_invalid(13u, context, offered.w);
    }
    return pev_ok();
}
