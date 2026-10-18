// A Work owns one complete normalization allocation. Counting, emission,
// exact source replay, candidate validation, and publication are separated by
// dispatch barriers. Only serial commit stages publish admitted prefixes.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_store_lifecycle;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_term_candidate;
import type_checker.program_evidence.proof_normalization_sources;
import type_checker.program_evidence.proof_goal_admission;
import type_checker.program_evidence.proof_span_coverage;
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
    if (count > PEV_INVALID - total) return false;
    total += count; return true;
}
uint pps_normalization_input_root(uint4 predicate, uint4 arguments, uint ordinal)
{ return ordinal == 0u ? predicate.w : arguments.x + ordinal - 1u; }
uint pps_normalization_domain(uint ordinal)
{ return ordinal == 0u ? PEV_ADMITTED_DOMAIN_TYPE : PEV_ADMITTED_DOMAIN_EITHER; }

// Source authority comes from the admitted original obligation or the exact
// admitted prerequisite edge. NormRequest rows cannot select their own source,
// caller owner, environment, or substitution.
EvidenceStatus pps_normalization_source(uint work, uint4 key, uint4 completion, uint4 source,
    out uint owner, out bool require_closed, out uint4 predicate, out uint4 arguments)
{
    owner = PEV_INVALID; require_closed = false;
    predicate = uint4(PEV_INVALID, PEV_INVALID, PEV_INVALID, PEV_INVALID); arguments = predicate;
    uint state;
    if (source.x > 1u || !pev_context_goal_scope(key.x, owner, require_closed) ||
        !pev_output_read(2u, key.x, 0u, state) || state != PEV_VALID ||
        !pev_read8(8u, source.y, predicate, arguments) || arguments.y > 32u ||
        arguments.z != 0u || arguments.w != 0u ||
        (arguments.y == 0u && arguments.x != 0u) ||
        !pev_row_span(7u, arguments.x, arguments.y) || !pev_nominal_is_valid(predicate.z))
        return pev_invalid(65u, work, source.y);
    if (source.x == 0u)
    {
        uint4 obligation; uint4 call;
        if (!pev_read4(16u, completion.w, 0u, obligation) ||
            obligation.y != source.y || obligation.z != source.z ||
            !pev_read4(15u, obligation.x, 0u, call) || call.x != key.x)
            return pev_invalid(65u, work, completion.w);
    }
    else
    {
        uint4 edge; uint4 parent; uint4 selected; uint4 finished; uint4 original;
        uint4 substitution; uint4 implementation; uint4 prerequisites;
        if (!pps_read4(PPS_REQUIREMENTS, completion.w, 0u, edge) ||
            edge.y != source.y || edge.z != work || edge.w != PEV_INVALID ||
            !pps_work_read(edge.x, parent, selected, finished, original) ||
            parent.x != key.x || selected.y != source.z ||
            completion.w < selected.z || completion.w - selected.z >= selected.w ||
            !pps_read4(PPS_SUBSTITUTIONS, source.z, 0u, substitution) ||
            substitution.x != selected.x || substitution.w != parent.y ||
            !pev_read4(9u, selected.x, 0u, implementation) || predicate.y != implementation.y ||
            !pev_read4(9u, selected.x, 8u, prerequisites) ||
            prerequisites.z != 0u || prerequisites.w != 0u ||
            prerequisites.y != selected.w || !pev_row_span(8u, prerequisites.x, prerequisites.y) ||
            source.y != prerequisites.x + (completion.w - selected.z))
            return pev_invalid(65u, work, completion.w);
    }
    return pev_ok();
}

