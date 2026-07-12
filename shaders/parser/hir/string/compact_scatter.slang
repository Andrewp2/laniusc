// Scatter string nodes and publish one-workgroup-per-string indirect arguments.
import prefix_scan;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_list_rank_flag;
StructuredBuffer<uint> hir_list_rank_local_prefix;
StructuredBuffer<uint> hir_list_rank_block_prefix;
RWStructuredBuffer<uint> hir_string_node;
RWStructuredBuffer<uint> hir_string_count;
RWStructuredBuffer<uint> hir_list_rank_dispatch_args;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirString.uses_status_count != 0u ? min(gHirString.n, tree_count_status[5u]) : gHirString.n; }
uint block_count() { return (gHirString.n + WG_SIZE - 1u) / WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    uint count = inclusive_scan_total(block_count(), hir_list_rank_block_prefix);
    if (node == 0u)
    {
        hir_string_count[0] = count;
        hir_list_rank_dispatch_args[0] = min(count, MAX_GROUPS_X);
        hir_list_rank_dispatch_args[1] = count == 0u ? 0u : (count + MAX_GROUPS_X - 1u) / MAX_GROUPS_X;
        hir_list_rank_dispatch_args[2] = count == 0u ? 0u : 1u;
    }
    if (node >= active_node_count() || hir_list_rank_flag[node] == 0u)
        return;
    uint block = node / WG_SIZE;
    uint base = block == 0u ? 0u : hir_list_rank_block_prefix[block - 1u];
    hir_string_node[base + hir_list_rank_local_prefix[node]] = node;
}
