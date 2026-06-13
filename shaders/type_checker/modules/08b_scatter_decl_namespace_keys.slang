// GPU declaration namespace table scatter.
//
// Scheduling contract:
// - Dispatch after type/value declaration flags have been prefix-scanned.
// - The input order is the sorted declaration-key table, so filtering by a
//   single namespace preserves sorted (module, name) lookup order for each
//   output table.
// - It does not resolve imports, expand visibility, resolve type/value paths,
//   read source bytes, or apply same-source shortcuts.

import scatter;

struct Params
{
    uint decl_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> sorted_decl_key_order;
StructuredBuffer<uint> decl_type_key_flag;
StructuredBuffer<uint> decl_type_key_prefix;
StructuredBuffer<uint> decl_value_key_flag;
StructuredBuffer<uint> decl_value_key_prefix;

RWStructuredBuffer<uint> decl_type_key_to_decl_id;
RWStructuredBuffer<uint> decl_value_key_to_decl_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_decl_count()
{
    return min(decl_count_out[0], gParams.decl_capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.decl_capacity)
        return;

    decl_type_key_to_decl_id[i] = INVALID;
    decl_value_key_to_decl_id[i] = INVALID;

    if (i >= active_decl_count())
        return;

    uint decl_i = sorted_decl_key_order[i];
    if (decl_i >= active_decl_count())
        return;

    CompactScatterSlot type_slot = compact_scatter_slot(decl_type_key_flag[i], decl_type_key_prefix[i]);
    if (type_slot.active != 0u)
    {
        compact_scatter_store<uint>(
            type_slot,
            decl_type_key_to_decl_id,
            gParams.decl_capacity,
            decl_i);
    }

    CompactScatterSlot value_slot =
        compact_scatter_slot(decl_value_key_flag[i], decl_value_key_prefix[i]);
    if (value_slot.active != 0u)
    {
        compact_scatter_store<uint>(
            value_slot,
            decl_value_key_to_decl_id,
            gParams.decl_capacity,
            decl_i);
    }
}
