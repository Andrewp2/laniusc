// Clear one canonical generic-arity row per dependency declaration.

import gpu_index;

struct Params
{
    uint type_count;
    uint declaration_count;
    uint member_count;
    uint path_capacity;
    uint token_capacity;
};

ConstantBuffer<Params> gParams;
RWStructuredBuffer<uint> declaration_generic_arity;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint declaration_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (declaration_i < gParams.declaration_count)
        declaration_generic_arity[declaration_i] = 0u;
}
