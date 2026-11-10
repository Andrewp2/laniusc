// A Work owns one complete normalization allocation. Counting, emission,
// exact source replay, candidate validation, and publication are separated by
// dispatch barriers. Only the committing threads publish admitted prefixes.
import type_checker.trait_solver.abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.batch_io;
import type_checker.trait_solver.catalog_io;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_store_lifecycle;
import type_checker.trait_solver.proof_work;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.proof_term_normalization;
import type_checker.trait_solver.proof_term_candidate;
import type_checker.trait_solver.proof_normalization_sources;
import type_checker.trait_solver.proof_goal_admission;
import type_checker.trait_solver.proof_commit_audit;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_scratch;

// Zero-sized allocation spans have canonical first=0. Nonempty spans must be
// wholly in this wave's reserved suffix, never in an immutable admitted prefix.
bool pps_normalization_pending_span(uint table, uint first, uint count)
{
    uint4 span; uint accepted;
    if (!pps_descriptor(table, span, accepted)) return false;
    if (count == 0u) return first == 0u;
    return first >= span.w && first < span.y && count <= span.y - first;
}
bool pps_normalization_add(inout uint total, uint count)
{
    if (count > TS_INVALID - total) return false;
    total += count; return true;
}
uint pps_normalization_input_root(uint4 predicate, uint4 arguments, uint ordinal)
{ return ordinal == 0u ? predicate.w : arguments.x + ordinal - 1u; }
uint pps_normalization_domain(uint ordinal)
{ return ordinal == 0u ? TS_ADMITTED_DOMAIN_TYPE : TS_ADMITTED_DOMAIN_EITHER; }

// Source authority comes from the admitted original obligation or the exact
// admitted prerequisite edge. NormRequest rows cannot select their own source,
// caller owner, environment, or substitution.
SolverStatus pps_normalization_source(uint work, uint4 key, uint4 completion, uint4 source,
    out uint owner, out bool require_closed, out uint4 predicate, out uint4 arguments)
{
    owner = TS_INVALID; require_closed = false;
    predicate = uint4(TS_INVALID, TS_INVALID, TS_INVALID, TS_INVALID); arguments = predicate;
    uint state;
    if (source.x > 1u || !ts_context_goal_scope(key.x, owner, require_closed) ||
        !ts_output_read(2u, key.x, 0u, state) || state != TS_VALID ||
        !ts_read8(8u, source.y, predicate, arguments) || arguments.y > 32u ||
        arguments.z != 0u || arguments.w != 0u ||
        (arguments.y == 0u && arguments.x != 0u) ||
        !ts_row_span(7u, arguments.x, arguments.y) || !ts_nominal_is_valid(predicate.z))
        return ts_invalid(65u, work, source.y);
    if (source.x == 0u)
    {
        uint4 obligation; uint4 call;
        if (!ts_read4(16u, completion.w, 0u, obligation) ||
            obligation.y != source.y || obligation.z != source.z ||
            !ts_read4(15u, obligation.x, 0u, call) || call.x != key.x)
            return ts_invalid(65u, work, completion.w);
    }
    else
    {
        uint4 edge; uint4 parent; uint4 selected; uint4 finished; uint4 original;
        uint4 substitution; uint4 implementation; uint4 prerequisites;
        if (!pps_read4(PPS_REQUIREMENTS, completion.w, 0u, edge) ||
            edge.y != source.y || edge.z != work || edge.w != TS_INVALID ||
            !pps_work_read(edge.x, parent, selected, finished, original) ||
            parent.x != key.x || selected.y != source.z ||
            completion.w < selected.z || completion.w - selected.z >= selected.w ||
            !pps_read4(PPS_SUBSTITUTIONS, source.z, 0u, substitution) ||
            substitution.x != selected.x || substitution.w != parent.y ||
            !ts_read4(9u, selected.x, 0u, implementation) || predicate.y != implementation.y ||
            !ts_read4(9u, selected.x, 8u, prerequisites) ||
            prerequisites.z != 0u || prerequisites.w != 0u ||
            prerequisites.y != selected.w || !ts_row_span(8u, prerequisites.x, prerequisites.y) ||
            source.y != prerequisites.x + (completion.w - selected.z))
            return ts_invalid(65u, work, completion.w);
    }
    return ts_ok();
}

