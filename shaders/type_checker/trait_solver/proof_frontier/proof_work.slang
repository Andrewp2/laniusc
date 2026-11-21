// The proof search of one batch. PPS_WORK is a queue of goals. Row i below
// the root count is source obligation `first + i`. Every later row is one
// prerequisite of an implementation that a proof applied. One lane owns one
// row from its goal to its proof.
//
// A recorded step runs the rows [cursor, cursor + count) through four lane
// kernels: build_proof_goals, select_proof_assumptions,
// select_proof_implementations and write_proof_rows. The rows a step appends
// run in a later step, so a step is one nesting level of obligations at
// most. plan_proof_wave chooses each step's rows on the GPU, and the host
// reads the state back once after the recorded steps.
//
// Rows are not shared between obligations: two obligations with the same
// goal prove it twice. A goal equal to one of its ancestors is a cycle.
import type_checker.trait_solver.solver_abi;
import type_checker.trait_solver.batches.batch_io;
import type_checker.trait_solver.catalog.catalog_io;
import type_checker.trait_solver.proof_store_abi;
import type_checker.trait_solver.proof_term_graph;
import type_checker.scoped_types.scoped_type_hash;
import type_checker.scoped_types.scoped_type_equality;
import type_checker.trait_solver.scoped_type_scratch;

// Work16 words.
public static const uint PPS_WORK_CONTEXT = 0u;
public static const uint PPS_WORK_GOAL = 1u;
public static const uint PPS_WORK_STATE = 2u;
public static const uint PPS_WORK_PARENT = 3u;      // Work row, INVALID for a root
public static const uint PPS_WORK_ROOT = 4u;        // the root Work of this tree
public static const uint PPS_WORK_PREDICATE = 5u;   // catalog/batch predicate row
// A root's environment, or the substitution of the parent's implementation.
public static const uint PPS_WORK_SOURCE = 6u;
public static const uint PPS_WORK_PARENT_EDGE = 7u; // parent's ProofEdge row, INVALID for a root
public static const uint PPS_WORK_PROOF = 8u;
public static const uint PPS_WORK_IMPLEMENTATION = 9u;
public static const uint PPS_WORK_DEPTH = 10u;
// Roots only: the worst outcome of the tree (PPS_VERDICT_*), an atomic max.
public static const uint PPS_WORK_VERDICT = 11u;
public static const uint PPS_WORK_ASSUMPTION = 12u;
public static const uint PPS_WORK_OBLIGATION = 13u; // roots only

public static const uint PPS_WORK_PENDING = 0u;
public static const uint PPS_WORK_BUILT = 1u;    // the goal row exists
public static const uint PPS_WORK_SELECTED = 2u; // implementation and assumption words are final
public static const uint PPS_WORK_PROVEN = 3u;
public static const uint PPS_WORK_REFUTED = 4u;

public static const uint PPS_VERDICT_CYCLE = 1u;
public static const uint PPS_VERDICT_MISSING = 2u;

// Proof8 word 7. A proof with a refuted descendant is no proof: every reader
// accepts only CLOSED or CONDITIONAL.
public static const uint PPS_PROOF_CLOSED = 1u;
public static const uint PPS_PROOF_CONDITIONAL = 2u;
public static const uint PPS_PROOF_REFUTED = 3u;

public static const uint PPS_ATOMIC_ATTEMPTS = 65536u;
public static const uint PPS_LOGICAL_WORK_LIMIT = 65536u;

