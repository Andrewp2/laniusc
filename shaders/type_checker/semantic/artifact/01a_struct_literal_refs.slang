// Project raw-HIR struct-literal inference contexts into dense semantic HIR
// (struct_literal_refs.slang).

import type_checker.semantic.artifact.struct_literal_refs;

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    struct_literal_ref_lane(dtid);
}
