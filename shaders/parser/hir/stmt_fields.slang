// Derive parser-owned statement/local/const metadata from production ids.
//
// This pass consumes tree arrays and HIR classifications. It does not inspect
// token neighborhoods, source bytes, helper names, or stdlib names.
// Statement-scope ends are derived from the parser's statement-list/block
// records and fail closed to INVALID when the local grammar shape is not
// present.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_status_count;
};

ConstantBuffer<Params> gHirStmt;

StructuredBuffer<uint> tree_count_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
RWStructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_stmt_record;
RWStructuredBuffer<uint> hir_stmt_scope_end;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR = 14u;
static const uint HIR_ASSIGN_EXPR = 15u;
static const uint HIR_BINARY_EXPR = 16u;
static const uint HIR_UNARY_EXPR = 17u;
static const uint HIR_POSTFIX_EXPR = 18u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_TYPE = 5u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_LITERAL_EXPR = 23u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_PATH_EXPR = 33u;
static const uint HIR_MATCH_EXPR = 34u;
static const uint HIR_BLOCK = 6u;
static const uint HIR_EXPR_RANGE = 30u;
static const uint HIR_EXPR_RANGE_FROM = 31u;
static const uint HIR_EXPR_RANGE_TO = 32u;
static const uint HIR_EXPR_RANGE_FULL = 33u;
static const uint HIR_EXPR_RANGE_INCLUSIVE = 34u;
static const uint HIR_EXPR_RANGE_TO_INCLUSIVE = 35u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;
static const uint STMT_RECORD_KIND_FOR = 7u;
static const uint STMT_RECORD_KIND_BREAK = 8u;
static const uint STMT_RECORD_KIND_CONTINUE = 9u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint ASSIGN_OP_SET = 1u;
static const uint ASSIGN_OP_ADD = 2u;
static const uint ASSIGN_OP_SUB = 3u;
static const uint ASSIGN_OP_MUL = 4u;
static const uint ASSIGN_OP_DIV = 5u;
static const uint ASSIGN_OP_MOD = 6u;
static const uint ASSIGN_OP_XOR = 7u;
static const uint ASSIGN_OP_SHL = 8u;
static const uint ASSIGN_OP_SHR = 9u;
static const uint ASSIGN_OP_BAND = 10u;
static const uint ASSIGN_OP_BOR = 11u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirStmt.uses_status_count != 0u ? min(gHirStmt.n, tree_count_status[5u]) : gHirStmt.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
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

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint valid_end_or_invalid(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint end = hir_token_end[node];
    return end == 0u ? INVALID : end;
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

bool node_has_non_empty_span(uint node)
{
    return valid_node(node) &&
           hir_token_pos[node] != INVALID &&
           hir_token_end[node] != INVALID &&
           hir_token_pos[node] < hir_token_end[node];
}

uint token_after_keyword(uint node)
{
    if (!node_has_non_empty_span(node))
        return INVALID;
    uint token = hir_token_pos[node] + 1u;
    return token < hir_token_end[node] ? token : INVALID;
}

void clear_record(uint i)
{
    hir_stmt_record[stmt_slot(i, 0u)] = STMT_RECORD_KIND_NONE;
    hir_stmt_record[stmt_slot(i, 1u)] = INVALID;
    hir_stmt_record[stmt_slot(i, 2u)] = INVALID;
    hir_stmt_record[stmt_slot(i, 3u)] = INVALID;
    hir_stmt_scope_end[i] = INVALID;
}

uint valid_child_or_invalid(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint child = first_child[node];
    return valid_node(child) ? child : INVALID;
}

uint valid_sibling_or_invalid(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint sibling = next_sibling[node];
    return valid_node(sibling) ? sibling : INVALID;
}

uint child_if_production(uint node, uint prod)
{
    uint child = valid_child_or_invalid(node);
    return valid_node(child) && node_kind[child] == prod ? child : INVALID;
}

uint sibling_if_production(uint node, uint prod)
{
    uint sibling = valid_sibling_or_invalid(node);
    return valid_node(sibling) && node_kind[sibling] == prod ? sibling : INVALID;
}

bool is_hir_expression_kind(uint kind)
{
    return kind == HIR_EXPR ||
           kind == HIR_ASSIGN_EXPR ||
           kind == HIR_BINARY_EXPR ||
           kind == HIR_UNARY_EXPR ||
           kind == HIR_POSTFIX_EXPR ||
           kind == HIR_CALL_EXPR ||
           kind == HIR_INDEX_EXPR ||
           kind == HIR_MEMBER_EXPR ||
           kind == HIR_NAME_EXPR ||
           kind == HIR_LITERAL_EXPR ||
           kind == HIR_ARRAY_EXPR ||
           kind == HIR_STRUCT_LITERAL_EXPR ||
           kind == HIR_PATH_EXPR ||
           kind == HIR_MATCH_EXPR;
}

uint expr_record_form(uint node)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + HIR_EXPR_RECORD_FORM] : 0u;
}

