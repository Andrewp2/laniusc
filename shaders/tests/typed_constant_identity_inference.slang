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
    if (id < 22u || id > 30u) return;
    InferredConstant inferred[32]; uint mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = inferred_constant_reference(uint2(0u, INVALID));
    // Each lane keeps its original sequence and shared inference state. A
    // single call site per helper avoids duplicating the deep constraint graph
    // for every test case when the GPU driver expands shader functions.
    bool accepted[3];
    for (uint step = 0u; step < 3u; step++) accepted[step] = false;
    uint steps = id == 22u || id == 24u || id == 25u ? 2u : id == 26u ? 3u : 1u;
    [loop]
    for (uint step = 0u; step < steps; step++)
    {
        if (id <= 25u)
        {
            uint scalar = id <= 23u ? SCALAR_U32 : SCALAR_U64;
            uint2 actual = uint2(1u, 2u);
            if (id == 22u) actual.y = step;
            else if (id == 24u && step == 0u) actual = uint2(3u, 0u);
            else if (id == 25u && step == 0u) actual.y = 3u;
            accepted[step] = constant_parameter_constraint<LeftGraph>(scalar, 0u, INVALID,
                actual, 64u, true, inferred, mask);
        }
        else if (id == 26u)
        {
            uint2 pattern = uint2(step == 2u ? 3u : 1u, 0u);
            uint2 actual = uint2(1u, step == 0u ? 1u : 2u);
            accepted[step] = constant_reference_constraint<LeftGraph>(pattern, INVALID,
                INVALID, actual, 64u, false, inferred, mask);
        }
        else
        {
            uint scalar = id == 28u ? SCALAR_U8 : id == 29u ? SCALAR_U32 : SCALAR_U64;
            uint2 actual = uint2(id == 30u ? 2u : 1u,
                id == 28u ? 9u : id == 29u ? 4u : 0u);
            accepted[step] = array_count_parameter_constraint<LeftGraph>(scalar, 0u, INVALID,
                actual, 64u, true, inferred, mask);
        }
    }
    if (id == 22u)
    {
        bool a = accepted[0u];
        bool b = accepted[1u];
        results[id] = uint4(a ? 1u : 0u, b ? 1u : 0u, mask, inferred[0u].reference.y == 0u ? 1u : 0u);
    }
    else if (id == 23u)
    {
        bool a = accepted[0u];
        results[id] = uint4(a ? 1u : 0u, mask, inferred[0u].reference.x == 0u ? 1u : 0u,
            inferred[0u].reference.y == INVALID ? 1u : 0u);
    }
    else if (id == 24u)
    {
        bool a = accepted[0u];
        bool b = accepted[1u];
        results[id] = uint4(a ? 1u : 0u, b ? 1u : 0u, mask,
            all(inferred[0u].reference == uint2(3u, 0u)) ? 1u : 0u);
    }
    else if (id == 25u)
    {
        bool a = accepted[0u];
        bool b = accepted[1u];
        results[id] = uint4(a ? 1u : 0u, b ? 1u : 0u, mask,
            all(inferred[0u].reference == uint2(1u, 3u)) ? 1u : 0u);
    }
    else if (id == 26u)
    {
        bool a = accepted[0u];
        bool b = accepted[1u];
        bool c = accepted[2u];
        results[id] = uint4(a ? 1u : 0u, b ? 0u : 1u, c ? 1u : 0u, mask == 0u ? 1u : 0u);
    }
    else if (id == 27u)
    {
        bool ok = accepted[0u];
        uint3 value;
        bool closed = inferred_constant_request_value<LeftGraph>(inferred[0u], 64u, value);
        results[id] = uint4(ok ? 1u : 0u, mask, inferred[0u].target_scalar == SCALAR_U64 ? 1u : 0u,
            closed && all(value == uint3(SCALAR_U64, 3u, 0u)) ? 1u : 0u);
    }
    else if (id == 28u || id == 29u)
    {
        bool ok = accepted[0u];
        results[id] = uint4(ok ? 0u : 1u, mask == 0u ? 1u : 0u,
            inferred[0u].target_scalar == 0u ? 1u : 0u,
            inferred[0u].reference.x == 0u ? 1u : 0u);
    }
    else if (id == 30u)
    {
        bool ok = accepted[0u];
        InferredConstantDescriptor descriptor;
        bool admitted = inferred_constant_request_descriptor<LeftGraph>(inferred[0u], 64u, descriptor);
        uint3 value;
        bool closed = inferred_constant_request_value<LeftGraph>(inferred[0u], 64u, value);
        results[id] = uint4(ok ? 1u : 0u, admitted && descriptor.pending_fit == 1u ? 1u : 0u,
            closed ? 0u : 1u, all(inferred[0u].reference == uint2(2u, 0u)) &&
                inferred[0u].target_scalar == SCALAR_U64 ? 1u : 0u);
    }
}
