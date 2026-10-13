import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_frontier_selection;
import type_checker.program_evidence.proof_frontier_expansion;
import type_checker.program_evidence.proof_goal_equality;
import type_checker.program_evidence.proof_application_admission;

public EvidenceStatus pps_emit_ready_proof(uint event)
{
    uint2 queue;
    if (!pps_read2(PPS_REDUCTION_QUEUE, event, 0u, queue)) return pev_invalid(1u, event, PPS_REDUCTION_QUEUE);
    if (queue.y != PPS_EVENT_READY) return pev_ok();
    uint work = queue.x; uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source) || key.z != PPS_WORK_READY ||
        completion.y != 0u) return pev_invalid(70u, event, work);
    uint proof; uint edges;
    EvidenceStatus status = pps_reserve(PPS_PROOFS, 1u, work, proof);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_PROOF_EDGES, selected.w, work, edges);
    if (status.state != PEV_VALID) return status;
    uint4 goal; uint4 goal_extra;
    if (!pps_read8(PPS_GOALS, key.y, goal, goal_extra)) return pev_invalid(1u, work, key.y);
    bool concrete = goal_extra.z == 1u;
    uint kind = selected.x == PEV_INVALID ? 2u : 1u;
    uint evidence_source = selected.x;
    uint substitution = selected.y;
    if (kind == 2u)
    {
        uint4 assumption; uint4 context; uint4 context_extra;
        if (selected.w != 0u || !pev_read4(14u, selected.y, 0u, assumption) ||
            assumption.x != key.x || !pev_read4(13u, key.x, 0u, context) ||
            !pev_read4(13u, key.x, 4u, context_extra)) return pev_invalid(68u, work, selected.y);
        evidence_source = selected.y; substitution = PEV_INVALID;
        concrete = context_extra.y == 1u;
    }
    [loop]
    for (uint i = 0u; i < selected.w; i++)
    {
        uint4 requirement; uint4 child; uint4 child_completion; uint4 child_selected; uint4 child_source;
        uint4 child_proof; uint4 child_extra;
        if (!pps_read4(PPS_REQUIREMENTS, selected.z + i, 0u, requirement) || requirement.x != work ||
            !pps_work_read(requirement.z, child, child_selected, child_completion, child_source) ||
            (child.z != PPS_WORK_PROVEN && child.z != PPS_WORK_NOTIFIED) ||
            !pps_read8(PPS_PROOFS, child_completion.z, child_proof, child_extra) ||
            child_proof.z != key.x || child_completion.z >= proof ||
            !pps_write4(PPS_PROOF_EDGES, edges + i, 0u,
                uint4(proof, requirement.y, child_completion.z, 0u)))
            return pev_invalid(68u, work, selected.z + i);
        concrete = concrete && child_extra.w == 1u;
    }
    if (!pps_write8(PPS_PROOFS, proof, uint4(kind, key.y, key.x, evidence_source),
        uint4(substitution, edges, selected.w, concrete ? 1u : 2u))) return pev_invalid(1u, work, proof);
    key.z = PPS_WORK_PROOF_PENDING; completion.z = proof;
    if (!pps_work_write(work, key, selected, completion, source)) return pev_invalid(1u, work, proof);
    return pps_enqueue(work, PPS_EVENT_PROVEN);
}

// Both kind-specific validation passes inspect the same frozen pending rows.
// They publish no proof authority; phase60 commits only after both complete.
public EvidenceStatus pps_read_ready_proof(uint event, out uint proof, out uint kind)
{
    proof = PEV_INVALID; kind = 0u;
    uint2 queue; uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_read2(PPS_REDUCTION_QUEUE, event, 0u, queue)) return pev_invalid(1u, event, PPS_REDUCTION_QUEUE);
    if (queue.y != PPS_EVENT_READY) return pev_ok();
    if (!pps_work_read(queue.x, key, selected, completion, source) || key.z != PPS_WORK_PROOF_PENDING)
        return pev_invalid(70u, event, queue.x);
    uint4 low; uint4 high;
    if (!pps_read_pending8(PPS_PROOFS, completion.z, low, high) || low.y != key.y || low.z != key.x ||
        (low.x == 1u ? (low.w != selected.x || high.x != selected.y) :
            (low.x != 2u || selected.x != PEV_INVALID || low.w != selected.y)))
        return pev_invalid(68u, event, queue.x);
    proof = completion.z; kind = low.x;
    return pev_ok();
}

