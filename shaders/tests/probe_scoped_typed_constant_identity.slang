import primitive_types;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;
import tests.typed_constant_identity_fixture;

RWStructuredBuffer<uint4> results;

// Original case IDs and 64-lane dispatch are retained across fixture families.
[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint id = dtid.x;
    if (id < 20u || id > 21u) return;
    uint left = 0u; uint right = 1u; uint context = INVALID;
    uint a; uint b;
    bool equal = scoped_type_refs_equal<LeftGraph>(3u, left, context, 3u, right, INVALID, 22u, 64u);
    bool left_ok = scoped_type_ref_hash<LeftGraph>(3u, left, context, 22u, 64u, a);
    bool right_ok = scoped_type_ref_hash<LeftGraph>(3u, right, INVALID, 22u, 64u, b);
    uint3 reference = uint3(3u, 3u, id == 20u ? INVALID : 1u);
    ConstantReferenceDescriptor descriptor;
    bool ok = scoped_constant_reference<LeftGraph>(reference, 64u, descriptor);
    results[id] = uint4(ok ? 1u : 0u, descriptor.disposition, descriptor.pending_fit,
        ok && (id == 20u ? reference.z == INVALID : descriptor.value.x == SCALAR_U8) ? 1u : 0u);
    return;
}
