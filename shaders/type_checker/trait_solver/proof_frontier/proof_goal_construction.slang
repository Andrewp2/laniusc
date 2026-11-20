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

// Each root is counted, then emitted into rows reserved for exactly that
// count. The counts of the roots wait in the goal's Root2 rows, which the
// emission then overwrites with the roots. One loop holds the normalizer's
// one call site and the one reservation site.
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
    uint root_count = arguments.y + 1u;
    uint first_root = 0u; uint goal = 0u; uint node_cursor = 0u; uint edge_cursor = 0u;
    uint node_count = 0u; uint edge_count = 0u; bool all_closed = true;
    uint2 subject = uint2(0u, TS_INVALID);
    uint nodes = 0u; uint atoms;
    if (!ts_table_count(1u, atoms)) return ts_invalid(1u, work, 1u);
    uint hash = scoped_type_hash_mix(scoped_type_hash_mix(2166136261u, predicate.z), arguments.y);
    [loop]
    for (uint step = 0u; step < 2u * root_count; step++)
    {
        bool emit = step >= root_count;
        uint ordinal = emit ? step - root_count : step;
        if (ordinal == 0u)
        {
            // Before counting: the goal and its roots. Before emitting: the
            // nodes and edges of every root.
            uint2 reserved = uint2(0u);
            [loop]
            for (uint unit = 0u; unit < 2u; unit++)
            {
                uint table = emit ? (unit == 0u ? PPS_TERM_NODES : PPS_TERM_EDGES) :
                    (unit == 0u ? PPS_TERM_ROOTS : PPS_GOALS);
                uint count = emit ? (unit == 0u ? node_count : edge_count) :
                    (unit == 0u ? root_count : 1u);
                uint first;
                status = pps_reserve(table, count, work, first);
                if (status.state != TS_VALID) return status;
                reserved[unit] = first;
            }
            if (emit)
            {
                node_cursor = reserved.x; edge_cursor = reserved.y;
                if (!pps_count(PPS_TERM_NODES, nodes)) return ts_invalid(1u, work, PPS_TERM_NODES);
            }
            else { first_root = reserved.x; goal = reserved.y; }
        }
        uint2 input; uint2 counted = uint2(0u);
        if (!ts_read_root(ordinal == 0u ? predicate.w : arguments.x + ordinal - 1u, input) ||
            (emit && !pps_read2(PPS_TERM_ROOTS, first_root + ordinal, 0u, counted)))
            return ts_invalid(1u, work, ordinal);
        ProofNormalizationReservation reservation = (ProofNormalizationReservation)0;
        reservation.first_node = counted.x == 0u ? 0u : node_cursor;
        reservation.node_count = counted.x;
        reservation.first_edge = counted.y == 0u ? 0u : edge_cursor;
        reservation.edge_count = counted.y;
        uint2 normalized; bool closed; ProofNormalizationCounts measured;
        status = ts_normalize_proof_root<WorkGoalGraphs, WorkGoalBindings, SolverProofTermSink>(
            input, link.z, owner, ordinal == 0u ? TS_ADMITTED_DOMAIN_TYPE : TS_ADMITTED_DOMAIN_EITHER,
            emit, reservation, normalized, closed, measured);
        if (status.state != TS_VALID) return status;
        if (!emit)
        {
            if (require_closed && !closed) return ts_invalid(10u, work, ordinal);
            if (measured.nodes > TS_INVALID - node_count || measured.edges > TS_INVALID - edge_count)
                return ts_limit(64u, work, TS_INVALID, TS_INVALID - 1u);
            node_count += measured.nodes; edge_count += measured.edges;
            all_closed = all_closed && closed;
            if (!pps_write2(PPS_TERM_ROOTS, first_root + ordinal, 0u, uint2(measured.nodes, measured.edges)))
                return ts_invalid(1u, work, ordinal);
            continue;
        }
        uint root_hash;
        if (measured.nodes != counted.x || measured.edges != counted.y)
            return ts_invalid(65u, work, ordinal);
        if (!pps_write2(PPS_TERM_ROOTS, first_root + ordinal, 0u, normalized))
            return ts_invalid(1u, work, ordinal);
        if (!scoped_type_ref_hash_scratch<SolverProofTermGraph>(normalized.x, normalized.y,
            TS_INVALID, nodes, atoms, root_hash)) return ts_invalid(15u, work, ordinal);
        hash = scoped_type_hash_mix(hash, root_hash);
        if (ordinal == 0u) subject = normalized;
        node_cursor += counted.x; edge_cursor += counted.y;
    }
    if (!pps_write8(PPS_GOALS, goal,
        uint4(predicate.z, subject.x, subject.y, arguments.y == 0u ? 0u : first_root + 1u),
        uint4(arguments.y, hash, all_closed ? 1u : 0u, 0u)) ||
        !pps_write_word(PPS_WORK, work, PPS_WORK_GOAL, goal) ||
        !pps_write_word(PPS_WORK, work, PPS_WORK_STATE, PPS_WORK_BUILT))
        return ts_invalid(1u, work, goal);
    return ts_ok();
}
