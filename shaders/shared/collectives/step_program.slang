// A step program runs a sequence of steps inside one dispatch. Every lane
// finishes step N before any lane starts step N + 1, so a step may read what
// any lane wrote in an earlier step. The host records one dispatch for the
// whole sequence instead of one dispatch per step.
//
// Measured on an RTX 3090 (gpu/program_barrier_tests.rs), one read and one
// write per row:
//
//     one dispatch per step, recorded by the host   5 to 6 us of GPU time
//     step in a program, 1 group,   256 rows        0.6 us
//     step in a program, 1 group,   4,096 rows      1.9 us
//     step in a program, 1 group,   65,536 rows     22 us
//     step in a program, 64 groups, 16,384 rows     1.4 us
//     step in a program, 64 groups, 65,536 rows     2.4 us
//     step in a program, 64 groups, 524,288 rows    12 us
//     step in a program, 164 groups, 41,984 rows    1.9 us
//     step in a program, 492 groups, 125,952 rows   4.2 us
//
// When a program takes more GPU time than the dispatches it replaces:
//
// - A program runs `groups` x 256 lanes for its whole dispatch. 164 groups are
//   41,984 lanes, and the RTX 3090 runs 125,952 threads at once. A dispatched
//   kernel over a table of several hundred thousand rows uses all of them, so
//   a step that does more than a few reads per row over such a table takes
//   2.5 to 3 times as long in a 164-group program (measured on the parser's
//   token and tree passes of a 33,000-line build: 2.36 ms dispatched, 4.34 ms
//   in programs).
// - 492 groups use every thread, and those steps then take about what the
//   dispatched kernels took. A barrier then costs 4.2 us, which is close to
//   the cost of the dispatch it replaces, and a step that is one read and one
//   write per row takes 2 to 3 times as long as with 164 groups.
//
// So a program replaces a run of passes over small tables, where the fixed
// cost of each dispatch is most of its time. A pass over a large table that
// does real work per row stays a dispatched kernel between two programs.
//
// Use:
//
//     [numthreads(STEP_PROGRAM_GROUP_LANES, 1, 1)]
//     void main(uint3 group : SV_GroupID, uint3 local : SV_GroupThreadID)
//     {
//         StepProgram program = step_program_begin(group, local, groups, slot);
//         for (uint row = program.lane; row < rows; row += program.lanes) first_step(row);
//         if (!step_barrier(program)) return;
//         for (uint row = program.lane; row < rows; row += program.lanes) second_step(row);
//         ...
//     }
//
// Rules:
//
// - `groups` is the x of the dispatch, and y and z are 1. Every lane must get
//   the same `groups` and `slot`.
// - Every lane of every group calls `step_barrier` the same number of times.
//   A loop around a barrier must end on a value all lanes agree on, such as a
//   count read after the barrier before it.
// - A lane does not see what a lane of another group wrote earlier in the
//   dispatch through an ordinary buffer: each group runs on its own
//   processor, whose cache keeps the old word (measured: nearly every such
//   read was stale, and `Atomic<uint>.load` was stale too). The shader build
//   therefore marks every writable buffer of a step program coherent
//   (crates/laniusc-shaders/step_program_coherence.rs), and reads of them
//   are correct as written. Declare a buffer the program only reads
//   `StructuredBuffer`: its reads then stay cached.
// - `groups` must not exceed the number of groups the device runs at the same
//   time, or the wait never ends. 492 groups of 256 lanes ran on the RTX 3090
//   and 656 did not. `STEP_PROGRAM_MAX_GROUPS` is the limit programs use. A
//   wait that runs out of spins sets `STEP_SYNC_FAILED` in the slot and every
//   group returns: the host must read that word as a failed compile.
// - The host clears the program's slot of `step_program_sync` before the
//   dispatch.

public static const uint STEP_PROGRAM_GROUP_LANES = 256u;
public static const uint STEP_PROGRAM_MAX_GROUPS = 164u;
public static const uint STEP_PROGRAM_SPIN_LIMIT = 1u << 24u;

// Words of one program's slot in the sync buffer.
public static const uint STEP_SYNC_WORDS = 4u;
public static const uint STEP_SYNC_ARRIVALS = 0u;
public static const uint STEP_SYNC_FAILED = 1u;
public static const uint STEP_SYNC_LONGEST_WAIT = 2u;
public static const uint STEP_SYNC_FINISHED_GROUPS = 3u;

// One slot of `STEP_SYNC_WORDS` words for each step program of a compile.
public RWStructuredBuffer<uint> step_program_sync;

groupshared uint step_program_group_failed;

public struct StepProgram
{
    // This lane's index among all lanes of the dispatch, and their count.
    public uint lane;
    public uint lanes;
    public uint groups;
    // First word of this program's slot in the sync buffer.
    public uint sync_base;
    // Barriers passed so far.
    public uint step;
    public bool leader;
};

public StepProgram step_program_begin(uint3 group, uint3 local, uint groups, uint slot)
{
    StepProgram program;
    program.lane = group.x * STEP_PROGRAM_GROUP_LANES + local.x;
    program.lanes = groups * STEP_PROGRAM_GROUP_LANES;
    program.groups = groups;
    program.sync_base = slot * STEP_SYNC_WORDS;
    program.step = 0u;
    program.leader = local.x == 0u;
    if (program.leader) step_program_group_failed = 0u;
    GroupMemoryBarrierWithGroupSync();
    return program;
}

// Ends a step. Returns false when the wait for the other groups failed: the
// caller returns at once.
public bool step_barrier(inout StepProgram program)
{
    AllMemoryBarrierWithGroupSync();
    program.step += 1u;
    if (program.groups == 1u) return true;
    if (program.leader)
    {
        uint prior = 0u;
        InterlockedAdd(step_program_sync[program.sync_base + STEP_SYNC_ARRIVALS], 1u, prior);
        uint target = program.groups * program.step;
        uint arrived = prior + 1u;
        uint spins = 0u;
        while (arrived < target && spins < STEP_PROGRAM_SPIN_LIMIT)
        {
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_ARRIVALS], 0u, arrived);
            spins += 1u;
        }
        if (arrived < target)
        {
            InterlockedOr(step_program_sync[program.sync_base + STEP_SYNC_FAILED], 1u, prior);
            step_program_group_failed = 1u;
        }
        InterlockedMax(step_program_sync[program.sync_base + STEP_SYNC_LONGEST_WAIT], spins, prior);
    }
    AllMemoryBarrierWithGroupSync();
    return step_program_group_failed == 0u;
}

// Call once after the last step. The host can compare the count with `groups`.
public void step_program_end(StepProgram program)
{
    if (!program.leader) return;
    uint prior = 0u;
    InterlockedAdd(step_program_sync[program.sync_base + STEP_SYNC_FINISHED_GROUPS], 1u, prior);
}