// Wave state, written by plan_proof_wave and by the host before an attempt.
public StructuredBuffer<uint> trait_solver_wave;
public static const uint PSW_STOP = 0u;             // PSW_RUNNING .. PSW_DONE
public static const uint PSW_FAULT_DETAIL = 1u;
public static const uint PSW_CURSOR = 2u;           // first Work row no step has run
public static const uint PSW_ROOTS = 3u;            // source obligations: a bound from the host, the count after the first plan
public static const uint PSW_CHUNK_FIRST = 4u;      // this step's rows
public static const uint PSW_CHUNK_COUNT = 5u;
public static const uint PSW_OBLIGATIONS_FIRST = 6u; // host
public static const uint PSW_STEPS = 7u;            // steps that ran rows
public static const uint PSW_LANE_ARGS = 8u;        // indirect arguments, three words each
public static const uint PSW_PUBLISH_ARGS = 12u;
public static const uint PSW_CALLS_FIRST = 17u;     // host: the batch's new call rows
public static const uint PSW_CALLS_COUNT = 18u;
public static const uint PSW_REDUCE_ARGS = 20u;
public static const uint PSW_FINALIZE_ARGS = 24u;
public static const uint PSW_RUNNING = 0u;
public static const uint PSW_STOPPED = 1u;  // the batch or the store stopped building
public static const uint PSW_DONE = 2u;     // every Work ran; the finish published
// Rows of one step: every lane takes one thread-scratch slot.
public static const uint PSW_CHUNK_ROWS = 4096u;
public static const uint PSW_LANE_GROUP = 64u;

// The Work row of lane `local` in this step.
public bool pps_wave_lane(uint local, out uint work)
{
    work = TS_INVALID;
    if (local >= trait_solver_wave[PSW_CHUNK_COUNT] || !pps_building() || !ts_batch_is_building())
        return false;
    work = trait_solver_wave[PSW_CHUNK_FIRST] + local;
    return true;
}

public bool pps_write4(uint table, uint row, uint field, uint4 value)
{
    uint address;
    if (!pps_address(table, row, field, 4u, true, address)) return false;
    trait_solver_proof_store[address] = value.x;
    trait_solver_proof_store[address + 1u] = value.y;
    trait_solver_proof_store[address + 2u] = value.z;
    trait_solver_proof_store[address + 3u] = value.w;
    return true;
}
public bool pps_write_word(uint table, uint row, uint field, uint value)
{
    uint address;
    if (!pps_address(table, row, field, 1u, true, address)) return false;
    trait_solver_proof_store[address] = value; return true;
}
// Raises one word of a row of this batch to at least `value`. Several lanes
// of one dispatch may raise the same word. `previous` is the word before.
public bool pps_raise_word(uint table, uint row, uint field, uint value, out uint previous)
{
    previous = TS_INVALID; uint address;
    if (!pps_address(table, row, field, 1u, true, address)) return false;
    InterlockedMax(trait_solver_proof_store[address], value, previous);
    return true;
}

// A successful CAS is a prefix reservation. A lane reserves the complete
// rows of one table at once, and overflow never truncates a row. Rows of a
// failed attempt are never accepted (pps_accept_submission).
public SolverStatus pps_reserve(uint table, uint count, uint subject, out uint first)
{
    first = TS_INVALID;
    if (count == 0u) { first = 0u; return ts_ok(); }
    // The lane checked both receipts. Initialization admitted the directory,
    // and allocation can only grow the reserved count up to capacity.
    // If a peer fails, this lane's writes remain in the rejected suffix.
    uint address = PPS_DIRECTORY + table * 6u + 1u;
    uint capacity = trait_solver_proof_store[address + 1u];
    uint limit = table == PPS_WORK ? PPS_LOGICAL_WORK_LIMIT : TS_INVALID;
    // The active lanes of a subgroup that reserve rows of one table take
    // them with one exchange: a compare-exchange per lane on the table's
    // counter serializes every lane of a large stage. The total fits
    // exactly when every lane's rows fit after the others', so success and
    // the counter are those of the lane-by-lane reservation.
    bool shared = WaveActiveAllEqual(table) && WaveActiveMax(count) <= 4096u;
    uint lanes = shared ? WaveActiveSum(count) : count;
    uint before = shared ? WavePrefixSum(count) : 0u;
    bool leader = !shared || WaveIsFirstLane();
    uint outcome = 0u; uint expected = 0u;
    if (leader)
    {
        expected = trait_solver_proof_store[address];
        outcome = 3u;
        [loop]
        for (uint attempt = 0u; attempt < PPS_ATOMIC_ATTEMPTS; attempt++)
        {
            if (expected > limit || lanes > limit - expected) { outcome = 1u; break; }
            if (expected > capacity || lanes > capacity - expected || lanes >= TS_INVALID - expected)
            { outcome = 2u; break; }
            uint previous;
            InterlockedCompareExchange(trait_solver_proof_store[address], expected, expected + lanes, previous);
            if (previous == expected) { outcome = 0u; break; }
            expected = previous;
        }
    }
    if (shared)
    {
        outcome = WaveReadLaneFirst(outcome);
        expected = WaveReadLaneFirst(expected);
    }
    uint required = lanes > TS_INVALID - expected ? TS_INVALID : expected + lanes;
    if (outcome == 1u) return ts_limit(72u, table, required, limit);
    if (outcome == 2u) return ts_limit(69u, table, required, capacity);
    if (outcome == 3u) return ts_limit(8u, subject, PPS_ATOMIC_ATTEMPTS + 1u, PPS_ATOMIC_ATTEMPTS);
    first = expected + before;
    return ts_ok();
}

