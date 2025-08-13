// Add the block-level inclusive prefix (carry from previous blocks) to each
// thread's in-block prefix and write the final ALL/KEPT sums.

#define WORKGROUP_SIZE 256

struct Params
{
    uint n;
    uint n_states;
    uint start_state;
};
ConstantBuffer<Params> gParams;

StructuredBuffer<uint2> s_pair_inblock;    // length n
StructuredBuffer<uint2> block_prefix_pair; // length nb (inclusive per block)

RWStructuredBuffer<uint> s_all_final;  // length n
RWStructuredBuffer<uint> s_keep_final; // length n

[shader("compute")]
[numthreads(WORKGROUP_SIZE, 1, 1)]
void sum_apply_block_prefix_downsweep(uint3 tid: SV_GroupThreadID,
                                      uint3 gid: SV_DispatchThreadID,
                                      uint3 ggrp: SV_GroupID)
{
    const uint block = ggrp.x;
    const uint base = block * WORKGROUP_SIZE;
    const uint i = base + tid.x;

    if (i >= gParams.n)
        return;

    // Carry = inclusive prefix of all prior blocks
    uint2 carry = uint2(0u, 0u);
    if (block > 0u)
    {
        carry = block_prefix_pair[block - 1u];
    }

    uint2 res = s_pair_inblock[i] + carry;
    s_all_final[i] = res.x;
    s_keep_final[i] = res.y;
}
