// Turn the GPU-collected semantic feature summary into indirect dispatch grids.
// Optional semantic families receive zero workgroups when no relevant HIR was
// observed. Fixed-size radix helpers get their exact enabled grids as well.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_active_count;
StructuredBuffer<uint> semantic_feature_flags;
RWStructuredBuffer<uint> method_token_dispatch_args;
RWStructuredBuffer<uint> method_hir_dispatch_args;
RWStructuredBuffer<uint> method_token_hir_dispatch_args;
RWStructuredBuffer<uint> method_radix_prefix_dispatch_args;
RWStructuredBuffer<uint> method_radix_bases_dispatch_args;
RWStructuredBuffer<uint> predicate_token_dispatch_args;
RWStructuredBuffer<uint> predicate_hir_dispatch_args;
RWStructuredBuffer<uint> predicate_radix_prefix_dispatch_args;
RWStructuredBuffer<uint> predicate_radix_bases_dispatch_args;
RWStructuredBuffer<uint> predicate_single_dispatch_args;
RWStructuredBuffer<uint> match_hir_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint RADIX_BUCKETS = 257u;
static const uint SEMANTIC_FEATURE_METHODS = 1u << 0u;
static const uint SEMANTIC_FEATURE_PREDICATES = 1u << 1u;
static const uint SEMANTIC_FEATURE_MATCH = 1u << 2u;

bool feature_enabled(uint feature)
{
    return (semantic_feature_flags[0u] & feature) != 0u;
}

uint active_token_count()
{
    return min(gParams.n_tokens, token_count[0u]);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, hir_active_count[0u]);
}

void write_record_args(RWStructuredBuffer<uint> args, uint records, bool enabled)
{
    uint groups = enabled ? (records + WG_SIZE - 1u) / WG_SIZE : 0u;
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = groups == 0u ? 0u : (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
    args[2u] = groups == 0u ? 0u : 1u;
}

void write_fixed_args(RWStructuredBuffer<uint> args, uint groups, bool enabled)
{
    uint active_groups = enabled ? groups : 0u;
    args[0u] = active_groups;
    args[1u] = active_groups == 0u ? 0u : 1u;
    args[2u] = active_groups == 0u ? 0u : 1u;
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint active_tokens = active_token_count();
    uint active_hir = active_hir_node_count();
    bool methods = feature_enabled(SEMANTIC_FEATURE_METHODS);
    bool predicates = feature_enabled(SEMANTIC_FEATURE_PREDICATES);
    bool match_syntax = feature_enabled(SEMANTIC_FEATURE_MATCH);

    write_record_args(method_token_dispatch_args, active_tokens, methods);
    write_record_args(method_hir_dispatch_args, active_hir, methods);
    write_record_args(method_token_hir_dispatch_args, max(active_tokens, active_hir), methods);
    write_fixed_args(method_radix_prefix_dispatch_args, RADIX_BUCKETS, methods);
    write_fixed_args(method_radix_bases_dispatch_args, 1u, methods);

    write_record_args(predicate_token_dispatch_args, active_tokens, predicates);
    write_record_args(predicate_hir_dispatch_args, active_hir, predicates);
    write_fixed_args(predicate_radix_prefix_dispatch_args, RADIX_BUCKETS, predicates);
    write_fixed_args(predicate_radix_bases_dispatch_args, 1u, predicates);
    write_fixed_args(predicate_single_dispatch_args, 1u, predicates);
    write_record_args(match_hir_dispatch_args, active_hir, match_syntax);
}
