// Production substitution over retained program terms
// (docs/compiler-retained-substitution.md).
//
// A request names a declaration (DeclId), a normalized closed ENV term owned
// by that declaration and a term over the declaration's binder chain. The
// result is the exactly interned closed term, or a status with the exact
// provenance of the failure.
//
// Work is a memoized task graph. A task is one unique key
//   (binding environment, term)
// where the environment is the request's validated ENV TermId (its owner
// word is the owning definition) or 0 for the environment-independent
// evaluation of a closed term, which still carries pending CC_CAST fits.
// Leaves (scalars, arity-0 records, parameter leaves and sentinels) never
// become tasks: an edge resolves them in place. Each request also evaluates
// its ENV as a closed term (environment 0): the request is accepted only
// when that evaluation succeeds and returns the ENV itself.
//
// Phases of one attempt (each a GPU kernel, planners are single lanes):
//   00 begin        open the transaction, publish the root dispatch
//   01 roots        one lane per request: validate, create the root tasks
//   02 plan         plans one round of step 3: the next expansion
//                   frontier (tasks created by the last round), the
//                   scatter, or the next nonempty level
//   03 step         expansion: one lane per (frontier task, child index);
//                   scatter: one lane per task, bucket by level;
//                   evaluation: one lane per task of the level
//   04 publish      one lane per request
//   05 finish       commit, or roll back the store terms of the attempt
//   06 rollback     one lane per store term slot
// Rounds of (02, 03) run expansion, then the scatter, then evaluation, so
// the two share the rounds a batch records.
// A task's level is height(term) + height(env) - 1 (height(term) for
// env 0). Every child task has a strictly lower level, so evaluation in
// increasing level order sees every child result.
import primitive_types;
import constant_value;
import type_checker.retention.retention_store;
__exported import type_checker.retention.substitution.sb_layout;

// Requests (producer-owned): (DeclId, ENV TermId, term reference, tag).
public StructuredBuffer<uint4> sb_requests;
public StructuredBuffer<uint> sb_request_count;

public globallycoherent RWStructuredBuffer<uint> sb_counts;     // SB_C_* status words
public RWStructuredBuffer<uint> sb_config;                      // SB_CFG_*
// Per request, two uint4: (term edge, environment edge) and the request
// validation (status, ENV cause, failed node, failed value).
public globallycoherent RWStructuredBuffer<uint4> sb_req_root;
// Published results, SB_RESULT_WORDS uint4 per request:
//   r0 (result TermId or RT_UNKNOWN, status, failed node, failed env)
//   r1 (failed child value, request tag, run, store generation)
//   r2 (ENV cause, inner status, inner ENV cause, 0)
public globallycoherent RWStructuredBuffer<uint4> sb_results;
// Tasks: key (env, term, level | SB_DEAD, edge base); result (value,
// status, failed node, failed env); (failed child value, ENV cause).
public globallycoherent RWStructuredBuffer<uint4> sb_task_key;
public globallycoherent RWStructuredBuffer<uint4> sb_task_res;
public globallycoherent RWStructuredBuffer<uint2> sb_task_fail;
// Immutable candidate headers and slots (task + 1, published term).
public globallycoherent RWStructuredBuffer<uint4> sb_term_keys;
public globallycoherent RWStructuredBuffer<uint2> sb_term_slots;
// Edges: one uint2 per child of a task, (value, status) or (memo slot, SB_EDGE_TASK).
public globallycoherent RWStructuredBuffer<uint2> sb_edges;
// Zero in a key column means unclaimed. The environment is stored plus one.
public struct SbMemoEntry
{
    public uint environment;
    public uint term;
    public uint task;
}
public globallycoherent RWStructuredBuffer<SbMemoEntry> sb_memo;
// Live tasks ordered by level.
public globallycoherent RWStructuredBuffer<uint> sb_order;

public uint4 sb_task_result(uint task, out uint2 fault)
{
    uint4 result = sb_task_res[task];
    fault = sb_task_fail[task];
    if (result.y != SB_TERM_SLOT) return result;
    uint term = sb_term_slots[result.x].y;
    if (!rt_is_term(term)) return uint4(RT_UNKNOWN, SB_CAPACITY, result.zw);
    if (!rt_term_closed(term))
    {
        fault = uint2(term, SB_ENV_NONE);
        return uint4(RT_UNKNOWN, SB_INVARIANT, result.zw);
    }
    return uint4(term, SB_OK, RT_NONE, 0u);
}

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
    return min(min(a, b / SB_ROOT_WORDS), c / SB_RESULT_WORDS);
}

