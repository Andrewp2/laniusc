// Project a selected application from an already accepted, frozen proof arena.
// No matching, normalization, proof construction, or proof-store writes occur.
import type_checker.program_evidence.abi;
import type_checker.program_evidence.catalog_io;
import type_checker.program_evidence.proof_store_abi;
import type_checker.program_evidence.constant_atoms;
import type_checker.program_evidence.implementation_application.work_abi;
import type_checker.program_evidence.admitted_rows;
import type_checker.program_evidence.proof_term_graph;

// Exact declaration ordinal across the callable's composed owner chain. The
// accepted call's complete obligation count must still match that inventory.
EvidenceStatus iap_predicate_at(uint owner, uint ordinal, uint expected_count, out uint predicate)
{
    predicate = PEV_INVALID; uint total = 0u; uint original = owner;
    [loop]
    for (uint depth = 0u; owner != PEV_INVALID; depth++)
    {
        if (depth == PEV_DEPTH_LIMIT) return pev_limit(202u, original, depth + 1u, PEV_DEPTH_LIMIT);
        uint4 low; uint4 high;
        if (!pev_read_admitted_owner(owner, low, high) || !iap_catalog_span(8u, high.z, high.w))
            return pev_invalid(202u, original, owner);
        if (high.w > PEV_INVALID - 1u - total) return pev_invalid(202u, original, owner);
        if (predicate == PEV_INVALID && ordinal >= total && ordinal - total < high.w)
        {
            predicate = high.z + ordinal - total; uint actual_owner;
            if (!pev_word(8u, predicate, 1u, actual_owner) || actual_owner != owner)
                return pev_invalid(202u, original, predicate);
        }
        total += high.w; owner = low.w;
    }
    return total == expected_count && predicate != PEV_INVALID ? pev_ok() :
        pev_invalid(202u, original, ordinal);
}

// The initial accepted evidence lives in output5 immediately. Its CPU table-17
// copy is appended only after upload, so this query must not require that copy
// to have been uploaded by another (otherwise unnecessary) submission.
EvidenceStatus iap_output_evidence(uint obligation_row, out uint4 retained, out uint4 source,
    out uint4 proof, out uint4 proof_extra, out uint call_state)
{
    retained = uint4(PEV_INVALID); source = retained; proof = retained; proof_extra = retained;
    call_state = 0u;
    uint4 call; uint4 extra; uint4 obligation;
    uint4 outcome; uint context_state;
    if (!pev_output_read4(5u, obligation_row, 0u, retained) ||
        !pev_output_read4(5u, obligation_row, 4u, source) ||
        retained.x != 1u || source.z != obligation_row || source.w != 0u ||
        !pev_read8(15u, source.y, call, extra) || call.y == PEV_INVALID || extra.w != 0u ||
        source.z < extra.y || source.z - extra.y >= extra.z ||
        !pev_row_span(16u, extra.y, extra.z) ||
        !pev_read4(16u, source.z, 0u, obligation) ||
        any(obligation != uint4(source.y, retained.y, extra.x, 0u)) || retained.z != extra.x ||
        !pev_output_read4(3u, source.z, 0u, outcome) ||
        any(outcome != uint4(1u, 0u, source.z, retained.w)) ||
        !pev_output_read(4u, source.y, 0u, call_state) || (call_state != 1u && call_state != 2u) ||
        !pev_output_read(2u, call.x, 0u, context_state) || context_state != PEV_VALID ||
        !iap_accepted_span(PPS_PROOFS, retained.w, 1u) ||
        !iap_accepted_span(PPS_GOALS, source.x, 1u) ||
        !pps_read8(PPS_PROOFS, retained.w, proof, proof_extra) ||
        proof.y != source.x || proof.z != call.x || proof_extra.w != 1u)
        return pev_invalid(203u, obligation_row, source.z);
    uint4 goal; uint4 goal_extra; uint4 callable;
    if (!pps_read8(PPS_GOALS, source.x, goal, goal_extra) || goal_extra.z != 1u ||
        !iap_catalog_span(4u, call.w, 1u) || !pev_read4(4u, call.w, 0u, callable))
        return pev_invalid(203u, obligation_row, source.x);
    uint predicate;
    EvidenceStatus status = iap_predicate_at(callable.y, source.z - extra.y, extra.z, predicate);
    if (status.state != PEV_VALID) return status;
    return predicate == retained.y ? pev_ok() : pev_invalid(203u, obligation_row, predicate);
}

