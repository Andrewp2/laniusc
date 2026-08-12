// Clears the active bucket range of one exact call-claim index.

import type_checker.calls.claim_lookup;

struct Params
{
    uint claim_capacity;
    uint reserved0;
    uint reserved1;
    uint reserved2;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> claim_count_in;
RWStructuredBuffer<uint> claim_lookup_head;

static const uint MAX_GROUPS_X = 65535u;
static const uint WG_SIZE = 256u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(WG_SIZE, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint count = min(claim_count_in[0u], gParams.claim_capacity);
    if (row < call_claim_lookup_capacity(count))
        claim_lookup_head[row] = 0u;
}
