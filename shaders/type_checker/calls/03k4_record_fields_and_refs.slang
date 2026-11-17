// The record-literal field expectations (04_struct_init_fields) and the
// dense struct-literal references (01a_struct_literal_refs) of one inference
// round in one dispatch. Neither body reads a row the other writes, and each
// lane writes only its own rows, so running both per lane matches running
// them as two dispatches.

import type_checker.type.instances.struct_init_fields;
import type_checker.semantic.artifact.struct_literal_refs;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    struct_init_field_lane(dtid);
    struct_literal_ref_lane(dtid);
}
