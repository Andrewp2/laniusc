// HIR control and scalar expression validation.
//
// This pass consumes parser-owned HIR expression records and type fact buffers.
// It intentionally does not inspect token spelling, token neighborhoods, source
// bytes, helper names, or function-body shapes.

import generated_parse_production_ids;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> hir_nearest_loop_node;
struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_LOOP_CONTROL = 7u;

static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;
static const uint HIR_INDEX_EXPR = 20u;

static const uint TK_STAR = 7u;
static const uint TK_SLASH = 9u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_PIPE = 26u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PERCENT = 41u;
static const uint TK_CARET = 42u;
static const uint TK_SHL = 43u;
static const uint TK_SHR = 44u;
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_INFIX_MINUS = 61u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
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
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_GENERIC_BASE = 8192u;

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot];
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? expr_record_slot(node, slot) : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_left(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_LEFT);
}

uint expr_right(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_RIGHT);
}

uint expr_value_token(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
}

uint expr_result_root(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    if (valid_node(root))
        return root;
    return node;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

uint visible_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint ty = visible_type[token_i];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token_i];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token_i];
}

uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_TRUE || prod == PROD_FALSE)
        return TY_BOOL;
    if (prod == PROD_INT)
        return TY_INT;
    if (prod == PROD_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_STRING)
        return TY_STRING;
    if (prod == PROD_CHAR)
        return TY_CHAR;
    return TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    node = expr_result_root(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint literal_ty = scalar_type_for_literal_prod(node_kind[node]);
    if (literal_ty != TY_UNKNOWN)
        return literal_ty;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        return visible_type_for_token(token_i);
    }
    if (form == HIR_EXPR_INDEX)
    {
        uint token_i = hir_token_pos[node];
        return valid_token(token_i) ? call_return_type[token_i] : TY_UNKNOWN;
    }

    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

uint expr_error_token(uint node)
{
    node = expr_result_root(node);
    if (!valid_node(node))
        return 0u;

    uint token_i = expr_value_token(node);
    if (valid_token(token_i))
        return token_i;

    token_i = hir_token_pos[node];
    return valid_token(token_i) ? token_i : 0u;
}

bool is_array_type(uint ty)
{
    return (ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE) ||
           ty >= TY_ARRAY_BASE + TY_GENERIC_BASE;
}

bool assignable_to_int(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT || ty == TY_CHAR;
}

bool numeric_operand_ok(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT ||
           ty == TY_FLOAT || ty == TY_CHAR;
}

bool integer_operand_ok(uint ty)
{
    return assignable_to_int(ty);
}

bool equality_operand_ok(uint ty)
{
    return ty == TY_UNKNOWN || (!is_array_type(ty) && ty != TY_STRING);
}

bool is_integer_binary_form(uint form)
{
    return form == HIR_EXPR_MOD ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR;
}

bool is_numeric_binary_form(uint form)
{
    return form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE;
}

bool is_equality_binary_form(uint form)
{
    return form == HIR_EXPR_EQ || form == HIR_EXPR_NE;
}

bool binary_operand_ok(uint form, uint ty)
{
    if (is_integer_binary_form(form))
        return integer_operand_ok(ty);
    if (is_numeric_binary_form(form))
        return numeric_operand_ok(ty);
    if (is_equality_binary_form(form))
        return equality_operand_ok(ty);
    return true;
}

uint binary_operator_token(uint right)
{
    if (!valid_node(right))
        return INVALID;
    uint right_token = hir_token_pos[right];
    if (!valid_token(right_token) || right_token == 0u)
        return INVALID;
    return right_token - 1u;
}

