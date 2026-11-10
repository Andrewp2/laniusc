import type_checker.trait_solver.abi;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_store_lifecycle;
import type_checker.trait_solver.proof_work;
import type_checker.trait_solver.proof_frontier_selection;
import type_checker.trait_solver.proof_binding_materialization;
import type_checker.trait_solver.proof_frontier_expansion;
import type_checker.trait_solver.proof_frontier_reduction;
import type_checker.trait_solver.proof_substitution_walk;
import type_checker.trait_solver.proof_row_admission;
import type_checker.trait_solver.proof_commit_audit;

public bool pps_stage_row(uint local, uint table, out uint row)
{
    row = TS_INVALID; uint4 span; uint accepted;
    return pps_building() && ts_batch_is_building() && pps_descriptor(table, span, accepted) &&
        ts_dispatch_row(local, span.y, row);
}
public void pps_stage_initialize_work(uint local)
{
    uint count; uint row;
    if (!pps_building() || !ts_batch_is_building() || !ts_table_count(16u, count) ||
        !ts_dispatch_row(local, count, row)) return;
    ts_batch_failure(pps_initialize_obligation(row));
}

public SolverStatus pps_admit_work_request(uint work)
{
    uint4 key; uint4 selection; uint4 completion; uint4 source;
    if (!pps_pending4(PPS_WORK, work, 0u, key) || !pps_pending4(PPS_WORK, work, 4u, selection) ||
        !pps_pending4(PPS_WORK, work, 8u, completion) || !pps_pending4(PPS_WORK, work, 12u, source) ||
        key.y != TS_INVALID || key.z != PPS_WORK_REQUEST || key.w != TS_INVALID ||
        selection.x != TS_INVALID || selection.y != TS_INVALID || selection.w != 0u ||
        completion.x != TS_INVALID || completion.y != 0u || completion.z != TS_INVALID ||
        source.x > 1u || source.w != TS_INVALID) return ts_invalid(70u, work, PPS_WORK);
    uint state; uint owner; bool closed;
    if (!ts_output_read(2u, key.x, 0u, state) || state != TS_VALID ||
        !ts_context_goal_scope(key.x, owner, closed)) return ts_invalid(3u, work, key.x);
    if (source.x == 0u)
    {
        uint4 obligation; uint4 call; uint4 links; uint accepted; uint2 link;
        if (!ts_read4(16u, completion.w, 0u, obligation) ||
            !ts_read4(15u, obligation.x, 0u, call) || call.x != key.x ||
            obligation.y != source.y || obligation.z != source.z ||
            !pps_descriptor(PPS_ROOT_LINKS, links, accepted) || selection.z < links.w ||
            selection.z >= links.y || !pps_read_pending2(PPS_ROOT_LINKS, selection.z, 0u, link) ||
            link.x != completion.w || link.y != work)
            return ts_invalid(70u, work, completion.w);
    }
    else
    {
        uint4 edge; uint4 parent; uint4 selected; uint4 parent_completion; uint4 parent_source;
        uint4 prerequisites; uint4 requirements; uint accepted;
        if (selection.z != 0u || !pps_descriptor(PPS_REQUIREMENTS, requirements, accepted) ||
            completion.w < requirements.w || completion.w >= requirements.y ||
            !pps_pending4(PPS_REQUIREMENTS, completion.w, 0u, edge) || edge.z != work ||
            edge.y != source.y || edge.w != TS_INVALID ||
            !pps_work_read(edge.x, parent, selected, parent_completion, parent_source) ||
            parent.x != key.x || parent.z != PPS_WORK_WAITING || selected.y != source.z ||
            completion.w < selected.z || completion.w - selected.z >= selected.w ||
            !ts_read4(9u, selected.x, 8u, prerequisites) || prerequisites.y != selected.w ||
            edge.y != prerequisites.x + completion.w - selected.z)
            return ts_invalid(70u, work, completion.w);
    }
    return ts_ok();
}
public void pps_stage_admit_work(uint local)
{
    uint row;
    if (pps_stage_row(local, PPS_WORK, row)) ts_batch_failure(pps_admit_work_request(row));
}

