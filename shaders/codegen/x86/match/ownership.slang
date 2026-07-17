// x86_64 match ownership projection.
//
// This pass materializes match-arm relation tables with one GPU thread per HIR
// node. Later instruction stages can answer pattern/result ownership by
// reading ownership records instead of scanning every match in the file.

import atomics;
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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint4> x86_match_record;
RWStructuredBuffer<uint4> x86_match_arm_record;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> x86_match_result_dense_owner;
struct HirLinks { uint first_child; uint next_sibling; uint subtree_end; uint file_id; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirMatchArm> compact_match_arms;

RWStructuredBuffer<uint> x86_match_pattern_owner;
RWStructuredBuffer<uint> x86_match_result_value_owner;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FEATURE_MATCH = 1u << 1u;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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

bool valid_dense(uint node)
{
    return node != INVALID && node < min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

bool match_expr_is_return_value(uint match_node)
{
    if (!valid_node(match_node))
        return false;
    uint return_node = x86_match_return_node[match_node];
    return valid_node(return_node) && stmt_slot(return_node, 0u) == STMT_RECORD_KIND_RETURN;
}

bool supported_return_match(uint match_node)
{
    if (!has_match_feature() || !valid_node(match_node))
        return false;
    uint4 record = x86_match_record[match_node];
    return hir_kind[match_node] == HIR_MATCH_EXPR &&
           valid_node(record.x) &&
           valid_arm(record.y) &&
           record.z == 2u &&
           match_expr_is_return_value(match_node);
}

void publish_owner(RWStructuredBuffer<uint> owners, uint node, uint owner)
{
    if (valid_dense(node) && valid_arm(owner))
        atomic_u32_min(owners, node, owner);
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

    uint dense = raw_to_compact_hir[node];
    if (valid_dense(dense))
    {
        uint arm = x86_match_result_dense_owner[dense];
        if (valid_arm(arm))
        {
            uint result = compact_match_arms[arm].result;
            uint end = valid_dense(result) ? compact_hir_links[result].subtree_end : INVALID;
            if (valid_dense(result) && end != INVALID && dense >= result && dense < end)
            {
                HirCore result_core = compact_hir_core[result];
                HirCore node_core = compact_hir_core[dense];
                if (node_core.token_start >= result_core.token_start &&
                    node_core.token_end <= result_core.token_end)
                    x86_match_result_value_owner[node] = arm;
                if (dense == result)
                {
                    uint resolved = resolve_expr(node);
                    if (valid_node(resolved))
                    {
                        uint ignored;
                        InterlockedExchange(x86_match_arm_record[arm].w, resolved, ignored);
                    }
                }
            }
        }
    }

    if (valid_arm(node))
    {
        uint4 arm_record = x86_match_arm_record[node];
        if (valid_dense(arm_record.x))
            publish_owner(x86_match_pattern_owner, arm_record.x, node);
    }
}
