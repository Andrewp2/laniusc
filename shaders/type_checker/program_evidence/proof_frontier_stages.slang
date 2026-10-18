import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_store_lifecycle;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_frontier_selection;
import type_checker.program_evidence.proof_binding_materialization;
import type_checker.program_evidence.proof_frontier_expansion;
import type_checker.program_evidence.proof_frontier_reduction;
import type_checker.program_evidence.proof_substitution_walk;
import type_checker.program_evidence.proof_row_admission;
import type_checker.program_evidence.proof_span_coverage;

struct PendingBindingNodeSpans : IProofSpanSource
{
    static bool span(uint binding, uint table, out uint first, out uint count)
    {
        first = 0u; count = 0u; uint4 row; uint4 allocation;
        if (table != PPS_TERM_NODES || !pps_read_pending8(PPS_BINDINGS, binding, row, allocation) ||
            !pps_binding_node_span(allocation, true)) return false;
        first = allocation.x; count = allocation.y; return true;
    }
}
struct PendingSubstitutionBindingSpans : IProofSpanSource
{
    static bool span(uint substitution, uint table, out uint first, out uint count)
    {
        first = 0u; count = 0u; uint4 row;
        if (table != PPS_BINDINGS || !pps_read_pending4(PPS_SUBSTITUTIONS, substitution, 0u, row) ||
            row.z > 64u) return false;
        first = row.y; count = row.z; return true;
    }
}
struct SelectedWorkSubstitutionSpans : IProofSpanSource
{
    static bool span(uint work, uint table, out uint first, out uint count)
    {
        first = 0u; count = 0u;
        uint4 key; uint4 selected; uint4 completion; uint4 source; uint4 row;
        if (table != PPS_SUBSTITUTIONS || !pps_work_read(work, key, selected, completion, source)) return false;
        if (key.z != PPS_WORK_SELECTED) return true;
        if (!pps_read_pending4(PPS_SUBSTITUTIONS, selected.y, 0u, row) ||
            row.x != selected.x || row.w != key.y) return false;
        first = selected.y; count = 1u; return true;
    }
}

public bool pps_stage_row(uint local, uint table, out uint row)
{
    row = PEV_INVALID; uint4 span; uint accepted;
    return pps_building() && pev_batch_is_building() && pps_descriptor(table, span, accepted) &&
        pev_dispatch_row(local, span.y, row);
}
public void pps_stage_initialize_work(uint local)
{
    uint count; uint row;
    if (!pps_building() || !pev_batch_is_building() || !pev_table_count(16u, count) ||
        !pev_dispatch_row(local, count, row)) return;
    pev_batch_failure(pps_initialize_obligation(row));
}

