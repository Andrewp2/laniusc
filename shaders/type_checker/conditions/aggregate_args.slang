// Validate named aggregate type-argument equality requests emitted by
// conditions_hir.
//
// conditions_hir writes one request per HIR node and a counted scan turns each
// request's argument count into a compact comparison span. This pass runs one
// lane per argument pair and maps the row back to its request with a logarithmic
// prefix search.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> aggregate_compare_scan_input;
StructuredBuffer<uint> aggregate_compare_prefix;
StructuredBuffer<uint> aggregate_compare_count_out;
StructuredBuffer<uint> aggregate_compare_expected_instance;
StructuredBuffer<uint> aggregate_compare_actual_instance;
StructuredBuffer<uint> aggregate_compare_error_token;
StructuredBuffer<uint> aggregate_compare_error_detail;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_compare_count()
{
    return aggregate_compare_count_out[0u];
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint saturating_add(uint lhs, uint rhs)
{
    return lhs > 0xffffffffu - rhs ? 0xffffffffu : lhs + rhs;
}

uint request_node_for_compare(uint row)
{
    uint count = active_hir_node_count();
    uint lo = 0u;
    uint hi = count;
    [loop]
    for (uint step = 0u; step < 32u && lo < hi; step += 1u)
    {
        uint mid = lo + (hi - lo) / 2u;
        uint prefix = aggregate_compare_prefix[mid];
        uint width = aggregate_compare_scan_input[mid];
        uint end = saturating_add(prefix, width);
        if (end <= row)
            lo = mid + 1u;
        else
            hi = mid;
    }

    if (lo >= count)
        return INVALID;

    uint prefix = aggregate_compare_prefix[lo];
    uint width = aggregate_compare_scan_input[lo];
    return row >= prefix && row < saturating_add(prefix, width) ? lo : INVALID;
}

uint instance_arg_ref_index(uint instance_i, uint slot)
{
    uint start = type_instance_arg_start[instance_i];
    return start == INVALID ? INVALID : start + slot;
}

uint instance_arg_row_ref_index(uint instance_i, uint ordinal)
{
    uint start = type_instance_arg_row_start[instance_i];
    uint ref_i = start == INVALID ? INVALID : start + ordinal;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance_i, uint ordinal, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance_i))
        return false;
    if (ordinal >= type_instance_arg_count[instance_i])
        return false;

    uint row_ref_i = instance_arg_row_ref_index(instance_i, ordinal);
    if (row_ref_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_ref_i];
        payload = type_instance_arg_row_ref_payload[row_ref_i];
        if (tag != TYPE_REF_INVALID)
            return true;
    }

    if (ordinal >= TYPE_INSTANCE_ARG_REF_STRIDE)
        return false;

    uint fixed_ref_i = instance_arg_ref_index(instance_i, ordinal);
    if (fixed_ref_i == INVALID)
        return false;

    tag = type_instance_arg_ref_tag[fixed_ref_i];
    payload = type_instance_arg_ref_payload[fixed_ref_i];
    return tag != TYPE_REF_INVALID;
}

bool same_generic_type_param_ref(uint lhs_payload, uint rhs_payload)
{
    uint lhs_slot = valid_token(lhs_payload) ? type_generic_param_slot_by_token[lhs_payload] : INVALID;
    uint rhs_slot = valid_token(rhs_payload) ? type_generic_param_slot_by_token[rhs_payload] : INVALID;
    return lhs_slot != INVALID && lhs_slot == rhs_slot;
}

bool same_leaf_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    if (lhs_tag != rhs_tag)
        return false;
    if (lhs_tag == TYPE_REF_GENERIC_PARAM)
        return same_generic_type_param_ref(lhs_payload, rhs_payload);
    return lhs_payload == rhs_payload;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

void validate_compare_row(uint row)
{
    if (row >= active_compare_count())
        return;

    uint request_node = request_node_for_compare(row);
    if (request_node == INVALID)
        return;

    uint prefix = aggregate_compare_prefix[request_node];
    uint ordinal = row - prefix;
    uint expected_instance = aggregate_compare_expected_instance[request_node];
    uint actual_instance = aggregate_compare_actual_instance[request_node];

    uint expected_tag;
    uint expected_payload;
    uint actual_tag;
    uint actual_payload;
    if (!instance_arg_ref(expected_instance, ordinal, expected_tag, expected_payload) ||
        !instance_arg_ref(actual_instance, ordinal, actual_tag, actual_payload) ||
        !same_leaf_type_ref(expected_tag, expected_payload, actual_tag, actual_payload))
    {
        record_error(
            aggregate_compare_error_token[request_node],
            ERR_ASSIGN_MISMATCH,
            aggregate_compare_error_detail[request_node]);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    validate_compare_row(linear_thread_id(dtid));
}
