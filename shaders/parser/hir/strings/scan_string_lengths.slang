// Prefix-scan raw string reservation lengths over HIR node order.
import prefix_scan;

struct Params {
    uint n;
    uint source_len;
    uint uses_status_count;
    uint token_capacity;
    uint retain_debug_rows;
};
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_pos;
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
    bool is_string = node < active_node_count() && hir_expr_record[node * 4u] == 28u;
    uint literal_row = gHirString.retain_debug_rows != 0u ? node : hir_token_pos[node];
    bool valid_literal_row = literal_row != 0xffffffffu &&
        literal_row < (gHirString.retain_debug_rows != 0u ? gHirString.n : gHirString.token_capacity);
    uint len = is_string && valid_literal_row ? hir_expr_string_len[literal_row] + 1u : 0u;
    uint inclusive = prefix_scan_u32_256(ltid.x, len);
    if (node < gHirString.n)
        hir_list_rank_local_prefix[node] = inclusive - len;
    if (ltid.x == WG_SIZE - 1u)
        hir_list_rank_block_sum[block] = inclusive;
}
