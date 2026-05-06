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
    ActionHeader zero = { 0u, 0u, 0u, 0u };
    ActionHeader header = i < n_active ? out_headers[i] : zero;

    if (gParams.scan_step == 0u)
    {
        sc_prefix_out[i] = header.push_len + header.pop_count;
        emit_prefix_out[i] = header.emit_len;
        return;
    }

    if (gParams.scan_step < gParams.n_pairs)
    {
        uint sc = sc_prefix_in[i];
        uint emit = emit_prefix_in[i];
        if (i >= gParams.scan_step)
        {
            sc += sc_prefix_in[i - gParams.scan_step];
            emit += emit_prefix_in[i - gParams.scan_step];
        }
        sc_prefix_out[i] = sc;
        emit_prefix_out[i] = emit;
        return;
    }

    uint sc_total = i < n_active ? sc_prefix_in[i] : 0u;
    uint emit_total = i < n_active ? emit_prefix_in[i] : 0u;
    sc_offsets[i] = sc_total - (header.push_len + header.pop_count);
    emit_offsets[i] = emit_total - header.emit_len;

}
