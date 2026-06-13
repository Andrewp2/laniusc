struct Params
{
    uint n_pairs;
    uint emit_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> sc_total;
StructuredBuffer<uint> emit_total;
RWStructuredBuffer<uint> projected_status;

static const uint ERR_NONE = 0u;
static const uint ERR_OUTPUT_CAPACITY = 3u;

uint active_pair_count()
{
    uint active_tokens = token_count[0u] + 2u;
    uint active_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    return min(gParams.n_pairs, active_pairs);
}

[shader("compute")]
[numthreads(1, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if (dtid.x != 0u || dtid.y != 0u || dtid.z != 0u)
        return;

    uint n_active = active_pair_count();
    if (n_active == 0u || gParams.n_pairs == 0u)
    {
        projected_status[0u] = 1u;
        projected_status[1u] = 0u;
        projected_status[2u] = ERR_NONE;
        projected_status[3u] = 0u;
        projected_status[4u] = 0u;
        projected_status[5u] = 0u;
        return;
    }

    uint sc_sum = sc_total[0u];
    uint emit_sum = emit_total[0u];
    bool emit_overflow = emit_sum > gParams.emit_capacity;
    uint reported_emit = min(emit_sum, gParams.emit_capacity);

    projected_status[0u] = emit_overflow ? 0u : 1u;
    projected_status[1u] = emit_overflow ? n_active - 1u : 0u;
    projected_status[2u] = emit_overflow ? ERR_OUTPUT_CAPACITY : ERR_NONE;
    projected_status[3u] = emit_overflow ? emit_sum : 0u;
    projected_status[4u] = sc_sum;
    projected_status[5u] = reported_emit;
}
