// shaders/lex_scan_merge.slang
// Stage 2: inclusive scan over unary-function ids using merge table

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

StructuredBuffer<uint> merge_table; // m*m row-major

RWStructuredBuffer<uint> f_ping; // length n
RWStructuredBuffer<uint> f_pong; // length n

uint merge_ids(uint left_id, uint right_id)
{
    // right ∘ left
    return merge_table[left_id * gParams.m + right_id];
}

[shader("compute")]
[numthreads(128, 1, 1)]
void scan_step(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    if (gScan.use_ping_as_src != 0)
    {
        uint val = f_ping[i];
        if (i >= gScan.stride)
        {
            uint left = f_ping[i - gScan.stride];
            val = merge_ids(left, val);
        }
        f_pong[i] = val;
    }
    else
    {
        uint val = f_pong[i];
        if (i >= gScan.stride)
        {
            uint left = f_pong[i - gScan.stride];
            val = merge_ids(left, val);
        }
        f_ping[i] = val;
    }
}
