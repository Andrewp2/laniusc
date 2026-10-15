// Substitution over canonical IDs (docs/canonical-type-ids.md, "Substitution
// as a memo table"). ct_subst(slots, env, t) is the canonical ID of `t` with
// the parameters of environment `env` replaced by its bindings.
//
// - An environment is a CT_ENV record (ct_env.slang: bound type slots, then
//   bound constant slots; a mask hole is an unbound slot) or a CT_NAMED
//   application (a nominal receiver: type slot i is its i-th type operand).
// - Parameters map to slots through the kernel's ICtSlots adapter: a local
//   parameter by its declaration slot, a dependency parameter by the slot it
//   carries. A binding is already in the caller's scope and is never
//   substituted again. Envs reach only terms of their own binder; owners are
//   validated where bindings are produced.
// - Closed subterms map to themselves, so only open nodes are visited.
//
// There is no stack. A lane descends from the root to the first open child
// without a memo entry, builds and interns that node from its children's
// results, records it in the memo and starts again from the root. The memo
// is keyed by (env, t) and is only a cache: identity rests on interning, so
// a lost or duplicated memo entry costs work, never correctness.
//
// Graph-free: this module reads no checked-graph table.
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
__exported import type_checker.substitution.ct_spare;

// Memo slots: x = env, y = term, z = result (0 until written), w = claim.
// Power-of-two length; cleared to zero once per job.
public globallycoherent RWStructuredBuffer<uint4> ct_subst_memo;
// Substitution and realization counters; see CT_SUBST_COUNT_*.
public globallycoherent RWStructuredBuffer<uint> ct_subst_counts;

public static const uint CT_SUBST_COUNT_OVERFLOW = 0u;  // CT_SUBST_OVERFLOW_* bits
public static const uint CT_SUBST_COUNT_WORDS = 8u;
public static const uint CT_SUBST_OVERFLOW_MEMO = 1u;
public static const uint CT_SUBST_OVERFLOW_WORK = 2u;
public static const uint CT_SUBST_OVERFLOW_ROWS = 4u;
public static const uint CT_SUBST_OVERFLOW_CONSTANTS = 8u;

// Builds per substitution and memo probes per lookup. A term has at most
// CT_MAX_ARITY children per level and the old walkers capped depth at 64.
static const uint CT_SUBST_WORK_LIMIT = 1024u;
static const uint CT_SUBST_DEPTH_LIMIT = 64u;
static const uint CT_SUBST_PROBE_LIMIT = 64u;

public void ct_subst_flag(uint bits)
{
    InterlockedOr(ct_subst_counts[CT_SUBST_COUNT_OVERFLOW], bits);
}

// ---------------------------------------------------------------------------
// Memo table.
uint memo_capacity()
{
    uint count; uint stride;
    ct_subst_memo.GetDimensions(count, stride);
    return count;
}

uint memo_start(uint env, uint term)
{
    uint2 hash = ct_hash_word(ct_hash_word(CT_HASH_SEED, env), term);
    return (hash.x ^ (hash.y * 0x27d4eb2du)) & (memo_capacity() - 1u);
}

// The memoized result of (env, term), or CT_PENDING. Acquire: the result's
// record was published before the memo entry.
public uint ct_subst_memo_find(uint env, uint term)
{
    uint capacity = memo_capacity();
    if (capacity == 0u) return CT_PENDING;
    uint slot = memo_start(env, term);
    for (uint probe = 0u; probe < CT_SUBST_PROBE_LIMIT; probe++)
    {
        uint4 entry = ct_subst_memo[slot];
        if (entry.w == 0u) return CT_PENDING;
        if (entry.z != 0u && entry.x == env && entry.y == term)
        {
            DeviceMemoryBarrier();
            return entry.z;
        }
        slot = (slot + 1u) & (capacity - 1u);
    }
    return CT_PENDING;
}

// Record (env, term) -> result. An entry is claimed, its key written, then
// (release) its result; readers ignore an entry whose result is still 0.
public bool ct_subst_memo_insert(uint env, uint term, uint result)
{
    uint capacity = memo_capacity();
    if (capacity == 0u) return false;
    uint slot = memo_start(env, term);
    for (uint probe = 0u; probe < CT_SUBST_PROBE_LIMIT; probe++)
    {
        uint claim;
        InterlockedCompareExchange(ct_subst_memo[slot].w, 0u, 1u, claim);
        if (claim == 0u)
        {
            ct_subst_memo[slot].x = env;
            ct_subst_memo[slot].y = term;
            DeviceMemoryBarrier();
            ct_subst_memo[slot].z = result;
            return true;
        }
        uint4 entry = ct_subst_memo[slot];
        if (entry.z != 0u && entry.x == env && entry.y == term) return true;
        slot = (slot + 1u) & (capacity - 1u);
    }
    ct_subst_flag(CT_SUBST_OVERFLOW_MEMO);
    return false;
}

