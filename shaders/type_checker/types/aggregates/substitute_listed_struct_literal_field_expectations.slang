// substitute_struct_literal_field_expectations over the field rows of struct literals that
// list_struct_literal_rows listed, after each inference round's struct-literal fields. The
// passes that give a field its expected type (project_struct_init_fields and 04b,
// project_dependency_struct_literals) write only those rows' name tokens, so every other token
// keeps the CT_NONE that 01 wrote before the rounds.
#include "field_expected_ids.slang"
import shared.syntax.hir_records;

StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_literal_row_counts;
StructuredBuffer<uint> struct_literal_field_rows;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    if (lane >= struct_literal_row_counts[0u]) return;
    uint token = compact_fields[struct_literal_field_rows[lane]].name_token;
    uint count; uint stride;
    struct_init_field_expected_ct.GetDimensions(count, stride);
    if (token >= gParams.n_tokens || token >= count) return;
    struct_init_field_expected_ct[token] = field_expected_id(token);
}
