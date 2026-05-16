// HIR condition validation.
//
// This pass consumes parser-owned statement records and attributed expression
// records. It intentionally handles simple single-value conditions here and
// leaves compound expressions to dedicated expression-attribution passes rather
// than scanning condition token ranges.

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_IF = 3u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

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

static const uint PROD_LITERAL_INT = 159u;
static const uint PROD_LITERAL_FLOAT = 160u;
static const uint PROD_LITERAL_STRING = 161u;
static const uint PROD_LITERAL_CHAR = 162u;
static const uint PROD_LITERAL_TRUE = 169u;
static const uint PROD_LITERAL_FALSE = 170u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

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

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    uint child = valid_node(node) ? first_child[node] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    uint sibling = valid_node(node) ? next_sibling[node] : INVALID;
    return valid_node(sibling) ? sibling : INVALID;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_record_slot(uint node, uint slot)
{
    return hir_expr_record[node * EXPR_RECORD_STRIDE + slot];
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_left(node);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_LITERAL_INT)
        return TY_INT;
    if (prod == PROD_LITERAL_TRUE || prod == PROD_LITERAL_FALSE)
        return TY_BOOL;
    if (prod == PROD_LITERAL_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_LITERAL_STRING)
        return TY_STRING;
    if (prod == PROD_LITERAL_CHAR)
        return TY_CHAR;
    return TY_UNKNOWN;
}

uint direct_node_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint lit = scalar_type_for_literal_prod(node_kind[node]);
    if (lit != TY_UNKNOWN)
        return lit;

    uint token_i = hir_token_pos[node];
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    if (hir_kind[node] == HIR_NAME_EXPR)
    {
        uint visible_ty = visible_type[token_i];
        return visible_ty != TY_UNKNOWN ? visible_ty : call_return_type[token_i];
    }

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = token_i + 1u;
        if (!valid_token(member_token))
            return TY_UNKNOWN;
        uint visible_ty = visible_type[member_token];
        return visible_ty != TY_UNKNOWN ? visible_ty : call_return_type[member_token];
    }

    if (hir_kind[node] == HIR_CALL_EXPR && token_i > 0u)
        return call_return_type[token_i - 1u];

    return TY_UNKNOWN;
}

uint direct_expr_record_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        if (!valid_token(token_i))
            return TY_UNKNOWN;

        uint visible_ty = visible_type[token_i];
        return visible_ty != TY_UNKNOWN ? visible_ty : call_return_type[token_i];
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

uint next_descendant_node(uint root, uint cur)
{
    uint child = first_child_node(cur);
    if (child != INVALID)
        return child;

    uint node = cur;
    [loop]
    for (uint guard = 0u; guard < 96u && node != INVALID; guard += 1u)
    {
        if (node == root)
            return INVALID;
        uint sibling = next_sibling_node(node);
        if (sibling != INVALID)
            return sibling;
        node = parent_node(node);
    }
    return INVALID;
}

uint single_value_condition_type(uint expr_node)
{
    if (!valid_node(expr_node))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(expr_node);
    if (record_ty != TY_UNKNOWN)
        return record_ty;

    uint found = TY_UNKNOWN;
    uint count = 0u;
    uint node = expr_node;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (hir_kind[node] == HIR_CALL_EXPR || hir_kind[node] == HIR_MEMBER_EXPR)
            return TY_UNKNOWN;

        uint ty = direct_node_type(node);
        if (ty == TY_UNKNOWN)
        {
            node = next_descendant_node(expr_node, node);
            continue;
        }
        if (found != TY_UNKNOWN && found != ty)
            return TY_UNKNOWN;
        found = ty;
        count += 1u;
        node = next_descendant_node(expr_node, node);
    }
    return count == 1u ? found : TY_UNKNOWN;
}

void validate_if_node(uint node)
{
    if (hir_stmt_record[stmt_slot(node, 0u)] != STMT_RECORD_KIND_IF)
        return;

    uint expr_node = hir_stmt_record[stmt_slot(node, 1u)];
    uint ty = single_value_condition_type(expr_node);
    if (ty != TY_UNKNOWN && ty != TY_BOOL)
    {
        uint token_i = valid_node(expr_node) ? hir_token_pos[expr_node] : hir_token_pos[node];
        record_error(token_i, ERR_ASSIGN_MISMATCH, TY_BOOL * 256u + ty);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    validate_if_node(node);
}
