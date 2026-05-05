StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hist_push;
StructuredBuffer<uint> hist_pop;
RWStructuredBuffer<uint> off_push;
RWStructuredBuffer<uint> off_pop;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint total = token_count[0];
    uint n_layers = total + 2u;
    uint l = tid.x;
    if (l >= n_layers)
        return;

    uint ps = 0u;
    uint pp = 0u;
    for (uint k = 0u; k < l; k++)
    {
        ps += hist_push[k];
        pp += hist_pop[k];
    }
    off_push[l] = ps;
    off_pop[l] = pp;
}
