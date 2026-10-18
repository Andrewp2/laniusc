import primitive_types;
// Preserve the accepted concrete type of a local generic result. The legacy
// expression type code cannot represent a slice or an arbitrary nominal type.
// Use the existing per-call claim index instead of the replayed callee's body
// environment: different callers can instantiate the same declaration.
import hir_records;
import gpu_index;
import checked_semantic_artifact;
import type_checker.calls.claim_lookup;
import type_checker.calls.explicit_call_environment;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};
ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> call_return_generic_slot;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_lookup_head;
StructuredBuffer<uint> call_generic_claim_lookup_next;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<CheckedCallArtifact> semantic_calls_by_hir;

static const uint INVALID = 0xffffffffu;

bool accepted_argument(uint token, uint slot, out uint tag, out uint payload)
{
    tag = 0u; payload = INVALID;
    if (checked_explicit_environment_argument(0x80000000u | token, slot, tag, payload)) return true;
    uint claims = call_generic_claim_count_out[0u];
    if (claims == 0u || slot == INVALID) return false;
    uint link = call_generic_claim_lookup_head[call_claim_lookup_bucket(token, slot, claims)];
    uint accepted = INVALID;
    for (uint step = 0u; step < claims && link != 0u; step++)
    {
        uint candidate = link - 1u;
        if (candidate >= claims) break;
        if (call_generic_claim_callee[candidate] == token &&
            call_generic_claim_slot[candidate] == slot &&
            call_generic_claim_ref_tag[candidate] != 0u)
            accepted = min(accepted, candidate);
        link = call_generic_claim_lookup_next[candidate];
    }
    if (accepted == INVALID) return false;
    tag = call_generic_claim_ref_tag[accepted];
    payload = call_generic_claim_ref_payload[accepted];
    if (tag == 2u && payload < gParams.n_tokens)
    {
        uint concrete_tag = type_expr_ref_tag[payload];
        if (concrete_tag == 1u || concrete_tag == 3u)
        {
            tag = concrete_tag; payload = type_expr_ref_payload[payload];
        }
    }
    return tag != 0u && payload != INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_dispatch_thread_id_2d(dtid, 16776960u);
    uint count = min(gParams.n_hir_nodes, compact_hir_count[0u]);
    if (row >= count || compact_hir_core[row].kind != 19u) return;
    CheckedCallArtifact call = semantic_calls_by_hir[row];
    // Imported calls were checked against the caller's symbolic T before
    // replay. Resolve that accepted reference after the caller environment is
    // applied, just as local call claims are resolved below. This is needed
    // for generic bodies that forward a value into another source unit.
    if (call.return_ref_tag == 2u && call.return_ref_payload < gParams.n_tokens)
    {
        uint parameter = call.return_ref_payload;
        uint concrete_tag = type_expr_ref_tag[parameter];
        if (concrete_tag == 1u || concrete_tag == 3u)
        {
            call.return_ref_tag = concrete_tag;
            call.return_ref_payload = type_expr_ref_payload[parameter];
            if (concrete_tag == 1u && scalar_is_known(call.return_ref_payload))
                call.return_type = call.return_ref_payload;
            semantic_calls_by_hir[row] = call;
        }
    }
    if (call.callable_kind != 1u || call.target_token >= gParams.n_tokens) return;
    uint callee = compact_hir_payload[row].a;
    if (callee >= count) return;
    uint token = compact_hir_core[callee].kind == 21u
        ? compact_hir_payload[callee].c : compact_hir_payload[callee].d;
    if (token >= gParams.n_tokens) token = compact_hir_core[callee].token_start;
    if (token >= gParams.n_tokens) return;
    uint tag; uint payload;
    uint slot = call_return_generic_slot[call.target_token];
    if (slot != INVALID && accepted_argument(token, slot, tag, payload))
    {
        call.return_ref_tag = tag; call.return_ref_payload = payload;
        // The accepted call environment also owns the legacy type code.
        // Keeping another replay's scalar code here would misclassify a
        // record or array result as bool, float, or string in sibling calls.
        call.return_type = tag == 1u ? payload : 0u;
    }
    else if (call.return_ref_tag == 3u && call.return_ref_payload < gParams.n_tokens)
    {
        uint original = call.return_ref_payload;
        uint arguments = type_instance_arg_count[original];
        if (type_instance_kind[original] != 1u || arguments == 0u || arguments > 4u) return;
        uint tags[4]; uint payloads[4]; bool substituted = false;
        uint columns = type_instance_arg_row_start[original];
        uint total = type_instance_arg_row_count_out[0u];
        uint fixed = type_instance_arg_start[original];
        for (uint i = 0u; i < arguments; i++)
        {
            if (columns < total && i < total - columns)
            {
                tag = type_instance_arg_row_ref_tag[columns + i];
                payload = type_instance_arg_row_ref_payload[columns + i];
            }
            else if (fixed != INVALID)
            {
                tag = type_instance_arg_ref_tag[fixed + i];
                payload = type_instance_arg_ref_payload[fixed + i];
            }
            else return;
            if (tag == 2u && payload < gParams.n_tokens)
            {
                uint parameter_slot = type_generic_param_slot_by_token[payload];
                if (accepted_argument(token, parameter_slot, tag, payload)) substituted = true;
            }
            tags[i] = tag; payloads[i] = payload;
        }
        if (substituted)
        {
            // Each call owns its callee token. Keep the declaration instance
            // immutable so other calls can retain a different environment.
            // An imported nominal type has no local declaration token; its
            // (library, unit, local) triple is its identity, so the copy
            // keeps it (the late canonical stage interns this row by it).
            type_instance_kind[token] = 1u;
            type_instance_decl_token[token] = type_instance_decl_token[original];
            external_type_library_id[token] = external_type_library_id[original];
            external_type_unit_id[token] = external_type_unit_id[original];
            external_type_local_index[token] = external_type_local_index[original];
            type_instance_arg_count[token] = arguments;
            type_instance_len_kind[token] = type_instance_len_kind[original];
            type_instance_len_payload[token] = type_instance_len_payload[original];
            type_instance_arg_start[token] = token * 4u;
            type_instance_arg_row_start[token] = INVALID;
            for (uint i = 0u; i < arguments; i++)
            {
                type_instance_arg_ref_tag[token * 4u + i] = tags[i];
                type_instance_arg_ref_payload[token * 4u + i] = payloads[i];
            }
            call.return_ref_payload = token;
        }
    }
    semantic_calls_by_hir[row] = call;
}
