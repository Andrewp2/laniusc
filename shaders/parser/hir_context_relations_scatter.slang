// Publish parser-owned context-relation rows for semantic HIR nodes.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirContextRelations;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_contextual_stmt_value_a;
StructuredBuffer<uint> hir_nearest_stmt_value_a;
StructuredBuffer<uint> hir_nearest_block_value_a;
StructuredBuffer<uint> hir_nearest_enclosing_control_value_a;
StructuredBuffer<uint> hir_nearest_fn_value_a;

RWStructuredBuffer<uint> hir_nearest_stmt_node;
RWStructuredBuffer<uint> hir_nearest_block_node;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_node;
RWStructuredBuffer<uint> hir_nearest_fn_node;
RWStructuredBuffer<uint> hir_struct_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_array_lit_context_stmt_node;
RWStructuredBuffer<uint> hir_call_context_stmt_node;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirContextRelations.uses_ll1 != 0u
               ? min(gHirContextRelations.n, ll1_status[5u])
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
    hir_nearest_block_node[node] =
        valid_original_node(nearest_block) ? nearest_block : INVALID;
    uint nearest_control = hir_nearest_enclosing_control_value_a[row];
    hir_nearest_enclosing_control_node[node] =
        valid_original_node(nearest_control) ? nearest_control : INVALID;
    uint nearest_fn = hir_nearest_fn_value_a[row];
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
