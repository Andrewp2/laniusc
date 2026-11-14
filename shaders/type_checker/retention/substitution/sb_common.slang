// Production substitution over retained program terms
// (docs/compiler-retained-substitution.md).
//
// A request names a declaration (DeclId), a closed ENV term owned by that
// declaration and a term over the declaration's binder chain. The result is
// the exactly interned closed term, or a status with the exact provenance
// of the failure.
//
// Work is a memoized task graph. A task is one unique key
//   (binding environment, term)
// where the environment is the request's validated ENV TermId (its owner
// word is the owning definition) or 0 for the environment-independent
// evaluation of a closed term, which still carries pending CC_CAST fits.
// Leaves (scalars, arity-0 records, parameter leaves and sentinels) never
// become tasks: an edge resolves them in place.
//
// Phases of one attempt (each a GPU kernel, planners are single lanes):
//   00 begin        open the transaction, publish the root dispatch
//   01 roots        one lane per request: validate, create the root task
//   02 expand_plan  next frontier = tasks created by the last round
//   03 expand       one lane per (frontier task, child index)
//   04 scatter      one lane per task: bucket by level
//   05 eval_plan    next nonempty level
//   06 eval         one lane per task of the level
//   07 publish      one lane per request
//   08 finish       commit, or roll back the store terms of the attempt
//   09 rollback     one lane per store term slot
// A task's level is height(term) + height(env) - 1 (height(term) for
// env 0). Every child task has a strictly lower level, so evaluation in
// increasing level order sees every child result.
import primitive_types;
import constant_value;
import type_checker.retention.retention_store;

// Requests (producer-owned): (DeclId, ENV TermId, term reference, tag).
public StructuredBuffer<uint4> sb_requests;
public StructuredBuffer<uint> sb_request_count;

public globallycoherent RWStructuredBuffer<uint> sb_counts;     // SB_C_* status words
public RWStructuredBuffer<uint> sb_config;                      // SB_CFG_*
// Per request: the root edge (value or task, status).
public globallycoherent RWStructuredBuffer<uint2> sb_req_root;
// Published results, SB_RESULT_WORDS uint4 per request:
//   r0 (result TermId or RT_UNKNOWN, status, failed node, failed env)
//   r1 (failed child value, request tag, run, 0)
public globallycoherent RWStructuredBuffer<uint4> sb_results;
// Tasks: key (env, term, level | SB_DEAD, edge base); result (value,
// status, failed node, failed env); failed child value.
public globallycoherent RWStructuredBuffer<uint4> sb_task_key;
public globallycoherent RWStructuredBuffer<uint4> sb_task_res;
public globallycoherent RWStructuredBuffer<uint> sb_task_fail;
// Edges: one uint2 per child of a task, (value, status) or (task, SB_EDGE_TASK).
public globallycoherent RWStructuredBuffer<uint2> sb_edges;
// Memo: open-addressing slots holding task + 1.
public globallycoherent RWStructuredBuffer<uint> sb_memo;
// Live tasks ordered by level.
public globallycoherent RWStructuredBuffer<uint> sb_order;

public static const uint SB_RESULT_WORDS = 2u;

// Result statuses. Only SB_OK carries a term.
public static const uint SB_OK = 0u;
public static const uint SB_PENDING = 1u;       // internal: not evaluated yet
public static const uint SB_NOT_READY = 2u;     // the store's READY bit is clear
public static const uint SB_DECL = 3u;          // no committed, complete definition
public static const uint SB_ENV = 4u;           // not a closed ENV of the declaration
public static const uint SB_UNRESOLVED = 5u;    // a sentinel or invalid reference
public static const uint SB_PRIOR_FIT = 6u;     // an RT_FIT_FAILED reference in the input
public static const uint SB_FOREIGN = 7u;       // a parameter outside the declaration's binder
public static const uint SB_UNBOUND = 8u;       // a binder parameter the ENV leaves unbound
public static const uint SB_SLOT_PENDING = 9u;  // a dependency-signature slot leaf (needs its binder)
public static const uint SB_FIT_FAILED = 10u;   // a constant projection does not fit its target
public static const uint SB_COUNT = 11u;        // an array length that is not a count
public static const uint SB_UNSUPPORTED = 12u;  // a kind or constant shape substitution does not support
public static const uint SB_DEPTH = 13u;        // the result exceeds the 64-level type graph
public static const uint SB_CAPACITY = 14u;     // the attempt overflowed; never a language result
public static const uint SB_INVARIANT = 15u;    // an inconsistent store record
public static const uint SB_STATUSES = 16u;
public static const uint SB_EDGE_TASK = 0xffffffffu;
// An argument equal to an earlier argument of the same task: (that index, SB_EDGE_SAME).
public static const uint SB_EDGE_SAME = 0xfffffffeu;

