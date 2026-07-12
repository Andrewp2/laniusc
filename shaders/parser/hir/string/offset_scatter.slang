// Publish canonical string reservation offsets and total pool reservation.
import prefix_scan;

struct Params { uint n; uint uses_status_count; };
ConstantBuffer<Params> gHirString;
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
    uint block = node / WG_SIZE;
    uint base = block == 0u ? 0u : hir_list_rank_block_prefix[block - 1u];
    hir_string_data_offset[node] = base + hir_list_rank_local_prefix[node];
}
