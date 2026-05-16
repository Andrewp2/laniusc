// x86_64 function instruction-count ordering.
//
// This pass turns sparse per-function count rows into an explicit ordered scan
// input. Slot 0 is the compiler-owned entry function; every other HIR node owns
// slot node+1. Empty slots carry zero so the following staged scan can compute
// entry-first instruction ranges without per-thread full-array loops.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint4> x86_func_inst_count_record;
StructuredBuffer<uint> x86_func_inst_count_status;

RWStructuredBuffer<uint4> x86_func_inst_order_record;
RWStructuredBuffer<uint> x86_func_inst_order_slot;
RWStructuredBuffer<uint> x86_func_inst_scan_input;
RWStructuredBuffer<uint> x86_func_inst_order_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_FUNC_INST_COUNT_OK = 1u;
static const uint X86_FUNC_INST_ORDER_OK = 1u;
static const uint X86_ERR_UNSUPPORTED_RETURN = 3u;

uint linear_dispatch_id(uint3 tid)
{
    return tid.x + tid.y * DISPATCH_X_STRIDE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_count_record(uint node)
{
    if (!valid_node(node))
        return false;
    uint4 record = x86_func_inst_count_record[node];
    return record.x == node && record.y != 0u && record.y != INVALID;
}

bool count_status_ok()
{
    return x86_func_inst_count_status[0u] == X86_FUNC_INST_COUNT_OK &&
           x86_func_inst_count_status[1u] == 0u;
}

void write_empty_slot(uint slot)
{
    x86_func_inst_order_record[slot] = uint4(INVALID, 0u, 0u, INVALID);
    x86_func_inst_scan_input[slot] = 0u;
}

void write_order_slot(uint slot, uint node)
{
    uint4 record = x86_func_inst_count_record[node];
    x86_func_inst_order_record[slot] = record;
    x86_func_inst_scan_input[slot] = record.y;
    x86_func_inst_order_slot[node] = slot;
}

void publish_status(bool ok, uint owner)
{
    x86_func_inst_order_status[0u] = ok ? X86_FUNC_INST_ORDER_OK : 0u;
    x86_func_inst_order_status[1u] = ok ? 0u :
                                      (x86_func_inst_count_status[1u] == 0u ?
                                       X86_ERR_UNSUPPORTED_RETURN :
                                       x86_func_inst_count_status[1u]);
    x86_func_inst_order_status[2u] = ok ? INVALID :
                                      (x86_func_inst_count_status[1u] == 0u ?
                                       owner :
                                       x86_func_inst_count_status[2u]);
    x86_func_inst_order_status[3u] = ok ? x86_func_inst_count_status[3u] : 0u;
    x86_func_inst_order_status[4u] = ok ? x86_func_inst_count_status[4u] : INVALID;
    x86_func_inst_order_status[5u] = ok ? x86_func_inst_count_status[5u] : INVALID;
    x86_func_inst_order_status[6u] = ok ? x86_func_inst_count_status[6u] : 0u;
    x86_func_inst_order_status[7u] = ok ? x86_func_inst_count_status[7u] : INVALID;
    x86_func_inst_order_status[8u] = ok ? x86_func_inst_count_status[8u] : 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    uint n = active_hir_node_count();
    uint owner = x86_func_inst_count_status[4u];
    bool upstream_ok = count_status_ok();
    bool order_ok = upstream_ok && valid_count_record(owner);

    if (node_i == 0u)
        publish_status(order_ok, owner);

    if (node_i >= gParams.n_hir_nodes)
        return;

    x86_func_inst_order_slot[node_i] = INVALID;

    if (!order_ok)
        return;

    if (node_i == owner)
    {
        write_order_slot(0u, node_i);
        return;
    }

    uint slot = node_i + 1u;
    write_empty_slot(slot);
    if (node_i < n && valid_count_record(node_i))
        write_order_slot(slot, node_i);
}
