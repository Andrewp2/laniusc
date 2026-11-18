// Clear the reusable open-address table before rebuilding import visibility.

import gpu_index;

struct Params
{
    uint declaration_count;
    uint import_capacity;
    uint visible_capacity;
    uint lookup_capacity;
    uint source_len;
    uint path_capacity;
    uint namespace;
    uint hir_capacity;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> dependency_visible_lookup;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (i < gParams.lookup_capacity)
        dependency_visible_lookup[i] = INVALID;
}
