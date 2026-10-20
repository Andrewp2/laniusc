// The instance closure of an original job (docs: D_PLAN D1). Every concrete
// body the unit's own generic calls reach, found on the GPU in level rounds
// instead of one frontend replay per instantiation depth:
//
// - edges: each call to a local generic body, linked under the generic
//   function that contains it (01_mark);
// - roots: each such call in a nongeneric function whose environment is
//   complete and closed, at depth 1 (01_mark);
// - rounds: each frontier instance (F, E) substitutes E into the call
//   environment of every edge of F and inserts the callee's instance one
//   level deeper (03_expand, 02_advance between rounds);
// - export: the arguments of every instance as checked rows (04_export).
//
// An instance is keyed by its tagged environment: the callee's substituted
// call environment with words.x = callee HIR row + 1. Interning makes that
// key exact, and ct_env_binding reads only words.y/z, so a tagged
// environment substitutes like the call environment it came from.
//
// The closure is an optimization: the host still finds anything it misses
// after the replays it schedules. A full table only loses instances; a
// frontier left at the level limit (IC_FLAG_DEPTH) makes the host ignore
// the closure, since polymorphic recursion never closes.
import type_checker.canonical.canonical_api;

// Counters and round state; see IC_COUNT_*.
public RWStructuredBuffer<uint> instance_closure_counts;
// Open-addressing set: (tagged environment, ~smallest template call HIR).
// Zero is empty. Power-of-two length.
public RWStructuredBuffer<uint2> instance_closure_set;
// Two rows per instance, in discovery order:
//   2i:     (tagged environment, callee HIR row, depth, set slot)
//   2i + 1: (argument base, template call HIR, export status,
//            arity | type arguments << 16)
// Export status: 0 pending, 1 exported, 2 failed.
public RWStructuredBuffer<uint4> instance_closure_instances;
// The checked operand of each instance argument (realized type rows, then
// constants as (kind, payload)), at the instance's argument base.
public RWStructuredBuffer<uint2> instance_closure_refs;
// The routed target of each instance a bound-member edge found (03c):
// (function start token, native symbol, specialization symbol, type
// parameters), as host retention reads a routed call (generic_calls.rs);
// all INVALID for an instance of a direct call.
public RWStructuredBuffer<uint4> instance_closure_targets;
// Edges: the first call (+1) of each generic function row, and the next
// call (+1) of each call row; 0 ends a list.
public RWStructuredBuffer<uint> instance_closure_edge_head;
public RWStructuredBuffer<uint> instance_closure_edge_next;

public static const uint IC_COUNT_LENGTH = 0u;   // instances appended
public static const uint IC_COUNT_START = 1u;    // this round's first instance
public static const uint IC_COUNT_END = 2u;      // this round's end
public static const uint IC_COUNT_ROUND = 3u;    // advances so far
public static const uint IC_COUNT_FLAGS = 4u;    // IC_FLAG_* bits
public static const uint IC_COUNT_ARGS = 5u;     // argument words appended
public static const uint IC_COUNT_EDGES = 6u;    // linked edges (trace)
public static const uint IC_COUNT_SKIPPED = 7u;  // edges without a closed instance (trace)
public static const uint IC_COUNT_WORDS = 8u;

public static const uint IC_FLAG_INSTANCES = 1u;  // the instance table is full
public static const uint IC_FLAG_SET = 2u;        // a set probe ran out
public static const uint IC_FLAG_ARGS = 4u;       // the argument table is full
public static const uint IC_FLAG_DEPTH = 8u;      // a frontier was left at the level limit

// Expansion rounds; instances deeper than IC_LEVELS + 1 are never found
// (instance_closure_passes.rs, INSTANCE_CLOSURE_LEVELS).
public static const uint IC_LEVELS = 6u;

static const uint IC_PROBE_LIMIT = 64u;
static const uint IC_INVALID = 0xffffffffu;

public void ic_flag(uint bits)
{
    uint ignored;
    InterlockedOr(instance_closure_counts[IC_COUNT_FLAGS], bits, ignored);
}

public void ic_count(uint word)
{
    uint ignored;
    InterlockedAdd(instance_closure_counts[word], 1u, ignored);
}

