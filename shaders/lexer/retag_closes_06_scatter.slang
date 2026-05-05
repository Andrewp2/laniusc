import retag_closes_common;

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> layer;
StructuredBuffer<uint> rank;
StructuredBuffer<uint> off_push;
StructuredBuffer<uint> off_pop;
RWStructuredBuffer<uint> pushes_by_layer;
RWStructuredBuffer<uint> pops_by_layer;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    uint total = token_count[0];
    if (i >= total)
        return;

    uint kind = tokens_out[i].kind;
    bool push = is_open(kind);
    bool pop = is_close(kind);
    if (!push && !pop)
        return;

    uint l = layer[i];
    if (l >= total + 2u)
        return;

    uint r = rank[i];
    if (r >= total)
        return;

    if (push)
        pushes_by_layer[off_push[l] + r] = i;
    else
        pops_by_layer[off_pop[l] + r] = i;
}