public uint sb_request_total() { return sb_counts[SB_C_REQUESTS]; }

public void sb_overflow(uint bit) { InterlockedOr(sb_counts[SB_C_OVERFLOW], bit); }

// ---------------------------------------------------------------------------
// Term kind classes of closed operands.

// A type: a scalar or a NAMED, ARRAY, SLICE or REF record.
public bool sb_is_type(uint ref)
{
    uint kind = rt_term_kind(ref);
    return kind == RT_KIND_SCALAR || kind == RT_KIND_NAMED || kind == RT_KIND_ARRAY ||
        kind == RT_KIND_SLICE || kind == RT_KIND_REF;
}

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

public uint sb_mask(uint count) { return count >= 32u ? 0xffffffffu : (1u << count) - 1u; }
uint sb_below(uint mask, uint index) { return countbits(index >= 32u ? mask : mask & ((1u << index) - 1u)); }

// A check outcome: SB_OK, or the status, ENV cause, failed node and failed
// value.
public struct SbCheck
{
    public uint status;
    public uint cause;
    public uint node;
    public uint value;
}

public SbCheck sb_check(uint status, uint cause, uint node, uint value)
{
    SbCheck c; c.status = status; c.cause = cause; c.node = node; c.value = value; return c;
}

public SbCheck sb_check_ok() { return sb_check(SB_OK, SB_ENV_NONE, RT_NONE, RT_NONE); }

// The committed directory entry of `decl` plus one, or 0.
uint sb_committed_entry(uint decl)
{
    if (decl == 0u || decl >= rt_counts[RT_A_DECLS] || decl >= rt_capacity(RT_A_DECLS)) return 0u;
    uint def = rt_decl_def[decl];
    if (def == 0u || def - 1u >= rt_counts[RT_A_DIR]) return 0u;
    uint4 d0 = rt_dir[(def - 1u) * RT_DIR_WORDS];
    if (d0.x != decl || d0.w != RT_DIR_COMMITTED) return 0u;
    return def;
}

// An ENV record `env` (head `head`, arguments `args`) against its owner's
// committed binder: the owner word, the 32-slot limit, the masks, arity and
// type-slot count, then every bound slot. A type slot takes a type. A
// constant slot takes a CC_VALUE of the parameter's declared scalar (0 when
// none is recorded) or, when `pending` (an unevaluated request ENV), a
// CC_CAST to that scalar, which the ENV's own closed evaluation folds.
// `owner` is the required owner, or 0 for any committed declaration.
public SbCheck sb_check_env<A : IRtArgs>(uint env, uint4 head, A args, uint owner, bool pending)
{
    uint decl = head.y;
    if (decl == 0u || (owner != 0u && decl != owner)) return sb_check(SB_ENV, SB_ENV_OWNER, env, RT_NONE);
    uint def = sb_committed_entry(decl);
    if (def == 0u) return sb_check(SB_DECL, SB_ENV_NONE, env, RT_NONE);
    uint4 d1 = rt_dir[(def - 1u) * RT_DIR_WORDS + 1u];
    uint type_count = d1.y & 0xffffu;
    uint const_count = d1.y >> 16u;
    if (type_count > 32u || const_count > 32u) return sb_check(SB_LIMIT, SB_ENV_NONE, env, RT_NONE);
    uint type_mask = head.z;
    uint const_mask = head.w;
    uint arity = (head.x >> 8u) & 0xffu;
    if ((type_mask & ~sb_mask(type_count)) != 0u || (const_mask & ~sb_mask(const_count)) != 0u ||
        arity != countbits(type_mask) + countbits(const_mask) || (head.x >> 16u) != countbits(type_mask))
        return sb_check(SB_ENV, SB_ENV_SHAPE, env, RT_NONE);
    uint arg = 0u;
    for (uint slot = 0u; slot < type_count + const_count; slot++)
    {
        bool is_type = slot < type_count;
        uint bit = is_type ? slot : slot - type_count;
        if (((is_type ? type_mask : const_mask) >> bit & 1u) == 0u) continue;
        uint param = rt_binders[d1.x + slot];
        uint4 key = rt_param_key[param];
        uint binding = args.arg(arg);
        arg++;
        if (param == 0u || param >= rt_counts[RT_A_PARAMS] ||
            key.y != (is_type ? RT_DOMAIN_TYPE : RT_DOMAIN_CONST)) return sb_check(SB_INVARIANT, SB_ENV_NONE, env, RT_NONE);
        bool fits;
        if (is_type) fits = sb_is_type(binding);
        else
        {
            uint kind = rt_term_kind(binding);
            fits = (kind == RT_KIND_CC_VALUE || (pending && kind == RT_KIND_CC_CAST)) &&
                (key.w == 0u || rt_term_words(binding).x == key.w);
        }
        if (!fits) return sb_check(SB_ENV, SB_ENV_BINDING, binding, rt_param_leaf(param));
    }
    return sb_check_ok();
}