// Supporting replay assumptions name older table-17 inputs that were already
// admitted with their context. Check their exact copy against the accepted
// output, rather than promoting a child proof into a new source obligation.
EvidenceStatus iap_evidence(uint evidence, out uint4 retained, out uint4 source,
    out uint4 proof, out uint4 proof_extra, out uint call_state)
{
    uint4 supplied; uint4 supplied_source;
    if (!pev_read8(17u, evidence, supplied, supplied_source))
    {
        retained = uint4(PEV_INVALID); source = retained; proof = retained; proof_extra = retained;
        call_state = 0u;
        return pev_invalid(203u, evidence, PEV_INVALID);
    }
    EvidenceStatus status = iap_output_evidence(supplied_source.z,
        retained, source, proof, proof_extra, call_state);
    if (status.state != PEV_VALID) return status;
    return all(retained == supplied) && all(source == supplied_source) ? pev_ok() :
        pev_invalid(203u, evidence, supplied_source.z);
}

EvidenceStatus iap_subject_slot(uint predicate, uint expected_slot)
{
    uint4 requirement; uint2 subject; uint4 atom;
    if (expected_slot >= 32u || !iap_catalog_span(8u, predicate, 1u) ||
        !pev_read4(8u, predicate, 0u, requirement) ||
        !pev_read2(7u, requirement.w, 0u, subject) || subject.x != 2u ||
        !pev_read_admitted_parameter(subject.y, atom) || atom.z != 0u)
        return pev_invalid(204u, predicate, expected_slot);
    uint owner = requirement.y;
    [loop]
    for (uint depth = 0u; owner != PEV_INVALID; depth++)
    {
        if (depth == PEV_DEPTH_LIMIT) return pev_limit(204u, predicate, depth + 1u, PEV_DEPTH_LIMIT);
        uint4 low; uint4 high;
        if (!pev_read_admitted_owner(owner, low, high)) return pev_invalid(204u, predicate, owner);
        if (low.x == atom.y)
        {
            [loop]
            for (uint i = 0u; i < high.y; i++)
            {
                uint4 parameter;
                if (!pev_read4(3u, high.x + i, 0u, parameter) || parameter.x != owner)
                    return pev_invalid(204u, predicate, high.x + i);
                if (parameter.y == subject.y)
                    return parameter.w == 0u && parameter.z == expected_slot ? pev_ok() :
                        pev_invalid(204u, predicate, expected_slot);
            }
            return pev_invalid(204u, predicate, subject.y);
        }
        owner = low.w;
    }
    return pev_invalid(204u, predicate, subject.y);
}

EvidenceStatus iap_resolve(uint request, uint4 requested, uint4 identity, inout uint3 used,
    out uint resolved, out uint4 proof, out uint4 proof_extra, out uint first_hop, out uint hop_count)
{
    resolved = requested.x; proof = uint4(PEV_INVALID); proof_extra = proof;
    first_hop = used.z; hop_count = 0u;
    uint4 retained; uint4 source; uint call_state;
    EvidenceStatus status = iap_output_evidence(requested.w, retained, source, proof, proof_extra, call_state);
    if (status.state != PEV_VALID) return status;
    if (identity.w != 0u || retained.w != requested.x || source.x != requested.y ||
        source.y != requested.z || retained.y != identity.x || proof.z != identity.z || call_state != 1u)
        return pev_invalid(205u, request, requested.w);
    status = iap_subject_slot(identity.x, identity.y);
    if (status.state != PEV_VALID) return status;
    [loop]
    for (;;)
    {
        if (proof.x == 1u) return pev_ok();
        if (proof.x != 2u || proof_extra.x != PEV_INVALID || proof_extra.y != 0u ||
            proof_extra.z != 0u || proof_extra.w != 1u)
            return pev_invalid(206u, resolved, proof.x);
        if (hop_count == PEV_DEPTH_LIMIT)
            return pev_limit(206u, request, hop_count + 1u, PEV_DEPTH_LIMIT);
        uint4 offered; uint2 offered_tail; uint4 context; uint4 context_extra; uint origin_state;
        if (!pev_read4(14u, proof.w, 0u, offered) || !pev_read2(14u, proof.w, 4u, offered_tail) ||
            any(offered_tail != uint2(0u)) || !pev_read8(13u, proof.z, context, context_extra) ||
            context_extra.y != 1u || offered.x != proof.z || offered.z != context.z ||
            proof.w < context.w || proof.w - context.w >= context_extra.x ||
            !pev_output_read(4u, context_extra.z, 0u, origin_state) || origin_state != 1u)
            return pev_invalid(206u, resolved, proof.w);
        uint predicate;
        status = iap_predicate_at(context.y, proof.w - context.w, context_extra.x, predicate);
        if (status.state != PEV_VALID) return status;
        if (predicate != offered.y) return pev_invalid(206u, resolved, offered.y);
        uint4 prior; uint4 prior_extra;
        status = iap_evidence(offered.w, retained, source, prior, prior_extra, call_state);
        if (status.state != PEV_VALID) return status;
        // Frozen assumption admission proved semantic goal equality. Their
        // normalized goal IDs may differ, and are not compared positionally.
        if (retained.w >= resolved || prior.z >= proof.z)
            return pev_invalid(206u, resolved, retained.w);
        uint at;
        status = iap_reserve(2u, 1u, used, at);
        if (status.state != PEV_VALID) return status;
        iap_write4(IAP_HOP_ROW + at, uint4(resolved, proof.w, offered.w, retained.w));
        hop_count++; resolved = retained.w; proof = prior; proof_extra = prior_extra;
    }
}

