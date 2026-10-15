// Admit one substitution together with its complete owned binding span. Only
// their declared projection-node spans may be pending. The conclusion goal
// and exact request leaves remain admitted-only. This validator reads frozen rows and publishes no
// count, proof, or substitution authority on its own.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.batch_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.proof_term_graph;
import type_checker.program_evidence.proof_term_normalization;
import type_checker.program_evidence.proof_goal_admission;
import type_checker.program_evidence.proof_binding_materialization;
import type_checker.program_evidence.proof_term_candidate;
import type_checker.program_evidence.owned_implementation_graph;
import type_checker.program_evidence.implementation_goal_matching;
import type_checker.owned_type_constraint_contract;
import type_checker.owned_type_constraint_engine;
import type_checker.scoped_type_equality;

// Substitution4: implementation, first Binding, count, conclusion Goal.
// Binding8: substitution backlink, exact parameter atom, term tag/payload;
// owned projection-node span(first,count), two reserved zero words.
//
// A substitution walk admits, in order: the conclusion goal's roots, the
// implementation head match, then each binding's request leaf and, for a
// binding owning projection nodes, its candidate value. The walk is a state
// machine: its feeds consume the result of one call and name the next, which
// the caller makes. pps_substitution_feed_goal runs up to the head match and
// pps_substitution_feed_bindings from it, so the walk's dispatches
// (proof_substitution_walk.slang) each expand one normalization, root
// unification or constant resolution site for every call of its stage.
//
// INTERIM: the normalization, unification and constant resolution called
// here still keep per-thread DFS state, moved to the thread scratch table.
// The end state (P7) compares canonical type IDs in level rounds and deletes
// these walkers and the owned constraint engine.

static const uint PPS_SIDE_CANDIDATE = 2u;
// Normalization graphs of a walk: the solver proof terms on side 0, the
// binding candidate graph (pending rows included) on side PPS_SIDE_CANDIDATE.
// A walk normalizes without an environment, so a root's side is never left.
public struct PpsAdmissionGraphs : IProofNormalizationPair
{
    public static bool node(uint side, uint row, out uint4 low, out uint4 high)
    {
        if (side == PPS_SIDE_CANDIDATE) return CandidateProofTermGraph.node(row, low, high);
        return SolverProofTermGraph.node(row, low, high);
    }
    public static bool child(uint side, uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain)
    {
        if (side == PPS_SIDE_CANDIDATE)
            return CandidateProofTermGraph.child(low, high, ordinal, reference, domain);
        return SolverProofTermGraph.child(low, high, ordinal, reference, domain);
    }
    public static bool constant_value(uint side, uint row, out uint3 value)
    {
        if (side == PPS_SIDE_CANDIDATE) return CandidateProofTermGraph.constant_value(row, value);
        return SolverProofTermGraph.constant_value(row, value);
    }
}

public static const uint PPS_CALL_START = 0u;
// Normalize `term` in `domain` on graph side `side`.
public static const uint PPS_CALL_TERM = 1u;
// pev_match_roots(match, walk.state).
public static const uint PPS_CALL_ROOTS = 2u;
// Resolve constant term `resolve_term` into target list `targets`; the
// status and value land in walk.resolved and walk.resolution.
public static const uint PPS_CALL_RESOLVE = 3u;
// Nothing to call (a constant cell the head's finish need not recheck).
public static const uint PPS_CALL_SKIP = 4u;
public static const uint PPS_CALL_DONE = 5u;
public struct PpsSubstitutionCall
{
    public uint kind;
    public uint2 term; public uint domain; public uint side;
    public uint3 resolve_term; public uint targets;
    public PevRootMatch match;
}

