// Derive parser-owned statement/local/const metadata from production ids.
//
// This pass consumes tree arrays and HIR classifications. It does not inspect
// token neighborhoods, source bytes, helper names, or stdlib names.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirStmt;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_value_token;

RWStructuredBuffer<uint> hir_stmt_record;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR = 14u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_NONE = 0u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;
static const uint STMT_RECORD_KIND_IF = 3u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_ASSIGN = 5u;
static const uint STMT_RECORD_KIND_WHILE = 6u;

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
    return gHirStmt.uses_ll1 != 0u ? min(gHirStmt.n, ll1_status[5u]) : gHirStmt.n;
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

void clear_record(uint i)
{
    hir_stmt_record[stmt_slot(i, 0u)] = STMT_RECORD_KIND_NONE;
    hir_stmt_record[stmt_slot(i, 1u)] = INVALID;
    hir_stmt_record[stmt_slot(i, 2u)] = INVALID;
    hir_stmt_record[stmt_slot(i, 3u)] = INVALID;
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

bool has_ancestor_with_production(uint node, uint ancestor_prod, uint stop_node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur) || cur == stop_node)
            return false;
        uint p = parent[cur];
        if (!valid_node(p))
            return false;
        if (node_kind[p] == ancestor_prod)
            return true;
        cur = p;
    }
    return false;
}

bool atom_expr_candidate(uint node, uint container)
{
    if (!valid_node(node))
        return false;

    uint prod = node_kind[node];
    if (prod == PROD_IDENT && has_ancestor_with_production(node, PROD_PATH, container))
        return false;
    if (prod == PROD_IDENT_PLAIN &&
        (has_ancestor_with_production(node, PROD_IDENT, container) ||
         has_ancestor_with_production(node, PROD_PATH, container)))
        return false;

    return prod == PROD_INT || prod == PROD_TRUE || prod == PROD_FALSE ||
           prod == PROD_IDENT || prod == PROD_IDENT_PLAIN || prod == PROD_PATH;
}

bool unary_expr_production(uint prod)
{
    return prod == PROD_NEG || prod == PROD_NOT;
}

uint unary_ancestor_for_atom(uint atom, uint container)
{
    uint unary = INVALID;
    uint cur = atom;
    [loop]
    for (uint guard = 0u; guard < 64u; guard += 1u)
    {
        if (!valid_node(cur) || cur == container)
            break;
        uint p = parent[cur];
        if (!valid_node(p) || p == container)
            break;
        if (unary_expr_production(node_kind[p]))
        {
            if (unary != INVALID)
                return INVALID;
            unary = p;
        }
        cur = p;
    }
    return unary;
}

uint value_token_for_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint token_i = hir_expr_value_token[node];
    return token_i != INVALID ? token_i : hir_token_pos[node];
}

bool simple_value_node_in(
    uint container,
    out uint value_node,
    out uint operand_node,
    out uint value_token)
{
    value_node = INVALID;
    operand_node = INVALID;
    value_token = INVALID;
    if (!valid_node(container))
        return false;

    uint first_atom = INVALID;
    uint atom_count = 0u;
    uint end = min(subtree_end[container], active_node_count());
    [loop]
    for (uint node = container + 1u; node < end; node += 1u)
    {
        if (!atom_expr_candidate(node, container))
            continue;
        if (first_atom == INVALID)
            first_atom = node;
        atom_count += 1u;
        uint atom_end = subtree_end[node];
        if (atom_end > node + 1u && valid_node(atom_end - 1u))
            node = atom_end - 1u;
    }
    if (atom_count != 1u)
        return false;

    uint unary = unary_ancestor_for_atom(first_atom, container);
    if (unary != INVALID)
    {
        value_node = unary;
        operand_node = first_atom;
        value_token = value_token_for_expr(first_atom);
        return true;
    }

    value_node = first_atom;
    value_token = value_token_for_expr(first_atom);
    return true;
}

uint first_descendant_with_production(uint node, uint prod)
{
    if (!valid_node(node))
        return INVALID;
    uint end = min(subtree_end[node], active_node_count());
    [loop]
    for (uint i = node + 1u; i < end; i += 1u)
    {
        if (node_kind[i] == prod)
            return i;
    }
    return INVALID;
}