public EvidenceStatus pps_admit_work_request(uint work)
{
    uint4 key; uint4 selection; uint4 completion; uint4 source;
    if (!pps_pending4(PPS_WORK, work, 0u, key) || !pps_pending4(PPS_WORK, work, 4u, selection) ||
        !pps_pending4(PPS_WORK, work, 8u, completion) || !pps_pending4(PPS_WORK, work, 12u, source) ||
        key.y != PEV_INVALID || key.z != PPS_WORK_REQUEST || key.w != PEV_INVALID ||
        selection.x != PEV_INVALID || selection.y != PEV_INVALID || selection.w != 0u ||
        completion.x != PEV_INVALID || completion.y != 0u || completion.z != PEV_INVALID ||
        source.x > 1u || source.w != PEV_INVALID) return pev_invalid(70u, work, PPS_WORK);
    uint state; uint owner; bool closed;
    if (!pev_output_read(2u, key.x, 0u, state) || state != PEV_VALID ||
        !pev_context_goal_scope(key.x, owner, closed)) return pev_invalid(3u, work, key.x);
    if (source.x == 0u)
    {
        uint4 obligation; uint4 call; uint4 links; uint accepted; uint2 link;
        if (!pev_read4(16u, completion.w, 0u, obligation) ||
            !pev_read4(15u, obligation.x, 0u, call) || call.x != key.x ||
            obligation.y != source.y || obligation.z != source.z ||
            !pps_descriptor(PPS_ROOT_LINKS, links, accepted) || selection.z < links.w ||
            selection.z >= links.y || !pps_read_pending2(PPS_ROOT_LINKS, selection.z, 0u, link) ||
            link.x != completion.w || link.y != work)
            return pev_invalid(70u, work, completion.w);
    }
    else
    {
        uint4 edge; uint4 parent; uint4 selected; uint4 parent_completion; uint4 parent_source;
        uint4 prerequisites; uint4 requirements; uint accepted;
        if (selection.z != 0u || !pps_descriptor(PPS_REQUIREMENTS, requirements, accepted) ||
            completion.w < requirements.w || completion.w >= requirements.y ||
            !pps_pending4(PPS_REQUIREMENTS, completion.w, 0u, edge) || edge.z != work ||
            edge.y != source.y || edge.w != PEV_INVALID ||
            !pps_work_read(edge.x, parent, selected, parent_completion, parent_source) ||
            parent.x != key.x || parent.z != PPS_WORK_WAITING || selected.y != source.z ||
            completion.w < selected.z || completion.w - selected.z >= selected.w ||
            !pev_read4(9u, selected.x, 8u, prerequisites) || prerequisites.y != selected.w ||
            edge.y != prerequisites.x + completion.w - selected.z)
            return pev_invalid(70u, work, completion.w);
    }
    return pev_ok();
}
public void pps_stage_admit_work(uint local)
{
    uint row;
    if (pps_stage_row(local, PPS_WORK, row)) pev_batch_failure(pps_admit_work_request(row));
}

