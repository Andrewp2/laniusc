// Apply the selected body's lexical environment to an accepted reference
// column. Every compound type is a graph of these same references, so replacing
// its parameter edges specializes arbitrary nesting without copying or guessing
// layouts. Declaration signatures are not bound to this operation.
struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> reference_tag;
RWStructuredBuffer<uint> reference_payload;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = dtid.x + dtid.y * 16776960u;
    uint count; uint stride;
    reference_tag.GetDimensions(count, stride);
    if (row >= count || reference_tag[row] != 2u) return;
    uint parameter = reference_payload[row];
    if (parameter >= gParams.n_tokens) return;
    // 00f publishes concrete roots only for the selected declaration's
    // parameters. A same-named parameter in another scope remains symbolic.
    uint tag = type_expr_ref_tag[parameter];
    if (tag != 1u && tag != 3u) return;
    reference_payload[row] = type_expr_ref_payload[parameter];
    reference_tag[row] = tag;
}
