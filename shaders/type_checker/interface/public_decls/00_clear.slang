// Initialize the retained local-declaration to persisted-declaration map.
//
// This table crosses the module-resolution/type-graph phase boundary, so it
// must not alias namespace-key or import-visibility scratch.

struct Params
{
    uint capacity;
    uint reserved;
    uint n_blocks;
    uint key_step;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> interface_public_decl_count;
RWStructuredBuffer<uint> interface_public_decl_local_id;
RWStructuredBuffer<uint> interface_public_decl_index_by_local;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= gParams.capacity)
        return;
    interface_public_decl_local_id[row] = INVALID;
    interface_public_decl_index_by_local[row] = INVALID;
    if (row == 0u)
        interface_public_decl_count[0u] = 0u;
}
