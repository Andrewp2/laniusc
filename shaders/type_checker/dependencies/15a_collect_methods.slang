import type_checker.constant_constraints;
// Collect public implementation candidates from every retained dependency page.
// The candidate universe is this unit's retained interface inventory, not its
// source import edges. Visibility and global depth ranking finish only after
// all local and imported candidates have been offered.
#include "method_candidates.slang"

bool receiver_type_matches(uint type, uint tag, uint payload,
    out uint2 inferred[32], out uint inferred_mask,
    out InferredConstant constants[32], out uint constant_mask)
{
    return canonical_type_and_constant_constraints<MethodReceiverGraph>(INVALID,
        type, tag, payload, method_receiver_type_capacity(), gParams.visible_capacity,
        true, inferred, inferred_mask, constants, constant_mask, true);
}

bool imported_candidate_matches(uint member, bool dotted, uint tag, uint payload,
    out uint receiver_mode)
{
    receiver_mode = 0u;
    uint base = member * MEMBER_WORDS;
    uint2 inferred[32]; uint inferred_mask;
    InferredConstant constants[32]; uint constant_mask;
    if (!receiver_type_matches(dependency_member_word(base + 10u), tag, payload,
        inferred, inferred_mask, constants, constant_mask)) return false;
    uint mode = (dependency_member_word(base + 8u) >> 28u) & 3u;
    // Qualified static calls have no implicit receiver; dotted calls require
    // one. Ineligible methods must not shadow an applicable deeper candidate.
    if (!dotted) return mode == 0u || mode == 3u;
    if (mode == 0u) return false;
    if (mode == 1u || mode == 2u) { receiver_mode = mode; return true; }
    // A typed first parameter consumes exactly the adjusted receiver value.
    // Only syntactic &self creates a borrow of its place.
    uint first = dependency_method_parameter_type(member, 0u);
    if (first == INVALID) return false;
    uint2 first_types[32]; uint first_mask;
    InferredConstant first_constants[32]; uint first_constant_mask;
    if (!receiver_type_matches(first, tag, payload, first_types, first_mask,
        first_constants, first_constant_mask)) return false;
    for (uint slot = 0u; slot < 32u; slot++)
    {
        uint bit = 1u << slot;
        if ((inferred_mask & first_mask & bit) != 0u &&
            !scoped_type_refs_equal<MethodReceiverGraph>(inferred[slot].x, inferred[slot].y,
                INVALID, first_types[slot].x, first_types[slot].y, INVALID,
                method_receiver_type_capacity(), gParams.visible_capacity)) return false;
        if ((constant_mask & first_constant_mask & bit) != 0u &&
            !inferred_constant_claims_compatible<MethodReceiverGraph>(constants[slot], first_constants[slot], gParams.visible_capacity)) return false;
    }
    receiver_mode = 1u;
    return true;
}

void collect_at_depth(uint token, bool dotted, uint tag, uint payload, uint depth,
    inout MethodCandidate summary)
{
    uint name = name_id_by_token[token];
    if (name == INVALID || name >= gParams.visible_capacity) return;
    for (uint row = 0u; row < dependency_member_count(); row++)
    {
        uint base = row * MEMBER_WORDS;
        if (!dependency_public_implementation_method(row) ||
            dependency_member_word(base + 3u) != name_hash_lo[name] ||
            dependency_member_word(base + 4u) != name_hash_hi[name]) continue;
        uint mode;
        if (!imported_candidate_matches(row, dotted, tag, payload, mode)) continue;
        MethodCandidate candidate = method_candidate_empty();
        candidate.state = METHOD_CANDIDATE_UNIQUE;
        candidate.deref_count = depth;
        candidate.module_preference = 1u;
        candidate.callable_kind = METHOD_CALLABLE_DEPENDENCY;
        uint owner_local;
        if (!dependency_contract_owner_identity(dependency_member_word(base),
            candidate.library_id, candidate.unit_id, owner_local))
        { candidate.state = METHOD_CANDIDATE_INVALID; method_candidate_offer(summary, candidate); return; }
        candidate.local_index = dependency_member_word(base + 9u);
        candidate.matched_ref_tag = tag;
        candidate.matched_ref_payload = payload;
        candidate.receiver_mode = mode;
        method_candidate_offer(summary, candidate);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint call = linear_dispatch_thread_id_2d(dtid, DISPATCH_X_STRIDE);
    uint token; uint owner; uint receiver; bool dotted;
    if (!imported_method_call(call, token, owner, receiver, dotted)) return;
    uint tag = method_call_source_ref_tag[token];
    uint payload = method_call_source_ref_payload[token];
    if (tag == TYPE_REF_INVALID || payload == INVALID) return;
    MethodCandidate summary = method_candidate[token];
    uint visited[64]; uint visited_count = 0u;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        collect_at_depth(token, dotted, tag, payload, depth, summary);
        if (!dotted || tag != TYPE_REF_INSTANCE) break;
        if (payload >= method_receiver_type_capacity())
        { summary.state = METHOD_CANDIDATE_INVALID; break; }
        if (type_instance_kind[payload] != 4u) break;
        bool cycle = false;
        for (uint i = 0u; i < visited_count; i++) cycle = cycle || visited[i] == payload;
        if (cycle || depth == 63u) { summary.state = METHOD_CANDIDATE_INVALID; break; }
        visited[visited_count++] = payload;
        uint instance = payload;
        tag = type_instance_elem_ref_tag[instance];
        payload = type_instance_elem_ref_payload[instance];
        if (tag == TYPE_REF_INVALID || payload == INVALID) { summary.state = METHOD_CANDIDATE_INVALID; break; }
    }
    method_candidate[token] = summary;
}
