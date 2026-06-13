// Clear token-indexed type-reference and type-instance records.
//
// HIR type collection scatters from parser nodes into token-indexed records, so
// clearing must be a separate pass to avoid clear/write races.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_decl_generic_param_count;
RWStructuredBuffer<uint> type_decl_generic_param_count_by_node;
RWStructuredBuffer<uint> type_decl_const_param_count_by_node;
RWStructuredBuffer<uint> type_decl_first_generic_param_row_by_node;
RWStructuredBuffer<uint> type_decl_first_const_param_row_by_node;
RWStructuredBuffer<uint> type_decl_hir_node_by_token;
RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_INSTANCE_INVALID = 0u;
static const uint TYPE_INSTANCE_EMPTY = 0u;
static const uint TYPE_LEN_NONE = 0u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i < gParams.n_hir_nodes)
    {
        type_decl_generic_param_count_by_node[i] = 0u;
        type_decl_const_param_count_by_node[i] = 0u;
        type_decl_first_generic_param_row_by_node[i] = INVALID;
        type_decl_first_const_param_row_by_node[i] = INVALID;
    }

    if (i >= gParams.n_tokens)
        return;

    type_expr_ref_tag[i] = TYPE_REF_INVALID;
    type_expr_ref_payload[i] = INVALID;
    type_instance_kind[i] = TYPE_INSTANCE_INVALID;
    type_instance_head_token[i] = INVALID;
    type_decl_generic_param_count[i] = 0u;
    type_decl_hir_node_by_token[i] = INVALID;
    type_generic_param_slot_by_token[i] = INVALID;
    type_const_param_slot_by_token[i] = INVALID;
    type_instance_arg_start[i] = INVALID;
    type_instance_arg_count[i] = 0u;
    type_instance_elem_ref_tag[i] = TYPE_REF_INVALID;
    type_instance_elem_ref_payload[i] = INVALID;
    type_instance_len_kind[i] = TYPE_LEN_NONE;
    type_instance_len_payload[i] = INVALID;
    type_instance_state[i] = TYPE_INSTANCE_EMPTY;
    fn_return_ref_tag[i] = TYPE_REF_INVALID;
    fn_return_ref_payload[i] = INVALID;
    decl_type_ref_tag[i] = TYPE_REF_INVALID;
    decl_type_ref_payload[i] = INVALID;
    member_result_context_instance[i] = INVALID;
    member_result_ref_tag[i] = TYPE_REF_INVALID;
    member_result_ref_payload[i] = INVALID;
    member_result_field_ordinal[i] = INVALID;
}
