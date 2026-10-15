// Route bound-member calls of the selected replay body (07a) to the member of
// the implementation that the now-concrete receiver selects.
//
// Body specialization has substituted the call's accepted receiver. The
// required member names its trait; a candidate is an implementation method of
// that trait with the same name whose closed receiver pattern equals the
// receiver. Generic implementations would need their own call environment,
// which symbolic call inference cannot have produced for this call; they are
// rejected explicitly rather than routed (and so is a receiver with no match).
// Outside replay every accepted receiver of these calls is still a parameter,
// so nothing is routed and the enclosing body stays a template.

import gpu_index;
import hir_records;
import status;
import type_checker.methods.lookup;
import type_checker.instance_arguments;
import type_checker.scoped_type_equality;
import type_checker.methods.candidate;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<HirRange> compact_generic_param_ranges;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_receiver_ref_tag;
StructuredBuffer<uint> method_call_receiver_ref_payload;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;
StructuredBuffer<uint> method_decl_method_row;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> fn_hir_by_decl_token;
StructuredBuffer<uint> fn_start_token_by_decl_token;
StructuredBuffer<uint> call_dependency_library_id;
StructuredBuffer<uint> predicate_method_contract_owner_hir;
StructuredBuffer<uint> predicate_bound_reference;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<MethodCandidate> method_candidate;
RWStructuredBuffer<uint> call_fn_index;
RWStructuredBuffer<uint> backend_call_fn_index;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TRAIT_REFERENCE_DEPENDENCY = 0x80000000u;
static const uint HIR_ITEM = 2u;
static const uint HIR_ITEM_KIND_TRAIT = 10u;
static const uint ERR_CALL_MISMATCH = 10u;
static const uint CALL_MISMATCH_UNROUTED_BOUND_MEMBER = 0xffffff0eu;

#include "receiver_graph.slang"

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node < active_hir_count(); }

// Required members publish signature metadata without a lookup row (02_collect).
uint required_member_trait(uint target)
{
    if (target >= gParams.n_tokens || method_decl_method_row[target] != INVALID ||
        method_decl_receiver_mode[target] == 0u) return INVALID;
    uint member = fn_hir_by_decl_token[target];
    if (!valid_hir(member)) return INVALID;
    uint trait = predicate_method_contract_owner_hir[member];
    return valid_hir(trait) && compact_hir_core[trait].kind == HIR_ITEM &&
        compact_hir_payload[trait].a == HIR_ITEM_KIND_TRAIT ? trait : INVALID;
}

bool implements_trait(uint impl, uint trait)
{
    if (!valid_hir(impl)) return false;
    uint reference = predicate_bound_reference[impl];
    return (reference & TRAIT_REFERENCE_DEPENDENCY) == 0u &&
        reference < min(decl_count_out[0u], gParams.n_tokens) &&
        decl_hir_node[reference] == trait;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id_2d(dtid, 65535u, 256u);
    if (token >= min(token_count[0u], gParams.n_tokens) ||
        method_call_receiver_hir[token] == INVALID ||
        call_dependency_library_id[token] != INVALID) return;
    uint trait = required_member_trait(call_fn_index[token]);
    if (trait == INVALID) return;
    uint tag = method_call_receiver_ref_tag[token];
    uint payload = method_call_receiver_ref_payload[token];
    if (tag == TYPE_REF_GENERIC_PARAM || tag == 0u || payload == INVALID) return;
    uint count = min(compact_method_count[0u], gParams.n_hir_nodes);
    MethodReceiverHead head;
    uint selected = INVALID;
    uint matches = 0u;
    if (count != 0u && method_receiver_head<MethodReceiverGraph>(tag, payload,
        method_receiver_type_capacity(), gParams.n_tokens, head))
    {
        uint name_id = method_call_name_id[token];
        uint link = method_lookup_head[method_lookup_bucket(head, name_id, count)];
        for (uint visited = 0u; link != 0u && visited < count; visited++)
        {
            uint row = link - 1u;
            if (row >= count) { matches = 2u; break; }
            link = method_lookup_next[row];
            HirMethodCore core = compact_method_cores[row];
            uint candidate = core.name_token;
            if (candidate >= gParams.n_tokens || method_decl_name_id[candidate] != name_id ||
                !implements_trait(core.impl_node, trait) ||
                compact_generic_param_ranges[core.impl_node].count != 0u ||
                !scoped_type_refs_equal<MethodReceiverGraph>(
                    method_decl_receiver_ref_tag[candidate],
                    method_decl_receiver_ref_payload[candidate], INVALID,
                    tag, payload, INVALID, method_receiver_type_capacity(), gParams.n_tokens))
                continue;
            if (selected != candidate) matches++;
            selected = candidate;
        }
    }
    if (matches != 1u)
    {
        record_min_token_error(status, token, ERR_CALL_MISMATCH, CALL_MISMATCH_UNROUTED_BOUND_MEMBER);
        return;
    }
    // The accepted selection and its callee are one fact for call artifacts.
    MethodCandidate candidate = method_candidate[token];
    if (candidate.state != METHOD_CANDIDATE_UNIQUE ||
        candidate.callable_kind != METHOD_CALLABLE_LOCAL ||
        candidate.local_index != call_fn_index[token]) return;
    candidate.local_index = selected;
    candidate.matched_ref_tag = tag;
    candidate.matched_ref_payload = payload;
    method_candidate[token] = candidate;
    call_fn_index[token] = selected;
    uint start = fn_start_token_by_decl_token[selected];
    backend_call_fn_index[token] = start < gParams.n_tokens ? start : selected;
}