// The phase of the call last named.
static const uint PPS_WALK_START = 0u;
static const uint PPS_WALK_GOAL = 1u;
public static const uint PPS_WALK_HEAD = 2u;
static const uint PPS_WALK_RECHECK = 3u;
static const uint PPS_WALK_BINDING = 4u;
static const uint PPS_WALK_LEAF = 5u;
static const uint PPS_WALK_CANDIDATE = 6u;
public struct PpsSubstitutionWalk
{
    public uint substitution; public uint context;
    public OwnedConstraintLimits limits;
    public uint phase;
    // Goal root ordinal in PPS_WALK_GOAL, constant cell in PPS_WALK_RECHECK,
    // binding ordinal afterwards.
    public uint index;
    public uint4 row; public uint4 bindings;
    public PpsGoalAdmission goal;
    // Visible owner and closure requirement of the context's goal scope.
    public uint owner; public bool require_closed;
    // The head match; it retains its budgets for fixed prerequisite checks.
    public OwnedConstraintState state;
    // The last PPS_CALL_RESOLVE.
    public OwnedConstraintStatus resolved; public OwnedConstantResolution resolution;
    public uint previous; public uint2 covered; public bool all_closed;
    // The binding under admission: its rows, parameter domain (1 = constant)
    // and owned parameter index, request and leaf admission.
    public uint4 binding; public uint4 allocation; public uint domain; public uint member;
    public OwnedConstraintBindingRequest request; public bool constant; public bool value_closed;
    // Set when the walk is done: every term is closed.
    public bool concrete;
}

public void pps_substitution_walk_begin(uint substitution, uint context,
    OwnedConstraintLimits limits, out PpsSubstitutionWalk walk, out PpsSubstitutionCall call)
{
    walk = (PpsSubstitutionWalk)0;
    walk.substitution = substitution; walk.context = context; walk.limits = limits;
    walk.phase = PPS_WALK_START;
    call = (PpsSubstitutionCall)0;
    call.kind = PPS_CALL_START;
}

// Consumes `result` (and `closed`) of `call` and names the next call. The
// order of reads, checks and engine steps is exactly pps_substitution_row,
// pev_match_implementation_goal and the binding loop run in sequence. A
// failure is the walk's result.
//
// The goal stage (START and GOAL) ends by naming the head's PPS_CALL_ROOTS.
public EvidenceStatus pps_substitution_feed_goal(inout PpsSubstitutionWalk walk,
    inout PpsSubstitutionCall call, EvidenceStatus result, bool closed)
{
    if (walk.phase != PPS_WALK_START && result.state != PEV_VALID) return result;
    EvidenceStatus status;
    if (walk.phase == PPS_WALK_START)
    {
        uint4 substitutions; uint accepted;
        if (!pps_building() || !pps_descriptor(PPS_SUBSTITUTIONS, substitutions, accepted) ||
            !pps_descriptor(PPS_BINDINGS, walk.bindings, accepted) ||
            walk.substitution >= substitutions.y)
            return pev_invalid(68u, walk.substitution, PEV_INVALID);
        uint4 row;
        bool read = walk.substitution < substitutions.w
            ? pps_read4(PPS_SUBSTITUTIONS, walk.substitution, 0u, row)
            : pps_read_pending4(PPS_SUBSTITUTIONS, walk.substitution, 0u, row);
        walk.row = row;
        if (!read || row.z > 64u || (row.z == 0u && row.y != 0u) ||
            row.y > walk.bindings.y || row.z > walk.bindings.y - row.y)
            return pev_invalid(68u, walk.substitution, PEV_INVALID);
        // The goal-stage helper can inspect its own pending row. This consumer
        // must first prove that its referenced goal has already been admitted.
        uint goals;
        if (!pps_count(PPS_GOALS, goals) || row.w >= goals)
            return pev_invalid(68u, walk.substitution, row.w);
        status = pps_goal_admission_begin(row.w, walk.context, walk.goal);
        if (status.state != PEV_VALID) return status;
        walk.owner = walk.goal.owner; walk.require_closed = walk.goal.require_closed;
        walk.index = 0u;
    }
    else
    {
        // pps_admit_goal: each root as pps_admit_term, then its hash.
        if (walk.require_closed && !closed) return pev_invalid(10u, call.term.y, walk.owner);
        status = pps_goal_admission_mix<RecomputedGoalHash>(walk.goal, walk.index, call.term, closed);
        if (status.state != PEV_VALID) return status;
        walk.index++;
        if (walk.index > walk.goal.high.x)
        {
            bool conclusion_closed;
            status = pps_goal_admission_finish<RecomputedGoalHash>(walk.goal, conclusion_closed);
            if (status.state != PEV_VALID) return status;
            walk.all_closed = conclusion_closed;
            bool candidate;
            status = pev_begin_implementation_goal(walk.row.x, walk.row.w, walk.limits,
                owned_constraint_frame(0u), walk.state, call.match, candidate);
            if (status.state != PEV_VALID) return status;
            if (!candidate) return pev_invalid(68u, walk.substitution, walk.row.x);
            call.kind = PPS_CALL_ROOTS; walk.phase = PPS_WALK_HEAD;
            return pev_ok();
        }
    }
    uint2 root; uint domain;
    status = pps_goal_admission_root(walk.goal, walk.index, root, domain);
    if (status.state != PEV_VALID) return status;
    call.kind = PPS_CALL_TERM; call.term = root; call.domain = domain; call.side = 0u;
    walk.phase = PPS_WALK_GOAL;
    return pev_ok();
}