EvidenceStatus pps_emit_normalization<Source : IWorkNormalizationSource>(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_REQUEST) return pev_ok();
    if (source.x > 1u) return pev_invalid(65u, work, source.x);
    if (source.x != Source.kind()) return pev_ok();
    if (key.y != PEV_INVALID || source.w != PEV_INVALID) return pev_invalid(65u, work, key.y);
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    EvidenceStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != PEV_VALID) return status;
    uint root_count = arguments.y + 1u;
    uint2 measured[33]; bool closures[33];
    uint node_count = 0u; uint edge_count = 0u; bool all_closed = true;
    ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint2 input; uint2 unused; bool closed; ProofNormalizationCounts count;
        if (!pev_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input))
            return pev_invalid(1u, work, ordinal);
        status = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
            false, empty, unused, closed, count);
        if (status.state != PEV_VALID) return status;
        if (require_closed && !closed) return pev_invalid(10u, work, ordinal);
        if (!pps_normalization_add(node_count, count.nodes) ||
            !pps_normalization_add(edge_count, count.edges))
            return pev_limit(64u, work, PEV_INVALID, PEV_INVALID - 1u);
        measured[ordinal] = uint2(count.nodes, count.edges); closures[ordinal] = closed;
        all_closed = all_closed && closed;
    }
    uint first_node; uint first_edge; uint first_root; uint first_request; uint goal;
    status = pps_reserve(PPS_TERM_NODES, node_count, work, first_node);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_TERM_EDGES, edge_count, work, first_edge);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_TERM_ROOTS, root_count, work, first_root);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_NORMALIZATION_REQUESTS, root_count, work, first_request);
    if (status.state != PEV_VALID) return status;
    status = pps_reserve(PPS_GOALS, 1u, work, goal);
    if (status.state != PEV_VALID) return status;
    uint node_cursor = first_node; uint edge_cursor = first_edge; uint2 subject = uint2(0u, PEV_INVALID);
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        ProofNormalizationReservation reservation;
        reservation.first_node = measured[ordinal].x == 0u ? 0u : node_cursor;
        reservation.node_count = measured[ordinal].x;
        reservation.first_edge = measured[ordinal].y == 0u ? 0u : edge_cursor;
        reservation.edge_count = measured[ordinal].y;
        uint2 input; uint2 normalized; bool closed; ProofNormalizationCounts count;
        if (!pev_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input))
            return pev_invalid(1u, work, ordinal);
        status = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
            true, reservation, normalized, closed, count);
        if (status.state != PEV_VALID) return status;
        if (count.nodes != reservation.node_count || count.edges != reservation.edge_count ||
            closed != closures[ordinal]) return pev_invalid(65u, work, ordinal);
        if (!pps_write2(PPS_TERM_ROOTS, first_root + ordinal, 0u, normalized) ||
            !pps_write8(PPS_NORMALIZATION_REQUESTS, first_request + ordinal,
                uint4(work, ordinal, first_root + ordinal, reservation.first_node),
                uint4(reservation.node_count, reservation.first_edge, reservation.edge_count, closed ? 1u : 0u)))
            return pev_invalid(1u, work, ordinal);
        if (ordinal == 0u) subject = normalized;
        node_cursor += reservation.node_count; edge_cursor += reservation.edge_count;
    }
    if (!pps_write8(PPS_GOALS, goal,
        uint4(predicate.z, subject.x, subject.y, arguments.y == 0u ? 0u : first_root + 1u),
        uint4(arguments.y, 0u, all_closed ? 1u : 0u, 0u))) return pev_invalid(1u, work, goal);
    // Preserve all selection, completion and source-provenance metadata.
    if (!pps_transient_word(PPS_WORK, work, 1u, goal) ||
        !pps_transient_word(PPS_WORK, work, 15u, first_request) ||
        !pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZATION_EMITTED))
        return pev_invalid(1u, work, PPS_WORK);
    return pev_ok();
}

