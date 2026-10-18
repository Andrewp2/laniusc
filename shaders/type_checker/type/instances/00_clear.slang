// Clear token-indexed type-reference and type-instance records.
//
// HIR type collection scatters from parser nodes into token-indexed records, so
// clearing must be a separate pass to avoid clear/write races.
//
// The whole-table clears (every type row's kind, the lookup index and the
// imported field tables) give later passes their invariant: a row without a
// kind owns nothing (live_type_rows.slang). They stride over one lane per
// workspace token row, the lanes this pass is dispatched with, so a small job
// in a workspace retained from a larger one clears it in parallel.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
    uint dependency_interfaces_present;
    uint retain_callable_owners;
    uint trait_obligation_mode;
    uint authorized_replay_callable;
    uint canonical_library_id;
    uint canonical_unit_id;
    uint workspace_token_rows;
};

ConstantBuffer<Params> gParams;

static const uint PARSER_FEATURE_MEMBERS = 0x00000040u;

RWStructuredBuffer<uint> type_expr_ref_tag;
RWStructuredBuffer<uint> type_expr_ref_payload;
RWStructuredBuffer<uint> type_instance_kind;
RWStructuredBuffer<uint> type_instance_lookup_head;
RWStructuredBuffer<uint> type_instance_lookup_next;
RWStructuredBuffer<uint> type_instance_lookup_present;
RWStructuredBuffer<uint> type_application_count;
RWStructuredBuffer<uint2> imported_type_alias_target;
RWStructuredBuffer<uint> imported_field_ref_start;
RWStructuredBuffer<uint> imported_field_ref_count;
RWStructuredBuffer<uint> imported_field_ref_total;
RWStructuredBuffer<uint> imported_layout_kind;
RWStructuredBuffer<uint> imported_layout_group_start;
RWStructuredBuffer<uint> imported_layout_group_count;
RWStructuredBuffer<uint> imported_layout_group_total;
RWStructuredBuffer<uint2> imported_layout_groups;
RWStructuredBuffer<uint> imported_field_ref_tag;
RWStructuredBuffer<uint> imported_field_ref_payload;
RWStructuredBuffer<uint2> imported_field_name_hash;
RWStructuredBuffer<uint> type_instance_head_token;
RWStructuredBuffer<uint> type_decl_generic_param_count;
RWStructuredBuffer<uint> type_decl_generic_param_count_by_owner_token;
RWStructuredBuffer<uint> type_decl_const_param_count_by_owner_token;
RWStructuredBuffer<uint> type_generic_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_slot_by_token;
RWStructuredBuffer<uint> type_const_param_value_by_token;
RWStructuredBuffer<uint> type_instance_arg_start;
RWStructuredBuffer<uint> type_instance_arg_count;
RWStructuredBuffer<uint> type_instance_arg_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_ref_payload;
RWStructuredBuffer<uint> type_instance_arg_row_start;
RWStructuredBuffer<uint> type_instance_arg_row_count_out;
RWStructuredBuffer<uint> type_instance_arg_row_ref_tag;
RWStructuredBuffer<uint> type_instance_arg_row_ref_payload;
RWStructuredBuffer<uint> type_instance_elem_ref_tag;
RWStructuredBuffer<uint> type_instance_elem_ref_payload;
RWStructuredBuffer<uint> type_instance_len_kind;
RWStructuredBuffer<uint> type_instance_len_payload;
RWStructuredBuffer<uint> type_instance_state;
RWStructuredBuffer<uint> type_instance_decl_token;
RWStructuredBuffer<uint> type_instance_aggregate_word_count;
RWStructuredBuffer<uint> external_type_library_id;
RWStructuredBuffer<uint> external_type_unit_id;
RWStructuredBuffer<uint> external_type_local_index;
RWStructuredBuffer<uint> call_dependency_library_id;
RWStructuredBuffer<uint> call_dependency_unit_id;
RWStructuredBuffer<uint> call_dependency_local_index;
RWStructuredBuffer<uint> call_dependency_host_service;
RWStructuredBuffer<uint> fn_return_ref_tag;
RWStructuredBuffer<uint> fn_return_ref_payload;
RWStructuredBuffer<uint> decl_type_ref_tag;
RWStructuredBuffer<uint> decl_type_ref_payload;
RWStructuredBuffer<uint> decl_imported_type_token;
RWStructuredBuffer<uint> call_inference_result_tag;
RWStructuredBuffer<uint> call_inference_result_payload;
RWStructuredBuffer<uint> argument_expected_ref_tag;
RWStructuredBuffer<uint> argument_expected_ref_payload;
RWStructuredBuffer<uint> literal_context_type_by_hir;
RWStructuredBuffer<uint> semantic_iterable_kind_by_hir;
RWStructuredBuffer<uint> call_explicit_arg_constant_kind;
RWStructuredBuffer<uint> call_explicit_arg_constant_payload;
RWStructuredBuffer<uint> imported_match_payload_ref_tag;
RWStructuredBuffer<uint> imported_match_payload_ref_payload;
RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_INSTANCE_INVALID = 0u;
static const uint TYPE_INSTANCE_EMPTY = 0u;
static const uint TYPE_LEN_NONE = 0u;
static const uint TYPE_INSTANCE_ARG_REF_STRIDE = 4u;

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
        // Iteration kinds are retained through inference and final publication.
        semantic_iterable_kind_by_hir[i] = 0u;
        call_explicit_arg_constant_kind[i] = 0u;
        call_explicit_arg_constant_payload[i] = INVALID;
        uint result_capacity; uint result_stride;
        call_inference_result_tag.GetDimensions(result_capacity, result_stride);
        if (i < result_capacity)
        {
            call_inference_result_tag[i] = 0u;
            call_inference_result_payload[i] = INVALID;
            argument_expected_ref_tag[i] = 0u;
            argument_expected_ref_payload[i] = INVALID;
            literal_context_type_by_hir[i] = 0u;
            imported_match_payload_ref_tag[i] = 0u;
            imported_match_payload_ref_payload[i] = INVALID;
        }
        type_instance_arg_row_ref_tag[i] = TYPE_REF_INVALID;
        type_instance_arg_row_ref_payload[i] = INVALID;
    }

    if (i == 0u)
    {
        type_instance_arg_row_count_out[0u] = 0u;
        type_application_count[0u] = 0u;
        imported_field_ref_total[0u] = 0u;
        imported_layout_group_total[0u] = 0u;
    }

    uint lanes = max(gParams.workspace_token_rows, max(gParams.n_tokens, 1u));
    if (i < lanes)
    {
        uint capacity; uint stride;
        type_instance_lookup_head.GetDimensions(capacity, stride);
        for (uint bucket = i; bucket < capacity; bucket += lanes)
            type_instance_lookup_head[bucket] = 0u;
        type_instance_lookup_next.GetDimensions(capacity, stride);
        for (uint instance = i; instance < capacity; instance += lanes)
        {
            type_instance_lookup_next[instance] = 0u;
            type_instance_lookup_present[instance] = 0u;
        }
        type_instance_kind.GetDimensions(capacity, stride);
        for (uint instance = i; instance < capacity; instance += lanes)
            type_instance_kind[instance] = TYPE_INSTANCE_INVALID;
        imported_field_ref_start.GetDimensions(capacity, stride);
        for (uint instance = i; instance < capacity; instance += lanes)
        {
            imported_field_ref_start[instance] = INVALID;
            imported_field_ref_count[instance] = 0u;
            imported_layout_kind[instance] = 0u;
            imported_layout_group_start[instance] = INVALID;
            imported_layout_group_count[instance] = 0u;
        }
        imported_field_ref_tag.GetDimensions(capacity, stride);
        for (uint row = i; row < capacity; row += lanes)
        {
            imported_field_ref_tag[row] = 0u;
            imported_field_ref_payload[row] = INVALID;
            imported_field_name_hash[row] = uint2(0u, 0u);
        }
        imported_layout_groups.GetDimensions(capacity, stride);
        for (uint row = i; row < capacity; row += lanes)
            imported_layout_groups[row] = uint2(0u, 0u);
    }

    if (i >= gParams.n_tokens)
        return;

    uint alias_capacity; uint alias_stride;
    imported_type_alias_target.GetDimensions(alias_capacity, alias_stride);
    if (i < alias_capacity) imported_type_alias_target[i] = uint2(0u, INVALID);

    type_expr_ref_tag[i] = TYPE_REF_INVALID;
    type_expr_ref_payload[i] = INVALID;
    type_instance_head_token[i] = INVALID;
    type_decl_generic_param_count[i] = 0u;
    type_decl_generic_param_count_by_owner_token[i] = 0u;
    type_decl_const_param_count_by_owner_token[i] = 0u;
    type_generic_param_slot_by_token[i] = INVALID;
    type_const_param_slot_by_token[i] = INVALID;
    type_const_param_value_by_token[i] = INVALID;
    type_instance_arg_start[i] = INVALID;
    type_instance_arg_count[i] = 0u;
    type_instance_arg_row_start[i] = INVALID;
    uint arg_ref_i = i * TYPE_INSTANCE_ARG_REF_STRIDE;
    type_instance_arg_ref_tag[arg_ref_i + 0u] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[arg_ref_i + 0u] = INVALID;
    type_instance_arg_ref_tag[arg_ref_i + 1u] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[arg_ref_i + 1u] = INVALID;
    type_instance_arg_ref_tag[arg_ref_i + 2u] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[arg_ref_i + 2u] = INVALID;
    type_instance_arg_ref_tag[arg_ref_i + 3u] = TYPE_REF_INVALID;
    type_instance_arg_ref_payload[arg_ref_i + 3u] = INVALID;
    type_instance_elem_ref_tag[i] = TYPE_REF_INVALID;
    type_instance_elem_ref_payload[i] = INVALID;
    type_instance_len_kind[i] = TYPE_LEN_NONE;
    type_instance_len_payload[i] = INVALID;
    type_instance_state[i] = TYPE_INSTANCE_EMPTY;
    type_instance_decl_token[i] = INVALID;
    type_instance_aggregate_word_count[i] = 0u;
    external_type_library_id[i] = INVALID;
    external_type_unit_id[i] = INVALID;
    external_type_local_index[i] = INVALID;
    call_dependency_library_id[i] = INVALID;
    call_dependency_unit_id[i] = INVALID;
    call_dependency_local_index[i] = INVALID;
    call_dependency_host_service[i] = INVALID;
    fn_return_ref_tag[i] = TYPE_REF_INVALID;
    fn_return_ref_payload[i] = INVALID;
    decl_type_ref_tag[i] = TYPE_REF_INVALID;
    decl_type_ref_payload[i] = INVALID;
    decl_imported_type_token[i] = INVALID;
    member_result_context_instance[i] = INVALID;
    member_result_ref_tag[i] = TYPE_REF_INVALID;
    if ((gParams.parser_feature_flags & PARSER_FEATURE_MEMBERS) != 0u)
    {
        member_result_ref_payload[i] = INVALID;
        member_result_field_ordinal[i] = INVALID;
        member_result_field_node[i] = INVALID;
    }
}