public EvidenceStatus pps_admit_ready_implementation_proof(uint event)
{
    uint proof; uint kind;
    EvidenceStatus status = pps_read_ready_proof(event, proof, kind);
    if (status.state != PEV_VALID || kind != 1u) return status;
    return pps_admit_implementation_proof(proof, pps_matching_limits());
}

public EvidenceStatus pps_admit_ready_assumption_proof(uint event)
{
    uint proof; uint kind;
    EvidenceStatus status = pps_read_ready_proof(event, proof, kind);
    if (status.state != PEV_VALID || kind != 2u) return status;
    return pps_admit_assumption_proof(proof);
}

public EvidenceStatus pps_publish_work_proof(uint event)
{
    uint2 queue; uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_read2(PPS_REDUCTION_QUEUE, event, 0u, queue)) return pev_invalid(1u, event, PPS_REDUCTION_QUEUE);
    if (queue.y != PPS_EVENT_READY) return pev_ok();
    uint4 low; uint4 high;
    if (!pps_work_read(queue.x, key, selected, completion, source) || key.z != PPS_WORK_PROOF_PENDING ||
        !pps_read8(PPS_PROOFS, completion.z, low, high) || low.y != key.y || low.z != key.x)
        return pev_invalid(68u, event, queue.x);
    key.z = PPS_WORK_PROVEN;
    return pps_write4(PPS_WORK, queue.x, 0u, key) ? pev_ok() : pev_invalid(1u, event, queue.x);
}

public EvidenceStatus pps_process_notification(uint event)
{
    uint2 queue;
    if (!pps_read2(PPS_REDUCTION_QUEUE, event, 0u, queue)) return pev_invalid(1u, event, PPS_REDUCTION_QUEUE);
    if (queue.y == PPS_EVENT_READY) return pev_ok();
    if (queue.y != PPS_EVENT_PROVEN && queue.y != PPS_EVENT_FAILED)
        return pev_invalid(70u, event, queue.y);
    return pps_notify_work(queue.x, queue.y == PPS_EVENT_PROVEN);
}

// Only after every request is expanded and the readiness queue is drained.
// A remaining waiting component has no finite derivation. Changing-type growth
// never reaches this phase: its graph/work/capacity limit is reported earlier.
public EvidenceStatus pps_publish_root(uint link)
{
    uint2 root; uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_read2(PPS_ROOT_LINKS, link, 0u, root) ||
        !pps_work_read(root.y, key, selected, completion, source) || key.w == PEV_INVALID)
        return pev_invalid(70u, link, PPS_ROOT_LINKS);
    uint work = key.w;
    if (!pps_work_read(work, key, selected, completion, source) || key.w != work)
        return pev_invalid(70u, link, work);
    uint4 obligation; uint4 call; uint owner; bool closed;
    if (!pev_read4(16u, root.x, 0u, obligation) || !pev_read4(15u, obligation.x, 0u, call) ||
        call.x != key.x || !pev_context_goal_scope(key.x, owner, closed))
        return pev_invalid(3u, root.x, work);
    bool equal;
    EvidenceStatus status = pps_predicate_equals_goal(obligation.y, obligation.z, owner, key.y, closed, equal);
    if (status.state != PEV_VALID) return status;
    if (!equal) return pev_invalid(68u, root.x, work);
    if (key.z == PPS_WORK_FAILED || key.z == PPS_WORK_MISSING || key.z == PPS_WORK_WAITING)
    {
        // MISSING is terminal here only if its failure notification was already
        // drained; allowing it below is a diagnostic fallback, never success.
        uint detail = key.z == PPS_WORK_WAITING ? 71u : 0u;
        pev_obligation_status(root.x, 3u, detail, PEV_INVALID, selected.x,
            PEV_INVALID, 0u, 0u);
        return pev_ok();
    }
    uint4 proof; uint4 high;
    if (key.z != PPS_WORK_NOTIFIED || !pps_read8(PPS_PROOFS, completion.z, proof, high) ||
        proof.y != key.y || proof.z != key.x || (high.w != 1u && high.w != 2u))
        return pev_invalid(70u, root.x, work);
    if (!pev_output_evidence(root.x, uint4(high.w, obligation.y, obligation.z, completion.z),
        uint4(key.y, obligation.x, root.x, 0u))) return pev_invalid(1u, root.x, 5u);
    pev_obligation_status(root.x, high.w, 0u, root.x, completion.z, PEV_INVALID, 0u, 0u);
    return pev_ok();
}
