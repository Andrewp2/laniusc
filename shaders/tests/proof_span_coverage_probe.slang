// Source-only probe: execute one 24-thread workgroup during integration.
// result = (observed state, expected state, pass, charged work).
import type_checker.program_evidence.proof_span_coverage;
import type_checker.program_evidence.abi;

RWStructuredBuffer<uint4> coverage_results;
struct CoverageSpans : IProofSpanSource
{
    static bool span(uint owner, uint scenario, out uint first, out uint count)
    {
        first = 0u; count = 0u;
        switch (scenario)
        {
        case 1u: return true; // canonical zero spans on an empty suffix
        case 2u: first = 3u; return true; // zero spans must start at zero
        case 3u: first = owner == 0u ? 3u : 4u; count = owner == 0u ? 1u : 2u; return true;
        case 4u: first = owner == 0u ? 7u : 3u; count = owner == 0u ? 3u : 4u; return true;
        case 5u: first = 3u; count = 1u; return true; // duplicate equal requests + hidden row
        case 6u: first = owner == 0u ? 3u : 5u; count = 3u; return true; // overlap + hole
        case 7u: first = owner == 0u ? 3u : 6u; count = owner == 0u ? 2u : 1u; return true;
        case 8u: first = 3u; count = 2u; return true; // uncovered suffix
        case 9u: first = 2u; count = 2u; return true;
        case 10u: first = 4u; count = 2u; return true;
        case 11u: first = 0xfffffffdu; count = 4u; return true; // wrapped end
        case 12u: first = owner == 0u ? 0xfffffffau : 0xfffffffcu; count = 2u; return true;
        case 13u: first = owner == 0u ? 0u : 1023u; count = owner == 0u ? 1024u : 1u; return true;
        case 14u: first = owner == 0u ? 1075u : 53u; count = owner == 0u ? 1075u : 1022u; return true;
        case 15u: first = owner == 0u ? 17u : owner == 1u ? 48u : 80u;
            count = owner == 0u ? 31u : owner == 1u ? 32u : 2u; return true;
        case 16u: return false;
        case 17u: first = 3u; count = 1u; return true;
        case 18u: first = 3u; count = 1u; return true;
        case 19u: first = 3u; count = 1u; return true;
        case 20u: first = 0u; count = 2048u; return true;
        case 21u: return true; // canonical zero owners cannot cover nonempty suffix
        case 22u: first = 3u; count = 1u; return true;
        case 23u: first = 3u; count = 1u; return true;
        default: return false;
        }
    }
}

[shader("compute")]
[numthreads(24, 1, 1)]
void main(uint3 tid : SV_DispatchThreadID)
{
    uint id = tid.x; if (id >= 24u) return;
    uint first = 3u; uint end = 6u; uint owners = 2u; uint visits = 0u;
    uint expected = PEV_INVALID_INPUT;
    switch (id)
    {
    case 0u: end = first; owners = 0u; expected = PEV_VALID; break;
    case 1u: end = first; expected = PEV_VALID; break;
    case 2u: end = first; break;
    case 3u: expected = PEV_VALID; break;
    case 4u: end = 10u; expected = PEV_VALID; break;
    case 5u: end = 5u; break;
    case 6u: end = 9u; break;
    case 7u: end = 7u; break;
    case 8u: owners = 1u; break;
    case 9u: end = 5u; owners = 1u; break;
    case 10u: end = 5u; owners = 1u; break;
    case 11u: first = 0xfffffffbu; end = 0xfffffffeu; owners = 1u; break;
    case 12u: first = 0xfffffffau; end = 0xfffffffeu; expected = PEV_VALID; break;
    case 13u: first = 0u; end = 1025u; break;
    case 14u: first = 53u; end = 2150u; expected = PEV_VALID; break;
    case 15u: first = 17u; end = 82u; owners = 3u; expected = PEV_VALID; break;
    case 16u: end = 4u; owners = 1u; break;
    case 17u: end = 4u; owners = 1u; visits = PEV_VISIT_LIMIT; expected = PEV_RESOURCE_LIMIT; break;
    case 18u: end = 4u; owners = 1u; visits = PEV_VISIT_LIMIT - 3u; expected = PEV_VALID; break;
    case 19u: end = 4u; owners = 1u; visits = PEV_VISIT_LIMIT - 2u; expected = PEV_RESOURCE_LIMIT; break;
    case 20u: first = 0u; end = 2048u; owners = 1u; expected = PEV_VALID; break;
    case 21u: end = 4u; owners = 1u; break;
    case 22u: end = 4u; owners = 1u; visits = PEV_VISIT_LIMIT - 5u; expected = PEV_RESOURCE_LIMIT; break;
    case 23u: first = 5u; end = 4u; owners = 1u; break;
    }
    EvidenceStatus status = pps_check_span_cover<CoverageSpans>(id, first, end, 0u, owners, visits);
    // Separate destination audits must share the budget; resetting it here
    // would incorrectly admit row22 after six operations with only five left.
    if (id == 22u && status.state == PEV_VALID)
        status = pps_check_span_cover<CoverageSpans>(id, first, end, 0u, owners, visits);
    coverage_results[id] = uint4(status.state, expected, status.state == expected ? 1u : 0u, visits);
}
