// Substitution walk dispatches shared by proof work admission and
// implementation proof admission. The walk itself is in
// proof_substitution_admission.slang.
import thread_scratch;
import type_checker.program_evidence.abi;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_work;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_substitution_admission;
import type_checker.program_evidence.proof_application_admission;
import type_checker.program_evidence.proof_frontier_selection;
import type_checker.program_evidence.proof_frontier_reduction;
import type_checker.program_evidence.proof_scratch_handoff;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.implementation_goal_matching;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;

// INTERIM (P7): a substitution walk runs as separate dispatches over one chunk
// of at most THREAD_SCRATCH_SLOTS rows, so no kernel inlines more than two of
// its normalization, root unification and constant resolution sites:
//   54_walk_substitution_goals:    the consumer's checks, then the goal stage
//                                  (normalization);
//   54_walk_substitution_roots:    the head's root unification;
//   54_walk_substitution_bindings: the binding stage (normalization and
//                                  constant resolution);
// and, for implementation proof admission only, 54_walk_substitution_roots
// again as PPS_WALK_PHASE_PREREQUISITES for the fixed prerequisite checks.
// Proof work admission (phase 54, PPS_WORK rows) and implementation proof
// admission (phase 59, PPS_REDUCTION_QUEUE rows) share these kernels. The
// walk passes from one dispatch to the next in its row's thread-scratch slot
// (SCRATCH_PPS_HANDOFF, tagged with the consumer phase, row and serial), and
// its owned constraint state frame 0 stays where the head match wrote it.
public static const uint PPS_WALK_PHASE_WORK = 54u;
public static const uint PPS_WALK_PHASE_PROOFS = 59u;
public static const uint PPS_WALK_PHASE_PREREQUISITES = 66u;
// Handoff outcomes.
static const uint PPS_WALKED_SKIP = 1u;
static const uint PPS_WALKED_GOAL = 2u;
static const uint PPS_WALKED_HEAD = 3u;
static const uint PPS_WALKED_BINDINGS = 4u;
// Handoff cells after the tag: the walk (3 cells), its state (8), the head's
// root match (2) and an implementation proof's rows (2).
static const uint PPS_WALK_CELL = SCRATCH_PPS_HANDOFF + 1u;
static const uint PPS_WALK_STATE_CELL = SCRATCH_PPS_HANDOFF + 4u;
static const uint PPS_WALK_MATCH_CELL = SCRATCH_PPS_HANDOFF + 12u;
static const uint PPS_WALK_PROOF_CELL = SCRATCH_PPS_HANDOFF + 14u;

void pps_walk_save(PpsSubstitutionWalk walk)
{
    uint flags = (walk.require_closed ? 1u : 0u) | (walk.all_closed ? 2u : 0u) |
        (walk.concrete ? 4u : 0u);
    scratch_set_cell(PPS_WALK_CELL, uint4(walk.substitution, walk.context, walk.owner, flags));
    scratch_set_cell(PPS_WALK_CELL + 1u, walk.row);
    scratch_set_cell(PPS_WALK_CELL + 2u, walk.bindings);
    pps_handoff_save_state(PPS_WALK_STATE_CELL, walk.state);
}
// The walk as pps_walk_save left it, with every field the binding stage reads
// before writing it; the rest are zero as pps_substitution_walk_begin leaves them.
PpsSubstitutionWalk pps_walk_load()
{
    PpsSubstitutionWalk walk = (PpsSubstitutionWalk)0;
    uint4 value = scratch_cell(PPS_WALK_CELL);
    walk.substitution = value.x; walk.context = value.y; walk.owner = value.z;
    walk.require_closed = (value.w & 1u) != 0u; walk.all_closed = (value.w & 2u) != 0u;
    walk.concrete = (value.w & 4u) != 0u;
    walk.row = scratch_cell(PPS_WALK_CELL + 1u);
    walk.bindings = scratch_cell(PPS_WALK_CELL + 2u);
    walk.state = pps_handoff_load_state(PPS_WALK_STATE_CELL);
    return walk;
}

