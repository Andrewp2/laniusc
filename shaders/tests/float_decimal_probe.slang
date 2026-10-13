// Direct probe of the shared exact decimal conversion. No shader float/double
// operations or independent conversion implementation belong in this adapter.
import float_decimal;

struct Params
{
    uint query_count;
    uint source_len;
    uint workspace_words;
    uint workspace_stride;
};
ConstantBuffer<Params> gParams;
// scalar, negative, start, len, workspace_override, workspace_base, source_len, source_override.
StructuredBuffer<uint> queries;
ByteAddressBuffer source_bytes;
RWStructuredBuffer<uint> workspace;
// status, bits[2], consumed bytes, production workspace size.
RWStructuredBuffer<uint> results;

[shader("compute")]
[numthreads(32, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint row = dtid.x;
    if (row >= gParams.query_count) return;
    uint input = row * 8u;
    uint output = row * 5u;
    results[output + 4u] = FLOAT_DECIMAL_WORKSPACE_WORDS;
    // Fail visibly before any helper writes if host and helper sizing diverge.
    if (gParams.workspace_words != FLOAT_DECIMAL_WORKSPACE_WORDS)
    {
        results[output] = 0xffffffffu;
        results[output + 1u] = 0u;
        results[output + 2u] = 0u;
        results[output + 3u] = 0u;
        return;
    }
    uint workspace_base = queries[input + 4u] != 0u
        ? queries[input + 5u] : row * gParams.workspace_stride + 1u;
    uint2 bits;
    uint consumed;
    uint source_len = queries[input + 7u] != 0u ? queries[input + 6u] : gParams.source_len;
    uint status = float_decimal_parse_bits(source_bytes, source_len,
        queries[input + 2u], queries[input + 3u], queries[input],
        queries[input + 1u] != 0u, workspace, workspace_base, bits, consumed);
    results[output] = status;
    results[output + 1u] = bits.x;
    results[output + 2u] = bits.y;
    results[output + 3u] = consumed;
}
