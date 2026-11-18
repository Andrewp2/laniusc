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
    // Case 41 tested the deleted inference engine's request descriptors.
    if (id < 42u || id > 43u) return;
    // A 64-step projection chain folds; a longer one is rejected.
    uint3 reference = uint3(3u, id == 42u ? 100u : 163u, INVALID);
    ConstantReferenceDescriptor descriptor;
    bool ok = scoped_constant_reference<LeftGraph>(reference, 64u, descriptor);
    if (id == 42u)
        results[id] = uint4(ok ? 1u : 0u, descriptor.steps == 64u ? 1u : 0u,
            all(descriptor.value == uint3(SCALAR_U64, 3u, 0u)) ? 1u : 0u,
            descriptor.pending_fit == 0u ? 1u : 0u);
    else results[id] = uint4(ok ? 0u : 1u, 1u, 1u, 1u);
}