bool is_range_expr_form(uint form)
{
    return form == HIR_EXPR_RANGE ||
           form == HIR_EXPR_RANGE_FROM ||
           form == HIR_EXPR_RANGE_TO ||
           form == HIR_EXPR_RANGE_FULL ||
           form == HIR_EXPR_RANGE_INCLUSIVE ||
           form == HIR_EXPR_RANGE_TO_INCLUSIVE;
}

uint direct_expr_child(uint node)
{
    uint child = valid_child_or_invalid(node);
    return valid_node(child) && is_hir_expression_kind(hir_kind[child]) ? child : INVALID;
}

uint direct_expr_child_scan(uint node)
{
    uint child = valid_child_or_invalid(node);
    for (uint step = 0u; step < 8u && valid_node(child); step++)
    {
        if (is_hir_expression_kind(hir_kind[child]))
            return child;
        child = valid_sibling_or_invalid(child);
    }
    return INVALID;
}

bool is_for_iterable_production(uint prod)
{
    return prod == PROD_FOR_ITER_PATH ||
           prod == PROD_FOR_ITER_RANGE_FROM_START ||
           prod == PROD_FOR_ITER_RANGE_TO ||
           prod == PROD_FOR_ITER_RANGE_TO_INCLUSIVE;
}

uint direct_for_iterable_child(uint node)
{
    uint child = valid_child_or_invalid(node);
    for (uint step = 0u; step < 12u && valid_node(child); step++)
    {
        if (is_for_iterable_production(node_kind[child]))
            return child;
        child = valid_sibling_or_invalid(child);
    }
    return INVALID;
}

uint bounded_subtree_production_scan(uint node, uint prod, uint after_node)
{
    if (!valid_node(node))
        return INVALID;

    uint end = subtree_end[node];
    if (!valid_node(end - 1u))
        return INVALID;

    uint cursor = valid_node(after_node) ? after_node + 1u : node + 1u;
    for (uint step = 0u; step < 64u && cursor < end; step++, cursor++)
    {
        if (valid_node(cursor) && node_kind[cursor] == prod)
            return cursor;
    }
    return INVALID;
}

uint bounded_subtree_for_iterable_scan(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint end = subtree_end[node];
    if (!valid_node(end - 1u))
        return INVALID;

    for (uint step = 0u, cursor = node + 1u; step < 64u && cursor < end; step++, cursor++)
    {
        if (valid_node(cursor) && is_for_iterable_production(node_kind[cursor]))
            return cursor;
    }
    return INVALID;
}

uint semantic_for_iterable_scan(uint row, uint node)
{
    uint node_end = hir_token_end[node];
    for (uint step = 1u; step <= 64u; step++)
    {
        uint candidate = semantic_row_node(row + step);
        if (!valid_node(candidate))
            break;
        if (!node_has_non_empty_span(candidate))
            continue;
        if (hir_token_pos[candidate] >= node_end)
            break;
        if (is_for_iterable_production(node_kind[candidate]))
            return candidate;
    }
    return INVALID;
}

uint semantic_body_block_scan(uint row, uint node, uint after_node)
{
    uint node_end = hir_token_end[node];
    uint after_end = valid_node(after_node) ? hir_token_end[after_node] : hir_token_pos[node];
    for (uint step = 1u; step <= 64u; step++)
    {
        uint candidate = semantic_row_node(row + step);
        if (!valid_node(candidate))
            break;
        if (!node_has_non_empty_span(candidate))
            continue;
        if (hir_token_pos[candidate] >= node_end)
            break;
        if (hir_kind[candidate] == HIR_BLOCK && hir_token_pos[candidate] >= after_end)
            return candidate;
    }
    return INVALID;
}

uint nearby_body_block_scan(uint node, uint binding_token)
{
    uint node_end = hir_token_end[node];
    for (uint step = 1u; step <= 128u; step++)
    {
        uint candidate = node + step;
        if (valid_node(candidate) && (hir_kind[candidate] == HIR_BLOCK || node_kind[candidate] == PROD_BLOCK))
            return candidate;

        candidate = node >= step ? node - step : INVALID;
        if (valid_node(candidate) && (hir_kind[candidate] == HIR_BLOCK || node_kind[candidate] == PROD_BLOCK) &&
            node_has_non_empty_span(candidate) &&
            hir_token_pos[candidate] > binding_token &&
            hir_token_pos[candidate] < node_end)
            return candidate;
    }
    return INVALID;
}