// The binding stage: from the result of the head's PPS_CALL_ROOTS (HEAD)
// through the rechecks and bindings to PPS_CALL_DONE.
public EvidenceStatus pps_substitution_feed_bindings(inout PpsSubstitutionWalk walk,
    inout PpsSubstitutionCall call, EvidenceStatus result, bool closed)
{
    if (result.state != PEV_VALID) return result;
    EvidenceStatus status;
    bool recheck = false; bool next_binding = false;
    bool binding_rest = false; bool binding_failed = false;
    if (walk.phase == PPS_WALK_HEAD)
    {
        // pev_finish_implementation_goal, its fit rechecks resolved as calls.
        if (walk.state.status.state == OWNED_CONSTRAINT_NO_MATCH)
            return pev_invalid(68u, walk.substitution, walk.row.x);
        owned_constraints_finish_checks(walk.state);
        if (walk.state.status.state != OWNED_CONSTRAINT_MATCHED)
            return pev_owned_constraint_status(walk.state.status, walk.row.x);
        walk.index = 0u; recheck = true;
    }
    else if (walk.phase == PPS_WALK_RECHECK)
    {
        // owned_constant_recheck_fits: the first failing resolution is the status.
        if (call.kind == PPS_CALL_RESOLVE && walk.resolved.state != OWNED_CONSTRAINT_MATCHED)
        {
            walk.state.status = walk.resolved;
            return pev_owned_constraint_status(walk.state.status, walk.row.x);
        }
        walk.index++; recheck = true;
    }
    else if (walk.phase == PPS_WALK_BINDING)
    {
        binding_failed = !owned_constraint_binding_resolved(walk.state, walk.resolved,
            walk.resolution, walk.request);
        binding_rest = true;
    }
    else if (walk.phase == PPS_WALK_LEAF)
    {
        // pps_materialize_binding_request: the leaf as pps_admit_term, then its targets.
        if (walk.require_closed && !closed) return pev_invalid(10u, call.term.y, walk.owner);
        walk.value_closed = closed;
        uint2 expected;
        status = pps_binding_request_targets<OwnedBindingCheckSink>(walk.request, walk.binding.y,
            walk.allocation, call.term, walk.constant, expected);
        if (status.state != PEV_VALID) return status;
        if (any(walk.binding.zw != expected))
            return pev_invalid(68u, walk.substitution, walk.binding.y);
        if (walk.allocation.y != 0u)
        {
            // Reconstruct and compare every owned row, including concrete children
            // folded out of the reachable root. Only this span may still be pending.
            call.kind = PPS_CALL_TERM; call.term = walk.binding.zw;
            call.domain = PEV_ADMITTED_DOMAIN_CONSTANT; call.side = PPS_SIDE_CANDIDATE;
            walk.phase = PPS_WALK_CANDIDATE;
            return pev_ok();
        }
        walk.all_closed = walk.all_closed && walk.value_closed;
        walk.index++; next_binding = true;
    }
    else
    {
        if (closed != walk.value_closed || (walk.require_closed && !closed))
            return pev_invalid(68u, walk.substitution, walk.binding.y);
        walk.all_closed = walk.all_closed && walk.value_closed;
        walk.index++; next_binding = true;
    }
    if (recheck)
    {
        if (walk.index < 64u)
        {
            uint3 term;
            call.kind = owned_constraints_recheck(walk.state, walk.index, term)
                ? PPS_CALL_RESOLVE : PPS_CALL_SKIP;
            call.resolve_term = term; call.targets = OWNED_TARGETS_DISCARD;
            walk.phase = PPS_WALK_RECHECK;
            return pev_ok();
        }
        walk.state.status = owned_constraint_ok(); walk.state.finished = 1u;
        // The head matches: its bindings follow.
        if (walk.row.z != walk.state.counts.x + walk.state.counts.y)
            return pev_invalid(68u, walk.substitution, walk.row.x);
        uint nodes; uint atoms;
        if (!pps_count(PPS_TERM_NODES, nodes) || !pev_table_count(1u, atoms) ||
            !pev_context_goal_scope(walk.context, walk.owner, walk.require_closed))
            return pev_invalid(1u, walk.substitution, walk.context);
        walk.previous = PEV_INVALID; walk.covered = uint2(0u, 0u);
        walk.index = 0u; next_binding = true;
    }
    if (next_binding && walk.index < walk.row.z)
    {
        uint binding_row = walk.row.y + walk.index;
        uint4 binding; uint4 allocation; uint4 parameter;
        bool binding_read = binding_row < walk.bindings.w
            ? pps_read8(PPS_BINDINGS, binding_row, binding, allocation)
            : pps_read_pending8(PPS_BINDINGS, binding_row, binding, allocation);
        walk.binding = binding; walk.allocation = allocation;
        if (!binding_read || !pps_binding_node_span(allocation, binding_row >= walk.bindings.w) ||
            binding.x != walk.substitution ||
            (walk.index != 0u && binding.y <= walk.previous) ||
            !pev_read_admitted_parameter(binding.y, parameter))
            return pev_invalid(68u, walk.substitution, binding_row);
        walk.previous = binding.y;
        walk.domain = parameter.z;
        uint member = CatalogImplementationPatternGraph.owned_parameter(
            walk.state.owners.x, binding.y, parameter.z == 1u, walk.member);
        if (member != OWNED_PARAMETER_BINDABLE || walk.member >= 32u)
            return pev_invalid(68u, walk.substitution, binding.y);
        // owned_constraint_binding, a constant's resolution as a call.
        uint3 term;
        binding_failed = !owned_constraint_binding_begin(walk.state, parameter.z == 1u, walk.member,
            walk.request, term);
        if (!binding_failed && parameter.z == 1u)
        {
            call.kind = PPS_CALL_RESOLVE; call.resolve_term = term;
            call.targets = OWNED_TARGETS_REQUEST;
            walk.phase = PPS_WALK_BINDING;
            return pev_ok();
        }
        binding_rest = true;
    }
    if (binding_rest)
    {
        if (binding_failed)
            return walk.state.status.state == OWNED_CONSTRAINT_MATCHED
                ? pev_invalid(68u, walk.substitution, PEV_INVALID)
                : pev_owned_constraint_status(walk.state.status, walk.substitution);
        uint bit = 1u << walk.member;
        if ((walk.covered[walk.domain] & bit) != 0u)
            return pev_invalid(68u, walk.substitution, walk.binding.y);
        walk.covered[walk.domain] |= bit;

        uint2 leaf;
        status = pps_binding_request_leaf(walk.request, walk.binding.y, walk.allocation, leaf,
            walk.constant);
        if (status.state != PEV_VALID) return status;
        call.kind = PPS_CALL_TERM; call.term = leaf; call.side = 0u;
        call.domain = walk.constant ? PEV_ADMITTED_DOMAIN_CONSTANT : PEV_ADMITTED_DOMAIN_TYPE;
        walk.phase = PPS_WALK_LEAF;
        return pev_ok();
    }
    if (walk.covered.x != owned_constraint_mask(walk.state.counts.x) ||
        walk.covered.y != owned_constraint_mask(walk.state.counts.y))
        return pev_invalid(68u, walk.substitution, walk.row.x);
    walk.concrete = walk.all_closed;
    call.kind = PPS_CALL_DONE;
    return pev_ok();
}
