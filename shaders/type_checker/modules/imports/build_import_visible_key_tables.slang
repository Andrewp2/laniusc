// GPU imported-visibility exact lookup build for one namespace table.
//
// Scheduling contract:
// - Dispatch once for type imports and once for value imports after compact
//   visibility rows have been scattered.
// - Each immutable compact row is atomically published into an exact
//   `(importing module, name)` hash index.

import type_checker.modules.import_visible_lookup;

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_visible_count_out;
StructuredBuffer<uint> import_visible_key_module_id;
StructuredBuffer<uint> import_visible_key_name_id;
StructuredBuffer<uint> import_visible_key_to_decl_id;
RWStructuredBuffer<uint> import_visible_lookup_state;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint visible_capacity()
{
    return gParams.reserved == 0u ? gParams.capacity : gParams.reserved;
}

uint active_count()
{
    return min(import_visible_count_out[0], visible_capacity());
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_count())
        return;

    import_visible_lookup_insert(
        i,
        active_count(),
        visible_capacity(),
        import_visible_key_module_id,
        import_visible_key_name_id,
        import_visible_key_to_decl_id,
        import_visible_lookup_state);
}
