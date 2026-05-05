import retag_closes_common;

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<int> exscan_inblock;
StructuredBuffer<int> block_prefix;
RWStructuredBuffer<uint> layer;
RWStructuredBuffer<uint> hist_push;
RWStructuredBuffer<uint> hist_pop;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    uint total = token_count[0];
    if (i >= total)
        return;

    layer[i] = 0xFFFFFFFFu;

    uint kind = tokens_out[i].kind;
    bool push = is_open(kind);
    bool pop = is_close(kind);
    if (!push && !pop)
        return;

    int d0 = exscan_inblock[i] + block_prefix[i / 256u];
    int l_signed = push ? (d0 + 1) : d0;
    if (l_signed < 0)
        return;

    uint l = (uint)l_signed;
    if (l >= total + 2u)
        return;

    layer[i] = l;
    if (push)
        InterlockedAdd(hist_push[l], 1u);
    else
        InterlockedAdd(hist_pop[l], 1u);
}