// A closed nominal application is already a complete binding context for
// its own schema. Keep it as the memo key instead of allocating a duplicate
// ENV. Nominal arguments may interleave domains; binders group types first.
uint sb_nth(uint mask, uint ordinal)
{
    for (uint i = 0u; i < ordinal; i++) mask &= mask - 1u;
    return uint(firstbitlow(mask));
}
struct SbNominalArgs : IRtArgs
{
    uint term;
    uint types;
    uint arg(uint index)
    {
        uint mask = rt_term_head[term].z;
        uint slots = index < types ? (~mask & sb_mask(rt_term_arity(term))) : mask;
        return rt_term_arg(term, sb_nth(slots, index < types ? index : index-types));
    }
}

SbCheck sb_check_nominal(uint decl, uint term, uint counts)
{
    uint4 head = rt_term_head[term];
    uint types = counts & 0xffffu;
    uint constants = counts >> 16u;
    uint arity = rt_term_arity(term);
    if (arity > 32u) return sb_check(SB_LIMIT, SB_ENV_NONE, term, RT_NONE);
    if (arity != types+constants || (head.x >> 16u) != types ||
        (head.z & ~sb_mask(arity)) != 0u || countbits(head.z) != constants)
        return sb_check(SB_ENV, SB_ENV_SHAPE, term, RT_NONE);
    SbNominalArgs args;
    args.term = term; args.types = types;
    uint4 env_head = uint4(RT_KIND_ENV | (arity << 8u) | (types << 16u),
        head.y, sb_mask(types), sb_mask(constants));
    return sb_check_env(term, env_head, args, decl, true);
}

