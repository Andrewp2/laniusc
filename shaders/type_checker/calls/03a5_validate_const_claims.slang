import type_checker.concrete_type_equality;
import type_checker.calls.constant_claim_identity;
// Validate complete constant references only after expression inference closes.

import hir_records;
import status;
import type_checker.calls.checked_constant_environment;
import type_checker.calls.contextual_call_environment;
import type_checker.calls.explicit_call_environment;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> call_inference_state;
StructuredBuffer<uint> call_arg_row_node;

RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> call_const_claim_selected;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TY_ARRAY_BASE = 128u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[ForceInline]
uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u
        ? 0u : min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint claim_error_token(uint row, uint fallback_token)
{
    uint arg_row = call_const_claim_arg_row[row];
    uint arg_capacity; uint stride;
    call_arg_row_node.GetDimensions(arg_capacity, stride);
    if (arg_row >= arg_capacity) return fallback_token;
    uint arg_node = call_arg_row_node[arg_row];
    if (valid_node(arg_node))
    {
        uint token = compact_hir_core[arg_node].token_start;
        if (valid_token(token))
            return token;
    }
    return fallback_token;
}

void validate_claim_at(uint row)
{
    uint capacity; uint stride;
    call_const_claim_callee.GetDimensions(capacity, stride);
    uint active_count = min(call_const_claim_count_out[0u], capacity);
    if (row >= active_count) return;
    // Each lane owns exactly its publication flag. No other lane writes the
    // selected row, so clearing cannot race another claim's acceptance.
    call_const_claim_selected[row] = 0u;
    if (call_inference_state[0u] != 0u) return;
    uint callee = call_const_claim_callee[row];
    uint slot = call_const_claim_slot[row];
    if (callee == INVALID || slot >= 32u) return;
    uint2 actual = uint2(call_const_claim_ref_kind[row], call_const_claim_ref_payload[row]);
    if (actual.x == 0u && actual.y == INVALID) return;
    uint mode = call_const_claim_identity_mode[row];
    uint tokens = active_token_count();
    ConstantReferenceDescriptor descriptor; uint scalar;
    if (!valid_token(callee) ||
        !checked_constant_claim_descriptor(actual, mode, tokens, descriptor, scalar))
    {
        record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    uint environment = 0x80000000u | callee;
    uint2 argument; uint argument_mode; uint argument_row;
    // Validate the entire argument relation even when explicit/context evidence
    // has priority. A weaker count context cannot hide two disagreeing exact
    // argument claims that independently compare equal under count identity.
    if (!checked_argument_environment_constant_binding(environment, slot,
        argument.x, argument.y, argument_mode, argument_row))
    {
        record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH,
            TY_ARRAY_BASE * 256u + TY_UNKNOWN);
        return;
    }
    uint2 selected; uint selected_mode; uint selected_row;
    if (!checked_call_environment_constant_binding(environment, slot,
        selected.x, selected.y, selected_mode, selected_row) ||
        !checked_constant_claims_compatible(actual, mode, selected, selected_mode, tokens))
    {
        record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    uint2 context; uint context_mode;
    if (checked_context_environment_constant_binding(environment, slot,
        context.x, context.y, context_mode) &&
        !checked_constant_claims_compatible(selected, selected_mode, context, context_mode, tokens))
    {
        record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    // Retention copies this exact GPU-selected reference. No host comparison
    // may choose another count-equivalent projection or replace its provenance.
    if (row == selected_row) call_const_claim_selected[row] = 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_claim_at(linear_thread_id(dtid));
}
