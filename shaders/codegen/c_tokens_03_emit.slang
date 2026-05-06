import c_tokens_common;

StructuredBuffer<uint> offsets;
StructuredBuffer<uint> block_prefix;
RWStructuredBuffer<uint> status;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID, uint3 gid: SV_GroupID)
{
    uint i = tid.x;
    uint n_active = active_token_count();
    if (n_active == 0u)
    {
        if (i == 0u)
        {
            status[0] = 0u;
            status[1] = 1u;
        }
        return;
    }

    if (i >= gParams.n_tokens)
        return;
    if (i >= n_active)
        return;

    uint phase_base = gParams.emit_phase == EMIT_PHASE_TOP_LEVEL ? status[0] : 0u;
    uint block_idx = gid.x;
    uint block_base = block_idx == 0u ? 0u : block_prefix[block_idx - 1u];
    uint len = emit_token_fragment(i, phase_base + block_base + offsets[i], true);
    if (i + 1u == n_active)
    {
        uint total = phase_base + block_base + offsets[i] + len;
        status[0] = total;
        status[1] = total <= gParams.out_capacity ? 1u : 0u;
    }
}
