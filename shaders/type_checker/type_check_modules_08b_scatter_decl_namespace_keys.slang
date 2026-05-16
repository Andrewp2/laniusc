// GPU declaration namespace table scatter.
//
// Scheduling contract:
// - Dispatch after type/value declaration flags have been prefix-scanned.
// - The input order is the sorted declaration-key table, so filtering by a
//   single namespace preserves sorted (module, name) lookup order for each
//   output table.
// - It does not resolve imports, expand visibility, resolve type/value paths,
//   read source bytes, or apply same-source shortcuts.

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

    if (decl_type_key_flag[i] != 0u)
    {
        uint dst = decl_type_key_prefix[i];
        if (dst < gParams.decl_capacity)
            decl_type_key_to_decl_id[dst] = decl_i;
    }

    if (decl_value_key_flag[i] != 0u)
    {
        uint dst = decl_value_key_prefix[i];
        if (dst < gParams.decl_capacity)
            decl_value_key_to_decl_id[dst] = decl_i;
    }
}