SolverStatus pps_emit_normalization<Source : IWorkNormalizationSource>(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return ts_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_REQUEST) return ts_ok();
    if (source.x > 1u) return ts_invalid(65u, work, source.x);
    if (source.x != Source.kind()) return ts_ok();
    if (key.y != TS_INVALID || source.w != TS_INVALID) return ts_invalid(65u, work, key.y);
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    SolverStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != TS_VALID) return status;
    uint root_count = arguments.y + 1u;
    uint2 measured[33]; bool closures[33];
    uint node_count = 0u; uint edge_count = 0u; bool all_closed = true;
    ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint2 input; uint2 unused; bool closed; ProofNormalizationCounts count;
        if (!ts_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input))
            return ts_invalid(1u, work, ordinal);
        status = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
            false, empty, unused, closed, count);
        if (status.state != TS_VALID) return status;
        if (require_closed && !closed) return ts_invalid(10u, work, ordinal);
        if (!pps_normalization_add(node_count, count.nodes) ||
            !pps_normalization_add(edge_count, count.edges))
            return ts_limit(64u, work, TS_INVALID, TS_INVALID - 1u);
        measured[ordinal] = uint2(count.nodes, count.edges); closures[ordinal] = closed;
        all_closed = all_closed && closed;
    }
    uint first_node; uint first_edge; uint first_root; uint first_request; uint goal;
    status = pps_reserve(PPS_TERM_NODES, node_count, work, first_node);
    if (status.state != TS_VALID) return status;
    status = pps_reserve(PPS_TERM_EDGES, edge_count, work, first_edge);
    if (status.state != TS_VALID) return status;
    status = pps_reserve(PPS_TERM_ROOTS, root_count, work, first_root);
    if (status.state != TS_VALID) return status;
    status = pps_reserve(PPS_NORMALIZATION_REQUESTS, root_count, work, first_request);
    if (status.state != TS_VALID) return status;
    status = pps_reserve(PPS_GOALS, 1u, work, goal);
    if (status.state != TS_VALID) return status;
    uint node_cursor = first_node; uint edge_cursor = first_edge; uint2 subject = uint2(0u, TS_INVALID);
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        ProofNormalizationReservation reservation;
        reservation.first_node = measured[ordinal].x == 0u ? 0u : node_cursor;
        reservation.node_count = measured[ordinal].x;
        reservation.first_edge = measured[ordinal].y == 0u ? 0u : edge_cursor;
        reservation.edge_count = measured[ordinal].y;
        uint2 input; uint2 normalized; bool closed; ProofNormalizationCounts count;
        if (!ts_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input))
            return ts_invalid(1u, work, ordinal);
        status = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
            true, reservation, normalized, closed, count);
        if (status.state != TS_VALID) return status;
        if (count.nodes != reservation.node_count || count.edges != reservation.edge_count ||
            closed != closures[ordinal]) return ts_invalid(65u, work, ordinal);
        if (!pps_write2(PPS_TERM_ROOTS, first_root + ordinal, 0u, normalized) ||
            !pps_write8(PPS_NORMALIZATION_REQUESTS, first_request + ordinal,
                uint4(work, ordinal, first_root + ordinal, reservation.first_node),
                uint4(reservation.node_count, reservation.first_edge, reservation.edge_count, closed ? 1u : 0u)))
            return ts_invalid(1u, work, ordinal);
        if (ordinal == 0u) subject = normalized;
        node_cursor += reservation.node_count; edge_cursor += reservation.edge_count;
    }
    if (!pps_write8(PPS_GOALS, goal,
        uint4(predicate.z, subject.x, subject.y, arguments.y == 0u ? 0u : first_root + 1u),
        uint4(arguments.y, 0u, all_closed ? 1u : 0u, 0u))) return ts_invalid(1u, work, goal);
    // Preserve all selection, completion and source-provenance metadata.
    if (!pps_transient_word(PPS_WORK, work, 1u, goal) ||
        !pps_transient_word(PPS_WORK, work, 15u, first_request) ||
        !pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZATION_EMITTED))
        return ts_invalid(1u, work, PPS_WORK);
    return ts_ok();
}