public bool pps_goal_equal(uint left, uint right)
{
    uint4 a; uint4 aa; uint4 b; uint4 ba; uint nodes; uint atoms;
    if (!pps_read8(PPS_GOALS, left, a, aa) || !pps_read8(PPS_GOALS, right, b, ba) ||
        a.x != b.x || aa.x != ba.x || aa.y != ba.y || aa.x > 32u ||
        !pps_count(PPS_TERM_NODES, nodes) || !ts_table_count(1u, atoms)) return false;
    [loop]
    for (uint i = 0u; i <= aa.x; i++)
    {
        uint2 l = a.yz; uint2 r = b.yz;
        if (i != 0u && (!pps_read2(PPS_TERM_ROOTS, a.w + i - 1u, 0u, l) ||
            !pps_read2(PPS_TERM_ROOTS, b.w + i - 1u, 0u, r))) return false;
        if (!scoped_type_refs_equal_scratch<SolverProofTermGraph>(l.x, l.y, TS_INVALID,
            r.x, r.y, TS_INVALID, nodes, atoms)) return false;
    }
    return true;
}

// Work `work` of the tree of `root` is refuted. Every proof above it is no
// proof, and the root takes the verdict. `parent` is the Work's parent.
public SolverStatus pps_refute_work(uint work, uint parent, uint root, uint verdict)
{
    uint previous;
    if (!pps_write_word(PPS_WORK, work, PPS_WORK_STATE, PPS_WORK_REFUTED) ||
        !pps_raise_word(PPS_WORK, root, PPS_WORK_VERDICT, verdict, previous))
        return ts_invalid(1u, work, root);
    return pps_raise_ancestor_proofs(work, parent, PPS_PROOF_REFUTED);
}
// Raises the classification of the proof of every Work from `ancestor` up to
// the root. An ancestor already at `classification` or above ends the walk:
// the lane that raised it walks the rest.
public SolverStatus pps_raise_ancestor_proofs(uint work, uint ancestor, uint classification)
{
    [loop]
    for (uint depth = 0u; ancestor != TS_INVALID; depth++)
    {
        uint4 key; uint4 result; uint previous;
        if (depth > TS_DEPTH_LIMIT) return ts_limit(6u, work, depth + 1u, TS_DEPTH_LIMIT);
        if (!pps_read4(PPS_WORK, ancestor, 0u, key) || !pps_read4(PPS_WORK, ancestor, 8u, result) ||
            key.z != PPS_WORK_PROVEN ||
            !pps_raise_word(PPS_PROOFS, result.x, 7u, classification, previous))
            return ts_invalid(70u, work, ancestor);
        if (previous >= classification) break;
        ancestor = key.w;
    }
    return ts_ok();
}
