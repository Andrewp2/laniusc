import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_frontier_selection;
import type_checker.owned_type_constraint_contract;

public EvidenceStatus pps_initialize_obligation(uint obligation)
{
    uint4 source; uint4 call; uint owner; bool closed; uint state;
    if (!pev_read4(16u, obligation, 0u, source) || !pev_read4(15u, source.x, 0u, call) ||
        !pev_context_goal_scope(call.x, owner, closed) ||
        !pev_output_read(2u, call.x, 0u, state) || state != PEV_VALID)
        return pev_invalid(3u, obligation, source.x);
    uint work; uint link;
    EvidenceStatus status = pps_reserve(PPS_WORK, 1u, obligation, work);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_ROOT_LINKS, 1u, obligation, link);
    if (status.state != PEV_VALID) return status;
    if (!pps_work_write(work, uint4(call.x, PEV_INVALID, PPS_WORK_REQUEST, PEV_INVALID),
        uint4(PEV_INVALID, PEV_INVALID, link, 0u), uint4(PEV_INVALID, 0u, PEV_INVALID, obligation),
        uint4(0u, source.y, source.z, PEV_INVALID)) ||
        !pps_write2(PPS_ROOT_LINKS, link, 0u, uint2(obligation, work)))
        return pev_invalid(1u, obligation, work);
    return pev_ok();
}

