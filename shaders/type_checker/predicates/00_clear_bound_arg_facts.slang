// Clear predicate-bound argument facts before the structural scatter pass.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;

RWStructuredBuffer<uint> predicate_bound_arg_count;
RWStructuredBuffer<uint> predicate_bound_first_arg_token;
RWStructuredBuffer<uint> predicate_bound_second_arg_token;
RWStructuredBuffer<uint> predicate_status;
RWStructuredBuffer<uint> predicate_trait_impl_trait_type_node;
RWStructuredBuffer<uint> predicate_method_contract_owner_node;
RWStructuredBuffer<uint> predicate_method_contract_name_token;
RWStructuredBuffer<uint> predicate_method_contract_name_id;
RWStructuredBuffer<uint> predicate_method_contract_param_count;
RWStructuredBuffer<uint> predicate_method_contract_first_param_node;
RWStructuredBuffer<uint> predicate_method_contract_return_type_node;
RWStructuredBuffer<uint> predicate_method_contract_visibility;
RWStructuredBuffer<uint> predicate_method_contract_status;
RWStructuredBuffer<uint> predicate_method_contract_param_next_node;
RWStructuredBuffer<uint> predicate_method_contract_param_type_node;
RWStructuredBuffer<uint> predicate_method_contract_owner_range_first;
RWStructuredBuffer<uint> predicate_method_contract_owner_range_count;
RWStructuredBuffer<uint> predicate_method_validation_owner_node;
RWStructuredBuffer<uint> predicate_method_validation_peer_node;
RWStructuredBuffer<uint> predicate_method_validation_status;
RWStructuredBuffer<uint> predicate_method_validation_detail_token;
RWStructuredBuffer<uint> predicate_method_validation_first_error_row;

static const uint INVALID = 0xffffffffu;
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

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_hir_node_count())
        return;

    predicate_bound_arg_count[node] = 0u;
    predicate_bound_first_arg_token[node] = INVALID;
    predicate_bound_second_arg_token[node] = INVALID;
    predicate_status[node] = INVALID;
    predicate_trait_impl_trait_type_node[node] = INVALID;
    predicate_method_contract_owner_node[node] = INVALID;
    predicate_method_contract_name_token[node] = INVALID;
    predicate_method_contract_name_id[node] = INVALID;
    predicate_method_contract_param_count[node] = 0u;
    predicate_method_contract_first_param_node[node] = INVALID;
    predicate_method_contract_return_type_node[node] = INVALID;
    predicate_method_contract_visibility[node] = 0u;
    predicate_method_contract_status[node] = INVALID;
    predicate_method_contract_param_next_node[node] = INVALID;
    predicate_method_contract_param_type_node[node] = INVALID;
    predicate_method_contract_owner_range_first[node] = INVALID;
    predicate_method_contract_owner_range_count[node] = 0u;
    predicate_method_validation_owner_node[node] = INVALID;
    predicate_method_validation_peer_node[node] = INVALID;
    predicate_method_validation_status[node] = INVALID;
    predicate_method_validation_detail_token[node] = INVALID;
    predicate_method_validation_first_error_row[node] = INVALID;
}