// Serial, after the complete validation wave. Check every requested prefix
// before publishing any of them. Pending counts cannot change in this phase.
// `packed` holds `count` table ids, four bits each, the first one lowest.
public SolverStatus pps_commit_tables(uint packed, uint count)
{
    if (count > 8u) return ts_invalid(66u, count, TS_INVALID);
    [loop]
    for (uint step = 0u; step < 2u * count; step++)
    {
        uint table = (packed >> (4u * (step < count ? step : step - count))) & 15u;
        uint4 span; uint accepted; SolverStatus status;
        if (!pps_descriptor(table, span, accepted)) return ts_invalid(66u, table, TS_INVALID);
        if (step < count) status = pps_check_validated_prefix(table, span.w, span.y);
        else status = pps_publish_validated_prefix(table, span.w, span.y);
        if (status.state != TS_VALID) return status;
    }
    return ts_ok();
}
// Phase 50 over the whole grid: one audit lane per pending Work row, one
// thread that reserves the goal index, one lane per pending Work row that
// writes its index row, and one thread that commits (proof_commit_audit.slang).
public void pps_stage_audit_work(uint local)
{
    uint row; uint4 source;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    pca_add(PCA_AUDITED, 1u);
    if (!pps_pending4(PPS_WORK, row, 12u, source) || source.x > 1u) { pca_fail_owner(row); return; }
    pca_add(PCA_TOTALS + source.x, 1u);
}
// The reserving thread. The audit lanes counted the pending rows by source
// kind. On any failure the later lanes and thread do nothing.
public void pps_stage_reserve_goal_index()
{
    bool building = pps_building() && ts_batch_is_building();
    uint4 work = uint4(0u, 0u, 0u, 0u); uint4 index = work; uint4 requirements = work; uint4 roots = work;
    uint accepted;
    bool described = building && pps_descriptor(PPS_WORK, work, accepted) &&
        pps_descriptor(PPS_GOAL_INDEX, index, accepted) &&
        pps_descriptor(PPS_REQUIREMENTS, requirements, accepted) &&
        pps_descriptor(PPS_ROOT_LINKS, roots, accepted) && index.y == work.w;
    uint root_sources = pca_word(PCA_TOTALS); uint requirement_sources = pca_word(PCA_TOTALS + 1u);
    uint failed = pca_word(PCA_FAILED);
    SolverStatus audit = pca_audit_verdict(work.y - work.w);
    pca_reset();
    if (!building) return;
    if (!described) { ts_batch_failure(ts_invalid(70u, PPS_WORK, PPS_GOAL_INDEX)); return; }
    if (failed != 0u) { ts_batch_failure(ts_invalid(70u, ~failed, PPS_WORK)); return; }
    if (audit.state != TS_VALID) { ts_batch_failure(audit); return; }
    // Every request proved a unique row backlink in 49. Equal counts therefore
    // cover the entire pending edge/root inventory, including unused rows.
    if (root_sources != roots.y - roots.w || requirement_sources != requirements.y - requirements.w)
    { ts_batch_failure(ts_invalid(70u, PPS_WORK, PPS_REQUIREMENTS)); return; }
    uint first;
    SolverStatus status = pps_reserve(PPS_GOAL_INDEX, work.y - work.w, PPS_WORK, first);
    if (status.state != TS_VALID) { ts_batch_failure(status); return; }
    if (work.y != work.w && first != work.w)
    { ts_batch_failure(ts_invalid(70u, first, work.w)); return; }
    trait_solver_commit_audit[PCA_PUBLISHED] = 50u;
}
public void pps_stage_write_goal_index(uint local)
{
    uint row;
    if (pca_word(PCA_PUBLISHED) != 50u || !pps_stage_row(local, PPS_WORK, row)) return;
    if (!pps_write4(PPS_GOAL_INDEX, row, 0u, uint4(0u, TS_INVALID, row, 0u)))
        ts_batch_failure(ts_invalid(1u, row, PPS_GOAL_INDEX));
}
public void pps_stage_commit_work()
{
    bool reserved = pca_word(PCA_PUBLISHED) == 50u;
    pca_reset();
    if (!reserved || !pps_building() || !ts_batch_is_building()) return;
    ts_batch_failure(pps_commit_tables(PPS_WORK | (PPS_REQUIREMENTS << 4u) | (PPS_ROOT_LINKS << 8u) |
        (PPS_REDUCTION_QUEUE << 12u) | (PPS_GOAL_INDEX << 16u), 5u));
}
public void pps_stage_index_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_WORK, row)) ts_batch_failure(pps_insert_work(row)); }
public void pps_stage_resolve_work(uint local)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_resolve_work(row);
    ts_batch_failure(status);
}
// Work selection phases; see pps_select_implementation.
public void pps_stage_select_implementations(uint local, bool coarse)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_select_implementation(row, coarse);
    ts_batch_failure(status);
}
public void pps_stage_select_assumptions(uint local)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_select_assumption(row);
    ts_batch_failure(status);
}
public void pps_stage_select_work(uint local)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_WORK, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_select_finish(row);
    ts_batch_failure(status);
}
// Substitution walk dispatches over work rows (phase 54) or ready proof
// events (phases 59 and 66); see pps_walk_goals.
uint pps_walk_table(uint phase)
{ return phase == PPS_WALK_PHASE_WORK ? PPS_WORK : PPS_REDUCTION_QUEUE; }
public void pps_stage_walk_goals(uint local, uint consumer)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, pps_walk_table(consumer), row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_walk_goals(consumer, row);
    ts_batch_failure(status);
}
public void pps_stage_walk_roots(uint local, uint phase)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, pps_walk_table(phase), row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_walk_roots(phase, row);
    ts_batch_failure(status);
}
public void pps_stage_walk_bindings(uint local, uint consumer)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, pps_walk_table(consumer), row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_walk_bindings(consumer, row);
    ts_batch_failure(status);
}
public void pps_stage_admit_binding_rows(uint local)
{ uint row; if (pps_stage_row(local, PPS_BINDINGS, row)) ts_batch_failure(pps_admit_binding_row(row)); }
// Phase 55 over the whole grid: one audit lane per Work, then one committing
// thread (proof_commit_audit.slang). A selected Work owns its substitution,
// the substitution's bindings and each binding's nodes. Exact replay
// validates bytes; this cover validates ownership. Equal requests must not
// alias an allocation and hide an unchecked row.