EvidenceStatus pps_validate_normalization<Source : IWorkNormalizationSource>(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_NORMALIZATION_EMITTED) return pev_ok();
    if (source.x > 1u) return pev_invalid(65u, work, source.x);
    if (source.x != Source.kind()) return pev_ok();
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    EvidenceStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != PEV_VALID) return status;
    uint root_count = arguments.y + 1u; uint4 goal; uint4 extra;
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || goal.x != predicate.z ||
        extra.x != arguments.y || extra.y != 0u || extra.z > 1u || extra.w != 0u ||
        !pps_normalization_pending_span(PPS_NORMALIZATION_REQUESTS, source.w, root_count))
        return pev_invalid(65u, work, key.y);
    uint first_root = PEV_INVALID; uint next_node = PEV_INVALID; uint next_edge = PEV_INVALID;
    bool all_closed = true;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint4 request; uint4 counts; uint2 normalized;
        if (!pps_read_pending8(PPS_NORMALIZATION_REQUESTS, source.w + ordinal, request, counts) ||
            request.x != work || request.y != ordinal || counts.w > 1u ||
            !pps_normalization_pending_span(PPS_TERM_ROOTS, request.z, 1u) ||
            !pps_read_pending2(PPS_TERM_ROOTS, request.z, 0u, normalized))
            return pev_invalid(65u, work, ordinal);
        if (ordinal == 0u)
        {
            first_root = request.z;
            if (!pps_normalization_pending_span(PPS_TERM_ROOTS, first_root, root_count) ||
                any(goal.yz != normalized) || goal.w != (arguments.y == 0u ? 0u : first_root + 1u))
                return pev_invalid(65u, work, key.y);
        }
        if (request.z != first_root + ordinal ||
            !pps_normalization_pending_span(PPS_TERM_NODES, request.w, counts.x) ||
            !pps_normalization_pending_span(PPS_TERM_EDGES, counts.y, counts.z))
            return pev_invalid(65u, work, ordinal);
        if (counts.x != 0u)
        {
            if (next_node != PEV_INVALID && request.w != next_node) return pev_invalid(65u, work, ordinal);
            next_node = request.w + counts.x;
        }
        if (counts.z != 0u)
        {
            if (next_edge != PEV_INVALID && counts.y != next_edge) return pev_invalid(65u, work, ordinal);
            next_edge = counts.y + counts.z;
        }
        ProofNormalizationReservation reservation;
        reservation.first_node = request.w; reservation.node_count = counts.x;
        reservation.first_edge = counts.y; reservation.edge_count = counts.z;
        bool source_closed;
        status = Source.validate(pps_normalization_input_root(predicate, arguments, ordinal),
            source.z, owner, pps_normalization_domain(ordinal), reservation, normalized, source_closed);
        if (status.state != PEV_VALID) return status;
        // Independent candidate shape/visibility walk: pending terms still lack
        // equality/hash/matching capability, even after this check succeeds.
        uint2 unused; bool candidate_closed; ProofNormalizationCounts candidate;
        ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
        status = pev_normalize_proof_root<SameProofNormalizationGraph<CandidateProofTermGraph>,
            NoProofNormalizationBindings, NoProofNormalizationSink>(normalized, PEV_INVALID, owner,
                pps_normalization_domain(ordinal), false, empty, unused, candidate_closed, candidate);
        if (status.state != PEV_VALID) return status;
        // Exact source replay above checks every allocated row. Folding a
        // projection into Node6 can leave its checked child allocation outside
        // the reachable result; the candidate walk must not demand those rows.
        if (candidate.nodes > counts.x || candidate.edges > counts.z ||
            candidate_closed != source_closed || counts.w != (source_closed ? 1u : 0u) ||
            (require_closed && !source_closed)) return pev_invalid(65u, work, ordinal);
        all_closed = all_closed && source_closed;
    }
    if (extra.z != (all_closed ? 1u : 0u)) return pev_invalid(65u, work, key.y);
    return pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZATION_VALIDATED) ?
        pev_ok() : pev_invalid(1u, work, PPS_WORK);
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
        key.y != PEV_INVALID || source.w != PEV_INVALID) return false;
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    EvidenceStatus status = pps_normalization_source(work, key, completion, source,
        owner, require_closed, predicate, arguments);
    if (status.state != PEV_VALID) return false;
    uint root_count = arguments.y + 1u;
    ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
    bool valid = true;
    [loop]
    for (uint ordinal = 0u; ordinal < root_count; ordinal++)
    {
        uint2 input = uint2(0u, 0u); uint2 unused; bool closed;
        ProofNormalizationCounts count = (ProofNormalizationCounts)0;
        if (valid)
            valid = pev_read_root(pps_normalization_input_root(predicate, arguments, ordinal), input);
        if (valid)
            valid = Source.transform(input, source.z, owner, pps_normalization_domain(ordinal),
                false, empty, unused, closed, count).state == PEV_VALID;
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

public EvidenceStatus pps_normalize_original_work(uint work)
{ return pps_emit_normalization<OriginalWorkNormalizationSource>(work); }
public EvidenceStatus pps_normalize_prerequisite_work(uint work)
{ return pps_emit_normalization<PrerequisiteWorkNormalizationSource>(work); }
public EvidenceStatus pps_validate_original_work(uint work)
{ return pps_validate_normalization<OriginalWorkNormalizationSource>(work); }
public EvidenceStatus pps_validate_prerequisite_work(uint work)
{ return pps_validate_normalization<PrerequisiteWorkNormalizationSource>(work); }

struct PendingNormalizationRequestSpans : IProofSpanSource
{
    static bool span(uint row, uint table, out uint first, out uint count)
    {
        first = 0u; count = 0u;
        uint4 request; uint4 counts; uint4 key; uint4 selected; uint4 completion; uint4 source;
        uint4 goal; uint4 extra;
        // Reverse ownership makes every scanned request accountable to an
        // exact validated Work/ordinal, including otherwise orphaned rows.
        if (!pps_read_pending8(PPS_NORMALIZATION_REQUESTS, row, request, counts) ||
            !pps_work_read(request.x, key, selected, completion, source) ||
            key.z != PPS_WORK_NORMALIZATION_VALIDATED || row < source.w ||
            row - source.w != request.y || !pps_read_pending8(PPS_GOALS, key.y, goal, extra) ||
            extra.x > 32u || request.y > extra.x) return false;
        if (table == PPS_TERM_NODES) { first = request.w; count = counts.x; }
        else if (table == PPS_TERM_EDGES) { first = counts.y; count = counts.z; }
        else if (table == PPS_TERM_ROOTS) { first = request.z; count = 1u; }
        else return false;
        return true;
    }
}
struct PendingNormalizationWorkSpans : IProofSpanSource
{
    static bool span(uint work, uint table, out uint first, out uint count)
    {
        first = 0u; count = 0u;
        uint4 key; uint4 selected; uint4 completion; uint4 source; uint4 goal; uint4 extra;
        if (!pps_work_read(work, key, selected, completion, source)) return false;
        if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) return true;
        if (!pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u) return false;
        if (table == PPS_NORMALIZATION_REQUESTS) { first = source.w; count = extra.x + 1u; }
        else if (table == PPS_GOALS) { first = key.y; count = 1u; }
        else return false;
        return true;
    }
}

