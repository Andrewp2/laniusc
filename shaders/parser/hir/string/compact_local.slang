// Compact canonical string HIR nodes with a block-local prefix scan.
import prefix_scan;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_record;
RWStructuredBuffer<uint> hir_list_rank_flag;
RWStructuredBuffer<uint> hir_list_rank_local_prefix;
RWStructuredBuffer<uint> hir_list_rank_block_sum;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR_STRING = 28u;
uint linear_group_id(uint3 gid) { return gid.x + gid.y * MAX_GROUPS_X; }
uint active_node_count() { return gHirString.uses_status_count != 0u ? min(gHirString.n, tree_count_status[5u]) : gHirString.n; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint block = linear_group_id(gid);
    uint node = block * WG_SIZE + ltid.x;
    uint flag = node < active_node_count() && hir_expr_record[node * 4u] == HIR_EXPR_STRING ? 1u : 0u;
    uint inclusive = prefix_scan_u32_256(ltid.x, flag);
    if (node < gHirString.n)
    {
        hir_list_rank_flag[node] = flag;
        hir_list_rank_local_prefix[node] = inclusive - flag;
    }
    if (ltid.x == WG_SIZE - 1u)
        hir_list_rank_block_sum[block] = inclusive;
}
