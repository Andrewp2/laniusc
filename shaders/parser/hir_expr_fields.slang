// Derive parser-owned expression metadata from production ids and tree links.
//
// This pass records expression forms and operand/value nodes so backend passes
// can consume HIR records instead of rediscovering operators from token shapes.

import generated_parse_production_ids;

struct Params
{
    uint n;
    uint uses_ll1;
};

ConstantBuffer<Params> gHirExpr;

StructuredBuffer<uint> ll1_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> prev_sibling;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_semantic_dense_node;
StructuredBuffer<uint> hir_semantic_count;

RWStructuredBuffer<uint> hir_expr_record;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
static const uint HIR_EXPR_NAME = 2u;
static const uint HIR_EXPR_INT = 3u;
static const uint HIR_EXPR_TRUE = 4u;
static const uint HIR_EXPR_FALSE = 5u;
static const uint HIR_EXPR_NOT = 6u;
static const uint HIR_EXPR_EQ = 7u;
static const uint HIR_EXPR_NE = 8u;
static const uint HIR_EXPR_LT = 9u;
static const uint HIR_EXPR_GT = 10u;
static const uint HIR_EXPR_LE = 11u;
static const uint HIR_EXPR_GE = 12u;
static const uint HIR_EXPR_NEG = 13u;
static const uint HIR_EXPR_ADD = 14u;
static const uint HIR_EXPR_SUB = 15u;
static const uint HIR_EXPR_MUL = 16u;
static const uint HIR_EXPR_AND = 17u;
static const uint HIR_EXPR_OR = 18u;
static const uint HIR_EXPR_MOD = 19u;
static const uint HIR_EXPR_DIV = 20u;
static const uint HIR_EXPR_BIT_OR = 21u;
static const uint HIR_EXPR_BIT_XOR = 22u;
static const uint HIR_EXPR_BIT_AND = 23u;
static const uint HIR_EXPR_SHL = 24u;
static const uint HIR_EXPR_SHR = 25u;
static const uint HIR_EXPR_INDEX = 26u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_node_count()
{
    return gHirExpr.uses_ll1 != 0u ? min(gHirExpr.n, ll1_status[5u]) : gHirExpr.n;
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

uint first_child_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint child = first_child[i];
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint next = next_sibling[i];
    return valid_node(next) ? next : INVALID;
}

uint previous_sibling_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint previous = prev_sibling[node];
    return valid_node(previous) && parent[previous] == parent[node] ?
        previous :
        INVALID;
}

uint parent_node(uint i)
{
    if (!valid_node(i))
        return INVALID;
    uint p = parent[i];
    return valid_node(p) ? p : INVALID;
}

bool is_forward_expr_production(uint prod)
{
    return prod == PROD_EXPR || prod == PROD_ASSIGN || prod == PROD_OREXPR ||
           prod == PROD_ANDEXPR || prod == PROD_BIT_OR || prod == PROD_BIT_XOR ||
           prod == PROD_BIT_AND || prod == PROD_SHIFT || prod == PROD_ADD ||
           prod == PROD_MUL || prod == PROD_BASE || prod == PROD_POSTFIX ||
           prod == PROD_GROUP;
}

bool is_layered_binary_expr_production(uint prod)
{
    return prod == PROD_OREXPR || prod == PROD_ANDEXPR || prod == PROD_BIT_OR ||
           prod == PROD_BIT_XOR || prod == PROD_BIT_AND || prod == PROD_EQUALITY ||
           prod == PROD_COMPARE || prod == PROD_SHIFT || prod == PROD_ADD ||
           prod == PROD_MUL;
}

uint binary_form_for_tail(uint prod)
{
    if (prod == PROD_OR_TAIL)
        return HIR_EXPR_OR;
    if (prod == PROD_AND_TAIL)
        return HIR_EXPR_AND;
    if (prod == PROD_BOR_TAIL)
        return HIR_EXPR_BIT_OR;
    if (prod == PROD_XOR_TAIL)
        return HIR_EXPR_BIT_XOR;
    if (prod == PROD_BAND_TAIL)
        return HIR_EXPR_BIT_AND;
    if (prod == PROD_EQ_TAIL)
        return HIR_EXPR_EQ;
    if (prod == PROD_NE_TAIL)
        return HIR_EXPR_NE;
    if (prod == PROD_LT_TAIL)
        return HIR_EXPR_LT;
    if (prod == PROD_GT_TAIL)
        return HIR_EXPR_GT;
    if (prod == PROD_LE_TAIL)
        return HIR_EXPR_LE;
    if (prod == PROD_GE_TAIL)
        return HIR_EXPR_GE;
    if (prod == PROD_SHL_TAIL)
        return HIR_EXPR_SHL;
    if (prod == PROD_SHR_TAIL)
        return HIR_EXPR_SHR;
    if (prod == PROD_ADD_TAIL)
        return HIR_EXPR_ADD;
    if (prod == PROD_SUB_TAIL)
        return HIR_EXPR_SUB;
    if (prod == PROD_MUL_TAIL)
        return HIR_EXPR_MUL;
    if (prod == PROD_DIV_TAIL)
        return HIR_EXPR_DIV;
    if (prod == PROD_MOD_TAIL)
        return HIR_EXPR_MOD;
    return HIR_EXPR_NONE;
}

