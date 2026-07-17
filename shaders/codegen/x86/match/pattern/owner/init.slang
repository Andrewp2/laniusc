// x86_64 match-pattern owner initialization.
//
// This pass seeds the Pareas-style nearest-marked-ancestor resolution used by
// x86_match_pattern_owner_step. The marker is the parser/match-record-owned
// pattern root for each match arm.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint4> x86_match_arm_record;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<uint> x86_match_pattern_owner;

RWStructuredBuffer<uint> x86_match_pattern_node_owner;
RWStructuredBuffer<uint> x86_match_pattern_owner_link;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FEATURE_MATCH = 1u << 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

uint active_arm_count()
{
    return min(compact_match_arm_count[0u], gParams.n_hir_nodes);
}

bool valid_arm(uint arm)
{
    return arm != INVALID && arm < active_arm_count();
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

uint parent_node(uint node)
{
    return valid_node(node) ? compact_hir_core[node].parent : INVALID;
}

uint valid_pattern_owner_at(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint arm = x86_match_pattern_owner[node];
    if (!valid_arm(arm))
        return INVALID;

    uint4 record = x86_match_arm_record[arm];
    return record.x != INVALID && record.w != INVALID ? arm : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;
    if (!has_match_feature())
        return;

    uint owner = valid_pattern_owner_at(node);
    x86_match_pattern_node_owner[node] = owner;
    x86_match_pattern_owner_link[node] = valid_arm(owner) ? INVALID : parent_node(node);
}