SolverStatus pps_validate_normalization<Source : IWorkNormalizationSource>(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return ts_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_NORMALIZATION_EMITTED) return ts_ok();
    if (source.x > 1u) return ts_invalid(65u, work, source.x);
    if (source.x != Source.kind()) return ts_ok();
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    SolverStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != TS_VALID) return status;
    uint root_count = arguments.y + 1u; uint4 goal; uint4 extra;
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || goal.x != predicate.z ||
        extra.x != arguments.y || extra.y != 0u || extra.z > 1u || extra.w != 0u ||
        !pps_normalization_pending_span(PPS_NORMALIZATION_REQUESTS, source.w, root_count))
        return ts_invalid(65u, work, key.y);
    uint first_root = TS_INVALID; uint next_node = TS_INVALID; uint next_edge = TS_INVALID;
    bool all_closed = true;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint4 request; uint4 counts; uint2 normalized;
        if (!pps_read_pending8(PPS_NORMALIZATION_REQUESTS, source.w + ordinal, request, counts) ||
            request.x != work || request.y != ordinal || counts.w > 1u ||
            !pps_normalization_pending_span(PPS_TERM_ROOTS, request.z, 1u) ||
            !pps_read_pending2(PPS_TERM_ROOTS, request.z, 0u, normalized))
            return ts_invalid(65u, work, ordinal);
        if (ordinal == 0u)
        {
            first_root = request.z;
            if (!pps_normalization_pending_span(PPS_TERM_ROOTS, first_root, root_count) ||
                any(goal.yz != normalized) || goal.w != (arguments.y == 0u ? 0u : first_root + 1u))
                return ts_invalid(65u, work, key.y);
        }
        if (request.z != first_root + ordinal ||
            !pps_normalization_pending_span(PPS_TERM_NODES, request.w, counts.x) ||
            !pps_normalization_pending_span(PPS_TERM_EDGES, counts.y, counts.z))
            return ts_invalid(65u, work, ordinal);
        if (counts.x != 0u)
        {
            if (next_node != TS_INVALID && request.w != next_node) return ts_invalid(65u, work, ordinal);
            next_node = request.w + counts.x;
        }
        if (counts.z != 0u)
        {
            if (next_edge != TS_INVALID && counts.y != next_edge) return ts_invalid(65u, work, ordinal);
            next_edge = counts.y + counts.z;
        }
        ProofNormalizationReservation reservation;
        reservation.first_node = request.w; reservation.node_count = counts.x;
        reservation.first_edge = counts.y; reservation.edge_count = counts.z;
        bool source_closed;
        status = Source.validate(pps_normalization_input_root(predicate, arguments, ordinal),
            source.z, owner, pps_normalization_domain(ordinal), reservation, normalized, source_closed);
        if (status.state != TS_VALID) return status;
        // Independent candidate shape/visibility walk: pending terms still lack
        // equality/hash/matching capability, even after this check succeeds.
        uint2 unused; bool candidate_closed; ProofNormalizationCounts candidate;
        ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
        status = ts_normalize_proof_root<SameProofNormalizationGraph<CandidateProofTermGraph>,
            NoProofNormalizationBindings, NoProofNormalizationSink>(normalized, TS_INVALID, owner,
                pps_normalization_domain(ordinal), false, empty, unused, candidate_closed, candidate);
        if (status.state != TS_VALID) return status;
        // Exact source replay above checks every allocated row. Folding a
        // projection into Node6 can leave its checked child allocation outside
        // the reachable result; the candidate walk must not demand those rows.
        if (candidate.nodes > counts.x || candidate.edges > counts.z ||
            candidate_closed != source_closed || counts.w != (source_closed ? 1u : 0u) ||
            (require_closed && !source_closed)) return ts_invalid(65u, work, ordinal);
        all_closed = all_closed && source_closed;
    }
    if (extra.z != (all_closed ? 1u : 0u)) return ts_invalid(65u, work, key.y);
    return pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZATION_VALIDATED) ?
        ts_ok() : ts_invalid(1u, work, PPS_WORK);
}

// The rows pps_emit_normalization reserves for one request Work of this
// source kind, from the same source decode and measuring transform, writing
// nothing (phases 67 and 68). Other rows count nothing, nor do rows emission
// rejects: emission reports those.
bool pps_measure_normalization<Source : IWorkNormalizationSource>(uint work,
    out uint nodes, out uint edges, out uint roots)
{
    nodes = 0u; edges = 0u; roots = 0u;
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return false;
    if (key.z != PPS_WORK_REQUEST || source.x != Source.kind() ||
        key.y != TS_INVALID || source.w != TS_INVALID) return false;
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    SolverStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != TS_VALID) return false;
    uint root_count = arguments.y + 1u;
    ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
    bool valid = true;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint2 input = uint2(0u, 0u); uint2 unused; bool closed;
        ProofNormalizationCounts count = (ProofNormalizationCounts)0;
        if (valid)
            valid = ts_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input);
        if (valid)
            valid = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
                false, empty, unused, closed, count).state == TS_VALID;
        if (valid) valid = pps_normalization_add(nodes, count.nodes);
        if (valid) valid = pps_normalization_add(edges, count.edges);
    }
    roots = root_count;
    return valid;
}
public bool pps_measure_original_work(uint work, out uint nodes, out uint edges, out uint roots)
{ return pps_measure_normalization<OriginalWorkNormalizationSource>(work, nodes, edges, roots); }
public bool pps_measure_prerequisite_work(uint work, out uint nodes, out uint edges, out uint roots)
{ return pps_measure_normalization<PrerequisiteWorkNormalizationSource>(work, nodes, edges, roots); }

