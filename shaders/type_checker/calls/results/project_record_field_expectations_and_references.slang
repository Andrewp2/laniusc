// The record-literal field expectations (project_struct_init_fields) and the
// dense struct-literal references (01a_struct_literal_refs) of one inference
// round in one dispatch. Neither body reads a row the other writes, and each
// lane writes only its own rows, so running both per lane matches running
// them as two dispatches. The lanes visit the rows list_struct_literal_rows listed: the
// field rows of struct literals, then the member and struct-literal rows.
// The other rows are no-ops for both bodies.

import type_checker.types.aggregates.struct_init_fields;
import type_checker.semantic.artifact.struct_literal_refs;

StructuredBuffer<uint> struct_literal_row_counts;
StructuredBuffer<uint> struct_literal_field_rows;
StructuredBuffer<uint> struct_literal_hir_rows;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint lane = dtid.x + dtid.y * 16776960u;
    uint fields = struct_literal_row_counts[0u];
    if (lane < fields) struct_init_field_row(struct_literal_field_rows[lane]);
    else if (lane - fields < struct_literal_row_counts[1u])
        struct_literal_ref_row(struct_literal_hir_rows[lane - fields]);
}
