// Validate a completed implementation-application node independently of frontier
// search. Child proofs must already be admitted and precede the parent. Work
// goals, unresolved matches and frontier IDs never enter this retained format.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_goal_admission;
import type_checker.program_evidence.proof_substitution_admission;
import type_checker.program_evidence.proof_goal_equality;
import type_checker.program_evidence.replay_validation;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.implementation_goal_matching;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;

// The roots of a prerequisite predicate to recheck against the finished head
// state; pev_match_roots then unifies them without inferring bindings.
public EvidenceStatus pps_fixed_predicate_roots(uint predicate, uint goal, uint owner,
    out PevRootMatch match)
{
    uint4 pattern; uint4 args; uint4 actual; uint4 extra;
    bool valid = pev_read4(8u, predicate, 0u, pattern) && pev_read4(8u, predicate, 4u, args) &&
        pps_read8(PPS_GOALS, goal, actual, extra) && pattern.z == actual.x && args.y == extra.x &&
        args.y <= 32u && pattern.y == owner;
    match = { predicate, goal, pattern.w, args.x, args.y, false };
    return valid ? pev_ok() : pev_invalid(68u, predicate, goal);
}

// Proof8: kind, conclusion Goal, caller Context, impl/assumption source,
// substitution, first ProofEdge, child count, class(1 concrete/2 symbolic).
// Substitution4: implementation, first Binding, count, conclusion Goal.
// Binding8: substitution backlink, exact parameter atom, term tag/payload;
// owned projection-node span(first,count), two reserved zero words.
// ProofEdge4: parent proof, exact prerequisite predicate, child proof, zero.
public EvidenceStatus pps_admit_implementation_proof(uint proof, OwnedConstraintLimits limits)
{
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
    uint4 substitution;
    if (!pps_read4(PPS_SUBSTITUTIONS, high.x, 0u, substitution) ||
        substitution.x != low.w || substitution.w != low.y ||
        !pps_span(PPS_BINDINGS, substitution.y, substitution.z))
        return pev_invalid(68u, proof, high.x);
    // pps_admit_substitution(high.x, low.z, limits) as its walk (unit 0), then
    // the fixed prerequisite checks (units 1..high.z). The fixed checks unify
    // through the walk's call site, so the kernel expands one unification.
    PpsSubstitutionWalk walk; PpsSubstitutionCall call;
    pps_substitution_walk_begin(high.x, low.z, limits, walk, call);
    EvidenceStatus result = pev_ok(); bool closed = false;
    bool concrete = false;
    uint4 edges = uint4(0u); uint4 implementation_prerequisites = uint4(0u);
    uint4 edge = uint4(0u); uint4 child_extra = uint4(0u);
    uint unit = 0u;
    [loop]
    for (;;)
    {
        EvidenceStatus status;
        if (unit == 0u)
        {
            status = pps_substitution_feed(walk, call, result, closed);
            if (status.state != PEV_VALID) return status;
            if (call.kind == PPS_CALL_DONE)
            {
                concrete = walk.concrete;
                uint accepted_edges;
                if (!pps_descriptor(PPS_PROOF_EDGES, edges, accepted_edges))
                    return pev_invalid(68u, proof, PPS_PROOF_EDGES);
                if (!pev_read4(9u, low.w, 8u, implementation_prerequisites) ||
                    high.z != implementation_prerequisites.y || (high.z == 0u && high.y != 0u) ||
                    high.y > edges.y || high.z > edges.y - high.y) return pev_invalid(68u, proof, low.w);
                unit = 1u;
            }
        }
        else
        {
            if (result.state != PEV_VALID) return result;
            if (walk.state.status.state != OWNED_CONSTRAINT_MATCHED)
                return pev_owned_constraint_status(walk.state.status, edge.y);
            concrete = concrete && child_extra.w == 1u;
            unit++;
        }
        if (unit != 0u)
        {
            if (unit > high.z) break;
            uint4 child;
            uint edge_row = high.y + unit - 1u;
            bool edge_read = edge_row < edges.w ? pps_read4(PPS_PROOF_EDGES, edge_row, 0u, edge) :
                pps_read_pending4(PPS_PROOF_EDGES, edge_row, 0u, edge);
            if (!edge_read ||
                edge.x != proof || edge.y != implementation_prerequisites.x + unit - 1u || edge.w != 0u ||
                edge.z >= proof || edge.z >= admitted_proofs || !pps_read8(PPS_PROOFS, edge.z, child, child_extra) ||
                child.z != low.z || (child_extra.w != 1u && child_extra.w != 2u))
                return pev_invalid(68u, proof, edge_row);
            // No optimistic cycles: only a previously admitted children-first row
            // can support this proof, independently of unresolved Work graph edges.
            status = pps_fixed_predicate_roots(edge.y, child.y, walk.state.owners.x, call.match);
            if (status.state != PEV_VALID) return status;
            call.kind = PPS_CALL_ROOTS;
        }
        result = pps_substitution_call(walk, call, closed);
    }
    if (high.w != (concrete ? 1u : 2u)) return pev_invalid(68u, proof, high.w);
    return pev_ok();
}

