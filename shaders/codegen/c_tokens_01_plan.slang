import c_tokens_common;

RWStructuredBuffer<uint> lengths_out;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i >= gParams.n_tokens)
        return;
    lengths_out[i] = i < active_token_count() ? token_fragment_len(i) : 0u;
}