public static const uint SB_DEAD = 0x80000000u;
public static const uint SB_LEVELS = 256u;
public static const uint SB_MAX_HEIGHT = 64u;
public static const uint SB_ROUND_LOG = 128u;

// Phases.
public static const uint SB_PHASE_EXPAND = 1u;
public static const uint SB_PHASE_SCATTER = 2u;
public static const uint SB_PHASE_EVAL = 3u;
public static const uint SB_PHASE_DONE = 4u;
public static const uint SB_PHASE_OVERFLOW = 5u;
public static const uint SB_PHASE_FINAL = 6u;

// Published states.
public static const uint SB_STATE_OPEN = 1u;
public static const uint SB_STATE_PUBLISHED = 2u;
public static const uint SB_STATE_OVERFLOWED = 3u;

// Overflow bits.
public static const uint SB_OVERFLOW_TASKS = 1u;
public static const uint SB_OVERFLOW_EDGES = 2u;
public static const uint SB_OVERFLOW_MEMO = 4u;
public static const uint SB_OVERFLOW_STORE = 8u;

// sb_counts layout.
public static const uint SB_C_PHASE = 0u;
public static const uint SB_C_OVERFLOW = 1u;
public static const uint SB_C_TASKS = 2u;          // allocation counter (keeps the requested end)
public static const uint SB_C_EDGES = 3u;
public static const uint SB_C_DEMAND_TASKS = 4u;
public static const uint SB_C_DEMAND_EDGES = 5u;
public static const uint SB_C_FRONTIER_LO = 6u;
public static const uint SB_C_FRONTIER_HI = 7u;
public static const uint SB_C_FRONTIER_ARITY = 8u;
public static const uint SB_C_NEXT_ARITY = 9u;
public static const uint SB_C_ROUNDS = 10u;        // expansion rounds with a nonempty frontier
public static const uint SB_C_LEVEL = 11u;
public static const uint SB_C_EVAL_ROUNDS = 12u;   // nonempty levels evaluated
public static const uint SB_C_MAX_LEVEL = 13u;
public static const uint SB_C_REQUESTS = 14u;
public static const uint SB_C_SPARE_TASKS = 15u;   // tasks that lost a memo race
public static const uint SB_C_EDGE_LANES = 16u;    // expansion lanes dispatched
public static const uint SB_C_EDGES_RESOLVED = 17u;
public static const uint SB_C_MAX_FRONTIER = 18u;
public static const uint SB_C_STATE = 19u;
public static const uint SB_C_RUN = 20u;
public static const uint SB_C_STORE_TERMS_BASE = 21u;
public static const uint SB_C_STORE_ARGS_BASE = 22u;
public static const uint SB_C_STORE_SPARE_TERMS = 23u;
public static const uint SB_C_STORE_SPARE_ARGS = 24u;
public static const uint SB_C_STORE_OVERFLOW_SAVED = 25u;
public static const uint SB_C_STORE_DEMAND_TERMS_SAVED = 26u;
public static const uint SB_C_STORE_DEMAND_ARGS_SAVED = 27u;
public static const uint SB_C_STORE_OVERFLOW = 28u;
public static const uint SB_C_STORE_DEMAND_TERMS = 29u;
public static const uint SB_C_STORE_DEMAND_ARGS = 30u;
public static const uint SB_C_REQUEST_CLAMPED = 31u;
public static const uint SB_C_STATUS = 32u;        // + status: published results per status
public static const uint SB_C_EVAL_LANES = 48u;
public static const uint SB_C_MAX_ARITY = 49u;
public static const uint SB_C_STORE_NEW_TERMS = 50u; // store terms the committed attempt added
public static const uint SB_C_LEVEL_COUNT = 64u;   // + level: live tasks
public static const uint SB_C_LEVEL_BASE = 320u;   // + level: first sb_order index
public static const uint SB_C_LEVEL_CURSOR = 576u; // + level: scatter cursor
public static const uint SB_C_ROUND_LOG = 832u;    // + round: frontier tasks of the round
public static const uint SB_WORDS = 1024u;

