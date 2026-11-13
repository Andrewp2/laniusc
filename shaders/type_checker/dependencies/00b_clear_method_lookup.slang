// Clear the method index of the dependency page slot before 00c rebuilds it
// for the page loaded into the slot.

import gpu_index;

RWStructuredBuffer<uint> dependency_method_lookup;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint slot = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    uint length; uint stride;
    dependency_method_lookup.GetDimensions(length, stride);
    if (slot < length)
        dependency_method_lookup[slot] = 0xffffffffu;
}
