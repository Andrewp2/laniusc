// Build compact dispatch arguments for the x86 instruction-order prefix scan.
//
// x86_node_inst_order writes dense rows [0, order_count) plus a zero sentinel
// at order_count. The following scan only needs that compact range, not the
// whole HIR capacity.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
    uint inst_capacity;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> x86_node_inst_order_status;

RWStructuredBuffer<uint> active_node_order_scan_dispatch_args;
RWStructuredBuffer<uint> active_node_order_scan_block_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint X86_NODE_INST_ORDER_OK = 1u;

uint saturating_add_u32(uint a, uint b)
{
    uint sum = a + b;
    return sum < a ? 0xffffffffu : sum;
}

bool order_status_ok()
{
    return x86_node_inst_order_status[0u] == X86_NODE_INST_ORDER_OK &&
           x86_node_inst_order_status[1u] == 0u &&
           x86_node_inst_order_status[3u] <= gParams.n_hir_nodes;
}

uint order_scan_count()
{
    uint max_scan_count = saturating_add_u32(gParams.n_hir_nodes, 1u);
    uint order_count = order_status_ok() ? x86_node_inst_order_status[3u] : 0u;
    return min(saturating_add_u32(order_count, 1u), max_scan_count);
}

void write_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint groups = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    args[0u] = min(groups, MAX_GROUPS_X);
    args[1u] = max(1u, (groups + MAX_GROUPS_X - 1u) / MAX_GROUPS_X);
    args[2u] = 1u;
}

void write_scan_block_dispatch_args(RWStructuredBuffer<uint> args, uint active_records)
{
    uint active_blocks = max(1u, (active_records + WG_SIZE - 1u) / WG_SIZE);
    write_dispatch_args(args, active_blocks);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (tid.x != 0u || tid.y != 0u || tid.z != 0u)
        return;

    uint count = order_scan_count();
    write_dispatch_args(active_node_order_scan_dispatch_args, count);
    write_scan_block_dispatch_args(active_node_order_scan_block_dispatch_args, count);
}