public SolverStatus pps_normalize_original_work(uint work)
{ return pps_emit_normalization<OriginalWorkNormalizationSource>(work); }
public SolverStatus pps_normalize_prerequisite_work(uint work)
{ return pps_emit_normalization<PrerequisiteWorkNormalizationSource>(work); }
public SolverStatus pps_validate_original_work(uint work)
{ return pps_validate_normalization<OriginalWorkNormalizationSource>(work); }
public SolverStatus pps_validate_prerequisite_work(uint work)
{ return pps_validate_normalization<PrerequisiteWorkNormalizationSource>(work); }

// Phase 45 over the whole grid: one audit lane per Work, then one committing
// thread (proof_commit_audit.slang). A validated Work owns its goal and its
// requests, and through each request the request's nodes, edges and root.
// Folded child rows may be unreachable, but they still have exactly one
// checked request owner.
uint pps_normalization_commit_table(uint t)
{
    return t == 0u ? PPS_TERM_NODES : t == 1u ? PPS_TERM_EDGES : t == 2u ? PPS_TERM_ROOTS :
        t == 3u ? PPS_NORMALIZATION_REQUESTS : PPS_GOALS;
}
// The audit of one Work: the checks of the rows it owns and, when `claim` is
// set, a claim on each of them and their counts. The Work's lane claims. The
// committing thread repeats the checks of the lowest invalid Work for its
// status.
//
// Reverse ownership makes every request accountable to an exact validated
// Work and ordinal: the Works' request spans cover the pending requests
// exactly, so the requests reached here are every pending request, each once.
SolverStatus pps_audit_normalized_terms_work(uint work, bool claim)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return ts_invalid(1u, work, PPS_WORK);
    if (key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
        key.z == PPS_WORK_GOAL_VALIDATED) return ts_invalid(65u, work, key.z);
    if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) return ts_ok();
    uint4 nodes; uint4 edges; uint4 roots; uint4 requests; uint4 goals; uint accepted;
    if (!pps_descriptor(PPS_TERM_NODES, nodes, accepted) ||
        !pps_descriptor(PPS_TERM_EDGES, edges, accepted) ||
        !pps_descriptor(PPS_TERM_ROOTS, roots, accepted) ||
        !pps_descriptor(PPS_NORMALIZATION_REQUESTS, requests, accepted) ||
        !pps_descriptor(PPS_GOALS, goals, accepted)) return ts_invalid(1u, PPS_TERM_NODES, TS_INVALID);
    uint4 goal; uint4 extra;
    if (key.y < goals.w || key.y >= goals.y ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u ||
        !pca_pending_span(requests, source.w, extra.x + 1u)) return ts_invalid(65u, work, key.y);
    uint tag = pca_tag();
    uint node_total = 0u; uint edge_total = 0u;
    [loop]
    for (uint ordinal = 0u; ordinal <= extra.x; ordinal++)
    {
        uint row = source.w + ordinal; uint4 request; uint4 counts;
        if (!pps_read_pending8(PPS_NORMALIZATION_REQUESTS, row, request, counts) ||
            request.x != work || request.y != ordinal ||
            !pps_normalization_add(node_total, counts.x) || !pps_normalization_add(edge_total, counts.z))
            return ts_invalid(65u, work, ordinal);
        if (!pca_pending_span(nodes, request.w, counts.x)) return ts_invalid(66u, PPS_TERM_NODES, row);
        if (!pca_pending_span(edges, counts.y, counts.z)) return ts_invalid(66u, PPS_TERM_EDGES, row);
        if (!pca_pending_span(roots, request.z, 1u)) return ts_invalid(66u, PPS_TERM_ROOTS, row);
        if (!claim) continue;
        pca_claim(0u, PPS_TERM_NODES, nodes, request.w, counts.x, tag);
        pca_claim(1u, PPS_TERM_EDGES, edges, counts.y, counts.z, tag);
        pca_claim(2u, PPS_TERM_ROOTS, roots, request.z, 1u, tag);
    }
    if (!claim) return ts_ok();
    pca_claim(3u, PPS_NORMALIZATION_REQUESTS, requests, source.w, extra.x + 1u, tag);
    pca_claim(4u, PPS_GOALS, goals, key.y, 1u, tag);
    pca_add(PCA_TOTALS, node_total);
    pca_add(PCA_TOTALS + 1u, edge_total);
    pca_add(PCA_TOTALS + 2u, extra.x + 1u);
    pca_add(PCA_TOTALS + 3u, extra.x + 1u);
    pca_add(PCA_TOTALS + 4u, 1u);
    return ts_ok();
}
public void pps_stage_audit_normalized_terms(uint local)
{
    uint works; uint work;
    if (!pps_building() || !ts_batch_is_building() || !pps_count(PPS_WORK, works) ||
        !ts_dispatch_row(local, works, work)) return;
    pca_add(PCA_AUDITED, 1u);
    if (pps_audit_normalized_terms_work(work, true).state != TS_VALID) pca_fail_owner(work);
}
// The lanes' verdict, in the order a walk over the Works and then the tables
// meets the failures.
SolverStatus pps_normalized_terms_verdict()
{
    uint works; uint failed = pca_word(PCA_FAILED);
    if (!pps_count(PPS_WORK, works)) return ts_invalid(1u, PPS_WORK, TS_INVALID);
    if (failed != 0u)
    {
        SolverStatus invalid = pps_audit_normalized_terms_work(~failed, false);
        return invalid.state != TS_VALID ? invalid : ts_invalid(65u, ~failed, PPS_WORK);
    }
    SolverStatus status = pca_audit_verdict(works);
    [loop]
    for (uint t = 0u; t < 5u && status.state == TS_VALID; t++)
    {
        uint4 span; uint accepted; uint table = pps_normalization_commit_table(t);
        status = pps_descriptor(table, span, accepted) ?
            pca_cover_verdict(t, table, span.y - span.w, 65u) : ts_invalid(1u, table, TS_INVALID);
    }
    return status;
}
// Preflight every publication before changing any prefix. Goal rows remain
// private until hash/admission completes in the following dispatch.
SolverStatus pps_publish_normalized_terms()
{
    SolverStatus status = ts_ok();
    [loop]
    for (uint t = 0u; t < 4u && status.state == TS_VALID; t++)
    {
        uint4 span; uint accepted; uint table = pps_normalization_commit_table(t);
        status = pps_descriptor(table, span, accepted) ?
            pps_check_validated_prefix(table, span.w, span.y) : ts_invalid(1u, table, TS_INVALID);
    }
    [loop]
    for (uint t = 0u; t < 4u && status.state == TS_VALID; t++)
    {
        uint4 span; uint accepted; uint table = pps_normalization_commit_table(t);
        status = pps_descriptor(table, span, accepted) ?
            pps_publish_validated_prefix(table, span.w, span.y) : ts_invalid(1u, table, TS_INVALID);
    }
    return status;
}
// The committing thread of phase 45: it publishes when the lanes proved an
// exact cover of all five suffixes and otherwise reports their verdict.
public void pps_stage_commit_normalized_terms()
{
    bool building = pps_building() && ts_batch_is_building();
    SolverStatus status = ts_ok();
    if (building) status = pps_normalized_terms_verdict();
    pca_reset();
    if (!building) return;
    if (status.state == TS_VALID) status = pps_publish_normalized_terms();
    ts_batch_failure(status);
}

