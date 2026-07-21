// Collect semantic feature flags from parser-owned HIR metadata.
//
// Each HIR row is inspected independently. The only shared operation is an
// atomic OR into a one-word summary, so this remains parallel over the active
// HIR rather than rediscovering source structure on the host.

import generated_parse_production_ids;
import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

struct HirPayload { uint a; uint b; uint c; uint d; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_member_name_token;
RWStructuredBuffer<uint> semantic_feature_flags;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint SEMANTIC_FEATURE_METHODS = 1u << 0u;
static const uint SEMANTIC_FEATURE_PREDICATES = 1u << 1u;
static const uint SEMANTIC_FEATURE_MATCH = 1u << 2u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint HIR_MATCH_EXPR = 34u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint compact_item_kind_for_raw(uint node)
{
    if (node >= active_hir_node_count())
        return INVALID;
    uint dense = raw_to_compact_hir[node];
    uint count = min(compact_hir_count[0u], gParams.n_hir_nodes);
    return dense < count ? compact_hir_payload[dense].a : INVALID;
}

bool predicate_syntax(uint node)
{
    uint production = node_kind[node];
    return compact_item_kind_for_raw(node) == HIR_ITEM_KIND_TRAIT ||
           production == PROD_IMPL_INHERENT ||
           production == PROD_IMPL_TRAIT ||
           production == PROD_BOUND_TYPE_IDENT ||
           production == PROD_BOUND_TYPE_REF;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    uint flags = 0u;
    if ((node == 0u && compact_method_count[0u] != 0u) ||
        hir_member_name_token[node] != INVALID)
        flags |= SEMANTIC_FEATURE_METHODS;
    if (predicate_syntax(node))
        flags |= SEMANTIC_FEATURE_PREDICATES;
    if (hir_kind[node] == HIR_MATCH_EXPR)
        flags |= SEMANTIC_FEATURE_MATCH;
    if (flags != 0u)
        atomic_u32_or(semantic_feature_flags, 0u, flags);
}
