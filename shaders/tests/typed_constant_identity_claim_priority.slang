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
    if (id != 60u && id != 61u && id != 63u) return;
    InferredConstant direct = inferred_constant_reference(uint2(2u, 1u));
    InferredConstant nested = inferred_constant_reference(uint2(3u, 9u));
    InferredConstant retained; bool accepted = false;
    if (id == 60u || id == 61u || id == 63u)
    {
        InferredConstant inferred[32]; uint mask = 0u;
        for (uint slot = 0u; slot < 32u; slot++)
            inferred[slot] = inferred_constant_reference(uint2(0u, INVALID));
        bool count_mode = false; bool closed = false;
        uint3 value = uint3(0u, 0u, 0u);
        bool count_results[3];
        for (uint step = 0u; step < 3u; step++) count_results[step] = false;
        // Case 61 reads the value immediately after its first count constraint,
        // then checks its strict and count-only bounds in that order. Other
        // cases keep their single constraint and original inference state.
        [loop]
        for (uint step = 0u; step < (id == 61u ? 3u : 1u); step++)
        {
            uint scalar = id == 63u ? SCALAR_U8 : SCALAR_U64;
            uint slot = step == 0u ? 0u : 1u;
            uint environment = step == 0u ? INVALID : 3u;
            uint2 actual = uint2(3u, 9u);
            if (id == 61u && step == 0u) actual = uint2(1u, 0u);
            else if (id == 63u) actual = uint2(1u, 9u);
            uint identity_mode = id == 61u && step < 2u ? 0u : 1u;
            count_results[step] = array_count_parameter_constraint<LeftGraph>(scalar, slot,
                environment, actual, 64u, step == 0u, inferred, mask, identity_mode);
            if (step == 0u && id == 60u) count_mode = inferred[0u].identity_mode == 1u;
            if (step == 0u && id == 61u)
                closed = inferred_constant_request_value<LeftGraph>(inferred[0u], 64u, value);
        }
        if (id == 60u)
        {
            bool count = count_results[0u];
            bool exact = constant_parameter_constraint<LeftGraph>(SCALAR_U64, 0u, INVALID,
                uint2(2u, 1u), 64u, true, inferred, mask);
            results[id] = uint4(count && count_mode ? 1u : 0u, exact ? 1u : 0u,
                inferred[0u].identity_mode == 0u ? 1u : 0u,
                all(inferred[0u].reference == uint2(2u, 1u)) ? 1u : 0u);
        }
        else if (id == 61u)
        {
            accepted = count_results[0u];
            bool strict_bound = count_results[1u];
            bool count_bound = count_results[2u];
            results[id] = uint4(accepted ? 1u : 0u, inferred[0u].identity_mode == 0u ? 1u : 0u,
                closed && all(value == uint3(SCALAR_U64, 3u, 0u)) ? 1u : 0u,
                mask == 1u && !strict_bound && count_bound ? 1u : 0u);
        }
        else
        {
            accepted = count_results[0u];
            results[id] = uint4(accepted ? 0u : 1u, mask == 0u ? 1u : 0u, 1u, 1u);
        }
    }
}
