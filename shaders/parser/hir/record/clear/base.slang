// Clear HIR metadata buffers whose producers run over dense semantic rows.
//
// Dense publish passes should only write real HIR rows. This pass gives every
// active tree row the same invalid/none baseline that the old full-row passes
// produced, without inspecting source bytes, token spelling, or helper names.

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
    uint retain_debug_rows;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gClear;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> token_count;

RWStructuredBuffer<uint> hir_item_name_token;
RWStructuredBuffer<uint> hir_item_namespace;
RWStructuredBuffer<uint> hir_item_visibility;
RWStructuredBuffer<uint> hir_item_path_start;
RWStructuredBuffer<uint> hir_item_path_end;
RWStructuredBuffer<uint> hir_item_path_node;
RWStructuredBuffer<uint> hir_item_import_target_kind;
RWStructuredBuffer<uint> hir_param_record;
RWStructuredBuffer<uint> hir_param_type_node;
RWStructuredBuffer<uint> hir_method_owner_node;
RWStructuredBuffer<uint> hir_method_impl_node;
RWStructuredBuffer<uint> hir_method_name_token;
RWStructuredBuffer<uint> hir_method_first_param_token;
RWStructuredBuffer<uint> hir_method_receiver_mode;
RWStructuredBuffer<uint> hir_method_visibility;
RWStructuredBuffer<uint> hir_method_signature_flags;
RWStructuredBuffer<uint> hir_method_impl_receiver_type_node;
RWStructuredBuffer<uint> hir_expr_result_root_scratch_node;
RWStructuredBuffer<uint> hir_stmt_record;
RWStructuredBuffer<uint> hir_stmt_scope_end;
RWStructuredBuffer<uint> hir_nearest_stmt_node;
RWStructuredBuffer<uint> hir_nearest_block_node;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_node;
RWStructuredBuffer<uint> hir_nearest_loop_node;
RWStructuredBuffer<uint> hir_nearest_fn_node;
RWStructuredBuffer<uint> hir_nearest_array_element_node;
RWStructuredBuffer<uint> hir_call_context_stmt_node;
RWStructuredBuffer<uint> hir_array_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_struct_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_type_alias_target_node;
RWStructuredBuffer<uint> hir_fn_return_type_node;
RWStructuredBuffer<uint> hir_type_len_value;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_ITEM_NAMESPACE_NONE = 0u;
static const uint HIR_ITEM_VIS_PRIVATE = 0u;
static const uint HIR_ITEM_IMPORT_TARGET_NONE = 0u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint RECORD_STRIDE = 4u;
static const uint PARSER_FEATURE_PREDICATES = 0x00000020u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gClear.uses_status_count != 0u ? min(gClear.n, tree_count_status[5u]) : gClear.n;
}

uint slot(uint node, uint field)
{
    return node * RECORD_STRIDE + field;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (node >= active_node_count())
        return;

    // Parameter temporaries are token-anchored rather than raw-tree-indexed.
    // The raw-tree dispatch is always at least as wide as the token stream.
    if (node < token_count[0u])
    {
        hir_item_name_token[node] = INVALID;
        hir_item_namespace[node] = HIR_ITEM_NAMESPACE_NONE;
        hir_item_visibility[node] = HIR_ITEM_VIS_PRIVATE;
        hir_item_path_start[node] = INVALID;
        hir_item_path_end[node] = INVALID;
        hir_item_path_node[node] = INVALID;
        hir_item_import_target_kind[node] = HIR_ITEM_IMPORT_TARGET_NONE;
        hir_param_type_node[node] = INVALID;
        hir_param_record[slot(node, 0u)] = INVALID;
        hir_param_record[slot(node, 1u)] = INVALID;
        hir_param_record[slot(node, 2u)] = INVALID;
        hir_param_record[slot(node, 3u)] = INVALID;
    }

    if (gClear.retain_debug_rows != 0u)
    {
        hir_type_alias_target_node[node] = INVALID;
        hir_fn_return_type_node[node] = INVALID;
    }
    else if (node < token_count[0u])
    {
        // Production stores these owner facts by canonical HIR row, whose
        // checked upper bound is the token count.
        hir_type_alias_target_node[node] = INVALID;
        hir_fn_return_type_node[node] = INVALID;
    }
    hir_type_len_value[node] = INVALID;
    if ((gClear.parser_feature_flags & PARSER_FEATURE_PREDICATES) != 0u)
    {
        hir_method_owner_node[node] = INVALID;
        hir_method_impl_node[node] = INVALID;
        hir_method_name_token[node] = INVALID;
        hir_method_first_param_token[node] = INVALID;
        hir_method_receiver_mode[node] = 0u;
        hir_method_visibility[node] = HIR_ITEM_VIS_PRIVATE;
        hir_method_signature_flags[node] = 0u;
        hir_method_impl_receiver_type_node[node] = INVALID;
    }

    hir_expr_result_root_scratch_node[node] = INVALID;
    if (node == 0u)

    hir_stmt_record[slot(node, 0u)] = STMT_RECORD_KIND_NONE;
    hir_stmt_record[slot(node, 1u)] = INVALID;
    hir_stmt_record[slot(node, 2u)] = INVALID;
    hir_stmt_record[slot(node, 3u)] = INVALID;
    if (gClear.retain_debug_rows != 0u)
    {
        hir_stmt_scope_end[node] = INVALID;
        hir_nearest_stmt_node[node] = INVALID;
        hir_nearest_block_node[node] = INVALID;
        hir_nearest_enclosing_control_node[node] = INVALID;
        hir_nearest_loop_node[node] = INVALID;
        hir_nearest_fn_node[node] = INVALID;
        hir_nearest_array_element_node[node] = INVALID;
        hir_call_context_stmt_node[node] = INVALID;
        hir_array_lit_context_stmt_node[node] = INVALID;
        hir_struct_lit_context_stmt_node[node] = INVALID;
    }
}
