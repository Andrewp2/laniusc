// Apply reduced method-validation owner errors back to predicate status rows.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> predicate_method_validation_first_error_row;
StructuredBuffer<uint> predicate_method_validation_status;
StructuredBuffer<uint> predicate_method_validation_detail_token;

RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint PREDICATE_STATUS_OK = 0u;
static const uint PREDICATE_STATUS_MISSING_METHOD = 6u;
static const uint PREDICATE_STATUS_METHOD_ARITY_MISMATCH = 7u;
static const uint PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH = 8u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC = 16u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE = 17u;
static const uint PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD = 20u;
static const uint PREDICATE_STATUS_EXTRA_IMPL_METHOD = 23u;
static const uint PREDICATE_STATUS_DUPLICATE_IMPL_METHOD = 24u;
static const uint PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH = 26u;
static const uint PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW = 27u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool status_can_use_method_validation_rows(uint status)
{
    return status == INVALID ||
           status == PREDICATE_STATUS_OK ||
           status == PREDICATE_STATUS_MISSING_METHOD ||
           status == PREDICATE_STATUS_METHOD_ARITY_MISMATCH ||
           status == PREDICATE_STATUS_METHOD_SIGNATURE_MISMATCH ||
           status == PREDICATE_STATUS_UNSUPPORTED_METHOD_GENERIC ||
           status == PREDICATE_STATUS_UNSUPPORTED_METHOD_WHERE ||
           status == PREDICATE_STATUS_DUPLICATE_TRAIT_METHOD ||
           status == PREDICATE_STATUS_EXTRA_IMPL_METHOD ||
           status == PREDICATE_STATUS_DUPLICATE_IMPL_METHOD ||
           status == PREDICATE_STATUS_IMPL_METHOD_VISIBILITY_MISMATCH ||
           status == PREDICATE_STATUS_UNSUPPORTED_METHOD_CONTRACT_WINDOW;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint owner = linear_thread_id(dtid);
    if (!valid_node(owner) || node_kind[owner] != PROD_IMPL_TRAIT)
        return;

    uint row = predicate_method_validation_first_error_row[owner];
    if (!valid_node(row))
        return;

    uint status = predicate_method_validation_status[row];
    if (status == INVALID || status == PREDICATE_STATUS_OK)
        return;

    if (!status_can_use_method_validation_rows(predicate_status[owner]))
        return;

    predicate_bound_first_arg_token[owner] = predicate_method_validation_detail_token[row];
    predicate_bound_second_arg_token[owner] = INVALID;
    predicate_status[owner] = status;
}