// Serial, after the complete validation wave. Check every requested prefix
// before publishing any of them. Pending counts cannot change in this phase.
public EvidenceStatus pps_commit_tables(uint tables[5], uint count)
{
    uint4 spans[5]; uint accepted;
    if (count > 5u) return pev_invalid(66u, count, PEV_INVALID);
    for (uint i = 0u; i < count; i++)
    {
        if (!pps_descriptor(tables[i], spans[i], accepted)) return pev_invalid(66u, tables[i], PEV_INVALID);
        EvidenceStatus status = pps_check_validated_prefix(tables[i], spans[i].w, spans[i].y);
        if (status.state != PEV_VALID) return status;
    }
    for (uint i = 0u; i < count; i++)
    {
        EvidenceStatus status = pps_publish_validated_prefix(tables[i], spans[i].w, spans[i].y);
        if (status.state != PEV_VALID) return status;
    }
    return pev_ok();
}
public void pps_stage_commit_work()
{
    if (!pps_building() || !pev_batch_is_building()) return;
    uint4 work; uint4 index; uint4 requirements; uint4 roots; uint accepted;
    if (!pps_descriptor(PPS_WORK, work, accepted) || !pps_descriptor(PPS_GOAL_INDEX, index, accepted) ||
        !pps_descriptor(PPS_REQUIREMENTS, requirements, accepted) || !pps_descriptor(PPS_ROOT_LINKS, roots, accepted) ||
        index.y != work.w) { pev_batch_failure(pev_invalid(70u, PPS_WORK, PPS_GOAL_INDEX)); return; }
    uint source_count[2] = { 0u, 0u };
    [loop]
    for (uint row = work.w; row < work.y; row++)
    {
        uint4 source;
        if (!pps_pending4(PPS_WORK, row, 12u, source) || source.x > 1u)
        { pev_batch_failure(pev_invalid(70u, row, PPS_WORK)); return; }
        source_count[source.x]++;
    }
    // Every request proved a unique row backlink in 49. Equal counts therefore
    // cover the entire pending edge/root inventory, including unused rows.
    if (source_count[0] != roots.y - roots.w || source_count[1] != requirements.y - requirements.w)
    { pev_batch_failure(pev_invalid(70u, PPS_WORK, PPS_REQUIREMENTS)); return; }
    uint first;
    EvidenceStatus status = pps_reserve(PPS_GOAL_INDEX, work.y - work.w, PPS_WORK, first);
    if (status.state != PEV_VALID) { pev_batch_failure(status); return; }
    if (work.y != work.w && first != work.w)
    { pev_batch_failure(pev_invalid(70u, first, work.w)); return; }
    [loop]
    for (uint row = work.w; row < work.y; row++)
        if (!pps_write4(PPS_GOAL_INDEX, row, 0u, uint4(0u, PEV_INVALID, row, 0u)))
        { pev_batch_failure(pev_invalid(1u, row, PPS_GOAL_INDEX)); return; }
    uint tables[5] = { PPS_WORK, PPS_REQUIREMENTS, PPS_ROOT_LINKS, PPS_REDUCTION_QUEUE, PPS_GOAL_INDEX };
    pev_batch_failure(pps_commit_tables(tables, 5u));
}
public void pps_stage_index_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_WORK, row)) pev_batch_failure(pps_insert_work(row)); }
public void pps_stage_resolve_work(uint local)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_resolve_work(row);
    pev_batch_failure(status);
}
// Work selection phases; see pps_select_implementation.
public void pps_stage_select_implementations(uint local, bool coarse)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_select_implementation(row, coarse);
    pev_batch_failure(status);
}
public void pps_stage_select_assumptions(uint local)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_select_assumption(row);
    pev_batch_failure(status);
}
public void pps_stage_select_work(uint local)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_select_finish(row);
    pev_batch_failure(status);
}
// Substitution walk dispatches over work rows (phase 54) or ready proof
// events (phases 59 and 66); see pps_walk_goals.
uint pps_walk_table(uint phase)
{ return phase == PPS_WALK_PHASE_WORK ? PPS_WORK : PPS_REDUCTION_QUEUE; }
public void pps_stage_walk_goals(uint local, uint consumer)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, pps_walk_table(consumer), row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_walk_goals(consumer, row);
    pev_batch_failure(status);
}
public void pps_stage_walk_roots(uint local, uint phase)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, pps_walk_table(phase), row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_walk_roots(phase, row);
    pev_batch_failure(status);
}
public void pps_stage_walk_bindings(uint local, uint consumer)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, pps_walk_table(consumer), row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_walk_bindings(consumer, row);
    pev_batch_failure(status);
}
public void pps_stage_admit_binding_rows(uint local)
{ uint row; if (pps_stage_row(local, PPS_BINDINGS, row)) pev_batch_failure(pps_admit_binding_row(row)); }
public void pps_stage_commit_substitutions()
{
    if (!pps_building() || !pev_batch_is_building()) return;
    uint4 nodes; uint4 bindings; uint4 substitutions; uint accepted; uint works;
    if (!pps_descriptor(PPS_TERM_NODES, nodes, accepted) ||
        !pps_descriptor(PPS_BINDINGS, bindings, accepted) ||
        !pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted) || !pps_count(PPS_WORK, works))
    { pev_batch_failure(pev_invalid(68u, PPS_BINDINGS, PPS_TERM_NODES)); return; }
    // Exact replay validates bytes; independent coverage validates ownership.
    // Equal requests must not alias an allocation and hide an unchecked row.
    uint visits = 0u;
    EvidenceStatus cover = pps_check_span_cover<PendingBindingNodeSpans>(PPS_TERM_NODES,
        nodes.w, nodes.y, bindings.w, bindings.y, visits);
    if (cover.state != PEV_VALID) { pev_batch_failure(cover); return; }
    cover = pps_check_span_cover<PendingSubstitutionBindingSpans>(PPS_BINDINGS,
        bindings.w, bindings.y, substitutions.w, substitutions.y, visits);
    if (cover.state != PEV_VALID) { pev_batch_failure(cover); return; }
    cover = pps_check_span_cover<SelectedWorkSubstitutionSpans>(PPS_SUBSTITUTIONS,
        substitutions.w, substitutions.y, 0u, works, visits);
    if (cover.state != PEV_VALID) { pev_batch_failure(cover); return; }
    uint tables[5] = { PPS_TERM_NODES, PPS_SUBSTITUTIONS, PPS_BINDINGS, 0u, 0u };
    pev_batch_failure(pps_commit_tables(tables, 3u));
}
// Phase 55 as one 256-lane workgroup. The lanes run the three cover audits
// together; when that proves the serial audits succeed, lane 0 commits as
// pps_stage_commit_substitutions does after them. Otherwise lane 0 runs the
// serial stage for its exact result.
public void pps_stage_commit_substitutions_group(uint lane)
{
    if (!pps_building() || !pev_batch_is_building()) return;
    uint4 nodes; uint4 bindings; uint4 substitutions; uint accepted; uint works;
    bool audited = pps_descriptor(PPS_TERM_NODES, nodes, accepted) &&
        pps_descriptor(PPS_BINDINGS, bindings, accepted) &&
        pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted) && pps_count(PPS_WORK, works);
    uint charges = 0u;
    if (audited)
        audited = pps_group_check_span_cover<PendingBindingNodeSpans>(lane, PPS_TERM_NODES,
            nodes.w, nodes.y, bindings.w, bindings.y, charges);
    if (audited)
        audited = pps_group_check_span_cover<PendingSubstitutionBindingSpans>(lane, PPS_BINDINGS,
            bindings.w, bindings.y, substitutions.w, substitutions.y, charges);
    if (audited)
        audited = pps_group_check_span_cover<SelectedWorkSubstitutionSpans>(lane, PPS_SUBSTITUTIONS,
            substitutions.w, substitutions.y, 0u, works, charges);
    if (lane != 0u) return;
    if (!audited || charges > PEV_VISIT_LIMIT) { pps_stage_commit_substitutions(); return; }
    uint tables[5] = { PPS_TERM_NODES, PPS_SUBSTITUTIONS, PPS_BINDINGS, 0u, 0u };
    pev_batch_failure(pps_commit_tables(tables, 3u));
}
public void pps_stage_expand_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_WORK, row)) pev_batch_failure(pps_expand_work(row)); }
public void pps_stage_link_requirements(uint local)
{ uint row; if (pps_stage_row(local, PPS_REQUIREMENTS, row)) pev_batch_failure(pps_link_requirement(row)); }
public void pps_stage_emit_ready_proofs(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) pev_batch_failure(pps_emit_ready_proof(row)); }
public void pps_stage_admit_assumption_proofs(uint local)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_admit_ready_assumption_proof(row);
    pev_batch_failure(status);
}
public void pps_stage_admit_proof_edge_rows(uint local)
{ uint row; if (pps_stage_row(local, PPS_PROOF_EDGES, row)) pev_batch_failure(pps_admit_proof_edge_row(row)); }
public void pps_stage_commit_proofs()
{
    if (!pps_building() || !pev_batch_is_building()) return;
    uint tables[5] = { PPS_PROOFS, PPS_PROOF_EDGES, 0u, 0u, 0u };
    pev_batch_failure(pps_commit_tables(tables, 2u));
}
public void pps_stage_publish_work_proofs(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) pev_batch_failure(pps_publish_work_proof(row)); }
public void pps_stage_notify_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) pev_batch_failure(pps_process_notification(row)); }
public void pps_stage_commit_queue()
{
    if (!pps_building() || !pev_batch_is_building()) return;
    uint tables[5] = { PPS_REDUCTION_QUEUE, 0u, 0u, 0u, 0u };
    pev_batch_failure(pps_commit_tables(tables, 1u));
}
public void pps_stage_publish_roots(uint local)
{
    uint row; EvidenceStatus status;
    if (!pps_stage_row(local, PPS_ROOT_LINKS, row)) return;
    if (pev_bind_scratch(local, row, status)) status = pps_publish_root(row);
    pev_batch_failure(status);
}
