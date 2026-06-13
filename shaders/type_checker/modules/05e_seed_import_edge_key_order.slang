// GPU import-edge key order seeding.
//
// Scheduling contract:
// - Dispatch after imports have been resolved to target module ids.
// - Initializes a dense import-row order for the import-edge radix sort.
// - Does not inspect source text, resolve paths, use hashes, or walk module
//   graphs on the CPU.

import gpu_index;

struct Params
{
    uint module_capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> import_count_out;

RWStructuredBuffer<uint> import_edge_key_order;
RWStructuredBuffer<uint> import_edge_key_order_tmp;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint import_capacity()
{
    return gParams.module_capacity;
}

uint active_import_count()
{
    return min(import_count_out[0], import_capacity());
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint import_i = linear_thread_id(dtid);
    if (import_i >= import_capacity())
        return;

    uint value = import_i < active_import_count() ? import_i : INVALID;
    import_edge_key_order[import_i] = value;
    import_edge_key_order_tmp[import_i] = INVALID;
}