public EvidenceStatus pps_commit_normalized_terms()
{
    if (!pps_building() || !pev_batch_is_building()) return pev_invalid(66u, PPS_TERM_NODES, PEV_INVALID);
    uint4 spans[5]; uint tables[5] = {PPS_TERM_NODES, PPS_TERM_EDGES, PPS_TERM_ROOTS,
        PPS_NORMALIZATION_REQUESTS, PPS_GOALS};
    uint totals[5] = {0u, 0u, 0u, 0u, 0u}; uint accepted; uint works;
    for (uint t = 0u; t < 5u; t++)
        if (!pps_descriptor(tables[t], spans[t], accepted)) return pev_invalid(1u, tables[t], PEV_INVALID);
    if (!pps_count(PPS_WORK, works)) return pev_invalid(1u, PPS_WORK, PEV_INVALID);
    [loop]
    for (uint work = 0u; work < works; work++)
    {
        uint4 key; uint4 selected; uint4 completion; uint4 source;
        if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
        if (key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
            key.z == PPS_WORK_GOAL_VALIDATED) return pev_invalid(65u, work, key.z);
        if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) continue;
        uint4 goal; uint4 extra;
        if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
            !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u ||
            !pps_normalization_pending_span(PPS_NORMALIZATION_REQUESTS, source.w, extra.x + 1u))
            return pev_invalid(65u, work, key.y);
        for (uint ordinal = 0u; ordinal <= extra.x; ordinal++)
        {
            uint4 request; uint4 counts;
            if (!pps_read_pending8(PPS_NORMALIZATION_REQUESTS, source.w + ordinal, request, counts) ||
                request.x != work || request.y != ordinal ||
                !pps_normalization_add(totals[0], counts.x) || !pps_normalization_add(totals[1], counts.z))
                return pev_invalid(65u, work, ordinal);
        }
        if (!pps_normalization_add(totals[2], extra.x + 1u) ||
            !pps_normalization_add(totals[3], extra.x + 1u) || !pps_normalization_add(totals[4], 1u))
            return pev_limit(64u, work, PEV_INVALID, PEV_INVALID - 1u);
    }
    // Totals cheaply reject size mismatches; they do not prove disjointness.
    for (uint t = 0u; t < 5u; t++)
        if (totals[t] != spans[t].y - spans[t].w) return pev_invalid(65u, tables[t], totals[t]);
    // Independently cover all five suffixes before publishing any of them.
    // Folded child rows may be unreachable, but they still have exactly one
    // checked request owner. Share a bounded budget across the entire audit.
    uint visits = 0u;
    for (uint t = 0u; t < 3u; t++)
    {
        EvidenceStatus status = pps_check_span_cover<PendingNormalizationRequestSpans>(tables[t],
            spans[t].w, spans[t].y, spans[3].w, spans[3].y, visits);
        if (status.state != PEV_VALID) return status;
    }
    for (uint t = 3u; t < 5u; t++)
    {
        EvidenceStatus status = pps_check_span_cover<PendingNormalizationWorkSpans>(tables[t],
            spans[t].w, spans[t].y, 0u, works, visits);
        if (status.state != PEV_VALID) return status;
    }
    // Preflight every publication before changing any prefix. Goal rows remain
    // private until hash/admission completes in the following dispatch.
    for (uint t = 0u; t < 4u; t++)
    {
        EvidenceStatus status = pps_check_validated_prefix(tables[t], spans[t].w, spans[t].y);
        if (status.state != PEV_VALID) return status;
    }
    for (uint t = 0u; t < 4u; t++)
    {
        EvidenceStatus status = pps_publish_validated_prefix(tables[t], spans[t].w, spans[t].y);
        if (status.state != PEV_VALID) return status;
    }
    return pev_ok();
}

