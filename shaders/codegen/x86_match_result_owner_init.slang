// Seed nearest match-arm result ownership.

import gpu_index;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

struct FeatureParams
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
};

ConstantBuffer<FeatureParams> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> x86_match_result_root_owner;
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;

RWStructuredBuffer<uint> x86_match_result_owner;
RWStructuredBuffer<uint> x86_match_result_owner_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FEATURE_MATCH = 1u << 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!has_match_feature())
        return;
    if (!valid_node(node))
        return;

    uint owner = x86_match_result_root_owner[node];
    if (valid_node(owner))
    {
        x86_match_result_owner[node] = owner;
        x86_match_result_owner_link[node] = INVALID;
        return;
    }

    uint parent = x86_tree_parent[node];
    uint parent_owner = valid_node(parent) ? x86_match_result_root_owner[parent] : INVALID;
    if (valid_node(parent_owner))
    {
        x86_match_result_owner[node] = parent_owner;
        x86_match_result_owner_link[node] = INVALID;
        return;
    }

    x86_match_result_owner[node] = INVALID;
    x86_match_result_owner_link[node] = valid_node(parent) ? parent : INVALID;
}