uint first_descendant_hir_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint end = min(subtree_end[node], active_node_count());
    [loop]
    for (uint i = node + 1u; i < end; i += 1u)
    {
        if (hir_kind[i] == HIR_EXPR)
            return i;
    }
    return INVALID;
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

uint first_descendant_assignment_tail(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint end = min(subtree_end[node], active_node_count());
    [loop]
    for (uint i = node + 1u; i < end; i += 1u)
    {
        if (is_assignment_tail_production(node_kind[i]))
            return i;
    }
    return INVALID;
}

void publish_let(uint node)
{
    uint init = first_descendant_with_production(node, PROD_LET_INIT);
    uint init_expr = first_descendant_with_production(init, PROD_EXPR);
    uint value_node = INVALID;
    uint operand_node = INVALID;
    uint value_token = INVALID;
    simple_value_node_in(init, value_node, operand_node, value_token);

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_LET;
    hir_stmt_record[stmt_slot(node, 1u)] = hir_token_pos[node] == INVALID ? INVALID
                                                                          : hir_token_pos[node] + 1u;
    hir_stmt_record[stmt_slot(node, 2u)] = init_expr;
    hir_stmt_record[stmt_slot(node, 3u)] = operand_node;
}

void publish_return(uint node)
{
    uint ret_value = first_descendant_with_production(node, PROD_RETURN_VALUE);
    uint ret_expr = first_descendant_with_production(ret_value, PROD_EXPR);
    uint value_node = INVALID;
    uint operand_node = INVALID;
    uint value_token = INVALID;
    simple_value_node_in(ret_value, value_node, operand_node, value_token);

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_RETURN;
    hir_stmt_record[stmt_slot(node, 1u)] = ret_expr;
    hir_stmt_record[stmt_slot(node, 2u)] = operand_node;
    hir_stmt_record[stmt_slot(node, 3u)] = value_token;
}

void publish_if(uint node)
{
    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_IF;
    hir_stmt_record[stmt_slot(node, 1u)] = first_descendant_with_production(node, PROD_EXPR);
    hir_stmt_record[stmt_slot(node, 2u)] = first_descendant_with_production(node, PROD_IF_BLOCK);
    hir_stmt_record[stmt_slot(node, 3u)] = first_descendant_with_production(node, PROD_ELSE_BLOCK);
}

void publish_while(uint node)
{
    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_WHILE;
    hir_stmt_record[stmt_slot(node, 1u)] = first_descendant_with_production(node, PROD_EXPR);
    hir_stmt_record[stmt_slot(node, 2u)] = first_descendant_with_production(node, PROD_BLOCK);
    hir_stmt_record[stmt_slot(node, 3u)] = INVALID;
}

void publish_const(uint node)
{
    uint value_node = INVALID;
    uint operand_node = INVALID;
    uint value_token = INVALID;
    uint type_node = valid_child_or_invalid(node);
    uint value_expr = valid_sibling_or_invalid(type_node);
    simple_value_node_in(value_expr, value_node, operand_node, value_token);

    hir_stmt_record[stmt_slot(node, 0u)] = STMT_RECORD_KIND_CONST;
    hir_stmt_record[stmt_slot(node, 1u)] = hir_token_pos[node] == INVALID ? INVALID
                                                                          : hir_token_pos[node] + 1u;
    hir_stmt_record[stmt_slot(node, 2u)] = value_node;
    hir_stmt_record[stmt_slot(node, 3u)] = operand_node;
}

void publish_assignment(uint node)
{
    uint assign_tail = first_descendant_assignment_tail(node);
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
    uint i = linear_thread_id(dtid);
    if (i >= gHirStmt.n)
        return;

    clear_record(i);
    if (!valid_node(i))
        return;

    uint prod = node_kind[i];
    if (prod == PROD_LET_STMT)
        publish_let(i);
    else if (prod == PROD_RETURN_STMT)
        publish_return(i);
    else if (prod == PROD_IF_STMT)
        publish_if(i);
    else if (prod == PROD_WHILE_STMT)
        publish_while(i);
    else if (prod == PROD_CONST)
        publish_const(i);
    else if (prod == PROD_EXPR_STMT)
        publish_assignment(i);
}