// Phase 45 as one 256-lane workgroup. The lanes audit in parallel what
// pps_commit_normalized_terms audits serially, everything before its
// preflight. True proves the serial audit succeeds, so lane 0 then runs only
// the preflight and publication (pps_publish_normalized_terms); false proves
// nothing, and lane 0 runs the serial stage for its exact result.
groupshared uint4 pps_group_normalization_spans[5];
groupshared uint pps_group_normalization_totals[5];
groupshared uint pps_group_normalization_works;
// One word per phase: a word read after one barrier is written again only
// after the next one.
groupshared uint pps_group_normalization_known;
groupshared uint pps_group_normalization_failed;

uint pps_normalization_commit_table(uint t)
{
    return t == 0u ? PPS_TERM_NODES : t == 1u ? PPS_TERM_EDGES : t == 2u ? PPS_TERM_ROOTS :
        t == 3u ? PPS_NORMALIZATION_REQUESTS : PPS_GOALS;
}
// The serial audit's checks of one Work; adds the Work's rows to the totals.
bool pps_audit_normalized_work(uint work, inout uint nodes, inout uint edges, inout uint roots,
    inout uint requests, inout uint goals)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source) ||
        key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
        key.z == PPS_WORK_GOAL_VALIDATED) return false;
    if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) return true;
    uint4 goal; uint4 extra;
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u ||
        !pps_normalization_pending_span(PPS_NORMALIZATION_REQUESTS, source.w, extra.x + 1u))
        return false;
    bool valid = true;
    [loop]
    for (uint ordinal = 0u; ordinal <= extra.x; ordinal++)
    {
        uint4 request = uint4(0u, 0u, 0u, 0u); uint4 counts = request;
        if (valid)
            valid = pps_read_pending8(PPS_NORMALIZATION_REQUESTS, source.w + ordinal, request, counts) &&
                request.x == work && request.y == ordinal;
        if (valid) valid = pps_normalization_add(nodes, counts.x) && pps_normalization_add(edges, counts.z);
    }
    return valid && pps_normalization_add(roots, extra.x + 1u) &&
        pps_normalization_add(requests, extra.x + 1u) && pps_normalization_add(goals, 1u);
}
// Adds one lane's total; a sum past 32 bits fails the audit, as it fails the
// serial count.
void pps_group_normalization_add(uint t, uint count)
{
    uint previous;
    InterlockedAdd(pps_group_normalization_totals[t], count, previous);
    if (count > PEV_INVALID - previous) InterlockedOr(pps_group_normalization_failed, 1u);
}

