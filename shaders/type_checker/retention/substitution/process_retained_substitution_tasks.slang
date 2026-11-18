// Substitution step 3: the work of one round, chosen by the phase that
// step 2 left. No lane of a step writes the phase, so every lane of one
// dispatch takes the same branch.
//
// Expansion: one lane per (frontier task, child index). Resolves the child
// under the task's environment and writes the task's edge: an immediate
// value or failure, or the child's (possibly new) task. Each lane handles
// exactly one edge (and compares its argument with the earlier ones, at
// most 63); new tasks form the next frontier.
//
// Scatter: one lane per task. Places each live task in its level's block of
// sb_order.
//
// Evaluation: one lane per task of the current level. Every child
// result is final (children have lower levels). The first failing child in
// argument order decides the task's failure and its provenance, which is
// copied from that child's own result: provenance never depends on which
// lane created a task or on memo contents.
//
// Kinds (docs/compiler-retained-substitution.md, "Evaluation rules"):
// - NAMED keeps its words. Its head's type-slot count is its type-operand
//   count (canonical_candidates build_row), its constant-operand mask has
//   no bit at or past the arity, an operand under a mask bit is a CC_VALUE
//   and every other operand is a type. At most 32 operands.
// - ARRAY takes a type element and its length's count class (CC_COUNT), so
//   equal counts of different scalars give one array identity. SLICE and
//   REF take a type element.
// - ENV keeps its words and is checked against its owner's committed binder
//   (sb_check_env): owner, masks, arity, binding classes and declared
//   constant scalars.
// - CC_CAST folds its child's typed value to the target scalar with the
//   canonical rules (ct_build_projection) or fails its fit; this applies to
//   closed casts too, so a result never keeps a CC_CAST.
// - A type result taller than 64 levels is DEPTH. An ENV is not a type: its
//   height is one more than its tallest binding, and only the bindings,
//   which are types and values, are held to the 64-level limit.
import shared.semantics.primitive_types;
import shared.semantics.constant_value;
import type_checker.retention.retention_store;
import type_checker.retention.substitution.retained_substitution_workspace;

struct EdgeArgs : IRtArgs
{
    uint base;
    uint arg(uint index) { return sb_edges[base + index].x; }
}

void finish(uint task, uint value, uint status, uint node, uint env, uint fail_value, uint cause)
{
    sb_task_res[task] = uint4(value, status, node, env);
    sb_task_fail[task] = uint2(fail_value, cause);
}

void fail(uint task, uint status, uint node, uint env, uint fail_value)
{
    finish(task, RT_UNKNOWN, status, node, env, fail_value, SB_ENV_NONE);
}

// The CC_COUNT record of `count`, interned like the canonical cc_intern_count.
uint count_class(uint count)
{
    RtTermKey key = rt_key_begin(RT_KIND_CC_COUNT, 0u, 0u, uint3(count, 0u, 0u));
    RtStoredArgs none; none.base = 0u;
    return rt_intern_term(key, none);
}

void store_failed(uint task, uint term, uint env)
{
    sb_overflow(SB_OVERFLOW_STORE);
    fail(task, SB_CAPACITY, term, env, RT_NONE);
}

// Publish an immutable candidate address, then let just the winner allocate.
// Edges and root publication resolve the slot after this dispatch.
void stage_result(uint task, uint term, uint env, RtTermKey key, EdgeArgs args)
{
    uint4 header = uint4(key.head, key.words);
    sb_term_keys[task] = header;
    uint slots; uint stride;
    sb_term_slots.GetDimensions(slots, stride);
    uint slot = (key.hash.x & sb_config[SB_CFG_HASH_MASK]) & (slots - 1u);
    uint arity = (key.head >> 8u) & 0xffu;
    for (uint probe = 0u; probe < slots; probe++)
    {
        uint prior = sb_term_slots[slot].x;
        if (prior == 0u)
        {
            DeviceMemoryBarrier();
            InterlockedCompareExchange(sb_term_slots[slot].x, 0u, task + 1u, prior);
            if (prior == 0u)
            {
                uint result = rt_intern_term(key, args);
                sb_term_slots[slot].y = result;
                if (!rt_is_term(result)) { store_failed(task, term, env); return; }
                finish(task, slot, SB_TERM_SLOT, term, env, RT_NONE, SB_ENV_NONE);
                return;
            }
        }
        DeviceMemoryBarrier();
        bool same = all(sb_term_keys[prior - 1u] == header);
        uint base = sb_task_key[prior - 1u].w;
        for (uint i = 0u; same && i < arity; i++)
            same = sb_edges[base + i].x == args.arg(i);
        if (same)
        {
            finish(task, slot, SB_TERM_SLOT, term, env, RT_NONE, SB_ENV_NONE);
            return;
        }
        slot = (slot + 1u) & (slots - 1u);
    }
    fail(task, SB_INVARIANT, term, env, RT_NONE);
}

