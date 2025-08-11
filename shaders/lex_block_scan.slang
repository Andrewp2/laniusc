// shaders/lex_block_scan.slang
// Pass 2a: per-block inclusive scan of unary-function ids, plus block summary.

struct LexParams
{
    uint n;           // number of input chars
    uint m;           // number of function ids (merge is m*m)
    uint identity_id; // function id 0 = identity
};
ConstantBuffer<LexParams> gParams;

StructuredBuffer<uint> merge_table;       // m*m, row-major: merge[a*m + b] = (b ∘ a)
StructuredBuffer<uint> f_src;             // length n (function ids from map)
RWStructuredBuffer<uint> f_inblock;       // length n (intra-block prefix ids)
RWStructuredBuffer<uint> block_summaries; // length ceil(n / BLOCK)

static const uint BLOCK = 128u;

uint merge_ids(uint left_id, uint right_id)
{
    // right ∘ left
    return merge_table[left_id * gParams.m + right_id];
}

groupshared uint gVals[BLOCK];

[shader("compute")]
[numthreads(BLOCK, 1, 1)]
void block_scan(uint3 dtid: SV_DispatchThreadID,
                uint3 gid: SV_GroupID,
                uint lane: SV_GroupIndex)
{
    uint i = dtid.x;
    uint block_id = gid.x;
    uint block_base = block_id * BLOCK;

    // How many live lanes in this block?
    uint remaining = (gParams.n > block_base) ? (gParams.n - block_base) : 0u;
    uint live = (remaining < BLOCK) ? remaining : BLOCK;

    // Load value or identity outside range
    uint val = (i < gParams.n) ? f_src[i] : gParams.identity_id;
    gVals[lane] = val;
    GroupMemoryBarrierWithGroupSync();

    // Hillis–Steele inclusive scan inside the block
    for (uint ofs = 1u; ofs < BLOCK; ofs <<= 1u)
    {
        uint v = gVals[lane];
        if (lane >= ofs)
        {
            uint left = gVals[lane - ofs];
            v = merge_ids(left, v);
        }
        GroupMemoryBarrierWithGroupSync();
        gVals[lane] = v;
        GroupMemoryBarrierWithGroupSync();
    }

    // Write per-element in-block prefix
    if (i < gParams.n)
        f_inblock[i] = gVals[lane];

    // Last *live* lane writes the block summary
    if (live > 0u && lane + 1u == live)
        block_summaries[block_id] = gVals[lane];
}
