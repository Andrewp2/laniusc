import type_checker.constant_parameter_slots;
// Collect local candidates into the common cross-inventory transaction.
//
// Source refs are frozen before reset. This pass never writes callable or
// return facts; imported contributors can replace any deeper local candidate.
// Full patterns decide applicability after the shape/name bucket probe: the
// receiver's canonical ID is matched against each candidate's receiver
// pattern ID (ct_match, no interning).

import gpu_index;
import hir_records;
import type_checker.methods.lookup;
import type_checker.methods.candidate;
import type_checker.instance_arguments;
import type_checker.constant_atoms;
import type_checker.canonical.canonical_api;
import type_checker.canonical.canonical_candidates;
import type_checker.substitution.ct_spare;
import type_checker.substitution.ct_checked;
import type_checker.match.ct_match;

StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> external_type_library_id;
StructuredBuffer<uint> external_type_unit_id;
StructuredBuffer<uint> external_type_local_index;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_method_count;
StructuredBuffer<HirMethodCore> compact_method_cores;
StructuredBuffer<uint> method_call_source_ref_tag;
StructuredBuffer<uint> method_call_receiver_hir;
StructuredBuffer<uint> method_call_selection_owned;
RWStructuredBuffer<MethodCandidate> method_candidate;
StructuredBuffer<uint> method_call_source_ref_payload;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_site_module_id;
StructuredBuffer<uint> method_key_status;
StructuredBuffer<uint> method_lookup_head;
StructuredBuffer<uint> method_lookup_next;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> method_decl_module_id;
StructuredBuffer<uint> method_decl_name_id;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> call_param_count;
StructuredBuffer<uint> call_param_row_start;
StructuredBuffer<uint> call_param_row_count_out;
StructuredBuffer<uint> call_param_row_ref_tag;
StructuredBuffer<uint> call_param_row_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;



static const uint INVALID = 0xffffffffu;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint METHOD_KEY_STATUS_PRIVATE_OK = 0u;
static const uint METHOD_KEY_STATUS_PUBLIC_OK = 5u;
static const uint TY_UNKNOWN = 0u;

#include "receiver_graph.slang"

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return linear_thread_id_2d(dtid, MAX_GROUPS_X, WG_SIZE);
}

[ForceInline]
uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint instance_capacity()
{
    uint capacity; uint stride;
    type_instance_arg_count.GetDimensions(capacity, stride);
    return capacity;
}

uint active_method_count()
{
    return min(compact_method_count[0u], gParams.n_hir_nodes);
}

bool visible_method(uint token, uint fn_token)
{
    if (fn_token >= active_token_count()) return false;
    uint status = method_key_status[fn_token];
    return status == METHOD_KEY_STATUS_PUBLIC_OK ||
        (status == METHOD_KEY_STATUS_PRIVATE_OK &&
         method_call_site_module_id[token] != INVALID &&
         method_decl_module_id[fn_token] == method_call_site_module_id[token]);
}