public bool pps_group_audit_normalized_terms(uint lane)
{
    if (lane == 0u)
    {
        uint failed = 0u;
        [loop]
        for (uint t = 0u; t < 5u; t++)
        {
            uint4 span; uint accepted;
            if (!pps_descriptor(pps_normalization_commit_table(t), span, accepted)) failed = 1u;
            pps_group_normalization_spans[t] = span;
            pps_group_normalization_totals[t] = 0u;
        }
        uint works;
        if (!pps_count(PPS_WORK, works)) failed = 1u;
        pps_group_normalization_works = works;
        pps_group_normalization_known = failed;
        pps_group_normalization_failed = 0u;
    }
    GroupMemoryBarrierWithGroupSync();
    if (pps_group_normalization_known != 0u) return false;
    uint works = pps_group_normalization_works;
    uint nodes = 0u; uint edges = 0u; uint roots = 0u; uint requests = 0u; uint goals = 0u;
    bool valid = true;
    [loop]
    for (uint work = lane; work < works && valid; work += PPS_GROUP_LANES)
        valid = pps_audit_normalized_work(work, nodes, edges, roots, requests, goals);
    if (!valid) InterlockedOr(pps_group_normalization_failed, 1u);
    pps_group_normalization_add(0u, nodes);
    pps_group_normalization_add(1u, edges);
    pps_group_normalization_add(2u, roots);
    pps_group_normalization_add(3u, requests);
    pps_group_normalization_add(4u, goals);
    GroupMemoryBarrierWithGroupSync();
    bool audited = pps_group_normalization_failed == 0u;
    [loop]
    for (uint t = 0u; t < 5u; t++)
    {
        uint4 span = pps_group_normalization_spans[t];
        audited = audited && pps_group_normalization_totals[t] == span.y - span.w;
    }
    // Pending requests own the term rows; Works own the requests and goals.
    // The audits share one visit charge, as the serial audits share a budget.
    uint4 owners = pps_group_normalization_spans[3];
    uint charges = 0u;
    [loop]
    for (uint t = 0u; t < 3u && audited; t++)
    {
        uint4 span = pps_group_normalization_spans[t];
        audited = pps_group_check_span_cover<PendingNormalizationRequestSpans>(lane,
            pps_normalization_commit_table(t), span.w, span.y, owners.w, owners.y, charges);
    }
    [loop]
    for (uint t = 3u; t < 5u && audited; t++)
    {
        uint4 span = pps_group_normalization_spans[t];
        audited = pps_group_check_span_cover<PendingNormalizationWorkSpans>(lane,
            pps_normalization_commit_table(t), span.w, span.y, 0u, works, charges);
    }
    return audited && charges <= PEV_VISIT_LIMIT;
}
// pps_commit_normalized_terms after its audit, over the spans the group
// audit read.
public EvidenceStatus pps_publish_normalized_terms()
{
    if (!pps_building() || !pev_batch_is_building()) return pev_invalid(66u, PPS_TERM_NODES, PEV_INVALID);
    EvidenceStatus status = pev_ok();
    [loop]
    for (uint t = 0u; t < 4u && status.state == PEV_VALID; t++)
    {
        uint4 span = pps_group_normalization_spans[t];
        status = pps_check_validated_prefix(pps_normalization_commit_table(t), span.w, span.y);
    }
    [loop]
    for (uint t = 0u; t < 4u && status.state == PEV_VALID; t++)
    {
        uint4 span = pps_group_normalization_spans[t];
        status = pps_publish_validated_prefix(pps_normalization_commit_table(t), span.w, span.y);
    }
    return status;
}