public uint ic_instance_capacity()
{
    uint rows; uint stride;
    instance_closure_instances.GetDimensions(rows, stride);
    return rows / 2u;
}

uint set_capacity()
{
    uint rows; uint stride;
    instance_closure_set.GetDimensions(rows, stride);
    return rows;
}

uint ref_capacity()
{
    uint rows; uint stride;
    instance_closure_refs.GetDimensions(rows, stride);
    return rows;
}

// Append the new instance `env` (set slot `slot`): its two rows and its
// argument block.
void append_instance(uint env, uint callee, uint depth, uint slot, uint4 target)
{
    uint index;
    InterlockedAdd(instance_closure_counts[IC_COUNT_LENGTH], 1u, index);
    if (index >= ic_instance_capacity())
    {
        ic_flag(IC_FLAG_INSTANCES);
        return;
    }
    uint arity = ct_arity(env);
    uint base;
    InterlockedAdd(instance_closure_counts[IC_COUNT_ARGS], arity, base);
    uint capacity = ref_capacity();
    if (base > capacity || arity > capacity - base)
    {
        ic_flag(IC_FLAG_ARGS);
        base = IC_INVALID;
    }
    instance_closure_instances[2u * index] = uint4(env, callee, depth, slot);
    instance_closure_targets[index] = target;
    instance_closure_instances[2u * index + 1u] =
        uint4(base, IC_INVALID, 0u, arity | (ct_type_slots(env) << 16u));
}

// Insert instance `env` of callee row `callee`, reached at `depth` through
// template call `call`. The first lane to claim the key appends it; every
// lane keeps the smallest template call, so the result does not depend on
// lane order.
public void ic_insert(uint env, uint callee, uint depth, uint call)
{
    ic_insert_target(env, callee, depth, call, uint4(IC_INVALID, IC_INVALID, IC_INVALID, IC_INVALID));
}

// ic_insert for an instance with a routed target (instance_closure_targets).
public void ic_insert_target(uint env, uint callee, uint depth, uint call, uint4 target)
{
    uint capacity = set_capacity();
    if (capacity == 0u)
    {
        ic_flag(IC_FLAG_SET);
        return;
    }
    uint2 hash = ct_shash(env);
    uint slot = (hash.x ^ (hash.y * 0x9e3779b9u)) & (capacity - 1u);
    for (uint probe = 0u; probe < IC_PROBE_LIMIT; probe++)
    {
        uint previous;
        InterlockedCompareExchange(instance_closure_set[slot].x, 0u, env, previous);
        if (previous == 0u || previous == env)
        {
            uint ignored;
            InterlockedMax(instance_closure_set[slot].y, ~call, ignored);
            if (previous == 0u) append_instance(env, callee, depth, slot, target);
            return;
        }
        slot = (slot + 1u) & (capacity - 1u);
    }
    ic_flag(IC_FLAG_SET);
}

// Link call row `call` as an edge of generic function row `owner`: push it
// onto the owner's list with a compare-exchange. slangc (2026.2 here)
// segfaults on InterlockedExchange into this module's buffers. Each failed
// exchange means another lane linked its call, so `rows` attempts always
// suffice.
public void ic_link_edge(uint owner, uint call)
{
    uint rows; uint stride;
    instance_closure_edge_head.GetDimensions(rows, stride);
    if (owner >= rows) return;
    uint head = instance_closure_edge_head[owner];
    for (uint attempt = 0u; attempt < rows; attempt++)
    {
        instance_closure_edge_next[call] = head;
        uint previous;
        InterlockedCompareExchange(instance_closure_edge_head[owner], head, call + 1u, previous);
        if (previous == head)
        {
            ic_count(IC_COUNT_EDGES);
            return;
        }
        head = previous;
    }
}

// The first edge (+1) of function row `row`, 0 when it has none.
public uint ic_first_edge(uint row)
{
    uint rows; uint stride;
    instance_closure_edge_head.GetDimensions(rows, stride);
    return row < rows ? instance_closure_edge_head[row] : 0u;
}

// The next edge after call row `call` (helper, so a list walk carries one
// loaded value per step).
public uint ic_next_edge(uint call)
{
    uint rows; uint stride;
    instance_closure_edge_next.GetDimensions(rows, stride);
    return call < rows ? instance_closure_edge_next[call] : 0u;
}
