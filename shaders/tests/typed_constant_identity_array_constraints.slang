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
    if (id < 44u || id > 51u) return;
    InferredConstant inferred[32]; uint mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = inferred_constant_reference(uint2(0u, INVALID));
    if (id == 44u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, 2u), INVALID,
            uint2(1u, 2u), 64u, true, inferred, mask);
        uint3 value;
        bool closed = inferred_constant_request_value<LeftGraph>(inferred[0u], 64u, value);
        results[id] = uint4(ok ? 1u : 0u, mask == 1u ? 1u : 0u,
            inferred[0u].target_scalar == SCALAR_U32 ? 1u : 0u,
            closed && all(value == uint3(SCALAR_U32, 3u, 0u)) ? 1u : 0u);
    }
    else if (id == 45u || id == 49u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, id == 45u ? 3u : 9u),
            INVALID, uint2(1u, 9u), 64u, true, inferred, mask);
        results[id] = uint4(ok ? 0u : 1u, mask == 0u ? 1u : 0u,
            inferred[1u].reference.x == 0u ? 1u : 0u, 1u);
    }
    else if (id == 46u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, 3u), INVALID,
            uint2(2u, 0u), 64u, true, inferred, mask);
        InferredConstantDescriptor request;
        bool pending = inferred_constant_request_descriptor<LeftGraph>(inferred[1u], 64u, request) &&
            request.pending_fit == 1u;
        uint3 pattern = uint3(3u, 3u, INVALID); ConstantReferenceDescriptor descriptor;
        bool pattern_pending = scoped_constant_reference<LeftGraph>(pattern, 64u, descriptor) &&
            descriptor.pending_fit == 1u;
        results[id] = uint4(ok ? 1u : 0u, mask == 2u ? 1u : 0u,
            pending && pattern_pending ? 1u : 0u,
            inferred[1u].target_scalar == SCALAR_U64 &&
                all(inferred[1u].reference == uint2(2u, 0u)) ? 1u : 0u);
    }
    else if (id == 47u || id == 48u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, id == 47u ? 3u : 2u),
            id == 47u ? 1u : 2u, uint2(1u, 0u), 64u, true, inferred, mask);
        results[id] = uint4(ok == (id == 47u) ? 1u : 0u, mask == 0u ? 1u : 0u,
            inferred[0u].reference.x == 0u ? 1u : 0u, 1u);
    }
    else if (id == 50u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, 9u), INVALID,
            uint2(1u, 0u), 64u, true, inferred, mask);
        results[id] = uint4(ok ? 1u : 0u, mask == 2u ? 1u : 0u,
            inferred[1u].target_scalar == SCALAR_U64 ? 1u : 0u,
            all(inferred[1u].reference == uint2(1u, 0u)) ? 1u : 0u);
    }
    else if (id == 51u)
    {
        bool ok = array_count_reference_constraint<LeftGraph>(uint2(3u, 3u), INVALID,
            uint2(2u, 1u), 64u, false, inferred, mask);
        uint3 pattern = uint3(3u, 3u, INVALID); ConstantReferenceDescriptor descriptor;
        bool pending = scoped_constant_reference<LeftGraph>(pattern, 64u, descriptor) &&
            descriptor.pending_fit == 1u;
        results[id] = uint4(ok ? 1u : 0u, mask == 0u ? 1u : 0u, pending ? 1u : 0u, 1u);
    }
}
