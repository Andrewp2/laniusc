// Publish parser-owned context-relation rows for semantic HIR nodes.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
    uint semantic_parent_local_ancestor_span;
    uint retain_debug_rows;
};

ConstantBuffer<Params> gHirContextRelations;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_contextual_stmt_value_a;
StructuredBuffer<uint> hir_nearest_stmt_value_a;
StructuredBuffer<uint> hir_nearest_block_value_a;
StructuredBuffer<uint> hir_nearest_enclosing_control_value_a;
StructuredBuffer<uint> hir_nearest_loop_value_a;
StructuredBuffer<uint> hir_nearest_fn_value_a;
StructuredBuffer<uint> hir_nearest_array_element_value_a;
StructuredBuffer<uint> canonical_raw_to_dense;
StructuredBuffer<uint> canonical_alias_to_dense;

RWStructuredBuffer<uint> hir_nearest_stmt_node;
RWStructuredBuffer<uint> hir_nearest_block_node;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_node;
RWStructuredBuffer<uint> hir_nearest_loop_node;
RWStructuredBuffer<uint> hir_nearest_fn_node;
RWStructuredBuffer<uint> hir_nearest_array_element_node;
RWStructuredBuffer<uint> hir_struct_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_array_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_call_context_stmt_node;
RWStructuredBuffer<uint> hir_canonical_nearest_loop;
RWStructuredBuffer<uint> hir_canonical_nearest_block;
RWStructuredBuffer<uint> hir_canonical_nearest_control;
RWStructuredBuffer<uint> hir_canonical_nearest_fn;
RWStructuredBuffer<uint> hir_canonical_context_stmt;

static const uint INVALID = 0xffffffffu;
static const uint IMPL_OWNER_TAG = 0x80000000u;
static const uint HIR_STMT = 7u;
static const uint HIR_CALL_CONTEXT_STMT_BIT = 0x80000000u;
static const uint HIR_CALL_CONTEXT_ID_MASK = 0x7fffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirContextRelations.uses_status_count != 0u
               ? min(gHirContextRelations.n, tree_count_status[5u])
               : gHirContextRelations.n;
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

bool valid_original_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint dense_alias(uint node)
{
    return valid_original_node(node) ? canonical_alias_to_dense[node] : INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    if (row >= active_semantic_count())
        return;

    uint node = hir_semantic_dense_node[row];
    if (!valid_original_node(node))
        return;

    uint nearest_stmt = hir_nearest_stmt_value_a[row];
    uint nearest_block = hir_nearest_block_value_a[row];
    uint nearest_control = hir_nearest_enclosing_control_value_a[row];
    uint nearest_loop = hir_nearest_loop_value_a[row];
    uint nearest_fn = hir_nearest_fn_value_a[row];
    uint nearest_array_element = hir_nearest_array_element_value_a[row];

    uint context = hir_contextual_stmt_value_a[row];
    uint context_node = valid_original_node(context) ? context : INVALID;
    uint dense = canonical_raw_to_dense[node];
    if (dense != INVALID)
    {
        hir_canonical_nearest_loop[dense] = dense_alias(nearest_loop);
        hir_canonical_nearest_block[dense] = dense_alias(nearest_block);
        hir_canonical_nearest_control[dense] =
            (nearest_control & IMPL_OWNER_TAG) == 0u ? dense_alias(nearest_control) : INVALID;
        hir_canonical_nearest_fn[dense] = dense_alias(nearest_fn);
        uint dense_context = dense_alias(context_node);
        uint encoded_context = dense_context == INVALID
            ? HIR_CALL_CONTEXT_ID_MASK
            : dense_context;
        if (valid_original_node(context_node) && hir_kind[context_node] == HIR_STMT)
            encoded_context |= HIR_CALL_CONTEXT_STMT_BIT;
        hir_canonical_context_stmt[dense] = encoded_context;
    }

    if (gHirContextRelations.retain_debug_rows != 0u)
    {
        hir_nearest_stmt_node[node] = valid_original_node(nearest_stmt) ? nearest_stmt : INVALID;
        hir_nearest_block_node[node] =
            valid_original_node(nearest_block) ? nearest_block : INVALID;
        hir_nearest_enclosing_control_node[node] =
            (nearest_control & IMPL_OWNER_TAG) == 0u && valid_original_node(nearest_control)
                ? nearest_control
                : INVALID;
        hir_nearest_loop_node[node] =
            valid_original_node(nearest_loop) ? nearest_loop : INVALID;
        hir_nearest_fn_node[node] = valid_original_node(nearest_fn) ? nearest_fn : INVALID;
        hir_nearest_array_element_node[node] =
            valid_original_node(nearest_array_element) ? nearest_array_element : INVALID;
        uint prod = node_kind[node];
        if (prod == PROD_STRUCT_LIT)
            hir_struct_lit_context_stmt_node[node] = context_node;
        else if (prod == PROD_ARRAY_LIT)
            hir_array_lit_context_stmt_node[node] = context_node;
        else if (prod == PROD_POSTFIX_CALL)
            hir_call_context_stmt_node[node] = context_node;
    }
}
