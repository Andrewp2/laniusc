import prefix_scan;

struct ActionHeader
{
    uint push_len;
    uint emit_len;
    uint pop_tag;
    uint pop_count;
};

struct Params
{
    uint n_pairs;
    uint scan_step;
};

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> token_count;
StructuredBuffer<ActionHeader> out_headers;
StructuredBuffer<uint> sc_prefix_in;
StructuredBuffer<uint> emit_prefix_in;

RWStructuredBuffer<uint> sc_prefix_out;
RWStructuredBuffer<uint> emit_prefix_out;
RWStructuredBuffer<uint> sc_offsets;
RWStructuredBuffer<uint> emit_offsets;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

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
    if (i >= gParams.n_pairs)
        return;

    uint n_active = active_pair_count();
    ActionHeader zero = { 0u, 0u, 0u, 0u };
    ActionHeader header = i < n_active ? out_headers[i] : zero;
    uint sc_seed = header.push_len + header.pop_count;
    uint emit_seed = header.emit_len;

    if (gParams.scan_step < gParams.n_pairs)
    {
        sc_prefix_out[i] = parallel_scan_step_value<uint, PrefixScanU32Add>(
            i,
            gParams.scan_step,
            sc_seed,
            sc_prefix_in);
        emit_prefix_out[i] = parallel_scan_step_value<uint, PrefixScanU32Add>(
            i,
            gParams.scan_step,
            emit_seed,
            emit_prefix_in);
        return;
    }

    uint sc_total = i < n_active ? sc_prefix_in[i] : 0u;
    uint emit_total = i < n_active ? emit_prefix_in[i] : 0u;
    sc_offsets[i] = sc_total - (header.push_len + header.pop_count);
    emit_offsets[i] = emit_total - header.emit_len;

}
