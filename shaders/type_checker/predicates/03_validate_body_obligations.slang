// Imported calls are checked again against the selected body's own contract
// once its retained type/constant environment has been installed. Interfaces
// never authorize dropping a bound at an independently compiled call site.
#define LANIUS_BODY_OBLIGATION_VALIDATE_PASS 1
#include "02_obligations.slang"
StructuredBuffer<uint4> body_specialization_inputs;
StructuredBuffer<uint> interface_public_decl_index_by_hir;
#include "../type/instances/body_specialization_owner.slang"

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint pred = linear_thread_id(dtid);
    if (!valid_node(pred) || predicate_status[pred] != PREDICATE_STATUS_OK) return;
    uint owner = predicate_owner_node[pred];
    if (!valid_node(owner) || owner == pred || !body_specialization_selects_owner(owner)) return;
    uint row = lexical_parameter_row(pred, predicate_subject_token[pred], GENERIC_PARAM_KIND_TYPE);
    uint token = row != INVALID ? generic_param_token[row] : INVALID;
    if (!valid_token(token))
    { record_error(compact_hir_core[pred].token_start, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_SUBJECT); return; }
    uint2 subject = uint2(type_expr_ref_tag[token], type_expr_ref_payload[token]);
    uint count = predicate_bound_arg_count[pred];
    uint hash;
    if (!predicate_key_hash<PredicateTypeGraph>(subject, pred, count, INVALID, hash))
    { record_error(token, ERR_TRAIT_BOUND_UNSATISFIED, PREDICATE_STATUS_INVALID_ARG); return; }
    // The private request proves this selected owner's complete bound set in
    // the program catalog. Keep all owner and materialized-key checks above;
    // only the redundant provider-local implementation search is omitted.
    if (gParams.trait_obligation_mode == 2u &&
        valid_node(gParams.authorized_replay_callable) &&
        compact_hir_core[gParams.authorized_replay_callable].kind == 3u) return;
    uint first_match;
    uint matches = impl_index_match_count(predicate_bound_reference[pred], subject, pred,
        INVALID, count, hash, first_match);
    if (matches != 1u)
        record_error(token, matches == 0u ? ERR_TRAIT_BOUND_UNSATISFIED : ERR_TRAIT_BOUND_AMBIGUOUS,
            matches == 0u ? PREDICATE_STATUS_UNSATISFIED_BOUND : PREDICATE_STATUS_AMBIGUOUS_BOUND);
}
