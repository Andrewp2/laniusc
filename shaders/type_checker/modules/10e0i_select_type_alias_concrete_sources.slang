// Label every equivalence component containing a concrete type-expression ref.
// Only components reached from alias output nodes are consumed by finalization;
// unrelated syntax remains harmlessly isolated.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> alias_equiv_parent;
RWStructuredBuffer<uint> alias_equiv_component_source;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_ERROR = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_hir_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (node >= active_hir_count())
        return;
    uint token = hir_token_pos[node];
    if (token >= gParams.n_tokens)
        return;
    uint tag = type_expr_ref_tag[token];
    if (tag == TYPE_REF_INVALID || tag == TYPE_REF_GENERIC_PARAM || tag == TYPE_REF_ERROR)
        return;
    uint graph_node = gParams.n_tokens + node;
    uint root = alias_equiv_parent[graph_node];
    if (root < gParams.n_tokens + gParams.n_hir_nodes)
        atomic_u32_min(alias_equiv_component_source, root, graph_node);
}