// Run only after the whole substitution/binding wave was jointly admitted.
// Prerequisites retain the caller context; the impl's prerequisites never enter
// the caller assumption table. New children are request rows until normalization.
public EvidenceStatus pps_expand_work(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_SELECTED) return pev_ok();
    uint4 substitution; uint4 prerequisites;
    if (!pps_read4(PPS_SUBSTITUTIONS, selected.y, 0u, substitution) ||
        substitution.x != selected.x || substitution.w != key.y ||
        !pev_read4(9u, selected.x, 8u, prerequisites) || prerequisites.z != 0u || prerequisites.w != 0u)
        return pev_invalid(68u, work, selected.x);
    uint children; uint requirements;
    EvidenceStatus status = pps_reserve(PPS_WORK, prerequisites.y, work, children);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_REQUIREMENTS, prerequisites.y, work, requirements);
    if (status.state != PEV_VALID) return status;
    [loop]
    for (uint i = 0u; i < prerequisites.y; i++)
    {
        uint child = children + i; uint predicate = prerequisites.x + i;
        if (!pps_work_write(child, uint4(key.x, PEV_INVALID, PPS_WORK_REQUEST, PEV_INVALID),
            uint4(PEV_INVALID, PEV_INVALID, 0u, 0u),
            uint4(PEV_INVALID, 0u, PEV_INVALID, requirements + i),
            uint4(1u, predicate, selected.y, PEV_INVALID)) ||
            !pps_write4(PPS_REQUIREMENTS, requirements + i, 0u,
                uint4(work, predicate, child, PEV_INVALID))) return pev_invalid(1u, work, child);
    }
    key.z = prerequisites.y == 0u ? PPS_WORK_READY : PPS_WORK_WAITING;
    selected.zw = uint2(requirements, prerequisites.y); completion.y = prerequisites.y;
    if (!pps_work_write(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    return prerequisites.y == 0u ? pps_enqueue(work, PPS_EVENT_READY) : pev_ok();
}

public EvidenceStatus pps_mark_parent_failed(uint work)
{
    uint address;
    if (!pps_address(PPS_WORK, work, 2u, 1u, true, address)) return pev_invalid(1u, work, PPS_WORK);
    uint previous;
    InterlockedCompareExchange(program_evidence_proof_store[address], PPS_WORK_WAITING, PPS_WORK_MISSING, previous);
    if (previous == PPS_WORK_WAITING) return pps_enqueue(work, PPS_EVENT_FAILED);
    if (previous == PPS_WORK_MISSING || previous == PPS_WORK_FAILED) return pev_ok();
    return pev_invalid(70u, work, previous);
}
public EvidenceStatus pps_complete_requirement(uint parent)
{
    uint address; uint state_address;
    if (!pps_address(PPS_WORK, parent, 9u, 1u, true, address) ||
        !pps_address(PPS_WORK, parent, 2u, 1u, true, state_address))
        return pev_invalid(1u, parent, PPS_WORK);
    uint old;
    InterlockedAdd(program_evidence_proof_store[address], 0xffffffffu, old);
    if (old == 0u) return pev_invalid(70u, parent, PPS_REQUIREMENTS);
    if (old != 1u) return pev_ok();
    uint state;
    InterlockedCompareExchange(program_evidence_proof_store[state_address], PPS_WORK_WAITING, PPS_WORK_READY, state);
    if (state == PPS_WORK_WAITING) return pps_enqueue(parent, PPS_EVENT_READY);
    if (state == PPS_WORK_MISSING || state == PPS_WORK_FAILED) return pev_ok();
    return pev_invalid(70u, parent, state);
}

// Resolve child aliases before linking. Notifications run in a later dispatch.
// Already-notified children are handled immediately and never get a stale link.
public EvidenceStatus pps_link_requirement(uint requirement)
{
    uint4 edge; uint4 child; uint4 selected; uint4 completion; uint4 source;
    if (!pps_read4(PPS_REQUIREMENTS, requirement, 0u, edge) ||
        !pps_work_read(edge.z, child, selected, completion, source) ||
        child.w == PEV_INVALID) return pev_invalid(70u, requirement, PPS_REQUIREMENTS);
    uint canonical = child.w;
    if (!pps_work_read(canonical, child, selected, completion, source) || child.w != canonical ||
        child.z == PPS_WORK_ALIAS) return pev_invalid(70u, requirement, canonical);
    edge.z = canonical;
    if (child.z == PPS_WORK_NOTIFIED || child.z == PPS_WORK_FAILED)
    {
        if (!pps_write4(PPS_REQUIREMENTS, requirement, 0u, edge)) return pev_invalid(1u, requirement, canonical);
        return child.z == PPS_WORK_NOTIFIED ? pps_complete_requirement(edge.x) : pps_mark_parent_failed(edge.x);
    }
    uint address; uint active;
    if (!pps_address(PPS_WORK, canonical, 8u, 1u, true, address) ||
        !pps_count(PPS_REQUIREMENTS, active)) return pev_invalid(1u, requirement, canonical);
    uint expected = PEV_INVALID;
    [loop]
    for (uint attempt = 0u; attempt < active; attempt++)
    {
        uint previous;
        InterlockedCompareExchange(program_evidence_proof_store[address], expected, requirement, previous);
        if (previous == expected)
        {
            edge.w = previous;
            return pps_write4(PPS_REQUIREMENTS, requirement, 0u, edge) ? pev_ok() :
                pev_invalid(1u, requirement, canonical);
        }
        expected = previous;
    }
    return pev_limit(8u, requirement, active + 1u, active);
}

public EvidenceStatus pps_notify_work(uint work, bool success)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source; uint requirements;
    if (!pps_work_read(work, key, selected, completion, source) ||
        key.z != (success ? PPS_WORK_PROVEN : PPS_WORK_MISSING) ||
        !pps_count(PPS_REQUIREMENTS, requirements)) return pev_invalid(70u, work, PPS_WORK);
    uint edge = completion.x;
    [loop]
    for (uint visits = 0u; edge != PEV_INVALID; visits++)
    {
        if (visits == PEV_VISIT_LIMIT) return pev_limit(7u, work, visits + 1u, PEV_VISIT_LIMIT);
        uint4 row;
        if (edge >= requirements || !pps_read4(PPS_REQUIREMENTS, edge, 0u, row) || row.z != work)
            return pev_invalid(70u, work, edge);
        EvidenceStatus status = success ? pps_complete_requirement(row.x) : pps_mark_parent_failed(row.x);
        if (status.state != PEV_VALID) return status;
        edge = row.w;
    }
    key.z = success ? PPS_WORK_NOTIFIED : PPS_WORK_FAILED;
    return pps_write4(PPS_WORK, work, 0u, key) ? pev_ok() : pev_invalid(1u, work, PPS_WORK);
}
