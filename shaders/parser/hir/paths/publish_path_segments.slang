// Count the segments of each owned path for owner-ordered compaction.

import parser.hir.paths.path_tree;
import shared.buffers.atomics;

struct Params { uint n; uint uses_status_count; uint retain_debug_rows; };
ConstantBuffer<Params> gHirPath;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_path_root_owner;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_path_segment_count;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
uint linear_thread_id(uint3 dtid) { return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE; }
uint active_node_count() { return gHirPath.uses_status_count != 0u ? min(gHirPath.n, tree_count_status[5u]) : gHirPath.n; }

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint root = linear_thread_id(dtid);
    uint active = active_node_count();
    if (root >= active)
        return;
    uint owner = path_root_owner(hir_path_root_owner[root]);
    if (owner >= active)
        return;
    uint count = 0u;
    for (uint segment = path_first_segment(root, active, first_child, node_kind);
         segment < active;
         segment = path_next_segment(segment, active, first_child, next_sibling, node_kind))
        ++count;
    uint owner_row = gHirPath.retain_debug_rows != 0u ? owner : hir_token_pos[owner];
    if (owner_row != PATH_TREE_INVALID && count != 0u)
        atomic_u32_max(hir_path_segment_count, owner_row, count);
}
