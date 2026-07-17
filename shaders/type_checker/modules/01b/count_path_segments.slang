// Publish compact path segment ranges without reconstructing parser lists.

import atomics;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirPath { uint owner; uint segment_start; uint segment_count; uint kind; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_path_count;
StructuredBuffer<HirPath> compact_paths;
StructuredBuffer<uint> compact_path_segment_count;
RWStructuredBuffer<uint> path_segment_base;
RWStructuredBuffer<uint> path_segment_count;
RWStructuredBuffer<uint> path_segment_count_out;
RWStructuredBuffer<uint> path_max_segment_count;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint tid(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = tid(dtid);
    if (row == 0u)
        path_segment_count_out[0u] = min(compact_path_segment_count[0u], gParams.n_tokens);
    uint count = min(compact_path_count[0u], gParams.n_hir_nodes);
    if (row >= count)
        return;
    HirPath path = compact_paths[row];
    path_segment_base[row] = path.segment_start;
    path_segment_count[row] = path.segment_count;
    atomic_u32_max(path_max_segment_count, 0u, path.segment_count);
}
