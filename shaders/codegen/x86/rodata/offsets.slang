// x86_64 rodata byte offsets by HIR node.

import gpu_index;
import prefix_scan;
import status;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_rodata_size_by_node;
StructuredBuffer<uint> x86_rodata_scan_local_prefix;
StructuredBuffer<uint> x86_rodata_scan_block_prefix;

RWStructuredBuffer<uint> x86_rodata_offset_by_node;
RWStructuredBuffer<uint> x86_rodata_len;
RWStructuredBuffer<uint> x86_rodata_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;
static const uint X86_RODATA_OK = 1u;
static const uint X86_ERR_RODATA_OFFSET = 64u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

bool rodata_status_ok()
{
    return x86_rodata_status[0u] == X86_RODATA_OK &&
           x86_rodata_status[1u] == 0u;
}

uint active_node_count()
{
    return rodata_status_ok() ? min(x86_rodata_status[3u], gScan.n_items) : 0u;
}

uint scanned_prefix_for_node(uint node)
{
    return global_exclusive_prefix(
        node,
        256u,
        x86_rodata_scan_local_prefix,
        x86_rodata_scan_block_prefix);
}

uint saturating_sum_or_oob(uint left, uint right)
{
    uint sum = left + right;
    return sum < left ? INVALID : sum;
}

uint scanned_total(uint count)
{
    if (count == 0u)
        return 0u;
    uint last = count - 1u;
    return saturating_sum_or_oob(
        scanned_prefix_for_node(last),
        x86_rodata_size_by_node[last]);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint count = active_node_count();
    uint total = rodata_status_ok() ? scanned_total(count) : 0u;
    bool ok = rodata_status_ok() && total != INVALID;

    if (node == 0u)
    {
        x86_rodata_len[0u] = ok ? total : 0u;
        x86_rodata_status[0u] = ok ? X86_RODATA_OK : 0u;
        if (!ok && x86_rodata_status[1u] == 0u)
        {
            x86_rodata_status[1u] = X86_ERR_RODATA_OFFSET;
            x86_rodata_status[2u] = count;
        }
    }

    if (!ok || node >= count)
        return;

    x86_rodata_offset_by_node[node] = scanned_prefix_for_node(node);
}
