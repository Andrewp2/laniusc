// Collect semantic feature flags from the compact semantic HIR artifact.
//
// Each HIR row is inspected independently. The only shared operation is an
// atomic OR into a one-word summary, so this remains parallel over the active
// HIR rather than rediscovering source structure on the host.

import atomics;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<uint> compact_predicate_count;
RWStructuredBuffer<uint> semantic_feature_flags;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint SEMANTIC_FEATURE_METHODS = 1u << 0u;
static const uint SEMANTIC_FEATURE_PREDICATES = 1u << 1u;
static const uint SEMANTIC_FEATURE_MATCH = 1u << 2u;
static const uint HIR_MATCH_EXPR = 34u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    uint flags = 0u;
    if (node == 0u)
    {
        if (compact_method_count[0u] != 0u)
            flags |= SEMANTIC_FEATURE_METHODS;
        if (compact_predicate_count[0u] != 0u)
            flags |= SEMANTIC_FEATURE_PREDICATES;
    }
    if (compact_hir_core[node].kind == HIR_MATCH_EXPR)
        flags |= SEMANTIC_FEATURE_MATCH;
    if (flags != 0u)
        atomic_u32_or(semantic_feature_flags, 0u, flags);
}
