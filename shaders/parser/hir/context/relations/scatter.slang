// Publish parser-owned context-relation rows for semantic HIR nodes.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirContextRelations;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_contextual_stmt_value_a;
StructuredBuffer<uint> hir_nearest_stmt_value_a;
StructuredBuffer<uint> hir_nearest_block_value_a;
StructuredBuffer<uint> hir_nearest_enclosing_control_value_a;
StructuredBuffer<uint> hir_nearest_loop_value_a;
StructuredBuffer<uint> hir_nearest_fn_value_a;

RWStructuredBuffer<uint> hir_nearest_stmt_node;
RWStructuredBuffer<uint> hir_nearest_block_node;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_node;
RWStructuredBuffer<uint> hir_nearest_loop_node;
RWStructuredBuffer<uint> hir_nearest_fn_node;
RWStructuredBuffer<uint> hir_struct_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_array_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_call_context_stmt_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;
static const uint FALLBACK_CONTEXT_SCAN_LIMIT = 8192u;

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

bool has_span(uint node)
{
    return valid_original_node(node) &&
           hir_token_pos[node] != INVALID &&
           hir_token_end[node] != INVALID &&
           hir_token_pos[node] < hir_token_end[node];
}

bool contains_span(uint owner, uint node)
{
    return has_span(owner) &&
           has_span(node) &&
           hir_token_pos[owner] <= hir_token_pos[node] &&
           hir_token_end[node] <= hir_token_end[owner];
}

uint fallback_nearest_containing(uint row, uint node, uint wanted_kind)
{
    if (!has_span(node))
        return INVALID;

    [loop]
    for (uint offset = 1u; offset <= FALLBACK_CONTEXT_SCAN_LIMIT; offset += 1u)
    {
        if (offset > row)
            break;
        uint candidate_row = row - offset;
        uint candidate = hir_semantic_dense_node[candidate_row];
        if (!valid_original_node(candidate))
            continue;
        if (hir_kind[candidate] == wanted_kind && contains_span(candidate, node))
            return candidate;
    }
    return INVALID;
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
    hir_nearest_stmt_node[node] = valid_original_node(nearest_stmt) ? nearest_stmt : INVALID;
    uint nearest_block = hir_nearest_block_value_a[row];
    if (!valid_original_node(nearest_block))
        nearest_block = fallback_nearest_containing(row, node, HIR_BLOCK);
    hir_nearest_block_node[node] =
        valid_original_node(nearest_block) ? nearest_block : INVALID;
    uint nearest_control = hir_nearest_enclosing_control_value_a[row];
    hir_nearest_enclosing_control_node[node] =
        valid_original_node(nearest_control) ? nearest_control : INVALID;
    uint nearest_loop = hir_nearest_loop_value_a[row];
    hir_nearest_loop_node[node] =
        valid_original_node(nearest_loop) ? nearest_loop : INVALID;
    uint nearest_fn = hir_nearest_fn_value_a[row];
    if (!valid_original_node(nearest_fn))
        nearest_fn = fallback_nearest_containing(row, node, HIR_FN);
    hir_nearest_fn_node[node] = valid_original_node(nearest_fn) ? nearest_fn : INVALID;

    uint context = hir_contextual_stmt_value_a[row];
    uint context_node = valid_original_node(context) ? context : INVALID;
    uint prod = node_kind[node];
    if (prod == PROD_STRUCT_LIT)
        hir_struct_lit_context_stmt_node[node] = context_node;
    else if (prod == PROD_ARRAY_LIT)
        hir_array_lit_context_stmt_node[node] = context_node;
    else if (prod == PROD_POSTFIX_CALL)
        hir_call_context_stmt_node[node] = context_node;
}
