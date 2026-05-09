struct ScanParams
{
    uint n_tokens;
    uint scan_step;
};

ConstantBuffer<ScanParams> gScan;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> bool_probe_status;
StructuredBuffer<uint> bool_stmt_len;
StructuredBuffer<uint> prefix_in;

RWStructuredBuffer<uint> prefix_out;
RWStructuredBuffer<uint> bool_stmt_offsets;
RWStructuredBuffer<uint> bool_scan_status;

uint active_token_count()
{
    return min(token_count[0], gScan.n_tokens);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    if (bool_probe_status[1u] == 0u)
        return;

    uint i = tid.x;
    if (i >= gScan.n_tokens)
        return;

    uint active = active_token_count();
    uint own_len = i < active ? bool_stmt_len[i] : 0u;

    if (gScan.scan_step == 0u)
    {
        prefix_out[i] = own_len;
        return;
    }

    if (gScan.scan_step < gScan.n_tokens)
    {
        uint value = prefix_in[i];
        if (i >= gScan.scan_step)
            value += prefix_in[i - gScan.scan_step];
        prefix_out[i] = value;
        return;
    }

    if (i < active)
        bool_stmt_offsets[i] = prefix_in[i] - own_len;

    if (i == 0u)
    {
        uint total = active == 0u ? 0u : prefix_in[active - 1u];
        bool_scan_status[0u] = total;
        bool_scan_status[1u] = total == 0u ? 0u : 1u;
    }
}