uint nearby_range_iterable_scan(uint node, uint binding_token, uint body)
{
    uint limit = valid_node(body) ? hir_token_pos[body] : hir_token_end[node];
    uint first_expr = INVALID;
    for (uint step = 1u; step <= 128u; step++)
    {
        uint candidate = node + step;
        if (!valid_node(candidate))
            break;
        if (!node_has_non_empty_span(candidate))
            continue;
        if (hir_token_pos[candidate] >= limit)
            break;
        if (hir_token_pos[candidate] <= binding_token)
            continue;
        if (is_hir_expression_kind(hir_kind[candidate]))
        {
            if (!valid_node(first_expr))
                first_expr = candidate;
            if (is_range_expr_form(expr_record_form(candidate)))
                return candidate;
        }
    }
    return first_expr;
}

uint direct_production_child_after(uint node, uint prod, uint after_node)
{
    if (valid_node(after_node))
    {
        uint candidate = subtree_end[after_node];
        if (valid_node(candidate) && parent[candidate] == node && node_kind[candidate] == prod)
            return candidate;
    }

    uint child = valid_child_or_invalid(node);
    bool after_seen = after_node == INVALID;
    for (uint step = 0u; step < 8u && valid_node(child); step++)
    {
        if (child == after_node)
            after_seen = true;
        else if (after_seen && node_kind[child] == prod)
            return child;
        child = valid_sibling_or_invalid(child);
    }

    uint sibling = valid_sibling_or_invalid(node);
    if (valid_node(sibling) && node_kind[sibling] == prod)
        return sibling;

    return INVALID;
}

uint let_init_child(uint node)
{
    uint let_type = valid_child_or_invalid(node);
    return sibling_if_production(let_type, PROD_LET_INIT);
}

uint let_type_node(uint node)
{
    uint let_type = valid_child_or_invalid(node);
    uint type_node = valid_child_or_invalid(let_type);
    return valid_node(type_node) && hir_kind[type_node] == HIR_TYPE ? type_node : INVALID;
}

uint return_value_child(uint node)
{
    return child_if_production(node, PROD_RETURN_VALUE);
}

uint block_child(uint node)
{
    return child_if_production(node, PROD_BLOCK);
}

uint if_block_child(uint node)
{
    return child_if_production(node, PROD_IF_BLOCK);
}

uint lexical_statement_list_scope_end(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    if (valid_node(p) && node_kind[p] == PROD_STMTS_MORE)
        return valid_end_or_invalid(p);

    uint pp = valid_node(p) ? parent[p] : INVALID;
    if (valid_node(pp) && node_kind[pp] == PROD_STMTS_MORE)
        return valid_end_or_invalid(pp);

    if (valid_node(p) &&
        (node_kind[p] == PROD_BLOCK ||
         node_kind[p] == PROD_IF_BLOCK ||
         node_kind[p] == PROD_FN_BLOCK ||
         node_kind[p] == PROD_IMPL_FN_BLOCK))
        return valid_end_or_invalid(p);

    return INVALID;
}

uint if_then_block(uint node)
{
    uint condition = direct_expr_child_scan(node);
    return direct_production_child_after(node, PROD_IF_BLOCK, condition);
}

uint else_block_for_if(uint node)
{
    uint child = valid_child_or_invalid(node);
    for (uint guard = 0u; guard < 16u && valid_node(child); guard++)
    {
        if (node_kind[child] == PROD_ELSE_STMT)
            return block_child(child);
        child = valid_sibling_or_invalid(child);
    }
    return INVALID;
}

uint value_token_for_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint result = hir_expr_result_root_node[node];
    if (!valid_node(result))
        return INVALID;
    uint token_i = expr_slot(result, HIR_EXPR_RECORD_VALUE_TOKEN);
    if (token_i != INVALID)
        return token_i;
    if (hir_kind[result] == HIR_MEMBER_EXPR && hir_member_name_token[result] != INVALID)
        return hir_member_name_token[result];
    return hir_token_pos[result];
}

bool is_assignment_tail_production(uint prod)
{
    return prod == PROD_ASSIGN_SET || prod == PROD_ASSIGN_ADD || prod == PROD_ASSIGN_SUB ||
           prod == PROD_ASSIGN_MUL || prod == PROD_ASSIGN_DIV || prod == PROD_ASSIGN_MOD ||
           prod == PROD_ASSIGN_XOR || prod == PROD_ASSIGN_SHL || prod == PROD_ASSIGN_SHR ||
           prod == PROD_ASSIGN_BAND || prod == PROD_ASSIGN_BOR;
}

