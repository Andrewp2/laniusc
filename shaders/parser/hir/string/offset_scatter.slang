// Publish canonical string reservation offsets and total pool reservation.
import prefix_scan;

struct Params {
    uint n;
    uint source_len;
    uint uses_status_count;
    uint token_capacity;
    uint retain_debug_rows;
};
ConstantBuffer<Params> gHirString;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_list_rank_local_prefix;
StructuredBuffer<uint> hir_list_rank_block_prefix;
RWStructuredBuffer<uint> hir_string_data_offset;
RWStructuredBuffer<uint> hir_string_pool_len;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint block_count() { return (gHirString.n + WG_SIZE - 1u) / WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node == 0u)
        hir_string_pool_len[0] = inclusive_scan_total(block_count(), hir_list_rank_block_prefix);
    if (node >= gHirString.n)
        return;
    if (hir_expr_record[node * 4u] != 28u)
        return;
    uint literal_row = gHirString.retain_debug_rows != 0u ? node : hir_token_pos[node];
    uint literal_capacity = gHirString.retain_debug_rows != 0u
        ? gHirString.n
        : gHirString.token_capacity;
    if (literal_row == 0xffffffffu || literal_row >= literal_capacity)
        return;
    uint block = node / WG_SIZE;
    uint base = block == 0u ? 0u : hir_list_rank_block_prefix[block - 1u];
    hir_string_data_offset[literal_row] = base + hir_list_rank_local_prefix[node];
}