public static const uint SB_CFG_HASH_MASK = 0u;
public static const uint SB_CFG_RUN = 1u;

// Lane numbering of 2D dispatches (set_dispatch).
public uint sb_lane(uint3 dtid) { return dtid.x + dtid.y * 16776960u; }

public uint sb_task_capacity()
{
    uint a; uint b; uint c; uint d; uint s;
    sb_task_key.GetDimensions(a, s); sb_task_res.GetDimensions(b, s);
    sb_task_fail.GetDimensions(c, s); sb_order.GetDimensions(d, s);
    return min(min(a, b), min(c, d));
}

public uint sb_edge_capacity() { uint n; uint s; sb_edges.GetDimensions(n, s); return n; }

public uint sb_request_capacity()
{
    uint a; uint b; uint c; uint s;
    sb_requests.GetDimensions(a, s); sb_req_root.GetDimensions(b, s); sb_results.GetDimensions(c, s);
    return min(min(a, b), c / SB_RESULT_WORDS);
}

public uint sb_request_total() { return sb_counts[SB_C_REQUESTS]; }

public void sb_overflow(uint bit) { InterlockedOr(sb_counts[SB_C_OVERFLOW], bit); }

// ---------------------------------------------------------------------------
// The binder of an ENV owner: the owner's committed directory entry.
public struct SbBinder
{
    public uint env;
    public uint base;
    public uint type_count;
    public uint const_count;
}

public SbBinder sb_binder(uint env)
{
    SbBinder b;
    b.env = env;
    b.base = 0u; b.type_count = 0u; b.const_count = 0u;
    if (env == 0u) return b;
    uint decl = rt_term_head[env].y;
    uint entry = rt_decl_def[decl] - 1u;
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    b.base = d1.x;
    b.type_count = d1.y & 0xffffu;
    b.const_count = d1.y >> 16u;
    return b;
}

uint sb_mask(uint count) { return count >= 32u ? 0xffffffffu : (1u << count) - 1u; }
uint sb_below(uint mask, uint index) { return countbits(index >= 32u ? mask : mask & ((1u << index) - 1u)); }

bool sb_type_binding(uint ref)
{
    uint kind = rt_term_kind(ref);
    return kind == RT_KIND_SCALAR || kind == RT_KIND_NAMED || kind == RT_KIND_ARRAY ||
        kind == RT_KIND_SLICE || kind == RT_KIND_REF;
}

// A constant binding of a parameter with declared scalar `scalar` (0 when
// none is recorded): a typed value of that scalar, or a pending projection
// to it.
bool sb_const_binding(uint ref, uint scalar)
{
    uint kind = rt_term_kind(ref);
    if (kind != RT_KIND_CC_VALUE && kind != RT_KIND_CC_CAST) return false;
    return scalar == 0u || rt_term_words(ref).x == scalar;
}

// Validates request (decl, env). SB_OK or the failing status.
public uint sb_validate(uint decl, uint env)
{
    if (rt_counts[RT_C_READY] == 0u) return SB_NOT_READY;
    if (decl == 0u || decl >= rt_counts[RT_A_DECLS] || decl >= rt_capacity(RT_A_DECLS)) return SB_DECL;
    uint def = rt_decl_def[decl];
    if (def == 0u || def - 1u >= rt_counts[RT_A_DIR]) return SB_DECL;
    uint entry = def - 1u;
    uint4 d0 = rt_dir[entry * RT_DIR_WORDS];
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    uint4 d3 = rt_dir[entry * RT_DIR_WORDS + 3u];
    if (d0.x != decl || d0.w != RT_DIR_COMMITTED || d3.w != 0u) return SB_DECL;
    uint type_count = d1.y & 0xffffu;
    uint const_count = d1.y >> 16u;
    if (type_count > 32u || const_count > 32u) return SB_ENV;
    if (!rt_is_stored_term(env) || env >= rt_counts[RT_A_TERMS] || rt_term_kind(env) != RT_KIND_ENV ||
        !rt_term_closed(env)) return SB_ENV;
    uint4 head = rt_term_head[env];
    uint type_mask = head.z;
    uint const_mask = head.w;
    if (head.y != decl || (type_mask & ~sb_mask(type_count)) != 0u || (const_mask & ~sb_mask(const_count)) != 0u ||
        rt_term_arity(env) != countbits(type_mask) + countbits(const_mask) ||
        (head.x >> 16u) != countbits(type_mask)) return SB_ENV;
    uint arg = 0u;
    for (uint slot = 0u; slot < type_count + const_count; slot++)
    {
        bool is_type = slot < type_count;
        uint bit = is_type ? slot : slot - type_count;
        if (((is_type ? type_mask : const_mask) >> bit & 1u) == 0u) continue;
        uint param = rt_binders[d1.x + slot];
        uint4 key = rt_param_key[param];
        uint binding = rt_term_arg(env, arg);
        arg++;
        if (key.y != (is_type ? RT_DOMAIN_TYPE : RT_DOMAIN_CONST)) return SB_INVARIANT;
        if (is_type ? !sb_type_binding(binding) : !sb_const_binding(binding, key.w)) return SB_ENV;
    }
    return SB_OK;
}

