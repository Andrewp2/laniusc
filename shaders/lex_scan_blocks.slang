// shaders/lex_scan_blocks.slang
// Pass 2b: scan block summaries (small array), using merge table.

struct LexParams
{
    uint n;
    uint m;
    uint identity_id;
};
ConstantBuffer<LexParams> gParams;

struct ScanParams
{
    uint stride;
    uint use_ping_as_src;
};
ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> merge_table; // m*m

RWStructuredBuffer<uint> block_ping; // length NB = ceil(n/BLOCK)
RWStructuredBuffer<uint> block_pong; // length NB

static const uint BLOCK = 128u; // must match block size used in block_scan

uint merge_ids(uint left_id, uint right_id)
{
    // right ∘ left
    return merge_table[left_id * gParams.m + right_id];
}

[shader("compute")]
[numthreads(128, 1, 1)]
void scan_blocks_step(uint3 tid: SV_DispatchThreadID)
{
    uint NB = (gParams.n + BLOCK - 1u) / BLOCK;
    uint i = tid.x;
    if (i >= NB)
        return;

    if (gScan.use_ping_as_src != 0u)
    {
        uint val = block_ping[i];
        if (i >= gScan.stride)
        {
            uint left = block_ping[i - gScan.stride];
            val = merge_ids(left, val);
        }
        block_pong[i] = val;
    }
    else
    {
        uint val = block_pong[i];
        if (i >= gScan.stride)
        {
            uint left = block_pong[i - gScan.stride];
            val = merge_ids(left, val);
        }
        block_ping[i] = val;
    }
}
