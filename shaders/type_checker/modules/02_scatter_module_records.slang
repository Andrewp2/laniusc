// Pre-resolution GPU module record scatter.
//
// Scheduling contract:
// - Dispatch after module_record_flag has an exclusive GPU prefix scan.
// - This pass scatters module declaration records from parser-owned HIR fields.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import scatter;

struct Params
{
    uint hir_node_capacity;
    uint module_capacity;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_record_flag;
StructuredBuffer<uint> module_record_prefix;
StructuredBuffer<uint> hir_item_file_id;
StructuredBuffer<uint> path_id_by_owner_hir;

RWStructuredBuffer<uint> module_file_id;
RWStructuredBuffer<uint> module_path_id;
RWStructuredBuffer<uint> module_owner_hir;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (i < gParams.module_capacity)
    {
        module_file_id[i] = INVALID;
        module_path_id[i] = INVALID;
        module_owner_hir[i] = INVALID;
    }

    if (i >= gParams.hir_node_capacity)
        return;

    CompactScatterSlot slot = compact_scatter_slot(module_record_flag[i], module_record_prefix[i]);
    if (slot.active == 0u || slot.dst >= gParams.module_capacity)
        return;

    module_file_id[slot.dst] = hir_item_file_id[i];
    module_path_id[slot.dst] = path_id_by_owner_hir[i];
    module_owner_hir[slot.dst] = i;
}