// The audit of one Work: the checks of the rows it owns and, when `claim` is
// set, a claim on each of them and their counts. The Work's lane claims. The
// committing thread repeats the checks of the lowest invalid Work for its
// status.
SolverStatus pps_audit_substitutions_work(uint work, bool claim)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source))
        return ts_invalid(66u, PPS_SUBSTITUTIONS, work);
    if (key.z != PPS_WORK_SELECTED) return ts_ok();
    uint4 nodes; uint4 bindings; uint4 substitutions; uint accepted; uint4 row;
    if (!pps_descriptor(PPS_TERM_NODES, nodes, accepted) ||
        !pps_descriptor(PPS_BINDINGS, bindings, accepted) ||
        !pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted))
        return ts_invalid(68u, PPS_BINDINGS, PPS_TERM_NODES);
    if (selected.y < substitutions.w || selected.y >= substitutions.y ||
        !pps_read_pending4(PPS_SUBSTITUTIONS, selected.y, 0u, row) ||
        row.x != selected.x || row.w != key.y) return ts_invalid(66u, PPS_SUBSTITUTIONS, work);
    if (row.z > 64u || !pca_pending_span(bindings, row.y, row.z))
        return ts_invalid(66u, PPS_BINDINGS, selected.y);
    uint tag = pca_tag();
    uint node_total = 0u;
    [loop]
    for (uint offset = 0u; offset < row.z; offset++)
    {
        uint4 binding; uint4 allocation;
        // At most 64 bindings below the depth limit each: the sum fits.
        if (!pps_read_pending8(PPS_BINDINGS, row.y + offset, binding, allocation) ||
            !pps_binding_node_span(allocation, true)) return ts_invalid(66u, PPS_TERM_NODES, row.y + offset);
        node_total += allocation.y;
        if (claim) pca_claim(0u, PPS_TERM_NODES, nodes, allocation.x, allocation.y, tag);
    }
    if (!claim) return ts_ok();
    pca_claim(1u, PPS_BINDINGS, bindings, row.y, row.z, tag);
    pca_claim(2u, PPS_SUBSTITUTIONS, substitutions, selected.y, 1u, tag);
    pca_add(PCA_TOTALS, node_total);
    pca_add(PCA_TOTALS + 1u, row.z);
    pca_add(PCA_TOTALS + 2u, 1u);
    return ts_ok();
}
public void pps_stage_audit_substitutions(uint local)
{
    uint works; uint work;
    if (!pps_building() || !ts_batch_is_building() || !pps_count(PPS_WORK, works) ||
        !ts_dispatch_row(local, works, work)) return;
    pca_add(PCA_AUDITED, 1u);
    if (pps_audit_substitutions_work(work, true).state != TS_VALID) pca_fail_owner(work);
}
// The lanes' verdict, in the order a walk over the Works and then the tables
// meets the failures.
SolverStatus pps_substitutions_verdict()
{
    uint works; uint failed = pca_word(PCA_FAILED);
    if (!pps_count(PPS_WORK, works)) return ts_invalid(68u, PPS_BINDINGS, PPS_TERM_NODES);
    if (failed != 0u)
    {
        SolverStatus invalid = pps_audit_substitutions_work(~failed, false);
        return invalid.state != TS_VALID ? invalid : ts_invalid(66u, PPS_SUBSTITUTIONS, ~failed);
    }
    SolverStatus status = pca_audit_verdict(works);
    [loop]
    for (uint t = 0u; t < 3u && status.state == TS_VALID; t++)
    {
        uint4 span; uint accepted;
        uint table = t == 0u ? PPS_TERM_NODES : t == 1u ? PPS_BINDINGS : PPS_SUBSTITUTIONS;
        status = pps_descriptor(table, span, accepted) ?
            pca_cover_verdict(t, table, span.y - span.w, 66u) : ts_invalid(68u, PPS_BINDINGS, PPS_TERM_NODES);
    }
    return status;
}
// The committing thread: it publishes when the lanes proved an exact cover of
// all three suffixes and otherwise reports their verdict.
public void pps_stage_commit_substitutions()
{
    bool building = pps_building() && ts_batch_is_building();
    SolverStatus status = ts_ok();
    if (building) status = pps_substitutions_verdict();
    pca_reset();
    if (!building) return;
    if (status.state == TS_VALID)
        status = pps_commit_tables(PPS_TERM_NODES | (PPS_SUBSTITUTIONS << 4u) | (PPS_BINDINGS << 8u), 3u);
    ts_batch_failure(status);
}
public void pps_stage_expand_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_WORK, row)) ts_batch_failure(pps_expand_work(row)); }
public void pps_stage_link_requirements(uint local)
{ uint row; if (pps_stage_row(local, PPS_REQUIREMENTS, row)) ts_batch_failure(pps_link_requirement(row)); }
public void pps_stage_emit_ready_proofs(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) ts_batch_failure(pps_emit_ready_proof(row)); }
public void pps_stage_admit_assumption_proofs(uint local)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_admit_ready_assumption_proof(row);
    ts_batch_failure(status);
}
public void pps_stage_admit_proof_edge_rows(uint local)
{ uint row; if (pps_stage_row(local, PPS_PROOF_EDGES, row)) ts_batch_failure(pps_admit_proof_edge_row(row)); }
public void pps_stage_commit_proofs()
{
    if (!pps_building() || !ts_batch_is_building()) return;
    ts_batch_failure(pps_commit_tables(PPS_PROOFS | (PPS_PROOF_EDGES << 4u), 2u));
}
public void pps_stage_publish_work_proofs(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) ts_batch_failure(pps_publish_work_proof(row)); }
public void pps_stage_notify_work(uint local)
{ uint row; if (pps_stage_row(local, PPS_REDUCTION_QUEUE, row)) ts_batch_failure(pps_process_notification(row)); }
public void pps_stage_commit_queue()
{
    if (!pps_building() || !ts_batch_is_building()) return;
    ts_batch_failure(pps_commit_tables(PPS_REDUCTION_QUEUE, 1u));
}
public void pps_stage_publish_roots(uint local)
{
    uint row; SolverStatus status;
    if (!pps_stage_row(local, PPS_ROOT_LINKS, row)) return;
    if (ts_bind_scratch(local, row, status)) status = pps_publish_root(row);
    ts_batch_failure(status);
}
