// One import round of the dependency closure summaries (summary.slang): one
// lane per node. A node whose children are imported interns its key, built
// as canonical_dependency builds the same dependency node (named, array,
// slice and reference keys, values and count projections through the
// shared constant builders), with its slot leaves immediate: a summary slot
// is the dependency slot leaf of its composed binding slot. A node that
// meets a pending child waits for the next round; the host records one
// round per level of the deepest node (closure_summary.rs).
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_constants;
import type_checker.closure.summary;
import constant_value;
import primitive_types;

static const uint INVALID = 0xffffffffu;
static const uint NAMED_OPERAND_LIMIT = 32u;

// The key of a named, array, slice or reference node. Pass 0 checks the
// children, pass 1 writes the key, reading each child at one call site.
uint build_composite(uint kind, uint4 node, uint2 tail, out CtKey key)
{
    key = ct_empty_key();
    uint arity = (node.x >> 8u) & 0xffu;
    if (kind == SUMMARY_NODE_NAMED ? arity > NAMED_OPERAND_LIMIT
        : arity != (kind == SUMMARY_NODE_ARRAY ? 2u : 1u)) return CT_UNKNOWN;
    uint mask = tail.y;
    if (kind == SUMMARY_NODE_ARRAY && mask != 2u) return CT_UNKNOWN;
    if (kind != SUMMARY_NODE_NAMED && kind != SUMMARY_NODE_ARRAY && mask != 0u) return CT_UNKNOWN;
    uint ct = kind == SUMMARY_NODE_NAMED ? CT_KIND_NAMED : kind == SUMMARY_NODE_ARRAY ? CT_KIND_ARRAY
        : kind == SUMMARY_NODE_SLICE ? CT_KIND_SLICE : CT_KIND_REF;
    uint3 words = kind == SUMMARY_NODE_NAMED ? node.yzw : uint3(0u, 0u, 0u);
    // A summary only names its dependencies' types.
    if (kind == SUMMARY_NODE_NAMED &&
        words.x == ct_counts[CT_COUNT_LIBRARY] && words.y == ct_counts[CT_COUNT_UNIT]) return CT_UNKNOWN;
    for (uint pass = 0u; pass < 2u; pass++)
    {
        if (pass == 1u)
        {
            // Acquire: children's records were published before their references.
            DeviceMemoryBarrier();
            key = ct_key_begin(ct, arity, kind == SUMMARY_NODE_NAMED ? arity - countbits(mask) : 0u, words);
            if (!ct_key_reserve_args(key)) return CT_UNKNOWN;
        }
        for (uint index = 0u; index < arity; index++)
        {
            uint child = summary_node_ref(summary_arg(tail.x + index));
            if (pass == 0u)
            {
                if (child == CT_PENDING) return CT_PENDING;
                if (!ct_is_resolved(child)) return CT_UNKNOWN;
                // Constants are named operands and array lengths only.
                if (ct_is_constant(child) != ((mask & (1u << index)) != 0u)) return CT_UNKNOWN;
                continue;
            }
            // Array identity uses the length's count class, not its typed value.
            if (kind == SUMMARY_NODE_ARRAY && index == 1u) child = cc_count_class(child);
            ct_key_arg(key, index, child);
        }
    }
    if (!key.ok) return CT_UNKNOWN;
    key.extra = uint2(INVALID, mask);
    return CT_KEY_BUILT;
}

// The reference of node `n`, CT_PENDING while a child is pending.
uint import_node(uint n)
{
    uint4 node = summary_node(n);
    uint2 tail = summary_node_tail(n);
    uint kind = node.x & 0xffu;
    // Type argument leaves are value scalars only (never `never`): the
    // bound stays explicit.
    if (kind == SUMMARY_NODE_SCALAR)
        return node.y >= 1u && node.y <= SCALAR_USIZE ? node.y : CT_UNKNOWN;
    if (kind == SUMMARY_NODE_TYPE_SLOT) return ct_dep_type_param(node.y);
    if (kind == SUMMARY_NODE_CONST_SLOT)
        return constant_scalar_is_supported(node.z) ? ct_dep_const_param(node.y, node.z) : CT_UNKNOWN;
    CtKey key;
    uint status;
    if (kind == SUMMARY_NODE_LITERAL)
    {
        status = ct_build_value(node.yzw, key);
    }
    else if (kind == SUMMARY_NODE_PROJECTION)
    {
        if (((node.x >> 8u) & 0xffu) != 1u) return CT_UNKNOWN;
        uint child = summary_node_ref(summary_arg(tail.x));
        if (child == CT_PENDING) return CT_PENDING;
        if (!ct_is_resolved(child)) return CT_UNKNOWN;
        // Acquire: the child's record was published before its reference.
        DeviceMemoryBarrier();
        bool fold;
        uint3 value;
        status = ct_build_projection(node.y, child, node.z, fold, value, key);
        if (fold) status = ct_build_value(value, key);
    }
    else if (kind >= SUMMARY_NODE_NAMED && kind <= SUMMARY_NODE_REF)
    {
        status = build_composite(kind, node, tail, key);
    }
    else
    {
        return CT_UNKNOWN;
    }
    if (status != CT_KEY_BUILT) return status;
    return ct_intern_key(key);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint n = dtid.x + dtid.y * 16776960u;
    if (n >= summary_node_count() || summary_node_ref(n) != CT_PENDING) return;
    uint ref = import_node(n);
    if (ref == CT_PENDING) return;
    // Release: the record precedes its reference.
    DeviceMemoryBarrier();
    summary_set_node_ref(n, ref);
}