public SolverStatus pps_hash_normalized_goal(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return ts_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) return ts_ok();
    uint4 goal; uint4 extra; uint nodes; uint atoms;
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u || extra.y != 0u ||
        !pps_count(PPS_TERM_NODES, nodes) || !ts_table_count(1u, atoms))
        return ts_invalid(65u, work, key.y);
    uint hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, goal.x), extra.x);
    [loop]
    for (uint ordinal = 0u; ordinal <= extra.x; ordinal++)
    {
        uint2 root = goal.yz; uint root_hash;
        if (ordinal != 0u && !pps_read2(PPS_TERM_ROOTS, goal.w + ordinal - 1u, 0u, root))
            return ts_invalid(1u, work, ordinal);
        if (!scoped_type_ref_hash_scratch<SolverProofTermGraph>(root.x, root.y, TS_INVALID, nodes, atoms, root_hash))
            return ts_invalid(15u, work, ordinal);
        hash = scoped_type_hash_mix(hash, root_hash);
    }
    extra.y = hash;
    if (!pps_write8(PPS_GOALS, key.y, goal, extra)) return ts_invalid(1u, work, key.y);
    // Admission rereads the row just written; its hash already covers these
    // unchanged roots, so only the other admission checks remain.
    bool closed;
    SolverStatus status = pps_admit_goal_checked<RecordedGoalHash>(key.y, key.x, closed);
    if (status.state != TS_VALID) return status;
    return pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_GOAL_VALIDATED) ?
        ts_ok() : ts_invalid(1u, work, PPS_WORK);
}

