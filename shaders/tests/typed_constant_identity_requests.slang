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
    if (id < 31u || id > 40u) return;
    InferredConstant inferred[32]; uint mask = 0u;
    for (uint slot = 0u; slot < 32u; slot++) inferred[slot] = inferred_constant_reference(uint2(0u, INVALID));
    InferredConstant request_left = (InferredConstant)0;
    InferredConstant request_right = (InferredConstant)0;
    if (id == 31u || id == 32u)
    {
        request_left = inferred_constant_reference(uint2(2u, 0u)); request_left.target_scalar = SCALAR_U64;
        request_right = inferred_constant_reference(uint2(3u, 2u));
        if (id == 32u) { request_right.reference = uint2(2u, 0u); request_right.target_scalar = SCALAR_U8; }
    }
    else if (id == 33u)
    {
        request_left = inferred_constant_reference(uint2(3u, 3u));
        request_right = inferred_constant_reference(uint2(2u, 1u));
    }
    else if (id == 35u)
    {
        request_left = inferred_constant_reference(uint2(3u, 5u));
        request_left.target_scalar = SCALAR_U64;
    }
    else if (id == 37u)
    {
        request_left = inferred_constant_reference(uint2(2u, 0u)); request_left.target_scalar = SCALAR_U64;
        request_right = inferred_constant_reference(uint2(2u, 1u)); request_right.target_scalar = SCALAR_U64;
    }
    else if (id == 39u)
    {
        request_left = inferred_constant_reference(uint2(1u, 0u));
        request_left.target_scalar = SCALAR_BOOL;
    }

    // Preserve each case's order through one call site per deep helper.
    // Case 37 compares counts before typed identity; cases 31–33 do the reverse.
    bool comparison[2]; comparison[0u] = false; comparison[1u] = false;
    if ((id >= 31u && id <= 33u) || id == 37u)
    {
        [loop]
        for (uint step = 0u; step < 2u; step++)
            comparison[step] = inferred_constant_requests_equal<LeftGraph>(
                request_left, request_right, 64u, id == 37u ? step == 0u : step != 0u);
    }
    InferredConstantDescriptor descriptor_left = (InferredConstantDescriptor)0;
    InferredConstantDescriptor descriptor_right = (InferredConstantDescriptor)0;
    bool descriptor_ok[2]; descriptor_ok[0u] = false; descriptor_ok[1u] = false;
    uint descriptor_count = id == 31u || id == 32u ? 2u :
        id == 33u || id == 35u || id == 39u ? 1u : 0u;
    [loop]
    for (uint step = 0u; step < descriptor_count; step++)
    {
        // The original two-descriptor expression short-circuits only after
        // admission of the left descriptor, before reading the right graph.
        if (step != 0u && !descriptor_ok[0u]) break;
        InferredConstant request = request_left;
        if (step != 0u) request = request_right;
        InferredConstantDescriptor current;
        descriptor_ok[step] = inferred_constant_request_descriptor<LeftGraph>(request, 64u, current);
        if (step == 0u) descriptor_left = current;
        else descriptor_right = current;
    }

    bool array_accepted[2]; array_accepted[0u] = false; array_accepted[1u] = false;
    if (id == 34u || id == 40u)
    {
        if (id == 40u)
        { inferred[0u] = inferred_constant_reference(uint2(1u, 0u)); mask = 1u; }
        [loop]
        for (uint step = 0u; step < (id == 34u ? 2u : 1u); step++)
        {
            uint2 actual = id == 40u ? uint2(1u, 0u) :
                step == 0u ? uint2(3u, 3u) : uint2(2u, 1u);
            array_accepted[step] = array_count_parameter_constraint<LeftGraph>(
                SCALAR_U64, 0u, INVALID, actual, 64u, true, inferred, mask);
        }
    }
    if (id == 31u || id == 32u)
    {
        InferredConstant a = request_left;
        bool typed = comparison[0u];
        bool count = comparison[1u];
        InferredConstantDescriptor left = descriptor_left;
        InferredConstantDescriptor right = descriptor_right;
        bool retained = descriptor_ok[0u] && descriptor_ok[1u] &&
            left.pending_fit == 1u && right.pending_fit == 1u;
        results[id] = uint4(typed == (id == 31u) ? 1u : 0u, count ? 1u : 0u,
            retained ? 1u : 0u, a.target_scalar == SCALAR_U64 ? 1u : 0u);
    }
    else if (id == 33u)
    {
        bool typed = comparison[0u];
        bool count = comparison[1u];
        InferredConstantDescriptor descriptor = descriptor_left;
        bool retained = descriptor_ok[0u] && descriptor.pending_fit == 1u;
        results[id] = uint4(typed ? 0u : 1u, count ? 1u : 0u, retained ? 1u : 0u, 1u);
    }
    else if (id == 34u)
    {
        bool a = array_accepted[0u];
        bool b = array_accepted[1u];
        // Count evidence admits both arrays; the later exact claim of the same
        // count and result scalar is compatible and wins the slot outright.
        // Each array graph keeps its own fit obligations.
        bool exact = constant_parameter_constraint<LeftGraph>(SCALAR_U64, 0u, INVALID,
            uint2(2u, 1u), 64u, true, inferred, mask);
        results[id] = uint4(a ? 1u : 0u, b ? 1u : 0u, exact ? 1u : 0u,
            all(inferred[0u].reference == uint2(2u, 1u)) &&
                inferred[0u].identity_mode == 0u ? 1u : 0u);
    }
    else if (id == 35u)
    {
        InferredConstant request = request_left;
        bool admitted = descriptor_ok[0u];
        uint3 value; bool closed = inferred_constant_request_value<LeftGraph>(request, 64u, value);
        results[id] = uint4(admitted ? 0u : 1u, closed ? 0u : 1u, 1u, 1u);
    }
    else if (id == 36u)
    {
        uint3 a = uint3(3u, 3u, INVALID); uint3 b = uint3(2u, 1u, INVALID);
        bool equal = scoped_constant_counts_equal<LeftGraph, LeftGraph>(a, b, 64u);
        uint hashes_by_side[2]; hashes_by_side[0u] = 0u; hashes_by_side[1u] = 0u;
        bool hash_ok[2]; hash_ok[0u] = false; hash_ok[1u] = false;
        [loop]
        for (uint side = 0u; side < 2u; side++)
        {
            hash_ok[side] = scoped_constant_count_hash<LeftGraph>(
                side == 0u ? a : b, 64u, hashes_by_side[side]);
        }
        bool hashes = hash_ok[0u] && hash_ok[1u] && hashes_by_side[0u] == hashes_by_side[1u];
        ConstantReferenceDescriptor descriptor;
        bool retained = scoped_constant_reference<LeftGraph>(a, 64u, descriptor) && descriptor.pending_fit == 1u;
        results[id] = uint4(equal ? 1u : 0u, hashes ? 1u : 0u, retained ? 1u : 0u,
            scoped_constant_refs_equal<LeftGraph, LeftGraph>(a, b, 64u) ? 0u : 1u);
    }
    else if (id == 37u)
    {
        results[id] = uint4(comparison[0u] ? 0u : 1u,
            comparison[1u] ? 0u : 1u, 1u, 1u);
    }
    else if (id == 38u)
    {
        uint3 projection_rows = uint3(9u, 0u, 4u);
        uint masks[3]; bool mask_ok[3];
        [loop]
        for (uint step = 0u; step < 3u; step++)
            mask_ok[step] = constant_reference_parameter_mask<LeftGraph>(
                uint2(3u, projection_rows[step]), 64u, masks[step]);
        uint projected_mask = masks[0u]; uint literal_mask = masks[1u]; uint cyclic_mask = masks[2u];
        bool projected = mask_ok[0u]; bool literal = mask_ok[1u]; bool cyclic = mask_ok[2u];
        results[id] = uint4(projected && projected_mask == 2u ? 1u : 0u,
            literal && literal_mask == 0u ? 1u : 0u, cyclic ? 0u : 1u, 1u);
    }
    else if (id == 39u)
    {
        bool valid = descriptor_ok[0u];
        results[id] = uint4(valid ? 0u : 1u, 1u, 1u, 1u);
    }
    else if (id == 40u)
    {
        bool valid = array_accepted[0u];
        results[id] = uint4(valid ? 0u : 1u, mask == 1u ? 1u : 0u,
            inferred[0u].target_scalar == 0u ? 1u : 0u, 1u);
    }
}