// ---------------------------------------------------------------------------
// Substitution.

// A parameter leaf under `env`: its binding, CT_UNKNOWN when unbound.
public uint ct_subst_param<S : ICtSlots>(S slots, uint env, uint param)
{
    return ct_env_binding(env, ct_param_slot(slots, param), ct_is_const_param(param));
}

// Child `child` of a node under `env`: closed children are themselves,
// parameters their bindings, open records their memoized result
// (CT_PENDING when not built yet).
uint subst_child<S : ICtSlots>(S slots, uint env, uint child)
{
    if (ct_is_param(child)) return ct_subst_param(slots, env, child);
    if (ct_closed(child)) return child;
    return ct_subst_memo_find(env, child);
}

// The first open child of `node` without a result under `env`, or CT_NONE.
uint pending_child(uint env, uint node)
{
    uint arity = ct_arity(node);
    for (uint index = 0u; index < arity; index++)
    {
        uint child = ct_arg(node, index);
        if (!ct_is_param(child) && !ct_closed(child) && ct_subst_memo_find(env, child) == CT_PENDING)
            return child;
    }
    return CT_NONE;
}

// Build `node` under `env` from its children's results and intern it (or,
// without `intern`, look it up). Every child must have a result.
uint subst_build<S : ICtSlots>(S slots, uint env, uint node, bool intern, inout CtSpare spare)
{
    // Acquire: the node's children were published before their references.
    DeviceMemoryBarrier();
    uint kind = ct_kind(node);
    uint arity = ct_arity(node);
    CtKey key = ct_empty_key();
    if (kind == CC_KIND_CAST)
    {
        uint child = subst_child(slots, env, ct_arg(node, 0u));
        if (!ct_is_resolved(child)) return CT_UNKNOWN;
        uint param_scalar = ct_is_const_param(child) ? ct_param_scalar(slots, child) : 0u;
        // A concrete child folds to a value of the target scalar; a symbolic
        // one is a cast (ct_build_projection writes its one argument).
        bool fold; uint3 value;
        uint status = ct_build_projection(ct_words(node).x, child, param_scalar, fold, value, key);
        if (fold) status = ct_build_value(value, key);
        if (status != CT_KEY_BUILT) return status;
        return ct_spare_publish(key, key.extra, intern, spare);
    }
    // An environment keeps its masks and substitutes its bindings, so a
    // call site's environment composes with its caller's.
    if ((kind < CT_KIND_NAMED || kind > CT_KIND_REF) && kind != CT_KIND_ENV) return CT_UNKNOWN;
    key = ct_key_begin(kind, arity, ct_type_slots(node), ct_words(node));
    if (!ct_spare_reserve(spare, key)) return CT_UNKNOWN;
    for (uint index = 0u; index < arity; index++)
    {
        uint child = subst_child(slots, env, ct_arg(node, index));
        // Array identity uses the length's count class, not its typed value.
        if (kind == CT_KIND_ARRAY && index == 1u && ct_is_resolved(child)) child = cc_count_class(child);
        if (!ct_is_resolved(child)) return CT_UNKNOWN;
        ct_key_arg(key, index, child);
    }
    if (!key.ok) return CT_UNKNOWN;
    // A named record keeps its bridge token and constant-operand mask.
    uint2 extra = kind == CT_KIND_NAMED ? ct_extra[node] : uint2(0xffffffffu, 0u);
    return ct_spare_publish(key, extra, intern, spare);
}

// The ID of `term` under `env`; CT_UNKNOWN when a parameter is unbound or a
// shape is unsupported, CT_NONE when `intern` is false and the result does
// not exist. CT_NONE as `env` substitutes nothing.
public uint ct_subst<S : ICtSlots>(S slots, uint env, uint term, bool intern, inout CtSpare spare)
{
    if (!ct_is_resolved(term)) return CT_UNKNOWN;
    if (env == CT_NONE) return term;
    if (ct_is_param(term)) return ct_subst_param(slots, env, term);
    if (ct_closed(term)) return term;
    uint result = ct_subst_memo_find(env, term);
    if (result != CT_PENDING) return result;
    for (uint work = 0u; work < CT_SUBST_WORK_LIMIT; work++)
    {
        // Descend to an open node whose open children all have results.
        // Each step is a call result, so the loop carries one value.
        uint node = term;
        uint child = pending_child(env, node);
        for (uint depth = 0u; depth < CT_SUBST_DEPTH_LIMIT && child != CT_NONE; depth++)
        {
            node = child;
            child = pending_child(env, node);
        }
        if (child != CT_NONE) break;
        result = subst_build(slots, env, node, intern, spare);
        if (!ct_is_resolved(result)) return result;
        bool stored = ct_subst_memo_insert(env, node, result);
        if (node == term) return result;
        if (!stored) return CT_UNKNOWN;
    }
    ct_subst_flag(CT_SUBST_OVERFLOW_WORK);
    return CT_UNKNOWN;
}