public EvidenceStatus pps_hash_normalized_goal(uint work)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source;
    if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
    if (key.z != PPS_WORK_NORMALIZATION_VALIDATED) return pev_ok();
    uint4 goal; uint4 extra; uint nodes; uint atoms;
    if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
        !pps_read_pending8(PPS_GOALS, key.y, goal, extra) || extra.x > 32u || extra.y != 0u ||
        !pps_count(PPS_TERM_NODES, nodes) || !pev_table_count(1u, atoms))
        return pev_invalid(65u, work, key.y);
    uint hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, goal.x), extra.x);
    [loop]
    for (uint ordinal = 0u; ordinal <= extra.x; ordinal++)
    {
        uint2 root = goal.yz; uint root_hash;
        if (ordinal != 0u && !pps_read2(PPS_TERM_ROOTS, goal.w + ordinal - 1u, 0u, root))
            return pev_invalid(1u, work, ordinal);
        if (!scoped_type_ref_hash_scratch<SolverProofTermGraph>(root.x, root.y, PEV_INVALID, nodes, atoms, root_hash))
            return pev_invalid(15u, work, ordinal);
        hash = scoped_type_hash_mix(hash, root_hash);
    }
    extra.y = hash;
    if (!pps_write8(PPS_GOALS, key.y, goal, extra)) return pev_invalid(1u, work, key.y);
    // Admission rereads the row just written; its hash already covers these
    // unchanged roots, so only the other admission checks remain.
    bool closed;
    EvidenceStatus status = pps_admit_goal_checked<RecordedGoalHash>(key.y, key.x, closed);
    if (status.state != PEV_VALID) return status;
    return pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_GOAL_VALIDATED) ?
        pev_ok() : pev_invalid(1u, work, PPS_WORK);
}

public EvidenceStatus pps_commit_normalized_goals()
{
    if (!pps_building() || !pev_batch_is_building()) return pev_invalid(66u, PPS_GOALS, PEV_INVALID);
    uint4 goals; uint accepted; uint works; uint validated = 0u;
    if (!pps_descriptor(PPS_GOALS, goals, accepted) || !pps_count(PPS_WORK, works))
        return pev_invalid(1u, PPS_GOALS, PEV_INVALID);
    [loop]
    for (uint work = 0u; work < works; work++)
    {
        uint4 key; uint4 selected; uint4 completion; uint4 source;
        if (!pps_work_read(work, key, selected, completion, source)) return pev_invalid(1u, work, PPS_WORK);
        if (key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
            key.z == PPS_WORK_NORMALIZATION_VALIDATED) return pev_invalid(65u, work, key.z);
        if (key.z != PPS_WORK_GOAL_VALIDATED) continue;
        if (!pps_normalization_pending_span(PPS_GOALS, key.y, 1u) ||
            !pps_normalization_add(validated, 1u)) return pev_invalid(65u, work, key.y);
    }
    if (validated != goals.y - goals.w) return pev_invalid(65u, PPS_GOALS, validated);
    EvidenceStatus status = pps_publish_validated_prefix(PPS_GOALS, goals.w, goals.y);
    if (status.state != PEV_VALID) return status;
    // This serial dispatch completes before indexing can consume NORMALIZED.
    [loop]
    for (uint work = 0u; work < works; work++)
    {
        uint4 key;
        if (!pps_read4(PPS_WORK, work, 0u, key)) return pev_invalid(1u, work, PPS_WORK);
        if (key.z == PPS_WORK_GOAL_VALIDATED &&
            !pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZED))
            return pev_invalid(1u, work, PPS_WORK);
    }
    return pev_ok();
}

