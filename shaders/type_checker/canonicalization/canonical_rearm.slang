// Re-arming one interning candidate after later producers added candidates
// (docs/canonical-type-ids.md, "Stages"): rows materialized or generated
// after the early pass, and constants published during inference. Every
// interned candidate keeps its reference; pending, empty and unknown
// candidates are retried (and every interned one when CT_COUNT_EARLY_REARM
// is set). The table, records and overflow bits are kept.
//
// A candidate that is still empty (a row without a kind, an atom without a
// value, a projection without an operand) gets CT_NONE here, the reference
// interning would publish for it (canonical_build_candidate_key), so the
// rounds do not intern the millions of empty slots of the capacity-sized
// tables.
import type_checker.canonicalization.canonical_api;
import type_checker.constants.constant_atoms;

// A sweep gives each candidate to one lane. No lane reads a candidate
// another lane changes, so these views can use the cache.
RWStructuredBuffer<uint> canonical_row_rearm;
RWStructuredBuffer<uint> canonical_atom_rearm;
RWStructuredBuffer<uint> canonical_projection_rearm;

public StructuredBuffer<uint> type_instance_kind;
// The allocation counters that bound a later sweep (canonical_live_rearm).
// Not coherent, so each wave's load is served from L1. A load of the
// coherent ct_counts by every wave went to one L2 address, which cost more
// than the sweep skips.
public StructuredBuffer<uint> type_generic_param_slot_by_token;
public StructuredBuffer<uint> type_application_count;
public StructuredBuffer<uint4> checked_constant_storage_state;

bool candidate_empty(uint candidate, uint rows, uint atoms)
{
    if (candidate < rows)
    {
        uint count; uint stride;
        type_instance_kind.GetDimensions(count, stride);
        return candidate >= count || type_instance_kind[candidate] == 0u;
    }
    uint3 value; uint target; uint2 child;
    if (candidate - rows < atoms) return !checked_constant_atom_value(candidate - rows, value);
    return !checked_constant_projection(candidate - rows - atoms, target, child);
}

// Entries that may have acquired a key since the previous stage.
bool rearm_eligible(uint state, bool rearm_interned)
{
    return state == CT_PENDING || state == CT_NONE || state == CT_UNKNOWN ||
        (rearm_interned && ct_is_resolved(state));
}

// The candidates a re-arm sweep after the early stage visits
// (list_live_canonical_candidates_to_rearm, rearm_canonical_type_candidates): only what has been allocated. The early
// sweep visits the rest too, without reading their contents. Generated
// rows follow one source row per token row (allocate_application.slang,
// ct_realize), and constants fill the fixed regions below the dynamic arena,
// then the arena in order (constant_publication.slang). The early stage's
// sweep (list_canonical_candidates_to_rearm) visits every candidate and leaves the empty ones
// CT_NONE; no producer writes a candidate past these bounds, and the
// allocation counters only grow during a job, so re-arming the rest would
// leave them as they are.
public struct LiveRearm
{
    public uint rows;     // row capacity: the first constant candidate
    public uint atoms;    // atom capacity: the first projection past it
    public uint projections;
    public uint constants;  // live atoms, and live projections
    public uint source;   // live source rows, from row 0
    public uint generated;  // live generated rows, from `source`
    public bool rearm_interned;
}

// Every lane of a wave gets the same value; the counters are loaded once
// per wave.
public LiveRearm canonical_live_rearm()
{
    LiveRearm live;
    uint stride;
    canonical_row_rearm.GetDimensions(live.rows, stride);
    canonical_atom_rearm.GetDimensions(live.atoms, stride);
    canonical_projection_rearm.GetDimensions(live.projections, stride);
    uint4 storage = uint4(0u, 0u, 0u, 1u);
    uint generated = 0u;
    uint rearm_interned = 0u;
    if (WaveIsFirstLane())
    {
        storage = checked_constant_storage_state[0u];
        generated = type_application_count[0u];
        rearm_interned = ct_counts[CT_COUNT_EARLY_REARM];
    }
    storage = WaveReadLaneFirst(storage);
    generated = WaveReadLaneFirst(generated);
    live.rearm_interned = WaveReadLaneFirst(rearm_interned) != 0u;
    // A failed storage plan bounds nothing.
    bool bounded = storage.w == 0u && storage.x <= storage.y;
    uint constants = storage.x + min(storage.z, storage.y - storage.x);
    uint capacity = min(live.atoms, live.projections);
    live.constants = bounded ? min(constants, capacity) : capacity;
    uint token_rows;
    type_generic_param_slot_by_token.GetDimensions(token_rows, stride);
    live.source = min(token_rows, live.rows);
    live.generated = min(generated, live.rows - live.source);
    return live;
}

// Whether `candidate` is within the allocated candidates.
public bool canonical_live_rearm_holds(LiveRearm live, uint candidate)
{
    if (candidate < live.rows) return candidate - live.source < live.generated || candidate < live.source;
    uint constant = candidate - live.rows;
    if (constant >= live.atoms) constant -= live.atoms;
    return constant < live.constants;
}

public uint canonical_live_rearm_count(LiveRearm live)
{
    return 2u * live.constants + live.generated + live.source;
}

// The `index`-th live candidate (below canonical_live_rearm_count), in the
// early sweep's order: constants first, then rows from the last.
public uint canonical_live_rearm_candidate(LiveRearm live, uint index)
{
    uint generated_end = 2u * live.constants + live.generated;
    uint row = generated_end - 1u - index;
    if (index >= generated_end) row = live.source - 1u - (index - generated_end);
    else row = live.source + row;
    uint constant = index < live.constants ? live.rows + index :
        live.rows + live.atoms + (index - live.constants);
    return index < 2u * live.constants ? constant : row;
}

// The early sweep alone visits the capacity tail. Nothing can have
// published a reference there, so an empty entry needs no state load.
public bool canonical_rearm_candidate(LiveRearm live, uint candidate, bool may_hold = true)
{
    uint atom = candidate - live.rows;
    uint projection = atom - live.atoms;
    uint state = CT_PENDING;
    if (may_hold)
    {
        if (candidate < live.rows) state = canonical_row_rearm[candidate];
        else if (atom < live.atoms) state = canonical_atom_rearm[atom];
        else state = canonical_projection_rearm[projection];
        if (!rearm_eligible(state, live.rearm_interned)) return false;
    }
    uint next = may_hold && !candidate_empty(candidate, live.rows, live.atoms) ? CT_PENDING : CT_NONE;
    if (next != state)
    {
        if (candidate < live.rows) canonical_row_rearm[candidate] = next;
        else if (atom < live.atoms) canonical_atom_rearm[atom] = next;
        else canonical_projection_rearm[projection] = next;
    }
    return next == CT_PENDING;
}

// Lanes every re-arm sweep launches (canonical_passes.rs,
// CANONICAL_REARM_LANES). A sweep strides its candidates by this count, so
// its grid does not scale with the table's capacity.
public static const uint CANONICAL_REARM_LANES = 1u << 19u;

// Resets the round state for the rounds that follow (one lane).
public void canonical_rearm_reset_rounds(LiveRearm live)
{
    ct_counts[CT_COUNT_PENDING] = live.rows + live.atoms + live.projections;
    ct_counts[CT_COUNT_ROUND] = 0u;
    ct_counts[CT_COUNT_FRONTIER] = 0u;
    ct_counts[CT_COUNT_FRONTIER + 1u] = 0u;
    ct_counts[CT_COUNT_FINAL] = 0u;
}
