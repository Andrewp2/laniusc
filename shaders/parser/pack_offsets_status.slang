struct Params
{
    uint n_pairs;
    uint emit_capacity;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> sc_prefix;
StructuredBuffer<uint> emit_prefix;
RWStructuredBuffer<uint> projected_status;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_NONE = 0u;
static const uint ERR_OUTPUT_CAPACITY = 3u;

uint linear_thread_id(uint3 gid, uint3 ltid)
{
    return (gid.x + gid.y * MAX_GROUPS_X) * WG_SIZE + ltid.x;
}

uint active_pair_count()
{
    uint active_tokens = token_count[0u] + 2u;
    uint active_pairs = active_tokens > 0u ? active_tokens - 1u : 0u;
    return min(gParams.n_pairs, active_pairs);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 gid: SV_GroupID, uint3 ltid: SV_GroupThreadID)
{
    uint i = linear_thread_id(gid, ltid);
    if (i != 0u)
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

    uint last = n_active - 1u;
    uint sc_total = sc_prefix[last];
    uint emit_total = emit_prefix[last];
    bool emit_overflow = emit_total > gParams.emit_capacity;
    uint reported_emit = min(emit_total, gParams.emit_capacity);

    projected_status[0u] = emit_overflow ? 0u : 1u;
    projected_status[1u] = emit_overflow ? last : 0u;
    projected_status[2u] = emit_overflow ? ERR_OUTPUT_CAPACITY : ERR_NONE;
    projected_status[3u] = emit_overflow ? emit_total : 0u;
    projected_status[4u] = sc_total;
    projected_status[5u] = reported_emit;
}
