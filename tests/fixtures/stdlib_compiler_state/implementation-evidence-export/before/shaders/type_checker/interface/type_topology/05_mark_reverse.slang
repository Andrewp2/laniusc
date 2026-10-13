#include "checked_types.slang"
RWStructuredBuffer<uint> interface_type_reverse_flag;
// Each annotation root reserves its complete checked tree. An alias may expand
// to a different shape and number of nodes than its written arguments.
[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint active = min(compact_hir_count[0u], gParams.hir_capacity);
    if (row >= active) return;
    interface_type_reverse_flag[row] = 0u;
    uint root = active - 1u - row;
    if (interface_type_seed_owner[root] >= gParams.decl_capacity) return;
    uint count;
    if (!checked_export_size(root, count)) { checked_export_fail(root, 1u); return; }
    interface_type_reverse_flag[row] = count;
}
