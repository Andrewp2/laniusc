// Prefix-scan raw string reservation lengths over HIR node order.
import prefix_scan;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_string_len;
RWStructuredBuffer<uint> hir_list_rank_local_prefix;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gHirString.uses_status_count != 0u ? min(gHirString.n, tree_count_status[5u]) : gHirString.n; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id(gid);
    uint node = block * WG_SIZE + ltid.x;
    uint len = node < active_node_count() ? hir_expr_string_len[node] : 0u;
    uint inclusive = prefix_scan_u32_256(ltid.x, len);
    if (node < gHirString.n)
        hir_list_rank_local_prefix[node] = inclusive - len;
    if (ltid.x == WG_SIZE - 1u)
        hir_list_rank_block_sum[block] = inclusive;
}
