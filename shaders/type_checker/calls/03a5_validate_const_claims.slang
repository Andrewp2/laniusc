// Validate direct-call const length claims after final call resolution.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> call_arg_row_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_const_claim_callee;
StructuredBuffer<uint> call_const_claim_slot;
StructuredBuffer<uint> call_const_claim_len;
StructuredBuffer<uint> call_const_claim_order;

RWStructuredBuffer<uint> status;

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

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
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
    uint arg_node = call_arg_row_node[row];
    if (valid_node(arg_node))
    {
        uint token = hir_token_pos[arg_node];
        if (valid_token(token))
            return token;
    }
    return fallback_token;
}

bool concrete_claim(uint row)
{
    return call_const_claim_callee[row] != INVALID &&
           call_const_claim_slot[row] != INVALID &&
           call_const_claim_len[row] != INVALID;
}

void validate_claim_at(uint order_i)
{
    uint active_count = call_arg_row_count_out[0u];
    if (order_i == 0u || order_i >= active_count)
        return;

    uint row = call_const_claim_order[order_i];
    uint prev_row = call_const_claim_order[order_i - 1u];
    if (row >= active_count || prev_row >= active_count)
        return;
    if (!concrete_claim(row) || !concrete_claim(prev_row))
        return;

    uint callee = call_const_claim_callee[row];
    uint slot = call_const_claim_slot[row];
    if (callee != call_const_claim_callee[prev_row] ||
        slot != call_const_claim_slot[prev_row])
    {
        return;
    }

    uint len = call_const_claim_len[row];
    uint prev_len = call_const_claim_len[prev_row];
    if (len != prev_len)
        record_error(
            claim_error_token(row, callee),
            ERR_ASSIGN_MISMATCH,
            TY_ARRAY_BASE * 256u + TY_UNKNOWN);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_claim_at(linear_thread_id(dtid));
}
