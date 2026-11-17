// Record struct-literal field expectations from parser-owned HIR metadata
// (struct_init_fields.slang).

import type_checker.type.instances.struct_init_fields;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    struct_init_field_lane(dtid);
}
