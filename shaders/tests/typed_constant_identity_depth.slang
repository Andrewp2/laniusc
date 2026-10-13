import primitive_types;
import type_checker.concrete_type_equality;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_hash;
import type_checker.constant_constraints;
import tests.typed_constant_identity_fixture;

RWStructuredBuffer<uint4> results;

// Original case IDs and 64-lane dispatch are retained across fixture families.
[shader("compute")]
[numthreads(64, 1, 1)]
void main(uint3 dtid : SV_DispatchThreadID)
{
    uint id = dtid.x;
    if (id < 41u || id > 43u) return;
    InferredConstant inferred[32]; uint mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = inferred_constant_reference(uint2(0u, INVALID));
    if (id == 41u)
    {
        InferredConstant request = inferred_constant_reference(uint2(3u, 100u));
        InferredConstantDescriptor original; InferredConstantDescriptor extended;
        bool before = inferred_constant_request_descriptor<LeftGraph>(request, 64u, original);
        request.target_scalar = SCALAR_U64;
        bool after = inferred_constant_request_descriptor<LeftGraph>(request, 64u, extended);
        results[id] = uint4(before ? 1u : 0u, after ? 0u : 1u,
            original.source.steps == 64u ? 1u : 0u, 1u);
    }
    else if (id == 42u || id == 43u)
    {
        uint3 reference = uint3(3u, id == 42u ? 100u : 163u, INVALID);
        ConstantReferenceDescriptor descriptor;
        bool ok = scoped_constant_reference<LeftGraph>(reference, 64u, descriptor);
        if (id == 42u)
            results[id] = uint4(ok ? 1u : 0u, descriptor.steps == 64u ? 1u : 0u,
                all(descriptor.value == uint3(SCALAR_U64, 3u, 0u)) ? 1u : 0u,
                descriptor.pending_fit == 0u ? 1u : 0u);
        else results[id] = uint4(ok ? 0u : 1u, 1u, 1u, 1u);
    }
}
