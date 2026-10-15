// Per-thread walk frames and solver state in one GPU-wide table instead of
// Function-storage arrays. Drivers reserve local memory for the whole process
// at max(per-thread local bytes over every pipeline) x resident threads, and
// never shrink it. This table is sized by the dispatched row count instead.
//
// INTERIM: this is still per-thread DFS state, only moved to global memory.
// The end state (P7) is program evidence on canonical type IDs with level
// rounds, where these walkers and the owned constraint engine are deleted.
//
// Layout: slots are interleaved in groups of THREAD_SCRATCH_GROUP, like the
// driver's own local memory: cell c of slot s is element
// (s / GROUP * CELLS + c) * GROUP + s % GROUP, so the threads of one wave at
// the same depth touch adjacent elements. Each dispatch-local thread owns one
// slot of THREAD_SCRATCH_CELLS uint4 cells; the table holds whole groups.
// Every region below is disjoint, so any walker may call any other one. No
// walker re-enters itself (shaders cannot recurse, and no specialization of a
// walker calls another specialization of the same walker), so one region per
// walker suffices. Every region is written before it is read; the table is
// never cleared. Each region is private to one dispatch, except that a proof
// stage split over several dispatches hands SCRATCH_PPS_HANDOFF, tagged with
// its phase, row and serial, and the owned state frame it names on to its
// later dispatches (proof_scratch_handoff.slang).
public RWStructuredBuffer<uint4> thread_scratch;

static uint g_thread_scratch_base = 0u;

// Owned constraint state frames: bindings (128 cells), then constant
// parameters with their fit mask in .w (64 cells).
public static const uint SCRATCH_OWNED_STATE = 0u;
public static const uint SCRATCH_OWNED_STATE_CELLS = 192u;
public static const uint SCRATCH_OWNED_STATE_FRAMES = 2u;
// Owned constraint unification stack: 3 cells per depth.
public static const uint SCRATCH_OWNED_UNIFY = 384u;
// Owned constraint occurs stack: 2 cells per depth.
public static const uint SCRATCH_OWNED_OCCURS = 576u;
// Constant projection target scalars: four lists of 16 cells, 4 per cell.
public static const uint SCRATCH_OWNED_TARGETS = 704u;
// Proof-term normalization stack: 6 cells per depth.
public static const uint SCRATCH_PEV_NORMALIZE = 768u;
// Admitted-root graph walk: 2 cells per depth.
public static const uint SCRATCH_PEV_GRAPH = 1152u;
// Scoped type hash and equality stacks: 2 cells per depth each.
public static const uint SCRATCH_SCOPED_HASH = 1280u;
public static const uint SCRATCH_SCOPED_EQUALITY = 1408u;
// Native layout materialization stack: 2 cells per depth.
public static const uint SCRATCH_NATIVE_MATERIALIZE = 1536u;
// Concrete value layout stack: 2 cells per depth.
public static const uint SCRATCH_VALUE_LAYOUT = 1664u;
// Proof stage handoff: the tagged outcome cell, then 15 cells of the stage's
// own record. Unlike the regions above it outlives one dispatch: the
// dispatches of one chunk hand it on (proof_scratch_handoff.slang).
public static const uint SCRATCH_PPS_HANDOFF = 1792u;
public static const uint THREAD_SCRATCH_CELLS = 1808u;
public static const uint THREAD_SCRATCH_GROUP = 32u;

// Bind this thread to its slot and return the bound table's slot count. The
// caller must fail its row without touching scratch unless slot < the result.
public uint thread_scratch_begin(uint slot)
{
    uint cells; uint stride;
    thread_scratch.GetDimensions(cells, stride);
    g_thread_scratch_base = (slot / THREAD_SCRATCH_GROUP) * THREAD_SCRATCH_CELLS * THREAD_SCRATCH_GROUP +
        slot % THREAD_SCRATCH_GROUP;
    return thread_scratch_slots(cells);
}

// Slots held by a table of `cells` cells.
public uint thread_scratch_slots(uint cells)
{ return cells / (THREAD_SCRATCH_CELLS * THREAD_SCRATCH_GROUP) * THREAD_SCRATCH_GROUP; }

[ForceInline]
public uint4 scratch_cell(uint cell)
{ return thread_scratch[g_thread_scratch_base + cell * THREAD_SCRATCH_GROUP]; }

[ForceInline]
public void scratch_set_cell(uint cell, uint4 value)
{ thread_scratch[g_thread_scratch_base + cell * THREAD_SCRATCH_GROUP] = value; }

[ForceInline]
public uint scratch_word(uint cell, uint component)
{ return thread_scratch[g_thread_scratch_base + cell * THREAD_SCRATCH_GROUP][component]; }

[ForceInline]
public void scratch_set_word(uint cell, uint component, uint value)
{ thread_scratch[g_thread_scratch_base + cell * THREAD_SCRATCH_GROUP][component] = value; }