void expand_round(uint3 dtid)
{
    uint lane = sb_lane(dtid);
    uint arity_stride = sb_counts[SB_C_FRONTIER_ARITY];
    if (arity_stride == 0u) return;
    uint task = sb_counts[SB_C_FRONTIER_LO] + lane / arity_stride;
    uint index = lane % arity_stride;
    if (task >= sb_counts[SB_C_FRONTIER_HI]) return;
    uint4 key = sb_task_key[task];
    if ((key.z & SB_DEAD) != 0u) return;
    if (index >= rt_term_arity(key.y)) return;
    // A repeated argument (Pair<D, D>) shares the first occurrence's edge,
    // so two lanes of one task never race to create one child task.
    uint child = rt_term_arg(key.y, index);
    for (uint j = 0u; j < index; j++)
    {
        if (rt_term_arg(key.y, j) == child)
        {
            sb_edges[key.w + index] = uint2(j, SB_EDGE_SAME);
            return;
        }
    }
    SbBinder b = sb_binder(key.x);
    sb_edges[key.w + index] = sb_edge(sb_resolve(b, child));
    InterlockedAdd(sb_counts[SB_C_EDGES_RESOLVED], 1u);
}

void scatter_round(uint3 dtid)
{
    uint task = sb_lane(dtid);
    if (sb_counts[SB_C_PHASE] != SB_PHASE_SCATTER) return;
    if (task >= min(sb_counts[SB_C_TASKS], sb_task_capacity())) return;
    uint level = sb_task_key[task].z;
    if ((level & SB_DEAD) != 0u) return;
    uint at;
    InterlockedAdd(sb_counts[SB_C_LEVEL_CURSOR + level], 1u, at);
    sb_order[sb_counts[SB_C_LEVEL_BASE + level] + at] = task;
}

