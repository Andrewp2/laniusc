// shaders/lex_fixup.slang
// Pass 2c: apply block carries to in-block prefixes → global prefix (f_final).

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

StructuredBuffer<uint> merge_table;  // m*m
StructuredBuffer<uint> f_inblock;    // length n
StructuredBuffer<uint> block_prefix; // inclusive scan of summaries, length NB

RWStructuredBuffer<uint> f_final; // length n

static const uint BLOCK = 128u;

uint merge_ids(uint left_id, uint right_id)
{
    // right ∘ left
    return merge_table[left_id * gParams.m + right_id];
}

[shader("compute")]
[numthreads(128, 1, 1)]
void fixup_prefix(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    uint block_id = i / BLOCK;

    // exclusive carry: identity for block 0; else prefix[block_id-1]
    uint carry = (block_id == 0u) ? gParams.identity_id
                                  : block_prefix[block_id - 1u];

    uint global = merge_ids(carry, f_inblock[i]);
    f_final[i] = global;
}
