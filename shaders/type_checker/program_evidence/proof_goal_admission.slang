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
        NoProofNormalizationBindings, NoProofNormalizationSink>(
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
// A goal under admission: its row, its context's scope, the table counts for
// hashing and the hash and closure of the roots admitted so far.
public struct PpsGoalAdmission
{
    public uint goal; public uint context;
    public uint4 low; public uint4 high;
    public uint owner; public bool require_closed;
    public uint nodes; public uint atoms;
    public uint hash; public bool all_closed;
}
// The goal row and scope checks before its roots (pps_admit_goal_checked).
public EvidenceStatus pps_goal_admission_begin(uint goal, uint context, out PpsGoalAdmission admission)
{
    admission = (PpsGoalAdmission)0;
    admission.goal = goal; admission.context = context;
    uint4 low; uint4 high; uint owner; bool require_closed; uint state;
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
    admission.low = low; admission.high = high;
    admission.owner = owner; admission.require_closed = require_closed;
    admission.nodes = nodes; admission.atoms = atoms;
    admission.hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, low.x), high.x);
    admission.all_closed = true;
    return pev_ok();
}
// Root i (0 = subject) and its admission domain.
public EvidenceStatus pps_goal_admission_root(PpsGoalAdmission admission, uint i,
    out uint2 root, out uint domain)
{
    // Decode the captured row instead of rereading a pending goal through
    // the ordinary admitted-only pps_goal_root consumer.
    root = admission.low.yz;
    domain = i == 0u ? PEV_ADMITTED_DOMAIN_TYPE : PEV_ADMITTED_DOMAIN_EITHER;
    if (i != 0u && !pps_read2(PPS_TERM_ROOTS, admission.low.w + i - 1u, 0u, root))
        return pev_invalid(1u, admission.goal, i);
    return pev_ok();
}
// Root i was admitted with closure `root_closed`: mix it into the hash.
public EvidenceStatus pps_goal_admission_mix<Check : IGoalHashCheck>(
    inout PpsGoalAdmission admission, uint i, uint2 root, bool root_closed)
{
    admission.all_closed = admission.all_closed && root_closed;
    if (!Check.mix_root(root, admission.nodes, admission.atoms, admission.hash))
        return pev_invalid(15u, admission.goal, i);
    return pev_ok();
}
// After every root: the recorded hash and closure.
public EvidenceStatus pps_goal_admission_finish<Check : IGoalHashCheck>(
    PpsGoalAdmission admission, out bool closed)
{
    closed = false;
    if (!Check.matches(admission.hash, admission.high.y) ||
        admission.high.z != (admission.all_closed ? 1u : 0u))
        return pev_invalid(67u, admission.goal, admission.context);
    closed = admission.all_closed; return pev_ok();
}
public EvidenceStatus pps_admit_goal_checked<Check : IGoalHashCheck>(uint goal, uint context,
    out bool closed)
{
    closed = false;
    PpsGoalAdmission admission;
    EvidenceStatus status = pps_goal_admission_begin(goal, context, admission);
    if (status.state != PEV_VALID) return status;
    [loop]
    for (uint i = 0u; i <= admission.high.x; i++)
    {
        uint2 root; uint domain; bool root_closed;
        status = pps_goal_admission_root(admission, i, root, domain);
        if (status.state != PEV_VALID) return status;
        status = pps_admit_term(root, admission.owner, domain, admission.require_closed, root_closed);
        if (status.state != PEV_VALID) return status;
        status = pps_goal_admission_mix<Check>(admission, i, root, root_closed);
        if (status.state != PEV_VALID) return status;
    }
    return pps_goal_admission_finish<Check>(admission, closed);
}