// Phase 47 as one 256-lane workgroup, matching pps_commit_normalized_goals.
// The lanes audit the Works in parallel, including that each goal-validated
// Work's state word is writable. When the audit proves the serial audit
// succeeds, lane 0 publishes the goal prefix and then every lane marks its
// Works normalized, the writes the serial stage makes in order. Otherwise
// lane 0 runs the serial stage for its exact result.
groupshared uint pps_group_goal_validated;
groupshared uint pps_group_goal_failed;
groupshared uint pps_group_goal_published;

// The serial audit's checks of one Work; counts a goal-validated Work.
bool pps_audit_normalized_goal(uint work, inout uint validated)
{
    uint4 key; uint4 selected; uint4 completion; uint4 source; uint address;
    if (!pps_work_read(work, key, selected, completion, source) ||
        key.z == PPS_WORK_REQUEST || key.z == PPS_WORK_NORMALIZATION_EMITTED ||
        key.z == PPS_WORK_NORMALIZATION_VALIDATED) return false;
    if (key.z != PPS_WORK_GOAL_VALIDATED) return true;
    validated++;
    return pps_normalization_pending_span(PPS_GOALS, key.y, 1u) &&
        pps_address(PPS_WORK, work, 2u, 1u, true, address);
}

public void pps_group_commit_normalized_goals(uint lane)
{
    uint4 goals; uint accepted; uint works;
    bool known = pps_descriptor(PPS_GOALS, goals, accepted) && pps_count(PPS_WORK, works);
    if (lane == 0u) { pps_group_goal_validated = 0u; pps_group_goal_failed = known ? 0u : 1u; }
    GroupMemoryBarrierWithGroupSync();
    uint validated = 0u; bool valid = known;
    [loop]
    for (uint work = lane; work < works && valid; work += PPS_GROUP_LANES)
        valid = pps_audit_normalized_goal(work, validated);
    if (!valid) InterlockedOr(pps_group_goal_failed, 1u);
    InterlockedAdd(pps_group_goal_validated, validated);
    GroupMemoryBarrierWithGroupSync();
    bool audited = pps_group_goal_failed == 0u && pps_group_goal_validated == goals.y - goals.w;
    if (!audited)
    {
        if (lane == 0u) pev_batch_failure(pps_commit_normalized_goals());
        return;
    }
    // The serial stage's publication, then its Work writes.
    if (lane == 0u)
    {
        EvidenceStatus status = pps_publish_validated_prefix(PPS_GOALS, goals.w, goals.y);
        pps_group_goal_published = status.state == PEV_VALID ? 1u : 0u;
        pev_batch_failure(status);
    }
    GroupMemoryBarrierWithGroupSync();
    if (pps_group_goal_published == 0u) return;
    [loop]
    for (uint work = lane; work < works; work += PPS_GROUP_LANES)
    {
        uint4 key;
        if (pps_read4(PPS_WORK, work, 0u, key) && key.z == PPS_WORK_GOAL_VALIDATED)
            pps_transient_word(PPS_WORK, work, 2u, PPS_WORK_NORMALIZED);
    }
}
