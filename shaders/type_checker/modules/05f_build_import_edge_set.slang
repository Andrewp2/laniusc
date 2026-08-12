// Publishes every valid resolved import edge into the exact GPU hash set.

import gpu_index;
import type_checker.modules.import_edge_set;

struct Params
{
    uint import_capacity;
    uint path_capacity;
    uint path_segment_capacity;
    uint module_capacity;
    uint dependency_interfaces_present;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;
StructuredBuffer<uint> import_status;
StructuredBuffer<uint> import_module_id;
StructuredBuffer<uint> import_target_module_id;
RWStructuredBuffer<uint> import_edge_set_state;

public struct ImportEdgeStatusSource : IImportEdgeStatusSource
{
    public static uint status(uint row) { return import_status[row]; }
}

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, MAX_GROUPS_X * WG_SIZE);
    uint count = min(import_count_out[0u], gParams.import_capacity);
    if (row < count)
        import_edge_set_insert<ImportEdgeStatusSource>(
            row,
            count,
            import_module_id,
            import_target_module_id,
            import_edge_set_state);
}