// Validates request (decl, env, term) before it creates any task.
public SbCheck sb_validate(uint decl, uint env, uint term)
{
    if (rt_counts[RT_C_READY] == 0u) return sb_check(SB_NOT_READY, SB_ENV_NONE, term, RT_NONE);
    uint def = sb_committed_entry(decl);
    if (def == 0u || rt_dir[(def - 1u) * RT_DIR_WORDS + 3u].w != 0u)
        return sb_check(SB_DECL, SB_ENV_NONE, term, RT_NONE);
    uint counts = rt_dir[(def - 1u) * RT_DIR_WORDS + 1u].y;
    if ((counts & 0xffffu) > 32u || (counts >> 16u) > 32u) return sb_check(SB_LIMIT, SB_ENV_NONE, env, RT_NONE);
    if (!rt_is_stored_term(env) || env >= rt_counts[RT_A_TERMS] ||
        !rt_term_closed(env)) return sb_check(SB_ENV, SB_ENV_NOT_ENV, env, RT_NONE);
    uint kind = rt_term_kind(env);
    uint owner_kind = rt_dir[(def - 1u) * RT_DIR_WORDS].y;
    if (kind == RT_KIND_NAMED && (owner_kind == 5u || owner_kind == 6u))
        return sb_check_nominal(decl,env,counts);
    if (kind != RT_KIND_ENV) return sb_check(SB_ENV, SB_ENV_NOT_ENV, env, RT_NONE);
    RtStoredArgs args;
    args.base = rt_term_meta[env].x;
    return sb_check_env(env, rt_term_head[env], args, decl, true);
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
    // sb_resolve checked the leaf's constant bit against its parameter's
    // domain; a binder slot of the other domain is an inconsistent binder.
    bool is_const = (leaf & RT_CONST_BIT) != 0u;
    if (is_const != (slot >= b.type_count)) return sb_immediate(leaf, SB_INVARIANT);
    uint4 head = rt_term_head[b.env];
    if ((head.x & 0xffu) == RT_KIND_NAMED)
    {
        uint mask = is_const ? head.z : (~head.z & sb_mask(rt_term_arity(b.env)));
        uint index = sb_nth(mask, is_const ? slot-b.type_count : slot);
        return sb_value(rt_term_arg(b.env,index));
    }
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
        uint param = rt_leaf_param(ref);
        if (param == 0u || param >= rt_counts[RT_A_PARAMS]) return sb_immediate(ref, SB_UNRESOLVED);
        // A leaf's constant bit is its parameter's domain (rt_param_leaf).
        uint domain = rt_param_key[param].y;
        if (((ref & RT_CONST_BIT) != 0u) != (domain == RT_DOMAIN_CONST) ||
            (domain != RT_DOMAIN_TYPE && domain != RT_DOMAIN_CONST)) return sb_immediate(ref, SB_INVARIANT);
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

// Claim the exact key in two steps. The environment is immutable once
// claimed, so a lane can claim the term even if another lane set the
// environment. Only the term's winner allocates a task and its edges.
// Consumers resolve the slot to a task in a later dispatch.
uint sb_task_slot(uint env, uint term)
{
    uint slots; uint stride; sb_memo.GetDimensions(slots, stride);
    uint slot = sb_hash(env, term) & (slots - 1u);
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint saved_env = sb_memo[slot].environment;
        if (saved_env == 0u)
            InterlockedCompareExchange(sb_memo[slot].environment, 0u, env + 1u, saved_env);
        if (saved_env == 0u || saved_env == env + 1u)
        {
            uint saved_term = sb_memo[slot].term;
            if (saved_term == 0u)
                InterlockedCompareExchange(sb_memo[slot].term, 0u, term, saved_term);
            if (saved_term == 0u)
            {
                uint task = sb_alloc(SB_C_TASKS, SB_C_DEMAND_TASKS, sb_task_capacity(), 1u, SB_OVERFLOW_TASKS);
                if (task == RT_INVALID) return RT_INVALID;
                uint arity = rt_term_arity(term);
                uint level = sb_level(env, term);
                uint edge = sb_alloc(SB_C_EDGES, SB_C_DEMAND_EDGES, sb_edge_capacity(), arity, SB_OVERFLOW_EDGES);
                InterlockedAdd(sb_counts[SB_C_LEVEL_COUNT + level], 1u);
                if (edge == RT_INVALID) { sb_task_key[task] = uint4(env, term, level, 0u); sb_kill(task, level); return RT_INVALID; }
                sb_task_key[task] = uint4(env, term, level, edge);
                sb_task_res[task] = uint4(RT_UNKNOWN, SB_PENDING, RT_NONE, 0u);
                sb_task_fail[task] = uint2(RT_NONE, SB_ENV_NONE);
                InterlockedMax(sb_counts[SB_C_NEXT_ARITY], arity);
                InterlockedMax(sb_counts[SB_C_MAX_LEVEL], level);
                sb_memo[slot].task = task;
                return slot;
            }
            if (saved_term == term) return slot;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    sb_overflow(SB_OVERFLOW_MEMO);
    return RT_INVALID;
}

public uint sb_edge_task(uint slot) { return sb_memo[slot].task; }

// The edge word of a resolved child: an immediate, or the child's memo slot.
public uint2 sb_edge(SbChild c)
{
    if (!c.task) return uint2(c.a, c.b);
    if (sb_level(c.a, c.b) >= SB_LEVELS) return uint2(c.b, SB_DEPTH);
    uint slot = sb_task_slot(c.a, c.b);
    if (slot == RT_INVALID) return uint2(c.b, SB_CAPACITY);
    return uint2(slot, SB_EDGE_TASK);
}

// ---------------------------------------------------------------------------
// Dispatch arguments (planners only: a kernel dispatched indirectly must not
// bind sb_dispatch).
public static const uint SB_D_ROOTS = 0u;
public static const uint SB_D_STEP = 1u;
public static const uint SB_D_PUBLISH = 2u;
public static const uint SB_D_ROLLBACK = 3u;
public static const uint SB_D_SLOTS = 4u;
