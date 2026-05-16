// GPU imported-visibility sorted key table build for one namespace table.
//
// Scheduling contract:
// - Dispatch once for type imports and once for value imports after imported
//   visibility row ids have been sorted.
// - This pass materializes a final sorted key table:
//   (importing module id, name id) -> declaration id.
// - It does not resolve paths, scan source bytes, use hashes, perform CPU
//   lookup, or apply same-source shortcuts.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_key_order;
StructuredBuffer<uint> import_visible_module_id;
StructuredBuffer<uint> import_visible_name_id;
StructuredBuffer<uint> import_visible_decl_id;

RWStructuredBuffer<uint> import_visible_key_module_id;
RWStructuredBuffer<uint> import_visible_key_name_id;
RWStructuredBuffer<uint> import_visible_key_to_decl_id;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_count()
{
    return min(import_visible_count_out[0], gParams.capacity);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= gParams.capacity)
        return;

    import_visible_key_module_id[i] = INVALID;
    import_visible_key_name_id[i] = INVALID;
    import_visible_key_to_decl_id[i] = INVALID;

    if (i >= active_count())
        return;

    uint visible_i = import_visible_key_order[i];
    if (visible_i >= gParams.capacity)
        return;

    import_visible_key_module_id[i] = import_visible_module_id[visible_i];
    import_visible_key_name_id[i] = import_visible_name_id[visible_i];
    import_visible_key_to_decl_id[i] = import_visible_decl_id[visible_i];
}
