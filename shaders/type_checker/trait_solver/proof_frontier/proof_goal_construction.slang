// The goal of one Work: its predicate's roots copied into the proof store's
// own term namespace. A source obligation substitutes its call environment
// over the input graph. A prerequisite substitutes the bindings of the
// implementation its parent applied, whose terms are already proof-store
// terms.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.admitted_rows;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.packed_graph;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_term_graph;
import type_checker.trait_solver.proof_term_normalization;
import type_checker.trait_solver.proof_frontier.proof_work;
import type_checker.scoped_types.scoped_type_hash;
import type_checker.trait_solver.scoped_type_scratch;

// True while this lane builds a prerequisite's goal. One normalizer serves
// both sources, so a kernel expands the walk once.
static bool g_goal_substituted = false;

public struct WorkGoalGraphs : IProofNormalizationPair
{
    public static bool node(uint side, uint row, out uint4 low, out uint4 high)
    {
        if (side != 0u && g_goal_substituted) return SolverProofTermGraph.node(row, low, high);
        return InputProofNormalizationGraph.node(row, low, high);
    }
    public static bool child(uint side, uint4 low, uint4 high, uint ordinal,
        out uint2 reference, out uint domain)
    {
        if (side != 0u && g_goal_substituted)
            return SolverProofTermGraph.child(low, high, ordinal, reference, domain);
        return InputProofNormalizationGraph.child(low, high, ordinal, reference, domain);
    }
    public static bool constant_value(uint side, uint row, out uint3 value)
    {
        if (side != 0u && g_goal_substituted) return SolverProofTermGraph.constant_value(row, value);
        return InputProofNormalizationGraph.constant_value(row, value);
    }
}
public struct WorkGoalBindings : IProofNormalizationBindings
{
    public static bool replacement(uint environment, uint parameter, bool constant,
        out uint2 reference)
    {
        if (g_goal_substituted)
            return SolverProofBindings.replacement(environment, parameter, constant, reference);
        return InputProofNormalizationBindings.replacement(environment, parameter, constant, reference);
    }
}

// Each normalized compound owns a node and its own contiguous child span.
// Allocate them as the walk reaches the compound, so the lane need only
// normalize each root once. A failed walk leaves its rows unaccepted.
public struct WorkGoalSink : IProofNormalizationSink
{
    public override static bool reserve_during_walk() { return true; }
    public override static SolverStatus reserve(uint edges, uint subject, out uint node, out uint edge)
    {
        edge = 0u;
        SolverStatus status = pps_reserve(PPS_TERM_NODES, 1u, subject, node);
        if (status.state != TS_VALID || edges == 0u) return status;
        return pps_reserve(PPS_TERM_EDGES, edges, subject, edge);
    }
    public static bool begin_node(uint mode, uint row, uint4 low, uint4 high)
    { return SolverProofTermSink.begin_node(mode, row, low, high); }
    public static bool set_child(uint mode, uint row, uint slot, uint2 reference)
    { return SolverProofTermSink.set_child(mode, row, slot, reference); }
}

// A root Work's row, from source obligation `first + work`.
SolverStatus pps_begin_root_work(uint work, out uint4 key, out uint4 link)
{
    key = uint4(TS_INVALID); link = key;
    uint obligation = trait_solver_wave[PSW_OBLIGATIONS_FIRST] + work;
    uint4 source; uint4 call; uint state;
    if (!ts_read4(16u, obligation, 0u, source) || !ts_read4(15u, source.x, 0u, call) ||
        !ts_output_read(2u, call.x, 0u, state) || state != TS_VALID)
        return ts_invalid(3u, obligation, source.x);
    key = uint4(call.x, TS_INVALID, PPS_WORK_PENDING, TS_INVALID);
    link = uint4(work, source.y, source.z, TS_INVALID);
    if (!pps_write4(PPS_WORK, work, 0u, key) || !pps_write4(PPS_WORK, work, 4u, link) ||
        !pps_write4(PPS_WORK, work, 8u, uint4(TS_INVALID, TS_INVALID, 0u, 0u)) ||
        !pps_write4(PPS_WORK, work, 12u, uint4(TS_INVALID, obligation, 0u, 0u)))
        return ts_invalid(1u, obligation, work);
    return ts_ok();
}

