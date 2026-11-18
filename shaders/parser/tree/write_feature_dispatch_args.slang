// Build feature-gated indirect dispatch arguments for tree/HIR passes whose
// input records are only meaningful when a token feature was observed on GPU.

import token_features;

struct Params
{
    uint n;
    uint uses_status_count;
    uint n_node_blocks;
    uint n_prefix_blocks;
    uint scan_step;
};

ConstantBuffer<Params> gTree;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_feature_flags;
RWStructuredBuffer<uint> tree_enum_dispatch_args;
RWStructuredBuffer<uint> tree_match_dispatch_args;
RWStructuredBuffer<uint> tree_struct_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint active_node_count()
{
    return gTree.uses_status_count != 0u ? min(gTree.n, tree_count_status[5u]) : gTree.n;
}

void write_feature_args(RWStructuredBuffer<uint> args, uint feature)
{
    uint groups = 0u;
    if (parser_feature_enabled(token_feature_flags, feature))
        groups = (active_node_count() + WG_SIZE - 1u) / WG_SIZE;

    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = groups == 0u ? 0u : max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = groups == 0u ? 0u : 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    write_feature_args(tree_enum_dispatch_args, PARSER_FEATURE_ENUMS);
    write_feature_args(tree_match_dispatch_args, PARSER_FEATURE_MATCHES);
    write_feature_args(tree_struct_dispatch_args, PARSER_FEATURE_STRUCTS);
}
