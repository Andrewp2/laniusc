// Materialize independent member fields and index spans in one semantic-row walk.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirPostfix;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> hir_kind;
RWStructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;
StructuredBuffer<uint> hir_expr_record;

RWStructuredBuffer<uint> hir_member_receiver_node;
RWStructuredBuffer<uint> hir_member_receiver_token;
RWStructuredBuffer<uint> hir_member_name_token;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirPostfix.uses_status_count != 0u
        ? min(gHirPostfix.n, tree_count_status[5u])
        : gHirPostfix.n;
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_node_count();
}

uint active_semantic_count()
{
    return min(hir_semantic_count[0u], active_node_count());
}

uint semantic_row_node(uint row)
{
    if (row >= active_semantic_count())
        return INVALID;
    uint node = hir_semantic_dense_node[row];
    return valid_node(node) ? node : INVALID;
}

uint parent_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = parent[node];
    return valid_node(value) ? value : INVALID;
}

uint first_child_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = first_child[node];
    return valid_node(value) ? value : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint value = prev_sibling[node];
    return valid_node(value) ? value : INVALID;
}

bool is_postfix_operator(uint prod)
{
    return prod == PROD_POSTFIX_CALL || prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER;
}

uint token_before(uint token)
{
    return token != INVALID && token > 0u ? token - 1u : INVALID;
}

uint member_name_token_for_node(uint member_node)
{
    if (!valid_node(member_node))
        return INVALID;

    uint child = first_child_node(member_node);
    uint child_token = valid_node(child) ? hir_token_pos[child] : INVALID;
    if (child_token != INVALID && child_token > hir_token_pos[member_node])
        return child_token - 1u;

    uint end = hir_token_end[member_node];
    if (end != INVALID && end > hir_token_pos[member_node] + 1u)
        return end - 1u;
    return INVALID;
}

uint postfix_operator_head_token(uint operator_node)
{
    if (!valid_node(operator_node))
        return INVALID;
    if (node_kind[operator_node] == PROD_POSTFIX_MEMBER)
        return member_name_token_for_node(operator_node);
    return token_before(hir_token_pos[operator_node]);
}

uint receiver_token_for_node(uint receiver_node)
{
    if (!valid_node(receiver_node))
        return INVALID;
    if (is_postfix_operator(node_kind[receiver_node]))
        return postfix_operator_head_token(receiver_node);
    return hir_token_pos[receiver_node];
}

uint receiver_node_for_member(uint member_node)
{
    uint previous = previous_sibling_node(member_node);
    if (is_postfix_operator(node_kind[previous]))
        return previous;

    uint owner = parent_node(member_node);
    if (!valid_node(owner))
        return INVALID;
    if (is_postfix_operator(node_kind[owner]))
        return owner;
    return node_kind[owner] == PROD_POSTFIX ? first_child_node(owner) : INVALID;
}

uint expr_record(uint node, uint field)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + field];
}

void publish_member(uint node)
{
    uint receiver = receiver_node_for_member(node);
    uint receiver_token = receiver_token_for_node(receiver);
    uint member_token = member_name_token_for_node(node);
    if (receiver_token == INVALID || member_token == INVALID)
        return;

    hir_member_receiver_node[node] = receiver;
    hir_member_receiver_token[node] = receiver_token;
    hir_member_name_token[node] = member_token;
}

void publish_index_span(uint node)
{
    if (expr_record(node, HIR_EXPR_RECORD_FORM) != HIR_EXPR_INDEX)
        return;

    uint base = expr_record(node, HIR_EXPR_RECORD_LEFT);
    if (!valid_node(base))
        return;

    uint base_start = hir_token_pos[base];
    uint index_start = hir_token_pos[node];
    if (base_start != INVALID &&
        (index_start == INVALID || base_start < index_start))
        hir_token_pos[node] = base_start;

    uint index_expr = expr_record(node, HIR_EXPR_RECORD_RIGHT);
    if (!valid_node(index_expr))
        return;
    uint index_expr_end = hir_token_end[index_expr];
    if (index_expr_end != INVALID)
        hir_token_end[node] = index_expr_end + 1u;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint node = semantic_row_node(row);
    if (node == INVALID)
        return;

    hir_member_receiver_node[node] = INVALID;
    hir_member_receiver_token[node] = INVALID;
    hir_member_name_token[node] = INVALID;

    uint kind = hir_kind[node];
    if (kind == HIR_MEMBER_EXPR)
        publish_member(node);
    else if (kind == HIR_INDEX_EXPR)
        publish_index_span(node);
}
