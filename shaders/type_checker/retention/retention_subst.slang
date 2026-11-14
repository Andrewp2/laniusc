// Substitution over retained terms (docs/compiler-program-retention.md).
//
// A closed environment is an ENV term whose owner is a callee DeclId and
// whose arguments bind that callee's composed binder slots (type slots,
// then constant slots, each present when its mask bit is set). A parameter
// leaf resolves through the callee's committed binder map: its ParamId is
// found by identity, never by name or ordinal, so an inherited parameter
// and a shadowing one of the same spelling bind to different slots.
//
// The walk is post-order over global scratch (no per-thread arrays): a
// frame stack of (term, next child) pairs and a value stack, both inside the
// lane's region of rt_s_stack.
import type_checker.retention.retention_store;

public globallycoherent RWStructuredBuffer<uint> rt_s_stack;

public static const uint RT_SUBST_OK = 0u;
public static const uint RT_SUBST_UNBOUND = 1u;      // a parameter of the chain has no binding
public static const uint RT_SUBST_FOREIGN_LEAF = 2u; // a parameter outside the callee's chain
public static const uint RT_SUBST_SLOT_LEAF = 3u;    // a dependency-signature slot leaf
public static const uint RT_SUBST_DEPTH = 4u;        // the lane's scratch is too small
public static const uint RT_SUBST_INTERN = 5u;       // the store could not intern a result
public static const uint RT_SUBST_ENV = 6u;          // the environment is not a closed ENV of the callee

public struct RtBinding
{
    public uint env;
    public uint binder_base;
    public uint type_count;
    public uint const_count;
}

// The binding of callee `decl`'s committed directory entry for `env`.
public RtBinding rt_binding(uint entry, uint env)
{
    RtBinding b;
    uint4 d1 = rt_dir[entry * RT_DIR_WORDS + 1u];
    b.env = env;
    b.binder_base = d1.x;
    b.type_count = d1.y & 0xffffu;
    b.const_count = d1.y >> 16u;
    return b;
}

uint popcount_below(uint mask, uint index) { return countbits(index >= 32u ? mask : mask & ((1u << index) - 1u)); }

// The bound argument of parameter leaf `leaf`, or a status in .y.
public uint2 rt_bind_leaf(RtBinding b, uint leaf)
{
    uint param = rt_leaf_param(leaf);
    uint total = b.type_count + b.const_count;
    uint slot = 0xffffffffu;
    for (uint i = 0u; i < total; i++)
        if (rt_binders[b.binder_base + i] == param) { slot = i; break; }
    if (slot == 0xffffffffu) return uint2(RT_UNKNOWN, RT_SUBST_FOREIGN_LEAF);
    uint4 head = rt_term_head[b.env];
    uint type_mask = head.z;
    uint const_mask = head.w;
    uint arg_base = rt_term_meta[b.env].x;
    if (slot < b.type_count)
    {
        if ((type_mask >> slot & 1u) == 0u) return uint2(RT_UNKNOWN, RT_SUBST_UNBOUND);
        return uint2(rt_term_args[arg_base + popcount_below(type_mask, slot)], RT_SUBST_OK);
    }
    uint c = slot - b.type_count;
    if ((const_mask >> c & 1u) == 0u) return uint2(RT_UNKNOWN, RT_SUBST_UNBOUND);
    return uint2(rt_term_args[arg_base + countbits(type_mask) + popcount_below(const_mask, c)], RT_SUBST_OK);
}

public struct RtScratchArgs : IRtArgs
{
    public uint base;
    public uint arg(uint index) { return rt_s_stack[base + index]; }
}

// Substitute `b` into `term`. Region [base, base + words) of rt_s_stack is
// the lane's scratch: frames grow up from base, values down from the end.
public uint2 rt_subst(RtBinding b, uint term, uint base, uint words)
{
    if (!rt_is_stored_term(b.env) || rt_term_kind(b.env) != RT_KIND_ENV || !rt_term_closed(b.env))
        return uint2(RT_UNKNOWN, RT_SUBST_ENV);
    uint frames = 0u;   // 2 words each from base
    uint values = 0u;   // 1 word each, downward from base + words - 1
    rt_s_stack[base] = term;
    rt_s_stack[base + 1u] = 0u;
    frames = 1u;
    for (uint step = 0u; step < 0x100000u && frames != 0u; step++)
    {
        uint at = base + (frames - 1u) * 2u;
        uint t = rt_s_stack[at];
        uint next = rt_s_stack[at + 1u];
        uint result = RT_UNKNOWN;
        bool done = false;
        if (rt_is_param_leaf(t))
        {
            uint2 bound = rt_bind_leaf(b, t);
            if (bound.y != RT_SUBST_OK) return bound;
            result = bound.x;
            done = true;
        }
        else if (rt_is_slot_leaf(t)) return uint2(RT_UNKNOWN, RT_SUBST_SLOT_LEAF);
        else if (!rt_is_stored_term(t) || rt_term_closed(t))
        {
            result = t;
            done = true;
        }
        else
        {
            uint arity = rt_term_arity(t);
            if (next < arity)
            {
                rt_s_stack[at + 1u] = next + 1u;
                if ((frames + 1u) * 2u + values + arity + 1u > words) return uint2(RT_UNKNOWN, RT_SUBST_DEPTH);
                rt_s_stack[at + 2u] = rt_term_arg(t, next);
                rt_s_stack[at + 3u] = 0u;
                frames++;
                continue;
            }
            // Children are the top `arity` values, last child on top. Copy
            // them in order just above the frames, then intern.
            uint top = base + words - values;
            uint args_base = base + frames * 2u;
            for (uint i = 0u; i < arity; i++) rt_s_stack[args_base + i] = rt_s_stack[top + (arity - 1u - i)];
            values -= arity;
            uint4 head = rt_term_head[t];
            RtTermKey key = rt_key_begin(head.x & 0xffu, arity, head.x >> 16u, head.yzw);
            RtScratchArgs args;
            args.base = args_base;
            for (uint i = 0u; i < arity; i++) rt_key_fold(key, args.arg(i));
            result = rt_intern_term(key, args);
            if (!rt_is_term(result)) return uint2(RT_UNKNOWN, RT_SUBST_INTERN);
            done = true;
        }
        if (done)
        {
            frames--;
            if (frames * 2u + values + 1u > words) return uint2(RT_UNKNOWN, RT_SUBST_DEPTH);
            values++;
            rt_s_stack[base + words - values] = result;
        }
    }
    if (frames != 0u || values != 1u) return uint2(RT_UNKNOWN, RT_SUBST_DEPTH);
    return uint2(rt_s_stack[base + words - 1u], RT_SUBST_OK);
}