// ---------------------------------------------------------------------------
// Edges. A child reference under an environment is either resolved in
// place (an immediate value with SB_OK, or the offending reference with a
// failure status) or names a task key.
public struct SbChild
{
    public bool task;
    public uint a;      // value / offending reference, or task env
    public uint b;      // status, or task term
}

SbChild sb_immediate(uint value, uint status)
{
    SbChild c; c.task = false; c.a = value; c.b = status; return c;
}

SbChild sb_task_child(uint env, uint term)
{
    SbChild c; c.task = true; c.a = env; c.b = term; return c;
}

// A value term already in the receiving scope: arity-0 records and scalars
// are final; a compound record still needs its closed evaluation (fits).
SbChild sb_value(uint ref)
{
    if (!rt_is_resolved(ref) || ref >= RT_PARAM_BIT) return sb_immediate(ref, SB_UNRESOLVED);
    if (ref < RT_FIRST_TERM) return sb_immediate(ref, SB_OK);
    if (ref >= rt_counts[RT_A_TERMS]) return sb_immediate(ref, SB_UNRESOLVED);
    if (rt_term_arity(ref) == 0u) return sb_immediate(ref, SB_OK);
    return sb_task_child(0u, ref);
}

// The binding of parameter leaf `leaf` in binder `b`.
SbChild sb_bind_leaf(SbBinder b, uint leaf)
{
    if (b.env == 0u) return sb_immediate(leaf, SB_INVARIANT); // a closed term has no leaves
    uint param = rt_leaf_param(leaf);
    uint total = b.type_count + b.const_count;
    uint slot = 0xffffffffu;
    for (uint i = 0u; i < total; i++)
        if (rt_binders[b.base + i] == param) { slot = i; break; }
    if (slot == 0xffffffffu) return sb_immediate(leaf, SB_FOREIGN);
    bool is_const = (leaf & RT_CONST_BIT) != 0u;
    if (is_const != (slot >= b.type_count)) return sb_immediate(leaf, SB_FOREIGN);
    uint4 head = rt_term_head[b.env];
    uint index;
    if (!is_const)
    {
        if ((head.z >> slot & 1u) == 0u) return sb_immediate(leaf, SB_UNBOUND);
        index = sb_below(head.z, slot);
    }
    else
    {
        uint c = slot - b.type_count;
        if ((head.w >> c & 1u) == 0u) return sb_immediate(leaf, SB_UNBOUND);
        index = countbits(head.z) + sb_below(head.w, c);
    }
    return sb_value(rt_term_arg(b.env, index));
}

public SbChild sb_resolve(SbBinder b, uint ref)
{
    if (ref == RT_FIT_FAILED) return sb_immediate(ref, SB_PRIOR_FIT);
    if (!rt_is_resolved(ref)) return sb_immediate(ref, SB_UNRESOLVED);
    if (rt_is_slot_leaf(ref)) return sb_immediate(ref, SB_SLOT_PENDING);
    if (rt_is_param_leaf(ref))
    {
        if (rt_leaf_param(ref) == 0u || rt_leaf_param(ref) >= rt_counts[RT_A_PARAMS])
            return sb_immediate(ref, SB_UNRESOLVED);
        return sb_bind_leaf(b, ref);
    }
    if (ref < RT_FIRST_TERM) return sb_immediate(ref, SB_OK);
    if (ref >= rt_counts[RT_A_TERMS]) return sb_immediate(ref, SB_UNRESOLVED);
    if (rt_term_arity(ref) == 0u) return sb_immediate(ref, SB_OK);
    return sb_task_child(rt_term_closed(ref) ? 0u : b.env, ref);
}

