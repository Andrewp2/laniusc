// Closure summaries of the job's dependencies (D1b; host side in
// type_checker/closure_summary.rs). Each library unit's summary lists, per
// generic function, its calls to generic functions with their environments
// in slot form: every parameter of the caller is the dependency slot leaf of
// its composed binding slot. The host uploads them merged:
//
// - header: function, edge, node and argument counts, the four section
//   bases, and the import rounds;
// - functions, sorted by (library, unit, symbol): (library, unit, symbol,
//   first edge), (end edge, type mask, constant mask, 0);
// - edges: (callee function or INVALID, type mask, constant mask, first
//   argument), the bindings being nodes at the first argument;
// - nodes: (kind | arity << 8, w0, w1, w2), (first child, constant mask, 0,
//   0), the children being nodes at the first child (summary node kinds:
//   closure_summary.rs, NODE_*).
//
// 00b_import_summary interns every node into closure_summary_ct; 01b seeds
// roots from the job's closed calls into a summary function and 03b
// expands their edges.
import type_checker.canonical.canonical_api;

public StructuredBuffer<uint> closure_summary_inputs;
// Canonical reference + 1 of each node; 0 (cleared every job) until imported.
public globallycoherent RWStructuredBuffer<uint> closure_summary_ct;

public static const uint SUMMARY_TAG = 0x80000000u;

public static const uint SUMMARY_NODE_SCALAR = 1u;
public static const uint SUMMARY_NODE_TYPE_SLOT = 2u;
public static const uint SUMMARY_NODE_NAMED = 3u;
public static const uint SUMMARY_NODE_ARRAY = 4u;
public static const uint SUMMARY_NODE_SLICE = 5u;
public static const uint SUMMARY_NODE_REF = 6u;
public static const uint SUMMARY_NODE_CONST_SLOT = 8u;
public static const uint SUMMARY_NODE_LITERAL = 9u;
public static const uint SUMMARY_NODE_PROJECTION = 10u;

static const uint SUMMARY_INVALID = 0xffffffffu;

uint summary_word(uint index)
{
    uint count; uint stride;
    closure_summary_inputs.GetDimensions(count, stride);
    return index < count ? closure_summary_inputs[index] : 0u;
}

public uint summary_fn_count() { return summary_word(0u); }
public uint summary_edge_count() { return summary_word(1u); }
public uint summary_node_count()
{
    uint count; uint stride;
    closure_summary_ct.GetDimensions(count, stride);
    return min(summary_word(2u), count);
}
uint summary_arg_count() { return summary_word(3u); }

// (library, unit, symbol, first edge) of function `f`.
public uint4 summary_fn(uint f)
{
    uint base = summary_word(4u) + f * 8u;
    return uint4(summary_word(base), summary_word(base + 1u), summary_word(base + 2u), summary_word(base + 3u));
}

// (end edge, type mask, constant mask, SUMMARY_FN_* flags) of function `f`.
public uint4 summary_fn_tail(uint f)
{
    uint base = summary_word(4u) + f * 8u + 4u;
    return uint4(summary_word(base), summary_word(base + 1u), summary_word(base + 2u), summary_word(base + 3u));
}

// The function has a call its summary could not spell: no dependent roots
// or expands it (closure_summary.rs, SUMMARY_FN_INCOMPLETE).
public static const uint SUMMARY_FN_INCOMPLETE = 1u;

// The edges [first, end) of function `f`, empty when it is incomplete.
public uint2 summary_fn_edges(uint f)
{
    if (f >= summary_fn_count()) return uint2(0u, 0u);
    uint4 tail = summary_fn_tail(f);
    if ((tail.w & SUMMARY_FN_INCOMPLETE) != 0u) return uint2(0u, 0u);
    return uint2(summary_fn(f).w, min(tail.x, summary_edge_count()));
}

// (callee function or INVALID, type mask, constant mask, first argument).
public uint4 summary_edge(uint e)
{
    uint base = summary_word(5u) + e * 4u;
    return uint4(summary_word(base), summary_word(base + 1u), summary_word(base + 2u), summary_word(base + 3u));
}

public uint4 summary_node(uint n)
{
    uint base = summary_word(6u) + n * 8u;
    return uint4(summary_word(base), summary_word(base + 1u), summary_word(base + 2u), summary_word(base + 3u));
}

// (first child, constant mask).
public uint2 summary_node_tail(uint n)
{
    uint base = summary_word(6u) + n * 8u + 4u;
    return uint2(summary_word(base), summary_word(base + 1u));
}

// Argument word `i`: a node index.
public uint summary_arg(uint i)
{
    return i < summary_arg_count() ? summary_word(summary_word(7u) + i) : SUMMARY_INVALID;
}

// The canonical reference of node `n`: CT_PENDING until imported,
// CT_UNKNOWN out of range.
public uint summary_node_ref(uint n)
{
    if (n >= summary_node_count()) return CT_UNKNOWN;
    uint stored = closure_summary_ct[n];
    return stored == 0u ? CT_PENDING : stored - 1u;
}

public void summary_set_node_ref(uint n, uint ref)
{
    if (n < summary_node_count() && ref != CT_PENDING) closure_summary_ct[n] = ref + 1u;
}

// The function whose key is (library, unit, symbol), or INVALID.
public uint summary_find_fn(uint3 key)
{
    uint low = 0u;
    uint high = summary_fn_count();
    for (uint step = 0u; step < 32u && low < high; step++)
    {
        uint middle = (low + high) / 2u;
        uint3 probe = summary_fn(middle).xyz;
        bool less = probe.x != key.x ? probe.x < key.x : probe.y != key.y ? probe.y < key.y : probe.z < key.z;
        if (all(probe == key)) return middle;
        if (less) low = middle + 1u;
        else high = middle;
    }
    return SUMMARY_INVALID;
}