uint assignment_op_for_production(uint prod)
{
    if (prod == PROD_ASSIGN_SET)
        return ASSIGN_OP_SET;
    if (prod == PROD_ASSIGN_ADD)
        return ASSIGN_OP_ADD;
    if (prod == PROD_ASSIGN_SUB)
        return ASSIGN_OP_SUB;
    if (prod == PROD_ASSIGN_MUL)
        return ASSIGN_OP_MUL;
    if (prod == PROD_ASSIGN_DIV)
        return ASSIGN_OP_DIV;
    if (prod == PROD_ASSIGN_MOD)
        return ASSIGN_OP_MOD;
    if (prod == PROD_ASSIGN_XOR)
        return ASSIGN_OP_XOR;
    if (prod == PROD_ASSIGN_SHL)
        return ASSIGN_OP_SHL;
    if (prod == PROD_ASSIGN_SHR)
        return ASSIGN_OP_SHR;
    if (prod == PROD_ASSIGN_BAND)
        return ASSIGN_OP_BAND;
    if (prod == PROD_ASSIGN_BOR)
        return ASSIGN_OP_BOR;
    return 0u;
}

uint direct_assignment_tail(uint expr_stmt)
{
    uint expr = direct_expr_child(expr_stmt);
    if (!valid_node(expr))
        return INVALID;

    uint assign = node_kind[expr] == PROD_ASSIGN ?
        expr :
        child_if_production(expr, PROD_ASSIGN);
    if (!valid_node(assign))
        return INVALID;

    uint lhs = valid_child_or_invalid(assign);
    uint tail = valid_sibling_or_invalid(lhs);
    return valid_node(tail) && is_assignment_tail_production(node_kind[tail])
        ? tail
        : INVALID;
}

void publish_let(uint node)
{
    uint init = let_init_child(node);
    uint init_expr = direct_expr_child(init);
    uint type_node = let_type_node(node);
    uint name_token = token_after_keyword(node);
    if (name_token == INVALID)
        return;

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_LET;
    hir_stmt_record[stmt_slot(node, 1u)] = name_token;
    hir_stmt_record[stmt_slot(node, 2u)] = init_expr;
    hir_stmt_record[stmt_slot(node, 3u)] = type_node;
    hir_stmt_scope_end[node] = lexical_statement_list_scope_end(node);
}

void publish_return(uint node)
{
    uint ret_value = return_value_child(node);
    uint ret_expr = direct_expr_child(ret_value);

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_RETURN;
    hir_stmt_record[stmt_slot(node, 1u)] = ret_expr;
    hir_stmt_record[stmt_slot(node, 2u)] = INVALID;
    hir_stmt_record[stmt_slot(node, 3u)] = value_token_for_expr(ret_expr);
}

void publish_return_value(uint node)
{
    uint ret_expr = direct_expr_child(node);

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_RETURN;
    hir_stmt_record[stmt_slot(node, 1u)] = ret_expr;
    hir_stmt_record[stmt_slot(node, 2u)] = INVALID;
    hir_stmt_record[stmt_slot(node, 3u)] = value_token_for_expr(ret_expr);
}

bool compressed_if_return_value(uint node)
{
    if (!valid_node(node) || node_kind[node] != PROD_RETURN_VALUE)
        return false;
    uint p = parent[node];
    return valid_node(p) && node_kind[p] == PROD_IF_STMT;
}

void publish_if(uint node)
{
    uint else_block = else_block_for_if(node);
    uint cond = direct_expr_child_scan(node);
    uint then_block = if_then_block(node);
    uint then_return = return_value_child(node);
    uint then_arm = valid_node(then_block) ? then_block : then_return;

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_IF;
    hir_stmt_record[stmt_slot(node, 1u)] = cond;
    hir_stmt_record[stmt_slot(node, 2u)] = then_arm;
    hir_stmt_record[stmt_slot(node, 3u)] = else_block;
}

void publish_while(uint node)
{
    uint cond = direct_expr_child_scan(node);
    uint body = direct_production_child_after(node, PROD_BLOCK, cond);
    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_WHILE;
    hir_stmt_record[stmt_slot(node, 1u)] = cond;
    hir_stmt_record[stmt_slot(node, 2u)] = valid_node(body) && node_kind[body] == PROD_BLOCK
        ? body
        : INVALID;
    hir_stmt_record[stmt_slot(node, 3u)] = INVALID;
}