// The consumer's checks before its walk: whether row `row` has a substitution
// to walk, and its (substitution, context). An implementation proof's rows are
// handed on for its prerequisite checks.
EvidenceStatus pps_walk_subject(uint consumer, uint row, out bool walks,
    out uint substitution, out uint context)
{
    walks = false; substitution = PEV_INVALID; context = PEV_INVALID;
    if (consumer == PPS_WALK_PHASE_WORK)
    {
        // A selected work walks its substitution in its caller context.
        uint4 key; uint4 selected; uint4 completion; uint4 source;
        if (!pps_work_read(row, key, selected, completion, source)) return pev_invalid(1u, row, PPS_WORK);
        walks = key.z == PPS_WORK_SELECTED;
        substitution = selected.y; context = key.x;
        return pev_ok();
    }
    // A ready implementation proof: its pending row, then its substitution.
    uint proof; uint kind;
    EvidenceStatus status = pps_read_ready_proof(row, proof, kind);
    if (status.state != PEV_VALID || kind != 1u) return status;
    uint4 low; uint4 high; uint admitted_proofs;
    if (!pps_count(PPS_PROOFS, admitted_proofs)) return pev_invalid(1u, proof, PPS_PROOFS);
    bool read = proof < admitted_proofs ? pps_read8(PPS_PROOFS, proof, low, high) :
        pps_read_pending8(PPS_PROOFS, proof, low, high);
    if (!read || low.x != 1u || (high.w != 1u && high.w != 2u))
        return pev_invalid(68u, proof, PEV_INVALID);
    uint goals; uint substitutions;
    if (!pps_building() || !pps_count(PPS_GOALS, goals) || low.y >= goals ||
        !pps_count(PPS_SUBSTITUTIONS, substitutions) || high.x >= substitutions)
        return pev_invalid(68u, proof, low.y);
    // Substitution admission is a prior stage. Rechecking it here fixes the
    // complete head match used for every prerequisite; no child may infer new
    // implementation bindings after that head has been accepted.
    uint4 row4;
    if (!pps_read4(PPS_SUBSTITUTIONS, high.x, 0u, row4) ||
        row4.x != low.w || row4.w != low.y || !pps_span(PPS_BINDINGS, row4.y, row4.z))
        return pev_invalid(68u, proof, high.x);
    scratch_set_cell(PPS_WALK_PROOF_CELL, uint4(proof, low.z, low.w, high.w));
    scratch_set_cell(PPS_WALK_PROOF_CELL + 1u, uint4(high.y, high.z, admitted_proofs, 0u));
    walks = true; substitution = high.x; context = low.z;
    return pev_ok();
}

// Goal stage: the consumer's checks, then the walk up to the head match.
public EvidenceStatus pps_walk_goals(uint consumer, uint row)
{
    bool walks; uint substitution; uint context;
    EvidenceStatus status = pps_walk_subject(consumer, row, walks, substitution, context);
    if (status.state != PEV_VALID) return status;
    if (!walks) { pps_handoff_tag(consumer, row, PPS_WALKED_SKIP); return pev_ok(); }
    PpsSubstitutionWalk walk; PpsSubstitutionCall call;
    pps_substitution_walk_begin(substitution, context, pps_matching_limits(), walk, call);
    EvidenceStatus result = pev_ok(); bool closed = false;
    [loop]
    for (;;)
    {
        status = pps_substitution_feed_goal(walk, call, result, closed);
        if (status.state != PEV_VALID) return status;
        if (call.kind == PPS_CALL_ROOTS) break;
        // Goal roots are solver proof terms (side 0).
        uint2 unused; ProofNormalizationCounts measured;
        ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
        result = pev_normalize_proof_root_on_side<SameProofNormalizationGraph<SolverProofTermGraph>,
            NoProofNormalizationBindings, NoProofNormalizationSink>(call.term, PEV_INVALID, walk.owner,
            call.domain, false, empty, 0u, unused, closed, measured);
    }
    pps_walk_save(walk);
    PevRootMatch match = call.match;
    scratch_set_cell(PPS_WALK_MATCH_CELL,
        uint4(match.subject, match.goal, match.first_root, match.argument_root));
    scratch_set_cell(PPS_WALK_MATCH_CELL + 1u, uint4(match.arguments, match.head ? 1u : 0u, 0u, 0u));
    pps_handoff_tag(consumer, row, PPS_WALKED_GOAL);
    return pev_ok();
}