// Phase 47 over the whole grid: one audit lane per Work, one committing
// thread, then one lane per Work again. When the audit lanes prove that the
// goal-validated Works number the pending goals and that each one's state
// word is writable, the thread publishes the goal prefix and the last lanes
// mark their Works normalized. Otherwise the thread reports the lanes'
// verdict and the last lanes do nothing.

// The checks of one Work; `validated` counts a goal-validated Work.
SolverStatus pps_audit_normalized_goal(uint work, out uint validated)
{
    validated = 0u;
    uint4 key; uint4 selected; uint4 completion; uint4 source; uint address;
    if (!pps_work_read(work, key, selected, completion, source)) return ts_invalid(1u, work, PPS_WORK);
    if (key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
        key.z == PPS_WORK_NORMALIZATION_VALIDATED) return ts_invalid(65u, work, key.z);
    if (key.z != PPS_WORK_GOAL_VALIDATED) return ts_ok();
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u)) return ts_invalid(65u, work, key.y);
    if (!pps_address(PPS_WORK, work, 2u, 1u, true, address)) return ts_invalid(1u, work, PPS_WORK);
    validated = 1u;
    return ts_ok();
}
public void pps_stage_audit_normalized_goals(uint local)
{
    uint works; uint work;
    if (!pps_building() || !ts_batch_is_building() || !pps_count(PPS_WORK, works) ||
        !ts_dispatch_row(local, works, work)) return;
    pca_add(PCA_AUDITED, 1u);
    uint validated;
    if (pps_audit_normalized_goal(work, validated).state != TS_VALID) pca_fail_owner(work);
    else pca_add(PCA_TOTALS, validated);
}
SolverStatus pps_normalized_goals_verdict(out uint4 goals)
{
    goals = uint4(0u, 0u, 0u, 0u);
    uint accepted; uint works; uint failed = pca_word(PCA_FAILED); uint validated = pca_word(PCA_TOTALS);
    if (!pps_descriptor(PPS_GOALS, goals, accepted) || !pps_count(PPS_WORK, works))
        return ts_invalid(1u, PPS_GOALS, TS_INVALID);
    if (failed != 0u)
    {
        uint unused;
        SolverStatus invalid = pps_audit_normalized_goal(~failed, unused);
        return invalid.state != TS_VALID ? invalid : ts_invalid(65u, ~failed, PPS_WORK);
    }
    SolverStatus status = pca_audit_verdict(works);
    if (status.state != TS_VALID) return status;
    return validated == goals.y - goals.w ? ts_ok() : ts_invalid(65u, PPS_GOALS, validated);
}
public void pps_stage_commit_normalized_goals()
{
    bool building = pps_building() && ts_batch_is_building();
    uint4 goals = uint4(0u, 0u, 0u, 0u);
    SolverStatus status = ts_ok();
    if (building) status = pps_normalized_goals_verdict(goals);
    pca_reset();
    if (!building) return;
    if (status.state == TS_VALID) status = pps_publish_validated_prefix(PPS_GOALS, goals.w, goals.y);
    // The marking lanes complete before indexing can consume NORMALIZED.
    if (status.state == TS_VALID) trait_solver_commit_audit[PCA_PUBLISHED] = 47u;
    ts_batch_failure(status);
}
public void pps_stage_mark_normalized_goals(uint local)
{
    uint works; uint work; uint4 key;
    if (pca_word(PCA_PUBLISHED) != 47u || !pps_count(PPS_WORK, works) ||
        !ts_dispatch_row(local, works, work)) return;
    if (!pps_read4(PPS_WORK, work, 0u, key) || (key.z == PPS_WORK_GOAL_VALIDATED &&
        !pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZED)))
        ts_batch_failure(ts_invalid(1u, work, PPS_WORK));
}
