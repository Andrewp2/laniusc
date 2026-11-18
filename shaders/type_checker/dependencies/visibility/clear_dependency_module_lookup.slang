// Clear the reusable dependency-module hash table before every rebuild. A
// source-pack type-check may be recorded more than once when a speculative
// capacity is retried, so upload-time initialization alone is insufficient.

import gpu_index;

struct Params
{
    uint module_count;
    uint lookup_capacity;
    uint import_capacity;
    uint source_len;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> dependency_module_lookup;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint slot = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (slot < gParams.lookup_capacity)
        dependency_module_lookup[slot] = INVALID;
}
