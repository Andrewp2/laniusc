// Substitution step 6: one lane per task of the current level. Every child
// result is final (children have lower levels). The first failing child in
// argument order decides the task's failure and its provenance, which is
// copied from that child's own result: provenance never depends on which
// lane created a task or on memo contents.
//
// Kinds: NAMED, SLICE, REF and ENV rebuild with their words unchanged.
// ARRAY takes its length's count class (CC_COUNT), so equal counts of
// different scalars give one array identity. CC_CAST folds its child's
// typed value to the target scalar with the canonical rules
// (constant_value_to_count, constant_value_from_count) or fails its fit;
// this applies to closed casts too, so a result never keeps a CC_CAST.
import primitive_types;
import constant_value;
import type_checker.retention.retention_store;
import type_checker.retention.substitution.sb_common;

struct EdgeArgs : IRtArgs
{
    uint base;
    uint arg(uint index) { return sb_edges[base + index].x; }
}

void finish(uint task, uint value, uint status, uint node, uint env, uint fail_value)
{
    sb_task_res[task] = uint4(value, status, node, env);
    sb_task_fail[task] = fail_value;
}

void fail(uint task, uint status, uint node, uint env, uint fail_value)
{
    finish(task, RT_UNKNOWN, status, node, env, fail_value);
}

// The CC_COUNT record of `count`, interned like the canonical cc_intern_count.
uint count_class(uint count)
{
    RtTermKey key = rt_key_begin(RT_KIND_CC_COUNT, 0u, 0u, uint3(count, 0u, 0u));
    RtStoredArgs none; none.base = 0u;
    return rt_intern_term(key, none);
}

uint value_term(uint3 value)
{
    RtTermKey key = rt_key_begin(RT_KIND_CC_VALUE, 0u, 0u, value);
    RtStoredArgs none; none.base = 0u;
    return rt_intern_term(key, none);
}

void store_failed(uint task, uint term, uint env)
{
    sb_overflow(SB_OVERFLOW_STORE);
    fail(task, SB_CAPACITY, term, env, RT_NONE);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
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
            uint4 r = sb_task_res[e.x];
            if (r.y != SB_OK)
            {
                fail(task, r.y == SB_PENDING ? SB_INVARIANT : r.y, r.z, r.w, sb_task_fail[e.x]);
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
        uint count;
        if (!constant_value_to_count(rt_term_words(child), count)) { fail(task, SB_UNSUPPORTED, term, env, child); return; }
        uint3 value;
        if (!constant_value_from_count(count, words.x, value)) { fail(task, SB_FIT_FAILED, term, env, child); return; }
        uint folded = value_term(value);
        if (!rt_is_term(folded)) { store_failed(task, term, env); return; }
        finish(task, folded, SB_OK, RT_NONE, 0u, RT_NONE);
        return;
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
    else if (kind != RT_KIND_NAMED && kind != RT_KIND_SLICE && kind != RT_KIND_REF && kind != RT_KIND_ENV)
    {
        fail(task, SB_UNSUPPORTED, term, env, RT_NONE);
        return;
    }
    RtTermKey built = rt_key_begin(kind, arity, head.x >> 16u, words);
    EdgeArgs args;
    args.base = base;
    for (uint i = 0u; i < arity; i++) rt_key_fold(built, args.arg(i));
    if (!built.ok) { fail(task, SB_INVARIANT, term, env, RT_NONE); return; }
    if (built.height > SB_MAX_HEIGHT) { fail(task, SB_DEPTH, term, env, RT_NONE); return; }
    uint result = rt_intern_term(built, args);
    if (!rt_is_term(result)) { store_failed(task, term, env); return; }
    if (!rt_term_closed(result)) { fail(task, SB_INVARIANT, term, env, result); return; }
    finish(task, result, SB_OK, RT_NONE, 0u, RT_NONE);
}
