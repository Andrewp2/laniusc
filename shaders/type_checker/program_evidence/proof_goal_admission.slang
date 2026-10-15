// Shared semantic admission for normalized terms and a validator's own goal.
// Referenced terms and argument roots remain admitted-only throughout.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.packed_graph;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.scoped_type_hash;
import type_checker.scoped_type_scratch;

public EvidenceStatus pps_admit_term(uint2 reference, uint owner, uint domain,
    bool require_closed, out bool closed)
{
    closed = false; uint2 unpublished; ProofNormalizationCounts counts;
    ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
    EvidenceStatus status = pev_normalize_proof_root<SameProofNormalizationGraph<SolverProofTermGraph>,
        SolverProofBindings, SolverProofTermSink>(
        reference, PEV_INVALID, owner, domain, false, reservation, unpublished, closed, counts);
    if (status.state != PEV_VALID) return status;
    if (require_closed && !closed) return pev_invalid(10u, reference.y, owner);
    return pev_ok();
}
// A goal hash is a pure function of its rows. Ordinary admission recomputes
// and compares it; the stage that has just computed and recorded it from the
// same unchanged rows skips that identical second traversal.
public interface IGoalHashCheck
{
    static bool mix_root(uint2 root, uint nodes, uint atoms, inout uint hash);
    static bool matches(uint hash, uint recorded);
}
public struct RecomputedGoalHash : IGoalHashCheck
{
    [ForceInline]
    public static bool mix_root(uint2 root, uint nodes, uint atoms, inout uint hash)
    {
        uint root_hash;
        if (!scoped_type_ref_hash_scratch<SolverProofTermGraph>(root.x, root.y,
            PEV_INVALID, nodes, atoms, root_hash)) return false;
        hash = scoped_type_hash_mix(hash, root_hash);
        return true;
    }
    [ForceInline]
    public static bool matches(uint hash, uint recorded) { return hash == recorded; }
}
public struct RecordedGoalHash : IGoalHashCheck
{
    public static bool mix_root(uint2 root, uint nodes, uint atoms, inout uint hash) { return true; }
    public static bool matches(uint hash, uint recorded) { return true; }
}

[ForceInline]
public EvidenceStatus pps_admit_goal(uint goal, uint context, out bool closed)
{
    return pps_admit_goal_checked<RecomputedGoalHash>(goal, context, closed);
}
public EvidenceStatus pps_admit_goal_checked<Check : IGoalHashCheck>(uint goal, uint context,
    out bool closed)
{
    closed = false; uint4 low; uint4 high; uint owner; bool require_closed; uint state;
    uint admitted_goals;
    if (!pps_count(PPS_GOALS, admitted_goals)) return pev_invalid(1u, goal, PPS_GOALS);
    // Only this validator's own goal may still be pending. Referenced terms and
    // argument roots must already have passed their complete admission stage.
    bool read = goal < admitted_goals ? pps_read8(PPS_GOALS, goal, low, high) :
        pps_read_pending8(PPS_GOALS, goal, low, high);
    if (!read || !pev_nominal_is_valid(low.x) ||
        high.x > 32u || high.z > 1u || high.w != 0u ||
        (high.x == 0u && low.w != 0u) || !pps_span(PPS_TERM_ROOTS, low.w, high.x) ||
        !pev_context_goal_scope(context, owner, require_closed) ||
        !pev_output_read(2u, context, 0u, state) || state != PEV_VALID)
        return pev_invalid(67u, goal, context);
    uint nodes; uint atoms;
    if (!pps_count(PPS_TERM_NODES, nodes) || !pev_table_count(1u, atoms))
        return pev_invalid(1u, goal, context);
    uint hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, low.x), high.x);
    bool all_closed = true;
    [loop]
    for (uint i = 0u; i <= high.x; i++)
    {
        // Decode the captured row instead of rereading a pending goal through
        // the ordinary admitted-only pps_goal_root consumer.
        uint2 root = low.yz; bool root_closed;
        if (i != 0u && !pps_read2(PPS_TERM_ROOTS, low.w + i - 1u, 0u, root))
            return pev_invalid(1u, goal, i);
        EvidenceStatus status = pps_admit_term(root, owner,
            i == 0u ? PEV_ADMITTED_DOMAIN_TYPE : PEV_ADMITTED_DOMAIN_EITHER,
            require_closed, root_closed);
        if (status.state != PEV_VALID) return status;
        all_closed = all_closed && root_closed;
        if (!Check.mix_root(root, nodes, atoms, hash)) return pev_invalid(15u, goal, i);
    }
    if (!Check.matches(hash, high.y) || high.z != (all_closed ? 1u : 0u))
        return pev_invalid(67u, goal, context);
    closed = all_closed; return pev_ok();
}