void eval_round(uint3 dtid)
{
    uint lane = sb_lane(dtid);
    if (sb_counts[SB_C_PHASE] != SB_PHASE_EVAL) return;
    uint level = sb_counts[SB_C_LEVEL];
    if (level >= SB_LEVELS || lane >= sb_counts[SB_C_LEVEL_COUNT + level]) return;
    uint task = sb_order[sb_counts[SB_C_LEVEL_BASE + level] + lane];
    uint4 key = sb_task_key[task];
    uint env = key.x;
    uint term = key.y;
    uint base = key.w;
    uint4 head = rt_term_head[term];
    uint kind = head.x & 0xffu;
    uint arity = (head.x >> 8u) & 0xffu;

    // Child values, in argument order; the first failure wins.
    for (uint i = 0u; i < arity; i++)
    {
        uint2 e = sb_edges[base + i];
        if (e.y == SB_EDGE_SAME) { sb_edges[base + i] = sb_edges[base + e.x]; continue; }
        if (e.y == SB_EDGE_TASK)
        {
            uint2 f;
            uint4 r = sb_task_result(sb_edge_task(e.x), f);
            if (r.y != SB_OK)
            {
                finish(task, RT_UNKNOWN, r.y == SB_PENDING ? SB_INVARIANT : r.y, r.z, r.w, f.x, f.y);
                return;
            }
            sb_edges[base + i] = uint2(r.x, SB_OK);
        }
        else if (e.y != SB_OK)
        {
            fail(task, e.y, e.x, env, RT_NONE);
            return;
        }
    }

    uint3 words = head.yzw;
    if (kind == RT_KIND_CC_CAST)
    {
        uint child = sb_edges[base].x;
        if (rt_term_kind(child) != RT_KIND_CC_VALUE) { fail(task, SB_UNSUPPORTED, term, env, child); return; }
        // ct_build_projection: a value whose count is not a count, including
        // the count word 0xffffffff that the canonical store reserves for
        // "not a count", has no folded identity.
        uint count;
        if (!constant_value_to_count(rt_term_words(child), count) || count == 0xffffffffu)
        {
            fail(task, SB_UNSUPPORTED, term, env, child);
            return;
        }
        uint3 value;
        if (!constant_value_from_count(count, words.x, value)) { fail(task, SB_FIT_FAILED, term, env, child); return; }
        EdgeArgs no_args;
        no_args.base = 0u;
        stage_result(task, term, env, rt_key_begin(RT_KIND_CC_VALUE, 0u, 0u, value), no_args);
        return;
    }
    if (kind == RT_KIND_ARRAY || kind == RT_KIND_SLICE || kind == RT_KIND_REF)
    {
        uint element = sb_edges[base].x;
        if (!sb_is_type(element)) { fail(task, SB_KIND, term, env, element); return; }
    }
    if (kind == RT_KIND_ARRAY)
    {
        uint length = sb_edges[base + 1u].x;
        uint length_kind = rt_term_kind(length);
        if (length_kind == RT_KIND_CC_VALUE)
        {
            uint count;
            if (!constant_value_to_count(rt_term_words(length), count)) { fail(task, SB_COUNT, term, env, length); return; }
            uint klass = count_class(count);
            if (!rt_is_term(klass)) { store_failed(task, term, env); return; }
            sb_edges[base + 1u].x = klass;
        }
        else if (length_kind != RT_KIND_CC_COUNT) { fail(task, SB_COUNT, term, env, length); return; }
    }
    else if (kind == RT_KIND_NAMED)
    {
        if (arity > 32u) { fail(task, SB_LIMIT, term, env, RT_NONE); return; }
        uint mask = words.y;
        if ((mask & ~sb_mask(arity)) != 0u || (head.x >> 16u) != arity - countbits(mask))
        {
            fail(task, SB_INVARIANT, term, env, RT_NONE);
            return;
        }
        for (uint i = 0u; i < arity; i++)
        {
            uint operand = sb_edges[base + i].x;
            bool constant = (mask >> i & 1u) != 0u;
            if (constant ? rt_term_kind(operand) != RT_KIND_CC_VALUE : !sb_is_type(operand))
            {
                fail(task, SB_KIND, term, env, operand);
                return;
            }
        }
    }
    else if (kind == RT_KIND_ENV)
    {
        EdgeArgs bound;
        bound.base = base;
        SbCheck check = sb_check_env(term, head, bound, 0u, false);
        if (check.status != SB_OK)
        {
            finish(task, RT_UNKNOWN, check.status, check.node, env, check.value, check.cause);
            return;
        }
    }
    else if (kind != RT_KIND_SLICE && kind != RT_KIND_REF)
    {
        fail(task, SB_UNSUPPORTED, term, env, RT_NONE);
        return;
    }
    RtTermKey built = rt_key_begin(kind, arity, head.x >> 16u, words);
    EdgeArgs args;
    args.base = base;
    for (uint i = 0u; i < arity; i++) rt_key_fold(built, args.arg(i));
    if (!built.ok) { fail(task, SB_INVARIANT, term, env, RT_NONE); return; }
    if (kind != RT_KIND_ENV && built.height > SB_MAX_HEIGHT) { fail(task, SB_DEPTH, term, env, RT_NONE); return; }
    stage_result(task, term, env, built, args);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint phase = sb_counts[SB_C_PHASE];
    if (phase == SB_PHASE_EXPAND) expand_round(dtid);
    else if (phase == SB_PHASE_SCATTER) scatter_round(dtid);
    else if (phase == SB_PHASE_EVAL) eval_round(dtid);
}
