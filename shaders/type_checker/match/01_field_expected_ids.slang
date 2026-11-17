// Substitute each struct-literal field's declaration-side expected type under
// its literal's application (field_expected_ids.slang). Recorded after the
// struct-literal fields that precede call inference. One lane per token, and
// every token is written, so the column follows its inputs; only the field
// name tokens of struct literals have inputs (calls/03k5).
#include "field_expected_ids.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = dtid.x + dtid.y * 16776960u;
    uint count; uint stride;
    struct_init_field_expected_ct.GetDimensions(count, stride);
    if (token >= gParams.n_tokens || token >= count) return;
    struct_init_field_expected_ct[token] = field_expected_id(token);
}