public SolverStatus pps_build_goal(uint work)
{
    uint4 key; uint4 link; SolverStatus status;
    if (work < trait_solver_wave[PSW_ROOTS])
    {
        status = pps_begin_root_work(work, key, link);
        if (status.state != TS_VALID) return status;
    }
    else if (!pps_read4(PPS_WORK, work, 0u, key) || !pps_read4(PPS_WORK, work, 4u, link) ||
        key.z != PPS_WORK_PENDING || key.w == TS_INVALID)
        return ts_invalid(70u, work, PPS_WORK);
    g_goal_substituted = key.w != TS_INVALID;
    uint owner; bool require_closed; uint4 predicate; uint4 arguments;
    if (!ts_context_goal_scope(key.x, owner, require_closed) ||
        !ts_read8(8u, link.y, predicate, arguments) || arguments.y > 32u ||
        arguments.z != 0u || arguments.w != 0u ||
        (arguments.y == 0u && arguments.x != 0u) ||
        !ts_row_span(7u, arguments.x, arguments.y) || !ts_nominal_is_valid(predicate.z))
        return ts_invalid(65u, work, link.y);
    uint first_root; uint goal;
    status = pps_reserve(PPS_TERM_ROOTS, arguments.y, work, first_root);
    if (status.state != TS_VALID) return status;
    status = pps_reserve(PPS_GOALS, 1u, work, goal);
    if (status.state != TS_VALID) return status;
    bool all_closed = true;
    uint2 subject = uint2(0u, TS_INVALID);
    uint atoms;
    if (!ts_table_count(1u, atoms)) return ts_invalid(1u, work, 1u);
    uint hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, predicate.z), arguments.y);
    [loop]
    for (uint ordinal = 0u; ordinal <= arguments.y; ordinal++)
    {
        uint2 input;
        if (!ts_read_root(ordinal == 0u ? predicate.w : arguments.x + ordinal - 1u, input))
            return ts_invalid(1u, work, ordinal);
        ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
        uint2 normalized; bool closed; ProofNormalizationCounts measured;
        status = ts_normalize_proof_root<WorkGoalGraphs, WorkGoalBindings, WorkGoalSink>(
            input, link.z, owner, ordinal == 0u ? TS_ADMITTED_DOMAIN_TYPE : TS_ADMITTED_DOMAIN_EITHER,
            true, reservation, normalized, closed, measured);
        if (status.state != TS_VALID) return status;
        if (require_closed && !closed) return ts_invalid(10u, work, ordinal);
        all_closed = all_closed && closed;
        if (ordinal == 0u) subject = normalized;
        else if (!pps_write2(PPS_TERM_ROOTS, first_root + ordinal - 1u, 0u, normalized))
            return ts_invalid(1u, work, ordinal);
        uint nodes; uint root_hash;
        if (!pps_count(PPS_TERM_NODES, nodes)) return ts_invalid(1u, work, PPS_TERM_NODES);
        if (!scoped_type_ref_hash_scratch<SolverProofTermGraph>(normalized.x, normalized.y,
            TS_INVALID, nodes, atoms, root_hash)) return ts_invalid(15u, work, ordinal);
        hash = scoped_type_hash_mix(hash, root_hash);
    }
    if (!pps_write8(PPS_GOALS, goal,
        uint4(predicate.z, subject.x, subject.y, first_root),
        uint4(arguments.y, hash, all_closed ? 1u : 0u, 0u)) ||
        !pps_write_word(PPS_WORK, work, PPS_WORK_GOAL, goal) ||
        !pps_write_word(PPS_WORK, work, PPS_WORK_STATE, PPS_WORK_BUILT))
        return ts_invalid(1u, work, goal);
    return ts_ok();
}
