struct Params
{
    uint n_pairs;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> sc_prefix;
StructuredBuffer<uint> emit_prefix;
RWStructuredBuffer<uint> projected_status;

uint active_pair_count()
{
    uint active_tokens = token_count[0] + 2u;
    uint active_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    return min(gParams.n_pairs, active_pairs);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n_pairs)
        return;

    uint n_active = active_pair_count();
    if (i >= max(n_active, 1u))
        return;

    uint last = n_active == 0u ? 0u : n_active - 1u;
    uint sc_total = n_active == 0u ? 0u : sc_prefix[last];
    uint emit_total = n_active == 0u ? 0u : emit_prefix[last];

    projected_status[0u] = 1u;
    projected_status[1u] = 0u;
    projected_status[2u] = 0u;
    projected_status[3u] = 0u;
    projected_status[4u] = sc_total;
    projected_status[5u] = emit_total;
}
