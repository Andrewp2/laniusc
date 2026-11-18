// Builds one exact `(callee, slot)` call-claim index. Heads and next links
// store row-plus-one so zero remains the empty-chain sentinel.

import atomics;
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
StructuredBuffer<uint> claim_callee;
StructuredBuffer<uint> claim_slot;
RWStructuredBuffer<uint> claim_lookup_head;
RWStructuredBuffer<uint> claim_lookup_next;
RWStructuredBuffer<uint> claim_slot_mask;

static const uint INVALID = 0xffffffffu;
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
    if (row >= count)
        return;

    claim_lookup_next[row] = 0u;
    uint callee = claim_callee[row];
    uint slot = claim_slot[row];
    if (callee == INVALID || slot == INVALID)
        return;

    // A conservative per-call summary avoids probing slots that no claim
    // has ever used in this compile. Retaining bits across inference rounds
    // is safe: consumers still read the current exact index. Slot 32 is an
    // error marker, not a binding; it remains in the index below.
    uint token_capacity; uint stride;
    claim_slot_mask.GetDimensions(token_capacity, stride);
    if (callee < token_capacity && slot < 32u)
    {
        uint ignored;
        InterlockedOr(claim_slot_mask[callee], 1u << slot, ignored);
    }

    uint bucket = call_claim_lookup_bucket(callee, slot, count);
    for (;;)
    {
        uint previous = claim_lookup_head[bucket];
        claim_lookup_next[row] = previous;
        uint observed = atomic_u32_compare_exchange(
            claim_lookup_head, bucket, previous, row + 1u);
        if (observed == previous)
            return;
    }
}
