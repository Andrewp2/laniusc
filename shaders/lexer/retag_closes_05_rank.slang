import retag_closes_common;

StructuredBuffer<uint> token_count;
StructuredBuffer<TokenOut> tokens_out;
StructuredBuffer<uint> layer;
StructuredBuffer<uint> hist_push;
StructuredBuffer<uint> hist_pop;
RWStructuredBuffer<uint> rank;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint l = tid.x;
    uint total = token_count[0];
    if (l >= total + 2u)
        return;

    if (hist_push[l] == 0u && hist_pop[l] == 0u)
        return;

    uint push_rank = 0u;
    uint pop_rank = 0u;
    for (uint i = 0u; i < total; i++)
    {
        if (layer[i] != l)
            continue;

        uint kind = tokens_out[i].kind;
        if (is_open(kind))
            rank[i] = push_rank++;
        else if (is_close(kind))
            rank[i] = pop_rank++;
    }
}