// Assumption leaves retain the authority of their caller context. An original
// hypothesis stays symbolic even when its particular goal contains no rigid
// parameters. Replay hypotheses require a prior accepted concrete proof.
public EvidenceStatus pps_admit_assumption_proof(uint proof)
{
    uint admitted; uint goals; uint4 low; uint4 high;
    if (!pps_building() || !pps_count(PPS_PROOFS, admitted) || !pps_count(PPS_GOALS, goals))
        return pev_invalid(68u, proof, PPS_PROOFS);
    bool read = proof < admitted ? pps_read8(PPS_PROOFS, proof, low, high) :
        pps_read_pending8(PPS_PROOFS, proof, low, high);
    if (!read || low.x != 2u || low.y >= goals || high.x != PEV_INVALID ||
        high.y != 0u || high.z != 0u || (high.w != 1u && high.w != 2u))
        return pev_invalid(68u, proof, PEV_INVALID);
    bool conclusion_closed;
    EvidenceStatus status = pps_admit_goal(low.y, low.z, conclusion_closed);
    if (status.state != PEV_VALID) return status;
    uint4 offered; uint2 tail; uint4 context; uint4 extra;
    if (!pev_read4(14u, low.w, 0u, offered) || !pev_read2(14u, low.w, 4u, tail) ||
        any(tail != uint2(0u, 0u)) || !pev_read8(13u, low.z, context, extra) ||
        offered.x != low.z || offered.z != context.z || extra.y > 1u ||
        low.w < context.w || low.w - context.w >= extra.x)
        return pev_invalid(68u, proof, low.w);
    // The preceding complete row/context stages established the exact ordered
    // applicable-predicate identity. Frozen input rows cannot change here.
    // One comparison call site serves this proof's goal and then, for a
    // replay hypothesis, the retained prior proof's conclusion.
    bool equal;
    uint compared_goal = low.y; bool compared_closed = extra.y == 1u;
    [loop]
    for (uint comparison = 0u; comparison < 2u; comparison++)
    {
        status = pps_predicate_equals_goal(offered.y, offered.z, context.y, compared_goal,
            compared_closed, equal);
        if (status.state != PEV_VALID) return status;
        if (comparison == 1u) return equal ? pev_ok() : pev_invalid(68u, proof, offered.w);
        if (!equal) return pev_invalid(68u, proof, low.w);
        if (extra.y == 0u)
        {
            if (offered.w != PEV_INVALID || high.w != 2u)
                return pev_invalid(68u, proof, low.w);
            return pev_ok();
        }
        if (high.w != 1u || !conclusion_closed) return pev_invalid(10u, proof, low.w);
        status = pev_validate_retained_evidence(offered.w);
        if (status.state != PEV_VALID) return status;
        uint4 supplied; uint4 origin;
        if (!pev_read8(17u, offered.w, supplied, origin) || supplied.x != 1u)
            return pev_invalid(10u, proof, offered.w);
        // Exact retained provenance above proves an accepted prior proof. Compare
        // its conclusion independently; equal IDs are neither needed nor enough.
        compared_goal = origin.x; compared_closed = true;
    }
    return pev_ok();
}

