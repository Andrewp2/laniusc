import type_checker.constant_constraints;
import type_checker.constant_parameter_slots;
// Collect local candidates into the common cross-inventory transaction.
//
// Source refs are frozen before reset. This pass never writes callable or
// return facts; imported contributors can replace any deeper local candidate.
// Full patterns decide applicability after the shape/name bucket probe.

import gpu_index;
import hir_records;
import type_checker.methods.lookup;
import type_checker.methods.candidate;
import type_checker.instance_arguments;
import type_checker.scoped_type_equality;
import type_checker.scoped_type_constraints;
import type_checker.methods.receiver_pattern;

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

bool local_receiver_matches(uint fn_token, uint mode, bool dotted, uint tag, uint payload)
{
    // Phase 0 matches the declared receiver pattern (the impl root of a dotted
    // mode-3 method). Phase 1 matches that method's self parameter and requires
    // its bindings to agree with phase 0. One inlined matcher serves both.
    uint phases = (!dotted || mode != 3u) ? 1u : 2u;
    uint2 impl_types[32]; uint impl_mask = 0u;
    InferredConstant impl_constants[32]; uint impl_constant_mask = 0u;
    uint2 types[32]; uint mask;
    InferredConstant constants[32]; uint constant_mask;
    [loop]
    for (uint phase = 0u; phase < phases; phase++)
    {
        uint pattern_tag = method_decl_receiver_ref_tag[fn_token];
        uint pattern_payload = method_decl_receiver_ref_payload[fn_token];
        if (phase == 1u)
        {
            uint row = call_param_row_start[fn_token];
            if (row >= call_param_row_count_out[0u]) return false;
            pattern_tag = call_param_row_ref_tag[row];
            pattern_payload = call_param_row_ref_payload[row];
        }
        if (!scoped_type_and_constant_constraints<MethodReceiverGraph>(
            pattern_tag, pattern_payload, INVALID,
            tag, payload, method_receiver_type_capacity(), active_token_count(),
            types, mask, constants, constant_mask, true)) return false;
        if (phase == 0u)
        {
            impl_types = types; impl_mask = mask;
            impl_constants = constants; impl_constant_mask = constant_mask;
        }
    }
    if (phases == 1u) return true;
    for (uint slot = 0u; slot < 32u; slot++)
    {
        if (((impl_mask & mask) & (1u << slot)) != 0u &&
            !scoped_type_refs_equal<MethodReceiverGraph>(impl_types[slot].x, impl_types[slot].y, INVALID,
                types[slot].x, types[slot].y, INVALID,
                method_receiver_type_capacity(), active_token_count())) return false;
        if (((impl_constant_mask & constant_mask) & (1u << slot)) != 0u &&
            !inferred_constant_claims_compatible<MethodReceiverGraph>(impl_constants[slot], constants[slot], active_token_count())) return false;
    }
    return true;
}

void collect_bucket(uint token, uint bucket, uint tag, uint payload,
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
        if (!local_receiver_matches(fn_token, mode, dotted, tag, payload)) continue;
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
    if (!receiver_pattern_valid<MethodReceiverGraph>(tag, payload,
        method_receiver_type_capacity(), active_token_count()))
    {
        summary.state = METHOD_CANDIDATE_INVALID;
        method_candidate[token] = summary;
        return;
    }
    bool dotted = method_call_receiver_hir[token] != INVALID;
    uint wildcard = method_lookup_bucket(method_receiver_wildcard_head(),
        method_call_name_id[token], active_method_count());
    for (uint depth = 0u; depth < 64u; depth++)
    {
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
            collect_bucket(token, source == 0u ? bucket : wildcard, tag, payload, depth, dotted, summary);
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
