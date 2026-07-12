// Seed parser-owned context-relation propagation for semantic HIR rows.
//
// This pass works over dense semantic-HIR rows. It records the nearest
// syntactic statement, block, enclosing-control, loop, and function contexts with
// pointer-jump links so consumers can avoid bounded ancestor walks over the
// parse tree. Contextual statement rows come from parser-owned statement
// records, plus generic expression-statement HIR rows for statement-call
// consumers.

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
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_semantic_parent;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_array_element_parent_lit;

RWStructuredBuffer<uint> hir_stmt_context_link_a;
RWStructuredBuffer<uint> hir_contextual_stmt_value_a;
RWStructuredBuffer<uint> hir_nearest_stmt_value_a;
RWStructuredBuffer<uint> hir_nearest_block_value_a;
RWStructuredBuffer<uint> hir_nearest_enclosing_control_value_a;
RWStructuredBuffer<uint> hir_nearest_loop_value_a;
RWStructuredBuffer<uint> hir_nearest_fn_value_a;
RWStructuredBuffer<uint> hir_nearest_array_element_value_a;

static const uint INVALID = 0xffffffffu;
static const uint IMPL_OWNER_TAG = 0x80000000u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint IMPL_WRAPPER_CHILD_BUDGET = 4u;

static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_IF_STMT = 10u;
static const uint HIR_WHILE_STMT = 11u;
static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_CONST_ITEM = 25u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_FN = 3u;

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

bool valid_semantic_row(uint row, uint semantic_count)
{
    return row != INVALID && row < semantic_count;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

bool block_node(uint node)
{
    return valid_original_node(node) && hir_kind[node] == HIR_BLOCK;
}

bool generic_statement_node(uint node)
{
    return valid_original_node(node) &&
           (node_kind[node] == PROD_BLOCK_STMT || node_kind[node] == PROD_EXPR_STMT);
}

bool nearest_statement_node(uint node, uint parent_node)
{
    if (!valid_original_node(node))
        return false;
    uint kind = hir_kind[node];
    return generic_statement_node(node) ||
           kind == HIR_LET_STMT || kind == HIR_RETURN_STMT ||
           kind == HIR_IF_STMT || kind == HIR_WHILE_STMT ||
           kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT ||
           kind == HIR_CONST_ITEM || kind == HIR_FOR_STMT;
}

bool context_statement_node(uint node, uint parent_node)
{
    if (!nearest_statement_node(node, parent_node))
        return false;
    uint kind = hir_stmt_record[stmt_slot(node, 0u)];
    return kind != STMT_RECORD_KIND_NONE || generic_statement_node(node);
}

bool function_node(uint node)
{
    return valid_original_node(node) && hir_kind[node] == HIR_FN;
}

bool control_node(uint node)
{
    if (!valid_original_node(node))
        return false;
    uint kind = hir_kind[node];
    return kind == HIR_IF_STMT || kind == HIR_WHILE_STMT ||
           kind == HIR_FOR_STMT || kind == HIR_MATCH_EXPR;
}

bool impl_owner_production(uint prod)
{
    return prod == PROD_IMPL_INHERENT || prod == PROD_IMPL_TRAIT;
}

uint impl_owner_for_context_node(uint node)
{
    if (!valid_original_node(node))
        return INVALID;
    uint prod = node_kind[node];
    if (impl_owner_production(prod))
        return node;
    if (prod != PROD_ITEM_IMPL && prod != PROD_PUB_IMPL)
        return INVALID;

    uint child = first_child[node];
    for (uint step = 0u; step < IMPL_WRAPPER_CHILD_BUDGET; step += 1u)
    {
        if (!valid_original_node(child) || parent[child] != node)
            return INVALID;
        if (impl_owner_production(node_kind[child]))
            return child;
        uint sibling = next_sibling[child];
        if (!valid_original_node(sibling) || sibling <= child)
            return INVALID;
        child = sibling;
    }
    return INVALID;
}

bool loop_node(uint node)
{
    if (!valid_original_node(node))
        return false;
    uint kind = hir_kind[node];
    return kind == HIR_WHILE_STMT || kind == HIR_FOR_STMT;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint semantic_count = active_semantic_count();
    if (row >= semantic_count)
        return;

    uint node = hir_semantic_dense_node[row];
    uint parent = hir_semantic_parent[row];
    uint parent_node =
        valid_semantic_row(parent, semantic_count) ? hir_semantic_dense_node[parent] : INVALID;
    hir_stmt_context_link_a[row] =
        valid_semantic_row(parent, semantic_count) ? parent : INVALID;
    hir_contextual_stmt_value_a[row] =
        context_statement_node(node, parent_node) ? node : INVALID;
    hir_nearest_stmt_value_a[row] =
        nearest_statement_node(node, parent_node) ? node : INVALID;
    hir_nearest_block_value_a[row] =
        block_node(node) ? node : INVALID;
    uint impl_owner = impl_owner_for_context_node(node);
    hir_nearest_enclosing_control_value_a[row] =
        control_node(parent_node)
            ? parent_node
            : (valid_original_node(impl_owner) ? (IMPL_OWNER_TAG | impl_owner) : INVALID);
    hir_nearest_loop_value_a[row] =
        loop_node(node) ? node : INVALID;
    hir_nearest_fn_value_a[row] =
        function_node(node) ? node : INVALID;
    hir_nearest_array_element_value_a[row] =
        valid_original_node(hir_array_element_parent_lit[node]) ? node : INVALID;
}