// Binding slots of the impl's own parameters.
struct ReceiverSlots : ICtSlots
{
    uint type_slot(uint token)
    { return token < active_token_count() ? type_generic_param_slot_by_token[token] : CT_SLOT_NONE; }
    uint const_slot(uint token)
    { return token < active_token_count() ? type_const_param_slot_by_token[token] : CT_SLOT_NONE; }
    uint const_scalar(uint token) { return checked_constant_parameter_scalar(token); }
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

bool local_receiver_matches(uint fn_token, uint mode, bool dotted, uint actual)
{
    // Root 0 matches the declared receiver pattern (the impl root of a dotted
    // mode-3 method). A dotted mode-3 method's self parameter is root 1,
    // matched against the same receiver; repeated parameters agree by ID
    // across both roots.
    uint pattern0 = ct_ref(method_decl_receiver_ref_tag[fn_token], method_decl_receiver_ref_payload[fn_token]);
    uint pattern1 = CT_NONE;
    uint actual1 = CT_NONE;
    if (dotted && mode == 3u)
    {
        uint row = call_param_row_start[fn_token];
        if (row >= call_param_row_count_out[0u]) return false;
        pattern1 = ct_ref(call_param_row_ref_tag[row], call_param_row_ref_payload[row]);
        actual1 = actual;
        if (!ct_is_resolved(pattern1)) return false;
    }
    if (!ct_is_resolved(pattern0) || !ct_is_resolved(actual)) return false;
    ReceiverSlots slots;
    CtSpare spare = ct_spare_none();
    uint count_mask;
    return ct_match<ReceiverSlots>(slots, pattern0, actual, pattern1, actual1,
        CT_NONE, 0u, false, spare, count_mask) == CT_MATCH_OK;
}

void collect_bucket(uint token, uint bucket, uint tag, uint payload, uint actual,
    uint deref_count, bool dotted, inout MethodCandidate summary)
{
    uint count = active_method_count();
    // Empty inventories dispatch no lookup initializer, so no bucket storage
    // belongs to this table. In particular, never read the capacity-one sentinel.
    if (count == 0u) return;
    uint link = method_lookup_head[bucket];
    for (uint visited = 0u; link != 0u && visited < count; visited++)
    {
        uint row = link - 1u;
        if (row >= count) { summary.state = METHOD_CANDIDATE_INVALID; return; }
        link = method_lookup_next[row];
        uint fn_token = compact_method_cores[row].name_token;
        if (!visible_method(token, fn_token) ||
            method_decl_name_id[fn_token] != method_call_name_id[token]) continue;
        uint mode = method_decl_receiver_mode[fn_token];
        if (dotted ? (mode == 0u || (mode == 3u && call_param_count[fn_token] == 0u)) :
            (mode == 1u || mode == 2u)) continue;
        if (!local_receiver_matches(fn_token, mode, dotted, actual)) continue;
        MethodCandidate candidate = method_candidate_empty();
        candidate.state = METHOD_CANDIDATE_UNIQUE;
        candidate.deref_count = deref_count;
        candidate.module_preference = method_decl_module_id[fn_token] ==
            method_call_site_module_id[token] ? 0u : 1u;
        candidate.callable_kind = METHOD_CALLABLE_LOCAL;
        candidate.local_index = fn_token;
        candidate.matched_ref_tag = tag;
        candidate.matched_ref_payload = payload;
        candidate.receiver_mode = dotted ? (mode == 2u ? 2u : 1u) : 0u;
        method_candidate_offer(summary, candidate);
    }
    if (link != 0u) summary.state = METHOD_CANDIDATE_INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id(dtid);
    if (token >= active_token_count() || method_call_selection_owned[token] == 0u ||
        method_call_name_id[token] == INVALID) return;
    uint tag = method_call_source_ref_tag[token];
    uint payload = method_call_source_ref_payload[token];
    if (tag == 0u || payload == INVALID) return;
    MethodCandidate summary = method_candidate[token];
    bool dotted = method_call_receiver_hir[token] != INVALID;
    uint wildcard = method_lookup_bucket(method_receiver_wildcard_head(),
        method_call_name_id[token], active_method_count());
    uint spare = CT_NONE;
    for (uint depth = 0u; depth < 64u; depth++)
    {
        // The receiver's canonical ID (interned here when inference produced
        // it); the whole receiver must have one.
        uint actual = ct_intern_checked<ReceiverRows>(tag, payload, spare);
        if (depth == 0u && !ct_is_resolved(actual)) { summary.state = METHOD_CANDIDATE_INVALID; break; }
        MethodReceiverHead head;
        if (!method_receiver_head<MethodReceiverGraph>(tag, payload,
            method_receiver_type_capacity(), active_token_count(), head))
        { summary.state = METHOD_CANDIDATE_INVALID; break; }
        uint bucket = method_lookup_bucket(head, method_call_name_id[token], active_method_count());
        // Head bucket, then the wildcard bucket when distinct; one inlined copy.
        [loop]
        for (uint source = 0u; source < 2u; source++)
        {
            if (source == 1u && wildcard == bucket) break;
            collect_bucket(token, source == 0u ? bucket : wildcard, tag, payload, actual, depth, dotted, summary);
        }
        if (summary.state == METHOD_CANDIDATE_INVALID || !dotted || tag != 3u ||
            type_instance_kind[payload] != 4u) break;
        if (depth == 63u) { summary.state = METHOD_CANDIDATE_INVALID; break; }
        uint source = payload;
        tag = type_instance_elem_ref_tag[source];
        payload = type_instance_elem_ref_payload[source];
    }
    method_candidate[token] = summary;
}
