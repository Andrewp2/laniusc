// Validate direct-call generic claims after final call resolution.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> call_generic_claim_count_out;
StructuredBuffer<uint> call_arg_row_node;
StructuredBuffer<uint> call_generic_claim_callee;
StructuredBuffer<uint> call_generic_claim_slot;
StructuredBuffer<uint> call_generic_claim_type;
StructuredBuffer<uint> call_generic_claim_ref_tag;
StructuredBuffer<uint> call_generic_claim_ref_payload;
StructuredBuffer<uint> call_generic_claim_arg_row;
StructuredBuffer<uint> call_generic_claim_order;
StructuredBuffer<uint> type_instance_external_canonical;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> aggregate_compare_scan_input;
RWStructuredBuffer<uint> aggregate_compare_expected_instance;
RWStructuredBuffer<uint> aggregate_compare_actual_instance;
RWStructuredBuffer<uint> aggregate_compare_error_token;
RWStructuredBuffer<uint> aggregate_compare_error_detail;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint TY_UNKNOWN = 0u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint GENERIC_CLAIM_CAPACITY_MULTIPLIER = 32u;

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
    return min(gParams.n_hir_nodes, compact_hir_count[0u]);
}

uint generic_claim_capacity()
{
    uint base = max(active_token_count(), active_hir_node_count());
    uint max_base = 0xffffffffu / GENERIC_CLAIM_CAPACITY_MULTIPLIER;
    return base > max_base ? 0xffffffffu : base * GENERIC_CLAIM_CAPACITY_MULTIPLIER;
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
    uint arg_row = call_generic_claim_arg_row[row];
    uint arg_node = arg_row < active_hir_node_count() ? call_arg_row_node[arg_row] : INVALID;
    if (valid_node(arg_node))
    {
        uint token = compact_hir_core[arg_node].token_start;
        if (valid_token(token))
            return token;
    }
    return fallback_token;
}

bool concrete_claim(uint row)
{
    return call_generic_claim_callee[row] != INVALID &&
           call_generic_claim_slot[row] != INVALID &&
           (call_generic_claim_type[row] != TY_UNKNOWN ||
            call_generic_claim_ref_tag[row] != TYPE_REF_INVALID);
}

void validate_claim_at(uint order_i)
{
    uint active_count = min(call_generic_claim_count_out[0u], generic_claim_capacity());
    if (order_i == 0u || order_i >= active_count)
        return;

    uint row = call_generic_claim_order[order_i];
    uint prev_row = call_generic_claim_order[order_i - 1u];
    if (row >= active_count || prev_row >= active_count)
        return;
    if (!concrete_claim(row) || !concrete_claim(prev_row))
        return;

    uint callee = call_generic_claim_callee[row];
    uint slot = call_generic_claim_slot[row];
    if (callee != call_generic_claim_callee[prev_row] ||
        slot != call_generic_claim_slot[prev_row])
    {
        return;
    }

    uint ty = call_generic_claim_type[row];
    uint prev_ty = call_generic_claim_type[prev_row];
    uint tag = call_generic_claim_ref_tag[row];
    uint prev_tag = call_generic_claim_ref_tag[prev_row];
    if (tag != TYPE_REF_INVALID && prev_tag != TYPE_REF_INVALID)
    {
        if (tag == TYPE_REF_SCALAR && prev_tag == TYPE_REF_SCALAR)
        {
            uint payload = call_generic_claim_ref_payload[row];
            uint prev_payload = call_generic_claim_ref_payload[prev_row];
            if (payload != prev_payload)
                record_error(
                    claim_error_token(row, callee),
                    ERR_ASSIGN_MISMATCH,
                    prev_payload * 256u + payload);
            return;
        }
        if (tag == TYPE_REF_INSTANCE && prev_tag == TYPE_REF_INSTANCE)
        {
            uint instance = call_generic_claim_ref_payload[row];
            uint prev_instance = call_generic_claim_ref_payload[prev_row];
            bool valid_instances = valid_token(instance) && valid_token(prev_instance);
            uint kind = valid_instances ? type_instance_kind[instance] : 0u;
            uint prev_kind = valid_instances ? type_instance_kind[prev_instance] : 0u;
            uint nominal = valid_instances ? type_instance_external_canonical[instance] : INVALID;
            uint prev_nominal = valid_instances
                ? type_instance_external_canonical[prev_instance]
                : INVALID;
            uint child_count = valid_instances ? type_instance_arg_count[instance] : 0u;
            bool matches = valid_instances && kind == prev_kind && child_count ==
                type_instance_arg_count[prev_instance];
            if (matches && kind == TYPE_INSTANCE_ARRAY)
                matches = type_instance_len_kind[instance] == type_instance_len_kind[prev_instance] &&
                    type_instance_len_payload[instance] == type_instance_len_payload[prev_instance];
            if (matches && kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
                matches = nominal != INVALID && nominal == prev_nominal;
            if (!matches)
            {
                record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, 0u);
                return;
            }
            uint request = call_generic_claim_arg_row[row];
            if (child_count != 0u && request < active_hir_node_count())
            {
                aggregate_compare_scan_input[request] = child_count;
                aggregate_compare_expected_instance[request] = prev_instance;
                aggregate_compare_actual_instance[request] = instance;
                aggregate_compare_error_token[request] = claim_error_token(row, callee);
                aggregate_compare_error_detail[request] = 0u;
            }
            return;
        }
        if (tag != prev_tag ||
            call_generic_claim_ref_payload[row] != call_generic_claim_ref_payload[prev_row])
            record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, 0u);
        return;
    }
    if (ty != prev_ty)
        record_error(claim_error_token(row, callee), ERR_ASSIGN_MISMATCH, prev_ty * 256u + ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_claim_at(linear_thread_id(dtid));
}