// Root unification: the head match of a walk (phase PPS_WALK_PHASE_WORK or
// PPS_WALK_PHASE_PROOFS), or the fixed prerequisite checks of an implementation
// proof after its walk (PPS_WALK_PHASE_PREREQUISITES). One unification site.
public EvidenceStatus pps_walk_roots(uint phase, uint row)
{
    bool prerequisites = phase == PPS_WALK_PHASE_PREREQUISITES;
    uint consumer = prerequisites ? PPS_WALK_PHASE_PROOFS : phase;
    uint outcome;
    EvidenceStatus status = pps_handoff_outcome(consumer, row, outcome);
    if (status.state != PEV_VALID) return status;
    if (outcome == PPS_WALKED_SKIP)
    {
        if (prerequisites) pps_handoff_consume();
        return pev_ok();
    }
    if (outcome != (prerequisites ? PPS_WALKED_BINDINGS : PPS_WALKED_GOAL))
        return pev_invalid(191u, row, outcome);
    OwnedConstraintState state = pps_handoff_load_state(PPS_WALK_STATE_CELL);
    uint4 a = scratch_cell(PPS_WALK_MATCH_CELL); uint4 b = scratch_cell(PPS_WALK_MATCH_CELL + 1u);
    PevRootMatch match = { a.x, a.y, a.z, a.w, b.x, b.y != 0u };
    // An implementation proof after its walk: proof, caller context,
    // implementation, class; first edge, edge count, admitted proofs.
    uint4 proof = uint4(0u); uint4 edges_of = uint4(0u); bool concrete = false;
    uint4 edges = uint4(0u); uint4 implementation_prerequisites = uint4(0u);
    uint4 edge = uint4(0u); uint4 child_extra = uint4(0u);
    if (prerequisites)
    {
        proof = scratch_cell(PPS_WALK_PROOF_CELL); edges_of = scratch_cell(PPS_WALK_PROOF_CELL + 1u);
        concrete = (scratch_cell(PPS_WALK_CELL).w & 4u) != 0u;
        uint accepted_edges;
        if (!pps_descriptor(PPS_PROOF_EDGES, edges, accepted_edges))
            return pev_invalid(68u, proof.x, PPS_PROOF_EDGES);
        if (!pev_read4(9u, proof.z, 8u, implementation_prerequisites) ||
            edges_of.y != implementation_prerequisites.y || (edges_of.y == 0u && edges_of.x != 0u) ||
            edges_of.x > edges.y || edges_of.y > edges.y - edges_of.x)
            return pev_invalid(68u, proof.x, proof.z);
    }
    uint unit = 1u;
    [loop]
    for (;;)
    {
        if (prerequisites)
        {
            if (unit > edges_of.y) break;
            uint4 child;
            uint edge_row = edges_of.x + unit - 1u;
            bool edge_read = edge_row < edges.w ? pps_read4(PPS_PROOF_EDGES, edge_row, 0u, edge) :
                pps_read_pending4(PPS_PROOF_EDGES, edge_row, 0u, edge);
            if (!edge_read ||
                edge.x != proof.x || edge.y != implementation_prerequisites.x + unit - 1u || edge.w != 0u ||
                edge.z >= proof.x || edge.z >= edges_of.z ||
                !pps_read8(PPS_PROOFS, edge.z, child, child_extra) ||
                child.z != proof.y || (child_extra.w != 1u && child_extra.w != 2u))
                return pev_invalid(68u, proof.x, edge_row);
            // No optimistic cycles: only a previously admitted children-first row
            // can support this proof, independently of unresolved Work graph edges.
            status = pps_fixed_predicate_roots(edge.y, child.y, state.owners.x, match);
            if (status.state != PEV_VALID) return status;
        }
        status = pev_match_roots(match, state);
        if (status.state != PEV_VALID) return status;
        if (!prerequisites)
        {
            pps_handoff_save_state(PPS_WALK_STATE_CELL, state);
            pps_handoff_tag(consumer, row, PPS_WALKED_HEAD);
            return pev_ok();
        }
        if (state.status.state != OWNED_CONSTRAINT_MATCHED)
            return pev_owned_constraint_status(state.status, edge.y);
        concrete = concrete && child_extra.w == 1u;
        unit++;
    }
    pps_handoff_consume();
    if (proof.w != (concrete ? 1u : 2u)) return pev_invalid(68u, proof.x, proof.w);
    return pev_ok();
}

// Binding stage: the walk from the head match to its end.
public EvidenceStatus pps_walk_bindings(uint consumer, uint row)
{
    uint outcome;
    EvidenceStatus status = pps_handoff_outcome(consumer, row, outcome);
    if (status.state != PEV_VALID) return status;
    if (outcome == PPS_WALKED_SKIP)
    {
        if (consumer == PPS_WALK_PHASE_WORK) pps_handoff_consume();
        return pev_ok();
    }
    if (outcome != PPS_WALKED_HEAD) return pev_invalid(191u, row, outcome);
    PpsSubstitutionWalk walk = pps_walk_load();
    walk.phase = PPS_WALK_HEAD;
    PpsSubstitutionCall call = (PpsSubstitutionCall)0;
    EvidenceStatus result = pev_ok(); bool closed = false;
    [loop]
    for (;;)
    {
        status = pps_substitution_feed_bindings(walk, call, result, closed);
        if (status.state != PEV_VALID) return status;
        if (call.kind == PPS_CALL_DONE) break;
        result = pev_ok(); closed = false;
        if (call.kind == PPS_CALL_RESOLVE)
            walk.resolved = owned_constraints_resolve<CatalogImplementationPatternGraph,
                SolverProofTermGraph>(call.resolve_term, call.targets, walk.state, walk.resolution);
        else if (call.kind != PPS_CALL_SKIP)
        {
            uint2 unused; ProofNormalizationCounts measured;
            ProofNormalizationReservation empty = (ProofNormalizationReservation)0;
            result = pev_normalize_proof_root_on_side<PpsAdmissionGraphs, NoProofNormalizationBindings,
                NoProofNormalizationSink>(call.term, PEV_INVALID, walk.owner, call.domain, false, empty,
                call.side, unused, closed, measured);
        }
    }
    if (consumer == PPS_WALK_PHASE_WORK) { pps_handoff_consume(); return pev_ok(); }
    pps_walk_save(walk);
    pps_handoff_tag(consumer, row, PPS_WALKED_BINDINGS);
    return pev_ok();
}
