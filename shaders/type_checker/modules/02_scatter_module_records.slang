// Pre-resolution GPU module record scatter.
//
// Scheduling contract:
// - Dispatch after module_record_flag has an exclusive GPU prefix scan.
// - This pass scatters module declaration records from parser-owned HIR fields.
// - It does not perform module lookup, import resolution, declaration lookup,
//   visibility checks, same-source shortcuts, hash-only lookup, or CPU path
//   lookup.

import hir_records;
import scatter;

struct Params
{
    uint hir_node_capacity;
    uint token_capacity;
    uint module_capacity;
    uint reserved;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> module_record_flag;
StructuredBuffer<uint> module_record_prefix;
StructuredBuffer<HirLinks> compact_hir_links;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> path_id_by_owner_token;
StructuredBuffer<uint> path_kind;

RWStructuredBuffer<uint> module_file_id;
RWStructuredBuffer<uint> module_path_id;
RWStructuredBuffer<uint> module_owner_hir;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INVALID = 0xffffffffu;
static const uint PATH_KIND_MODULE_DECL = 1u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);

    if (i >= gParams.hir_node_capacity)
        return;

    CompactScatterSlot slot = compact_scatter_slot(module_record_flag[i], module_record_prefix[i]);
    if (slot.active == 0u || slot.dst >= gParams.module_capacity)
        return;

    // Active prefixes cover every row below the published module count.
    // Clearing compact destinations in this dispatch races with scatters from
    // other workgroups; rows beyond the count are never consumed.

    module_file_id[slot.dst] = compact_hir_links[i].file_id;
    HirCore core = compact_hir_core[i];
    uint path_id = INVALID;
    for (uint token = core.token_start;
         token < core.token_end && token < gParams.token_capacity;
         token += 1u)
    {
        uint candidate = path_id_by_owner_token[token];
        if (candidate != INVALID && path_kind[candidate] == PATH_KIND_MODULE_DECL)
        {
            path_id = candidate;
            break;
        }
    }
    module_path_id[slot.dst] = path_id;
    module_owner_hir[slot.dst] = i;
}
