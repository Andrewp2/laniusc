// shaders/lex_scan_sum.slang
// Stage 4a: inclusive sum-scan over filtered_flags

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

RWStructuredBuffer<uint> s_ping; // length n
RWStructuredBuffer<uint> s_pong; // length n

[shader("compute")]
[numthreads(128, 1, 1)]
void scan_sum_step(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n)
        return;

    if (gScan.use_ping_as_src != 0)
    {
        uint val = s_ping[i];
        if (i >= gScan.stride)
        {
            val += s_ping[i - gScan.stride];
        }
        s_pong[i] = val;
    }
    else
    {
        uint val = s_pong[i];
        if (i >= gScan.stride)
        {
            val += s_pong[i - gScan.stride];
        }
        s_ping[i] = val;
    }
}
