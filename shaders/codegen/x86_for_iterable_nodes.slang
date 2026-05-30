// x86_64 for-loop iterable node projection.
//
// Parser HIR statement records store the for binding token, iterable HIR path
// node, and body node. This pass publishes the iterable relation from that
// parser-owned record so instruction planning can join by GPU-resident records
// instead of probing tree parents or re-keying through source-token starts.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_stmt_record;

RWStructuredBuffer<uint> x86_for_iterable_node;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint HIR_STMT = 7u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

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

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
}

bool is_for_stmt(uint node)
{
    if (!valid_node(node))
        return false;
    uint kind = hir_kind[node];
    return (kind == HIR_FOR_STMT || kind == HIR_STMT) &&
           stmt_slot(node, 0u) == STMT_RECORD_KIND_FOR;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!is_for_stmt(node))
        return;

    uint iterable_node = stmt_slot(node, 2u);
    if (!valid_node(iterable_node) || hir_kind[iterable_node] != HIR_PATH_EXPR)
        return;

    x86_for_iterable_node[node] = iterable_node;
}
