// Publish the normalized source selected by the alias equivalence graph. The
// declaration ref remains the single consumer-facing semantic source; callers
// do not walk alias syntax or repeat bounded projection passes.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_namespace;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> alias_equiv_parent;
StructuredBuffer<uint> alias_equiv_component_source;
StructuredBuffer<uint> alias_normalized_source;
RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> module_type_path_type;
RWStructuredBuffer<uint> module_type_path_status;

static const uint INVALID = 0xffffffffu;
static const uint HIR_ITEM_KIND_TYPE_ALIAS = 8u;
static const uint HIR_ITEM_NAMESPACE_TYPE = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint decl_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint count = min(decl_count_out[0u], gParams.n_hir_nodes);
    if (decl_i >= count || decl_kind[decl_i] != HIR_ITEM_KIND_TYPE_ALIAS ||
        decl_namespace[decl_i] != HIR_ITEM_NAMESPACE_TYPE)
        return;
    uint alias_node = decl_hir_node[decl_i];
    uint name_token = decl_name_token[decl_i];
    if (alias_node >= active_hir_count() || name_token >= gParams.n_tokens)
        return;
    uint source = alias_normalized_source[alias_node];
    if (source == INVALID)
    {
        uint output_node = gParams.n_tokens + alias_node;
        uint root = alias_equiv_parent[output_node];
        if (root < gParams.n_tokens + gParams.n_hir_nodes)
            source = alias_equiv_component_source[root];
    }
    uint tag = TYPE_REF_INVALID;
    uint payload = INVALID;
    if (source < gParams.n_tokens)
    {
        tag = TYPE_REF_GENERIC_PARAM;
        payload = source;
    }
    else if (source >= gParams.n_tokens)
    {
        uint node = source - gParams.n_tokens;
        uint token = node < active_hir_count() ? compact_hir_core[node].token_start : INVALID;
        if (token < gParams.n_tokens)
        {
            tag = type_expr_ref_tag[token];
            payload = type_expr_ref_payload[token];
        }
    }
    if (tag == TYPE_REF_INVALID)
        return;
    type_expr_ref_tag[name_token] = tag;
    type_expr_ref_payload[name_token] = payload;
    if (tag == TYPE_REF_SCALAR)
        module_type_path_type[name_token] = payload;
    module_type_path_status[name_token] = PATH_RESOLVE_STATUS_OK;
}