EvidenceStatus iap_bindings(uint implementation, uint substitution, uint owner,
    uint4 owner_low, uint4 owner_span, uint4 selected, uint first)
{
    // Accepted binding spans are strictly sorted by exact parameter atom, not
    // source order. Validate once, then look up each declaration independently.
    uint previous = PEV_INVALID;
    [loop]
    for (uint i = 0u; i < selected.z; i++)
    {
        uint4 binding; uint4 allocation;
        if (!pps_read8(PPS_BINDINGS, selected.y + i, binding, allocation) || binding.x != substitution ||
            (i != 0u && binding.y <= previous) || any(allocation.zw != uint2(0u)) ||
            !iap_accepted_span(PPS_TERM_NODES, allocation.x, allocation.y))
            return pev_invalid(207u, substitution, selected.y + i);
        previous = binding.y;
    }
    uint2 counts = uint2(0u);
    [loop]
    for (uint ordinal = 0u; ordinal < owner_span.y; ordinal++)
    {
        uint parameter_row = owner_span.x + ordinal; uint4 parameter; uint4 atom;
        if (!pev_read4(3u, parameter_row, 0u, parameter) || parameter.x != owner || parameter.w > 1u ||
            !pev_read_admitted_parameter(parameter.y, atom) || atom.y != owner_low.x ||
            atom.z != parameter.w || atom.w != ordinal)
            return pev_invalid(207u, implementation, parameter_row);
        if (parameter.z != counts[parameter.w])
            return pev_invalid(207u, implementation, parameter_row);
        if (counts[parameter.w] == 32u) return pev_limit(207u, parameter_row, 33u, 32u);
        counts[parameter.w]++;
        uint lo = 0u; uint hi = selected.z; uint4 binding = uint4(PEV_INVALID);
        [loop]
        for (uint step = 0u; step < 7u && lo < hi; step++)
        {
            uint middle = lo + (hi - lo) / 2u; uint4 candidate;
            if (!pps_read4(PPS_BINDINGS, selected.y + middle, 0u, candidate))
                return pev_invalid(207u, substitution, selected.y + middle);
            if (candidate.y == parameter.y) { binding = candidate; break; }
            if (candidate.y < parameter.y) lo = middle + 1u; else hi = middle;
        }
        if (binding.x != substitution || binding.y != parameter.y)
            return pev_invalid(207u, substitution, parameter.y);
        uint scalar = 0u; uint3 value = uint3(0u);
        if (parameter.w == 0u)
        {
            if ((binding.z != 1u && binding.z != 3u) || !pps_type_reference(binding.zw) ||
                (binding.z == 3u && !iap_accepted_span(PPS_TERM_NODES, binding.w, 1u)))
                return pev_invalid(208u, parameter_row, binding.w);
        }
        else
        {
            scalar = pev_constant_parameter_scalar(parameter.y);
            if (scalar == 0u || binding.z != 0x80000001u ||
                !iap_accepted_span(PPS_TERM_NODES, binding.w, 1u) ||
                !pps_constant_value(binding.w, value) || value.x != scalar)
                return pev_invalid(208u, parameter_row, binding.w);
        }
        uint at = IAP_BINDING_ROW + (first + ordinal) * 3u;
        iap_write4(at, uint4(parameter_row, parameter.w, parameter.z, ordinal));
        iap_write4(at + 1u, uint4(binding.z, binding.w, scalar, 0u));
        iap_write4(at + 2u, uint4(value, 0u));
    }
    return pev_ok();
}