uint end_production_for_expr_layer(uint prod)
{
    if (prod == PROD_OREXPR)
        return PROD_OR_END;
    if (prod == PROD_ANDEXPR)
        return PROD_AND_END;
    if (prod == PROD_BIT_OR)
        return PROD_BOR_END;
    if (prod == PROD_BIT_XOR)
        return PROD_XOR_END;
    if (prod == PROD_BIT_AND)
        return PROD_BAND_END;
    if (prod == PROD_EQUALITY)
        return PROD_EQ_END;
    if (prod == PROD_COMPARE)
        return PROD_COMPARE_END;
    if (prod == PROD_SHIFT)
        return PROD_SHIFT_END;
    if (prod == PROD_ADD)
        return PROD_ADD_END;
    if (prod == PROD_MUL)
        return PROD_MUL_END;
    return HIR_EXPR_NONE;
}

uint end_production_for_tail(uint prod)
{
    if (prod == PROD_OR_TAIL)
        return PROD_OR_END;
    if (prod == PROD_AND_TAIL)
        return PROD_AND_END;
    if (prod == PROD_BOR_TAIL)
        return PROD_BOR_END;
    if (prod == PROD_XOR_TAIL)
        return PROD_XOR_END;
    if (prod == PROD_BAND_TAIL)
        return PROD_BAND_END;
    if (prod == PROD_EQ_TAIL || prod == PROD_NE_TAIL)
        return PROD_EQ_END;
    if (prod == PROD_LT_TAIL || prod == PROD_GT_TAIL || prod == PROD_LE_TAIL ||
        prod == PROD_GE_TAIL)
        return PROD_COMPARE_END;
    if (prod == PROD_SHL_TAIL || prod == PROD_SHR_TAIL)
        return PROD_SHIFT_END;
    if (prod == PROD_ADD_TAIL || prod == PROD_SUB_TAIL)
        return PROD_ADD_END;
    if (prod == PROD_MUL_TAIL || prod == PROD_DIV_TAIL || prod == PROD_MOD_TAIL)
        return PROD_MUL_END;
    return HIR_EXPR_NONE;
}

bool is_expr_end_production(uint prod)
{
    return prod == PROD_ASSIGN_END ||
           prod == PROD_OR_END ||
           prod == PROD_AND_END ||
           prod == PROD_BOR_END ||
           prod == PROD_XOR_END ||
           prod == PROD_BAND_END ||
           prod == PROD_EQ_END ||
           prod == PROD_COMPARE_END ||
           prod == PROD_SHIFT_END ||
           prod == PROD_ADD_END ||
           prod == PROD_MUL_END ||
           prod == PROD_POSTFIX_END;
}

bool is_binary_tail_production(uint prod)
{
    return binary_form_for_tail(prod) != HIR_EXPR_NONE;
}

bool is_value_postfix_production(uint prod)
{
    return prod == PROD_POSTFIX_CALL ||
           prod == PROD_POSTFIX_INDEX ||
           prod == PROD_POSTFIX_MEMBER ||
           prod == PROD_POSTFIX_INC ||
           prod == PROD_POSTFIX_DEC;
}

uint tail_continuation(uint tail)
{
    uint right = first_child_node(tail);
    if (!valid_node(right))
        return INVALID;
    return next_sibling_node(right);
}

uint rightmost_leaf_parent(uint node)
{
    if (!valid_node(node))
        return INVALID;

    uint end = subtree_end[node];
    if (end <= node || end > active_node_count())
        return INVALID;

    uint leaf = end - 1u;
    if (!valid_node(leaf))
        return INVALID;

    return parent_node(leaf);
}

uint binary_tail_chain_result(uint tail)
{
    if (!valid_node(tail) || !is_binary_tail_production(node_kind[tail]))
        return INVALID;

    uint result = rightmost_leaf_parent(tail);
    if (!valid_node(result) || !is_binary_tail_production(node_kind[result]))
        return INVALID;

    uint continuation = tail_continuation(result);
    uint expected_end = end_production_for_tail(node_kind[result]);
    if (!valid_node(continuation) || node_kind[continuation] != expected_end)
        return INVALID;

    return result;
}

void write_expr_record(uint i, uint form, uint left, uint right, uint value_token)
{
    uint base = i * HIR_EXPR_RECORD_STRIDE;
    hir_expr_record[base + HIR_EXPR_RECORD_FORM] = form;
    hir_expr_record[base + HIR_EXPR_RECORD_LEFT] = left;
    hir_expr_record[base + HIR_EXPR_RECORD_RIGHT] = right;
    hir_expr_record[base + HIR_EXPR_RECORD_VALUE_TOKEN] = value_token;
}

