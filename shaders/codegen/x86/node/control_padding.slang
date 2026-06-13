// x86_64 control-padding projection.
//
// This pass publishes per-child padding from parser-owned HIR statement
// records before instruction counting. Consumers read a flat GPU table instead
// of rediscovering direct control parents locally. Padding is additive because
// one node can sit in more than one control context.

import atomics;
import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

struct FeatureSummary
{
    uint mask;
    uint enum_count;
    uint match_count;
    uint aggregate_count;
    uint scalar_inst_capacity;
    uint call_count;
    uint param_count;
    uint reserved;
};

ConstantBuffer<Params> gParams;
ConstantBuffer<FeatureSummary> gX86Features;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint4> x86_match_record;
StructuredBuffer<uint> x86_match_return_node;
StructuredBuffer<uint> x86_match_result_value_owner;
StructuredBuffer<uint> x86_for_iterable_node;

RWStructuredBuffer<uint> x86_node_control_padding;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_STMT = 7u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;

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

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

bool node_is_stmt_kind(uint node, uint stmt_kind)
{
    if (!valid_node(node))
        return false;
    uint kind = hir_kind[node];
    return (kind == HIR_STMT ||
            (stmt_kind == STMT_RECORD_KIND_IF && kind == HIR_IF_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_WHILE && kind == HIR_WHILE_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_FOR && kind == HIR_FOR_STMT) ||
            (stmt_kind == STMT_RECORD_KIND_RETURN && kind == HIR_RETURN_STMT)) &&
           stmt_slot(node, 0u) == stmt_kind;
}

void add_padding(uint child, uint padding)
{
    if (!valid_node(child))
        return;
    if (padding != 0u)
        atomic_u32_add(x86_node_control_padding, child, padding);
}

bool match_expr_is_return_value(uint match_node)
{
    if (!valid_node(match_node))
        return false;
    uint return_node = x86_match_return_node[match_node];
    return valid_node(return_node) &&
           stmt_slot(return_node, 0u) == STMT_RECORD_KIND_RETURN;
}

bool supported_return_match(uint match_node)
{
    if (!has_match_feature() || !valid_node(match_node) || hir_kind[match_node] != HIR_MATCH_EXPR)
        return false;
    uint4 record = x86_match_record[match_node];
    return valid_node(record.x) &&
           valid_node(record.y) &&
           record.z == 2u &&
           match_expr_is_return_value(match_node);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    if (has_match_feature() && valid_node(x86_match_result_value_owner[node]))
    {
        add_padding(node, 1u);
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_IF))
    {
        add_padding(stmt_slot(node, 1u), 1u);
        if (valid_node(stmt_slot(node, 3u)))
            add_padding(stmt_slot(node, 2u), 1u);
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_WHILE))
    {
        add_padding(stmt_slot(node, 1u), 1u);
        add_padding(stmt_slot(node, 2u), 1u);
        return;
    }

    if (node_is_stmt_kind(node, STMT_RECORD_KIND_FOR))
    {
        add_padding(x86_for_iterable_node[node], 3u);
        add_padding(stmt_slot(node, 3u), 1u);
        return;
    }

    if (supported_return_match(node))
    {
        add_padding(x86_match_record[node].x, 1u);
    }
}
