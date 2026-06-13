// Compact node-local virtual-instruction generation worklist.
//
// x86_node_inst_locations marks every HIR node that must execute the generator:
// either it owns a prefix-assigned instruction range or it writes a corrected
// control-flow instruction into a descendant padding slot. This pass scatters
// those nodes into a compact x86_node_inst_gen_node_record so x86_node_inst_gen
// can run over compact rows instead of sparse HIR capacity.

import gpu_index;
import prefix_scan;

struct ScanParams
{
    uint n_items;
    uint n_blocks;
    uint scan_step;
    uint inst_capacity;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> x86_node_inst_gen_flag;
StructuredBuffer<uint> x86_node_inst_scan_local_prefix;
StructuredBuffer<uint> x86_node_inst_scan_block_prefix;

RWStructuredBuffer<uint2> x86_node_inst_gen_node_record;
RWStructuredBuffer<uint> x86_node_inst_gen_input_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint WG_SIZE = 256u;
static const uint X86_ERR_NODE_VIRTUAL_INST = 11u;
static const uint X86_NODE_INST_GEN_INPUTS_OK = 1u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint scanned_prefix_for_node(uint node)
{
    return global_exclusive_prefix(
        node,
        WG_SIZE,
        x86_node_inst_scan_local_prefix,
        x86_node_inst_scan_block_prefix);
}

uint worklist_count()
{
    return inclusive_scan_total(gScan.n_blocks, x86_node_inst_scan_block_prefix);
}

uint worklist_capacity()
{
    return min(gScan.n_items == 0u ? 0u : gScan.n_items - 1u, gScan.inst_capacity);
}

uint worklist_base()
{
    return 0u;
}

bool upstream_ok()
{
    return x86_node_inst_gen_input_status[0u] == X86_NODE_INST_GEN_INPUTS_OK &&
           x86_node_inst_gen_input_status[1u] == 0u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    uint total = worklist_count();
    uint capacity = worklist_capacity();
    if (node == 0u)
    {
        x86_node_inst_gen_input_status[4u] = total;
        if (upstream_ok() && total > capacity)
        {
            x86_node_inst_gen_input_status[0u] = 0u;
            x86_node_inst_gen_input_status[1u] = X86_ERR_NODE_VIRTUAL_INST;
            x86_node_inst_gen_input_status[2u] = total;
            x86_node_inst_gen_input_status[3u] = 0u;
        }
    }

    if (total > capacity || node >= gScan.n_items)
        return;

    if (x86_node_inst_gen_flag[node] == 0u)
        return;

    uint dense_row = scanned_prefix_for_node(node);
    if (dense_row < total && dense_row < capacity)
        x86_node_inst_gen_node_record[worklist_base() + dense_row] = uint2(node, 0u);
}
