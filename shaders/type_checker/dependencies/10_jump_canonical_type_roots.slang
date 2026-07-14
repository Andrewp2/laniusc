// One race-free parallel pointer-jumping round over canonical type roots.

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
StructuredBuffer<uint> canonical_type_roots_in;
RWStructuredBuffer<uint> canonical_type_roots_out;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint type_i = linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
    if (type_i >= gParams.type_count)
        return;
    uint parent = canonical_type_roots_in[type_i];
    canonical_type_roots_out[type_i] = parent < gParams.type_count
        ? canonical_type_roots_in[parent]
        : type_i;
}
