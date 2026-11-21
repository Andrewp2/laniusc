// Collect the immutable work for aggregate typing once for this HIR. One
// root owns every consecutive member/index link or directly nested literal.
import shared.syntax.hir_records;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_hir_expr_parent;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
RWStructuredBuffer<uint> member_next_node;
RWStructuredBuffer<uint> member_chain_roots;
RWStructuredBuffer<uint> nested_literal_roots;
RWStructuredBuffer<uint> aggregate_root_counts;
RWStructuredBuffer<uint> member_chain_root_args;
RWStructuredBuffer<uint> nested_literal_root_args;

static const uint INVALID = 0xffffffffu;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_LITERAL = 28u;

#include "literal_parent.slang"
#include "member_chain_workgroup.slang"

bool link_or_list_member(uint node, uint kind, uint count)
{
    if (kind != HIR_MEMBER_EXPR && kind != HIR_INDEX_EXPR) return false;
    HirPayload payload = compact_hir_payload[node];
    if (kind == HIR_MEMBER_EXPR)
    {
        uint parent = compact_hir_expr_parent[node];
        if (payload.c >= gParams.n_tokens || (parent < count &&
            compact_hir_core[parent].kind == HIR_CALL_EXPR &&
            compact_hir_payload[parent].a == node)) return false;
    }

    uint receiver = payload.b;
    if (receiver >= count) return true;
    uint receiver_kind = compact_hir_core[receiver].kind;
    if (receiver_kind != HIR_MEMBER_EXPR && receiver_kind != HIR_INDEX_EXPR) return true;
    uint previous;
    InterlockedCompareExchange(member_next_node[receiver], INVALID, node, previous);
    return false;
}

bool has_nested_literal(uint root, uint count)
{
    HirPayload literal = compact_hir_payload[root];
    uint fields = min(compact_field_count[0u], gParams.n_hir_nodes);
    if (literal.b >= fields) return false;
    uint end = min(literal.c, fields - literal.b);
    for (uint ordinal = 0u; ordinal < end; ordinal++)
    {
        HirField field = compact_fields[literal.b + ordinal];
        if (field.owner == root && field.value < count && field.name_token < gParams.n_tokens &&
            compact_hir_core[field.value].kind == HIR_STRUCT_LITERAL)
            return literal_parent(root, count) == INVALID;
    }
    return false;
}

void append_root(uint node, bool hold, uint counter, uint roots_per_group, RWStructuredBuffer<uint> roots,
    RWStructuredBuffer<uint> args)
{
    uint size = WaveActiveCountBits(hold);
    uint base = 0u;
    if (WaveIsFirstLane() && size != 0u)
    {
        InterlockedAdd(aggregate_root_counts[counter], size, base);
        uint groups = (base + size + roots_per_group - 1u) / roots_per_group;
        uint ignored;
        InterlockedMax(args[0u], min(groups, 65535u), ignored);
        if (groups > 65535u) InterlockedMax(args[1u], (groups + 65534u) / 65535u, ignored);
    }
    uint slot = WaveReadLaneFirst(base) + WavePrefixCountBits(hold);
    if (hold) roots[slot] = node;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint node = dtid.x + dtid.y * 16776960u;
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    uint kind = node < count ? compact_hir_core[node].kind : 0u;
    append_root(node, link_or_list_member(node, kind, count), 0u, MEMBER_CHAINS_PER_WORKGROUP,
        member_chain_roots, member_chain_root_args);
    // Literal trees can carry a long substitution walk. Give each tree
    // its own workgroup.
    append_root(node, kind == HIR_STRUCT_LITERAL && has_nested_literal(node, count), 1u, 1u,
        nested_literal_roots, nested_literal_root_args);
}
