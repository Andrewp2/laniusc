// Collect public implementation candidates from every retained dependency page.
// The candidate universe is this unit's retained interface inventory, not its
// source import edges. Visibility and global depth ranking finish only after
// all local and imported candidates have been offered.
#include "method_candidates.slang"
import type_checker.constant_atoms;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.match.ct_match;

// Imported patterns bind only their declaration's slot leaves, which carry
// their own slots; a local parameter token has no slot here.
struct DependencySlots : ICtSlots
{
    uint type_slot(uint token) { return CT_SLOT_NONE; }
    uint const_slot(uint token) { return CT_SLOT_NONE; }
    uint const_scalar(uint token) { return 0u; }
}

// The canonical ID of node `t` of the resident page (an alias is its
// signature), interned with the page.
uint dependency_type_id(uint t)
{
    uint roots; uint stride;
    canonical_type_roots.GetDimensions(roots, stride);
    uint root = t < roots ? canonical_type_roots[t] : INVALID;
    uint base = dependency_constant_type_span_base();
    uint capacity = ct_dependency_capacity();
    if (root >= dependency_type_count() || base > capacity || root >= capacity - base) return CT_UNKNOWN;
    return canonical_dependency_type[base + root];
}

// Row reads for interning a receiver that inference produced.
struct ReceiverRows : ICtRowReader
{
    static uint kind(uint row) { return type_instance_kind[row]; }
    static uint decl_token(uint row) { return type_instance_decl_token[row]; }
    static uint arg_count(uint row) { return type_instance_arg_count[row]; }
    static bool argument(uint row, uint index, out uint tag, out uint payload)
    { return MethodReceiverGraph.argument(row, index, tag, payload); }
    static uint2 elem(uint row)
    { return uint2(type_instance_elem_ref_tag[row], type_instance_elem_ref_payload[row]); }
    static uint2 len(uint row)
    { return uint2(type_instance_len_kind[row], type_instance_len_payload[row]); }
    static uint3 external(uint row)
    { return uint3(external_type_library_id[row], external_type_unit_id[row], external_type_local_index[row]); }
    static uint generic_slot(uint token)
    {
        uint count; uint stride;
        type_generic_param_slot_by_token.GetDimensions(count, stride);
        return token < count ? type_generic_param_slot_by_token[token] : INVALID;
    }
}

// The canonical ID of a receiver operand: a signature node of the resident
// page, or a checked row (interned here when inference produced it).
uint receiver_actual_id(uint tag, uint payload, inout uint spare)
{
    if (tag == TYPE_REF_EXTERNAL_CANONICAL) return dependency_type_id(payload);
    return ct_intern_checked<ReceiverRows>(tag, payload, spare);
}

bool imported_candidate_matches(uint member, bool dotted, uint actual, out uint receiver_mode)
{
    receiver_mode = 0u;
    uint base = member * MEMBER_WORDS;
    uint mode = (dependency_member_word(base + 8u) >> 28u) & 3u;
    // Qualified static calls have no implicit receiver; dotted calls require
    // one. Ineligible methods must not shadow an applicable deeper candidate.
    // A typed first parameter of a dotted call consumes exactly the adjusted
    // receiver value, so it is a second root matched against the same actual;
    // repeated parameters agree by ID across both roots. Only syntactic &self
    // creates a borrow of its place.
    uint pattern0 = dependency_type_id(dependency_member_word(base + 10u));
    uint pattern1 = CT_NONE;
    uint actual1 = CT_NONE;
    if (dotted && mode == 3u)
    {
        uint first = dependency_method_parameter_type(member, 0u);
        if (first == INVALID) return false;
        pattern1 = dependency_type_id(first);
        actual1 = actual;
        if (!ct_is_resolved(pattern1)) return false;
    }
    if (!ct_is_resolved(pattern0) || !ct_is_resolved(actual)) return false;
    DependencySlots slots;
    CtSpare spare = ct_spare_none();
    uint count_mask;
    if (ct_match<DependencySlots>(slots, pattern0, actual, pattern1, actual1,
        CT_NONE, 0u, false, spare, count_mask) != CT_MATCH_OK) return false;
    if (!dotted) return mode == 0u || mode == 3u;
    if (mode == 0u) return false;
    receiver_mode = mode == 3u ? 1u : mode;
    return true;
}

void collect_at_depth(uint token, bool dotted, uint tag, uint payload, uint actual, uint depth,
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
        if (!imported_candidate_matches(row, dotted, actual, mode)) continue;
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
    // A cyclic reference chain has no canonical ID, so it matches nothing;
    // the depth bound ends its walk.
    uint spare = CT_NONE;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        collect_at_depth(token, dotted, tag, payload, receiver_actual_id(tag, payload, spare), depth, summary);
        if (!dotted || tag != TYPE_REF_INSTANCE) break;
        if (payload >= method_receiver_type_capacity())
        { summary.state = METHOD_CANDIDATE_INVALID; break; }
        if (type_instance_kind[payload] != 4u) break;
        if (depth == 63u) { summary.state = METHOD_CANDIDATE_INVALID; break; }
        uint instance = payload;
        tag = type_instance_elem_ref_tag[instance];
        payload = type_instance_elem_ref_payload[instance];
        if (tag == TYPE_REF_INVALID || payload == INVALID) { summary.state = METHOD_CANDIDATE_INVALID; break; }
    }
    method_candidate[token] = summary;
}