void publish_for(uint row, uint node)
{
    uint binding_token = token_after_keyword(node);
    if (binding_token == INVALID)
        return;

    uint iterable_owner = direct_for_iterable_child(node);
    if (!valid_node(iterable_owner))
        iterable_owner = bounded_subtree_for_iterable_scan(node);
    if (!valid_node(iterable_owner))
        iterable_owner = semantic_for_iterable_scan(row, node);
    uint body = direct_production_child_after(node, PROD_BLOCK, iterable_owner);
    if (!valid_node(body))
        body = bounded_subtree_production_scan(node, PROD_BLOCK, iterable_owner);
    if (!valid_node(body))
        body = semantic_body_block_scan(row, node, iterable_owner);
    if (!valid_node(body))
        body = nearby_body_block_scan(node, binding_token);

    if (!valid_node(iterable_owner))
        iterable_owner = nearby_range_iterable_scan(node, binding_token, body);
    uint iterable = valid_node(iterable_owner) ? hir_expr_result_root_node[iterable_owner] : INVALID;
    if (!valid_node(iterable) && valid_node(iterable_owner) &&
        is_hir_expression_kind(hir_kind[iterable_owner]))
        iterable = iterable_owner;
    if (valid_node(iterable) && valid_node(body) &&
        hir_token_end[iterable] > hir_token_pos[body])
    {
        hir_token_end[iterable] = hir_token_pos[body];
    }

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_FOR;
    hir_stmt_record[stmt_slot(node, 1u)] = binding_token;
    hir_stmt_record[stmt_slot(node, 2u)] = valid_node(iterable) && is_hir_expression_kind(hir_kind[iterable])
        ? iterable
        : INVALID;
    hir_stmt_record[stmt_slot(node, 3u)] = body;
    hir_stmt_scope_end[node] = valid_end_or_invalid(body);
}

void publish_loop_control(uint node, uint kind)
{
    if (!node_has_non_empty_span(node))
        return;
    hir_stmt_record[stmt_slot(node, 0u)] = kind;
    hir_stmt_record[stmt_slot(node, 1u)] = INVALID;
    hir_stmt_record[stmt_slot(node, 2u)] = INVALID;
    hir_stmt_record[stmt_slot(node, 3u)] = INVALID;
}

void publish_const(uint node)
{
    uint type_node = valid_child_or_invalid(node);
    uint value_expr = valid_sibling_or_invalid(type_node);
    uint name_token = token_after_keyword(node);
    if (name_token == INVALID)
        return;

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_CONST;
    hir_stmt_record[stmt_slot(node, 1u)] = name_token;
    hir_stmt_record[stmt_slot(node, 2u)] = value_expr;
    hir_stmt_record[stmt_slot(node, 3u)] = valid_node(type_node) && hir_kind[type_node] == HIR_TYPE
        ? type_node
        : INVALID;
    hir_stmt_scope_end[node] = lexical_statement_list_scope_end(node);
}

void publish_assignment(uint node)
{
    uint assign_tail = direct_assignment_tail(node);
    if (!valid_node(assign_tail))
        return;

    uint assign_parent = parent[assign_tail];
    uint target_expr = valid_child_or_invalid(assign_parent);
    uint rhs_expr = valid_child_or_invalid(assign_tail);
    uint op = assignment_op_for_production(node_kind[assign_tail]);
    if (!valid_node(target_expr) || !valid_node(rhs_expr) || op == 0u)
        return;

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_ASSIGN;
    hir_stmt_record[stmt_slot(node, 1u)] = target_expr;
    hir_stmt_record[stmt_slot(node, 2u)] = rhs_expr;
    hir_stmt_record[stmt_slot(node, 3u)] = op;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint i = semantic_row_node(row);
    if (i == INVALID)
        return;

    clear_record(i);
    uint prod = node_kind[i];
    if (prod == PROD_LET_STMT)
        publish_let(i);
    else if (prod == PROD_RETURN_STMT)
        publish_return(i);
    else if (compressed_if_return_value(i))
        publish_return_value(i);
    else if (prod == PROD_IF_STMT)
        publish_if(i);
    else if (prod == PROD_WHILE_STMT)
        publish_while(i);
    else if (prod == PROD_FOR_STMT || hir_kind[i] == HIR_FOR_STMT)
        publish_for(row, i);
    else if (prod == PROD_BREAK_STMT)
        publish_loop_control(i, STMT_RECORD_KIND_BREAK);
    else if (prod == PROD_CONTINUE_STMT)
        publish_loop_control(i, STMT_RECORD_KIND_CONTINUE);
    else if (prod == PROD_CONST)
        publish_const(i);
    else if (prod == PROD_EXPR_STMT)
        publish_assignment(i);
}
