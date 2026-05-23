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
StructuredBuffer<uint> x86_tree_parent;
StructuredBuffer<uint> x86_tree_subtree_end;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint4> x86_match_record;

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

bool has_match_feature()
{
    return (gX86Features.mask & X86_FEATURE_MATCH) != 0u;
}

uint parent_node(uint node)
{
    return valid_node(node) ? x86_tree_parent[node] : INVALID;
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

bool node_span_contains(uint ancestor, uint node)
{
    if (!valid_node(node) || !valid_node(ancestor))
        return false;
    uint end = x86_tree_subtree_end[ancestor];
    return end != INVALID && ancestor <= node && node < end;
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
           valid_node(record.y) &&
           record.z == 2u &&
           match_expr_is_return_value(match_node);
}

void publish_owner(RWStructuredBuffer<uint> owners, uint node, uint owner)
{
    if (valid_node(node) && valid_node(owner))
        atomic_u32_min(owners, node, owner);
}

void publish_unique_owner(RWStructuredBuffer<uint> owners, uint node, uint owner)
{
    if (valid_node(node) && valid_node(owner))
        owners[node] = owner;
}

void publish_return_result_owner(uint arm_node)
{
    if (!valid_node(arm_node))
        return;

    uint4 arm_record = x86_match_record[arm_node];
    uint result_root = arm_record.w;
    uint result_value = resolve_expr(result_root);
    publish_unique_owner(x86_match_result_value_owner, result_value, arm_node);
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

    uint4 record = x86_match_record[node];
    if (hir_kind[node] != HIR_MATCH_EXPR)
    {
        if (valid_node(record.x) && valid_node(record.w))
            publish_owner(x86_match_pattern_owner, record.x, node);
        return;
    }

    if (supported_return_match(node))
    {
        publish_return_result_owner(record.y);
        publish_return_result_owner(record.w);
    }
}