bool binary_operator_matches_form(uint form, uint operator_kind)
{
    if (form == HIR_EXPR_OR)
        return operator_kind == TK_OROR;
    if (form == HIR_EXPR_AND)
        return operator_kind == TK_ANDAND;
    if (form == HIR_EXPR_BIT_OR)
        return operator_kind == TK_PIPE;
    if (form == HIR_EXPR_BIT_XOR)
        return operator_kind == TK_CARET;
    if (form == HIR_EXPR_BIT_AND)
        return operator_kind == TK_AMPERSAND;
    if (form == HIR_EXPR_EQ)
        return operator_kind == TK_EQEQ;
    if (form == HIR_EXPR_NE)
        return operator_kind == TK_NOT_EQUAL;
    if (form == HIR_EXPR_LT)
        return operator_kind == TK_LT;
    if (form == HIR_EXPR_GT)
        return operator_kind == TK_GT;
    if (form == HIR_EXPR_LE)
        return operator_kind == TK_LE;
    if (form == HIR_EXPR_GE)
        return operator_kind == TK_GE;
    if (form == HIR_EXPR_SHL)
        return operator_kind == TK_SHL;
    if (form == HIR_EXPR_SHR)
        return operator_kind == TK_SHR;
    if (form == HIR_EXPR_ADD)
        return operator_kind == TK_INFIX_PLUS;
    if (form == HIR_EXPR_SUB)
        return operator_kind == TK_INFIX_MINUS;
    if (form == HIR_EXPR_MUL)
        return operator_kind == TK_STAR;
    if (form == HIR_EXPR_DIV)
        return operator_kind == TK_SLASH;
    if (form == HIR_EXPR_MOD)
        return operator_kind == TK_PERCENT;
    return false;
}

bool binary_operator_is_value_expr(uint form, uint right)
{
    uint operator_token = binary_operator_token(right);
    if (!valid_token(operator_token))
        return false;
    return binary_operator_matches_form(form, token_words[operator_token].kind);
}

bool enclosed_by_different_same_start_result(uint node)
{
    if (!valid_node(node))
        return false;

    uint start = hir_token_pos[node];
    uint cursor = parent[node];
    [loop]
    for (uint depth = 0u; depth < 64u && valid_node(cursor); depth += 1u)
    {
        if (hir_token_pos[cursor] == start)
        {
            uint root = hir_expr_result_root_node[cursor];
            if (valid_node(root) && root != node)
                return true;
        }

        uint next = parent[cursor];
        if (next == cursor)
            break;
        cursor = next;
    }
    return false;
}

void validate_binary_expr_node(uint node)
{
    if (expr_result_root(node) != node)
        return;

    uint form = expr_form(node);
    if (!is_integer_binary_form(form) &&
        !is_numeric_binary_form(form) &&
        !is_equality_binary_form(form))
        return;
    if (enclosed_by_different_same_start_result(node))
        return;

    uint left = expr_left(node);
    uint right = expr_right(node);
    if (!binary_operator_is_value_expr(form, right))
        return;

    uint left_ty = direct_expr_record_type(left);
    if (!binary_operand_ok(form, left_ty))
    {
        record_error(expr_error_token(left), ERR_ASSIGN_MISMATCH, form);
        return;
    }

    uint right_ty = direct_expr_record_type(right);
    if (!binary_operand_ok(form, right_ty))
        record_error(expr_error_token(right), ERR_ASSIGN_MISMATCH, form);
}

void validate_index_expr_node(uint node)
{
    if (hir_kind[node] != HIR_INDEX_EXPR && expr_form(node) != HIR_EXPR_INDEX)
        return;

    uint base = expr_left(node);
    uint base_ty = direct_expr_record_type(base);
    if (base_ty != TY_UNKNOWN && !is_array_type(base_ty))
    {
        record_error(expr_error_token(node), ERR_ASSIGN_MISMATCH, base_ty);
        return;
    }

    uint index = expr_right(node);
    uint index_ty = direct_expr_record_type(index);
    if (!assignable_to_int(index_ty))
        record_error(expr_error_token(index), ERR_ASSIGN_MISMATCH, TY_INT * 256u + index_ty);
}

void validate_loop_control_node(uint node)
{
    uint kind = hir_kind[node];
    if (kind != HIR_BREAK_STMT && kind != HIR_CONTINUE_STMT)
        return;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
    {
        record_error(0u, ERR_BAD_HIR, kind);
        return;
    }
    if (!valid_node(hir_nearest_loop_node[node]))
        record_error(token_i, ERR_LOOP_CONTROL, kind);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = tid.x;
    if (!valid_node(node))
        return;

    validate_loop_control_node(node);
    validate_index_expr_node(node);
    validate_binary_expr_node(node);
}