EvidenceStatus iap_project_one(uint request, inout uint3 used)
{
    uint4 requested = iap_read4(IAP_REQUEST_ROW + request * 2u);
    uint4 identity = iap_read4(IAP_REQUEST_ROW + request * 2u + 1u);
    uint resolved; uint4 proof; uint4 proof_extra; uint first_hop; uint hop_count;
    EvidenceStatus status = iap_resolve(request, requested, identity, used,
        resolved, proof, proof_extra, first_hop, hop_count);
    if (status.state != PEV_VALID) return status;
    uint4 implementation; uint4 implementation_extra; uint4 prerequisites;
    uint4 owner; uint4 owner_span; uint4 selected;
    if (!iap_catalog_span(9u, proof.w, 1u) ||
        !pev_read8(9u, proof.w, implementation, implementation_extra) ||
        !pev_read4(9u, proof.w, 8u, prerequisites) || any(prerequisites.zw != uint2(0u)) ||
        !pev_read_admitted_owner(implementation.y, owner, owner_span) ||
        any(owner_span.zw != prerequisites.xy) || !iap_catalog_span(8u, prerequisites.x, prerequisites.y) ||
        !iap_accepted_span(PPS_SUBSTITUTIONS, proof_extra.x, 1u) ||
        !pps_read4(PPS_SUBSTITUTIONS, proof_extra.x, 0u, selected) ||
        selected.x != proof.w || selected.w != proof.y || selected.z != owner_span.y ||
        selected.z > 64u || (selected.z == 0u && selected.y != 0u) ||
        !iap_accepted_span(PPS_BINDINGS, selected.y, selected.z) ||
        proof_extra.z != prerequisites.y || (proof_extra.z == 0u && proof_extra.y != 0u) ||
        !iap_accepted_span(PPS_PROOF_EDGES, proof_extra.y, proof_extra.z))
        return pev_invalid(209u, resolved, proof.w);
    uint ancestor = owner.w;
    [loop]
    for (uint depth = 1u; ancestor != PEV_INVALID; depth++)
    {
        if (depth == PEV_DEPTH_LIMIT) return pev_limit(209u, implementation.y, depth + 1u, PEV_DEPTH_LIMIT);
        uint4 ancestor_owner; uint4 span;
        if (!pev_read_admitted_owner(ancestor, ancestor_owner, span))
            return pev_invalid(209u, implementation.y, ancestor);
        if (span.y != 0u || span.w != 0u)
        {
            EvidenceStatus unsupported = pev_invalid(210u, implementation.y, ancestor);
            unsupported.state = PEV_UNSUPPORTED; return unsupported;
        }
        ancestor = ancestor_owner.w;
    }
    uint first_binding; uint first_prerequisite;
    status = iap_reserve(0u, selected.z, used, first_binding);
    if (status.state != PEV_VALID) return status;
    status = iap_reserve(1u, prerequisites.y, used, first_prerequisite);
    if (status.state != PEV_VALID) return status;
    status = iap_bindings(proof.w, proof_extra.x, implementation.y, owner, owner_span, selected, first_binding);
    if (status.state != PEV_VALID) return status;
    [loop]
    for (uint ordinal = 0u; ordinal < prerequisites.y; ordinal++)
    {
        uint4 edge; uint4 child; uint4 child_extra; uint actual_owner;
        if (!pps_read4(PPS_PROOF_EDGES, proof_extra.y + ordinal, 0u, edge) ||
            edge.x != resolved || edge.y != prerequisites.x + ordinal || edge.z >= resolved || edge.w != 0u ||
            !pev_word(8u, edge.y, 1u, actual_owner) || actual_owner != implementation.y ||
            !iap_accepted_span(PPS_PROOFS, edge.z, 1u) ||
            !pps_read8(PPS_PROOFS, edge.z, child, child_extra) || child_extra.w != 1u || child.z != proof.z ||
            !iap_accepted_span(PPS_GOALS, child.y, 1u))
            return pev_invalid(211u, resolved, proof_extra.y + ordinal);
        iap_write4(IAP_PREREQUISITE_ROW + first_prerequisite + ordinal,
            uint4(edge.y, edge.z, child.y, 0u));
    }
    uint at = IAP_APP_ROW + request * 3u;
    iap_write4(at, uint4(request, resolved, proof.w, proof_extra.x));
    iap_write4(at + 1u, uint4(first_binding, selected.z, first_prerequisite, prerequisites.y));
    iap_write4(at + 2u, uint4(first_hop, hop_count, implementation.y, requested.y));
    return pev_ok();
}

public EvidenceStatus iap_project()
{
    uint3 used = uint3(0u); uint count = iap_read4(1u).w;
    [loop]
    for (uint request = 0u; request < count; request++)
    {
        EvidenceStatus status = iap_project_one(request, used);
        if (status.state != PEV_VALID) return status;
    }
    iap_write4(5u, uint4(used, count));
    return pev_ok();
}