void clear_expr(uint i)
{
    write_expr_record(i, HIR_EXPR_NONE, INVALID, INVALID, INVALID);
}

void publish_forward(uint i, uint child)
{
    if (!valid_node(child))
        return;
    write_expr_record(i, HIR_EXPR_FORWARD, child, INVALID, INVALID);
}

bool publish_binary_from_tail(uint i, uint left, uint tail)
{
    if (!valid_node(left) || !valid_node(tail))
        return false;

    uint form = binary_form_for_tail(node_kind[tail]);
    if (form == HIR_EXPR_NONE)
        return false;

    uint right = first_child_node(tail);
    if (!valid_node(right))
        return false;
    uint continuation = next_sibling_node(right);
    uint expected_end = end_production_for_tail(node_kind[tail]);
    if (!valid_node(continuation) || node_kind[continuation] != expected_end)
        return false;

    write_expr_record(i, form, left, right, INVALID);
    return true;
}

bool publish_binary_tail_expr(uint i)
{
    uint form = binary_form_for_tail(node_kind[i]);
    if (form == HIR_EXPR_NONE)
        return false;

    uint p = parent_node(i);
    uint left = INVALID;
    if (valid_node(p) && is_layered_binary_expr_production(node_kind[p]))
        left = first_child_node(p);
    else if (valid_node(p) && is_binary_tail_production(node_kind[p]))
        left = p;
    if (!valid_node(left))
        return false;

    uint right = first_child_node(i);
    if (!valid_node(right))
        return false;

    uint continuation = tail_continuation(i);
    uint expected_end = end_production_for_tail(node_kind[i]);
    bool valid_continuation =
        valid_node(continuation) &&
        (node_kind[continuation] == expected_end ||
         is_binary_tail_production(node_kind[continuation]));
    if (!valid_continuation)
        return false;

    write_expr_record(i, form, left, right, INVALID);
    return true;
}

uint postfix_value_node(uint postfix)
{
    if (!valid_node(postfix) || node_kind[postfix] != PROD_POSTFIX)
        return INVALID;

    uint final_operator = rightmost_leaf_parent(postfix);
    if (valid_node(final_operator) &&
        is_value_postfix_production(node_kind[final_operator]))
        return final_operator;

    return first_child_node(postfix);
}

uint index_base_node(uint index_node)
{
    uint previous = previous_sibling_node(index_node);
    if (valid_node(previous))
        return previous;

    uint p = parent_node(index_node);
    return valid_node(p) && node_kind[p] == PROD_POSTFIX ? p : INVALID;
}

void publish_expr(uint i)
{
    uint prod = node_kind[i];
    uint child = first_child_node(i);

    if (prod == PROD_IDENT || prod == PROD_SELF_VALUE ||
        prod == PROD_PATH)
    {
        write_expr_record(i, HIR_EXPR_NAME, INVALID, INVALID, hir_token_pos[i]);
        return;
    }
    if (prod == PROD_INT)
    {
        write_expr_record(i, HIR_EXPR_INT, INVALID, INVALID, hir_token_pos[i]);
        return;
    }
    if (prod == PROD_TRUE)
    {
        write_expr_record(i, HIR_EXPR_TRUE, INVALID, INVALID, hir_token_pos[i]);
        return;
    }
    if (prod == PROD_FALSE)
    {
        write_expr_record(i, HIR_EXPR_FALSE, INVALID, INVALID, hir_token_pos[i]);
        return;
    }
    if (prod == PROD_NOT)
    {
        write_expr_record(i, HIR_EXPR_NOT, child, INVALID, INVALID);
        return;
    }
    if (prod == PROD_NEG)
    {
        write_expr_record(i, HIR_EXPR_NEG, child, INVALID, INVALID);
        return;
    }

    if (is_binary_tail_production(prod))
    {
        publish_binary_tail_expr(i);
        return;
    }

    if (prod == PROD_POSTFIX)
    {
        publish_forward(i, postfix_value_node(i));
        return;
    }

    if (prod == PROD_POSTFIX_INDEX)
    {
        write_expr_record(i, HIR_EXPR_INDEX, index_base_node(i), child, INVALID);
        return;
    }

    if (is_layered_binary_expr_production(prod))
    {
        uint tail = next_sibling_node(child);
        uint tail_result = binary_tail_chain_result(tail);
        if (valid_node(tail_result))
        {
            publish_forward(i, tail_result);
            return;
        }
        if (valid_node(tail) &&
            (node_kind[tail] == end_production_for_expr_layer(prod) ||
             is_expr_end_production(node_kind[tail])))
            publish_forward(i, child);
        return;
    }

    if (is_forward_expr_production(prod))
        publish_forward(i, child);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint row = linear_thread_id(dtid);
    uint i = semantic_row_node(row);
    if (i == INVALID)
        return;

    clear_expr(i);
    publish_expr(i);
}
