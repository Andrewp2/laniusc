// Publish the active compact-path count and its indirect dispatch arguments.
//
// The parser's compact path count is the authoritative domain. Publishing the
// count and dispatch shape together prevents a copied count and its dispatch
// from diverging at workgroup boundaries.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
    uint dependency_interfaces_present;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_path_count;
RWStructuredBuffer<uint> path_count_out;
RWStructuredBuffer<uint> path_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (any(dtid != uint3(0u)))
        return;

    uint count = min(compact_path_count[0u], gParams.n_hir_nodes);
    uint groups = max(1u, (count + WG_SIZE - 1u) / WG_SIZE);
    path_count_out[0u] = count;
    path_dispatch_args[0u] = min(groups, MAX_GROUPS_X);
    path_dispatch_args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    path_dispatch_args[2u] = 1u;
}