public uint sb_level(uint env, uint term)
{
    return rt_term_height(term) + (env == 0u ? 0u : rt_term_height(env) - 1u);
}

// ---------------------------------------------------------------------------
// Tasks.
uint sb_alloc(uint counter, uint demand, uint capacity, uint n, uint bit)
{
    uint base;
    InterlockedAdd(sb_counts[counter], n, base);
    if (base > capacity || n > capacity - base)
    {
        sb_overflow(bit);
        InterlockedMax(sb_counts[demand], base + n);
        return RT_INVALID;
    }
    return base;
}

void sb_kill(uint task, uint level)
{
    sb_task_key[task].z = level | SB_DEAD;
    InterlockedAdd(sb_counts[SB_C_LEVEL_COUNT + level], 0xffffffffu);
    InterlockedAdd(sb_counts[SB_C_SPARE_TASKS], 1u);
}

uint sb_hash(uint env, uint term)
{
    return rt_mix(rt_mix(0x2545f491u, env), term) & sb_config[SB_CFG_HASH_MASK];
}

// The task of key (env, term), created when absent; RT_INVALID after an
// overflow. A lane that loses the slot to an equal key kills its record.
public uint sb_task_find_or_create(uint env, uint term)
{
    uint level = sb_level(env, term);
    uint arity = rt_term_arity(term);
    uint slots; uint stride; sb_memo.GetDimensions(slots, stride);
    uint slot = sb_hash(env, term) & (slots - 1u);
    uint task = RT_INVALID;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint value = sb_memo[slot];
        if (value == 0u)
        {
            if (task == RT_INVALID)
            {
                task = sb_alloc(SB_C_TASKS, SB_C_DEMAND_TASKS, sb_task_capacity(), 1u, SB_OVERFLOW_TASKS);
                if (task == RT_INVALID) return RT_INVALID;
                uint edge = sb_alloc(SB_C_EDGES, SB_C_DEMAND_EDGES, sb_edge_capacity(), arity, SB_OVERFLOW_EDGES);
                InterlockedAdd(sb_counts[SB_C_LEVEL_COUNT + level], 1u);
                if (edge == RT_INVALID) { sb_task_key[task] = uint4(env, term, level, 0u); sb_kill(task, level); return RT_INVALID; }
                sb_task_key[task] = uint4(env, term, level, edge);
                sb_task_res[task] = uint4(RT_UNKNOWN, SB_PENDING, RT_NONE, 0u);
                sb_task_fail[task] = RT_NONE;
                InterlockedMax(sb_counts[SB_C_NEXT_ARITY], arity);
                InterlockedMax(sb_counts[SB_C_MAX_LEVEL], level);
            }
            DeviceMemoryBarrier();
            InterlockedCompareExchange(sb_memo[slot], 0u, task + 1u, value);
            if (value == 0u) return task;
        }
        DeviceMemoryBarrier();
        uint4 other = sb_task_key[value - 1u];
        if (other.x == env && other.y == term)
        {
            if (task != RT_INVALID) sb_kill(task, level);
            return value - 1u;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    sb_overflow(SB_OVERFLOW_MEMO);
    if (task != RT_INVALID) sb_kill(task, level);
    return RT_INVALID;
}

// The edge word of a resolved child: an immediate, or the child's task.
public uint2 sb_edge(SbChild c)
{
    if (!c.task) return uint2(c.a, c.b);
    if (sb_level(c.a, c.b) >= SB_LEVELS) return uint2(c.b, SB_DEPTH);
    uint task = sb_task_find_or_create(c.a, c.b);
    if (task == RT_INVALID) return uint2(c.b, SB_CAPACITY);
    return uint2(task, SB_EDGE_TASK);
}

// ---------------------------------------------------------------------------
// Dispatch arguments (planners only: a kernel dispatched indirectly must not
// bind sb_dispatch).
public static const uint SB_D_ROOTS = 0u;
public static const uint SB_D_EXPAND = 1u;
public static const uint SB_D_SCATTER = 2u;
public static const uint SB_D_EVAL = 3u;
public static const uint SB_D_PUBLISH = 4u;
public static const uint SB_D_ROLLBACK = 5u;
public static const uint SB_D_SLOTS = 6u;
