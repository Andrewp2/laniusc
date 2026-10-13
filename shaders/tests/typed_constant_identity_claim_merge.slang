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
    if (id != 52u && id != 53u && id != 54u && id != 55u && id != 56u && id != 57u && id != 58u && id != 59u && id != 62u) return;
    InferredConstant direct = inferred_constant_reference(uint2(2u, 1u));
    InferredConstant nested = inferred_constant_reference(uint2(3u, 9u));
    InferredConstant retained = direct;
    InferredConstant candidate = nested;
    if (id == 52u || id == 53u)
    {
        direct.identity_mode = 1u; nested.identity_mode = 1u;
        retained = direct; candidate = nested;
        if (id == 53u) { retained = nested; candidate = direct; }
    }
    else if (id == 54u || id == 55u)
    {
        nested.identity_mode = 1u;
        retained = nested; candidate = direct;
        if (id == 55u) { retained = direct; candidate = nested; }
    }
    else if (id == 56u)
    {
        retained = nested; retained.identity_mode = 1u;
        candidate = direct;
    }
    else if (id == 57u)
    {
        direct = inferred_constant_reference(uint2(1u, 0u)); direct.identity_mode = 1u;
        nested = inferred_constant_reference(uint2(1u, 2u)); nested.identity_mode = 1u;
        retained = direct; candidate = nested;
    }
    else if (id == 58u)
    {
        direct = inferred_constant_reference(uint2(1u, 5u)); direct.identity_mode = 1u;
    }
    else if (id == 62u)
    {
        direct = inferred_constant_reference(uint2(2u, 0u));
        direct.target_scalar = SCALAR_U64; direct.identity_mode = 1u;
        nested.identity_mode = 1u;
        retained = direct; candidate = nested;
    }

    bool accepted = false; bool pending = false; bool identity_equal = false;
    bool merge_results[2]; merge_results[0u] = false; merge_results[1u] = false;
    uint merge_count = id == 56u ? 2u : id == 58u ? 0u : 1u;
    // Four ordered phases share each deep helper call site while retaining
    // count comparison before merge in case 57 and typed comparison after
    // descriptor inspection in cases 52/53. Case 56 retains both stateful merges.
    [loop]
    for (uint phase = 0u; phase < 4u; phase++)
    {
        if ((id == 57u && phase == 0u) ||
            ((id == 52u || id == 53u) && phase == 3u))
            identity_equal = inferred_constant_requests_equal<LeftGraph>(
                direct, nested, 64u, id == 57u);
        if (phase >= 1u && phase <= merge_count)
        {
            if (phase == 2u) candidate = nested;
            accepted = merge_inferred_constant_claim<LeftGraph>(retained, candidate, 64u);
            merge_results[phase - 1u] = accepted;
            // These two cases originally passed direct as the inout value.
            // Copy back even after rejection to preserve the complete state.
            if (id == 57u || id == 62u) direct = retained;
        }
        if (phase == 2u && (id == 52u || id == 53u || id == 58u))
        {
            InferredConstant request = nested;
            if (id == 58u) request = direct;
            InferredConstantDescriptor descriptor;
            bool admitted = inferred_constant_request_descriptor<LeftGraph>(request, 64u, descriptor);
            if (id == 58u) accepted = admitted;
            else pending = admitted && descriptor.pending_fit == 1u;
        }
    }
    if (id == 52u || id == 53u)
    {
        results[id] = uint4(accepted ? 1u : 0u, retained.identity_mode == 1u ? 1u : 0u,
            pending ? 1u : 0u, identity_equal ? 0u : 1u);
    }
    else if (id == 54u || id == 55u)
    {
        results[id] = uint4(accepted ? 1u : 0u, retained.identity_mode == 0u ? 1u : 0u,
            all(retained.reference == direct.reference) ? 1u : 0u, retained.target_scalar == 0u ? 1u : 0u);
    }
    else if (id == 56u)
    {
        bool first = merge_results[0u]; bool second = merge_results[1u];
        results[id] = uint4(first ? 1u : 0u, second ? 0u : 1u,
            retained.identity_mode == 0u ? 1u : 0u, all(retained.reference == direct.reference) ? 1u : 0u);
    }
    else if (id == 57u)
    {
        bool same_count = identity_equal;
        results[id] = uint4(same_count ? 1u : 0u, accepted ? 0u : 1u, 1u, 1u);
    }
    else if (id == 58u)
    {
        results[id] = uint4(accepted ? 0u : 1u, 1u, 1u, 1u);
    }
    else if (id == 59u)
    {
        results[id] = uint4(accepted ? 0u : 1u, retained.identity_mode == 0u ? 1u : 0u,
            all(retained.reference == direct.reference) ? 1u : 0u, 1u);
    }
    else if (id == 62u)
    {
        results[id] = uint4(accepted ? 0u : 1u, 1u, 1u, 1u);
    }
}
