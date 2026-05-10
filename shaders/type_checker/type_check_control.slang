struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct TokenIn
{
    uint kind;
    uint start;
    uint len;
};

StructuredBuffer<TokenIn> token_words;
StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> visible_type;
StructuredBuffer<int> loop_depth;

// Shared with type_check_tokens: [0] ok, [1] first error token, [2] error code, [3] detail.
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_COND_TYPE = 5u;
static const uint ERR_BAD_HIR = 6u;
static const uint ERR_LOOP_CONTROL = 7u;

static const uint HIR_BREAK_STMT = 12u;
static const uint HIR_CONTINUE_STMT = 13u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_STAR = 7u;
static const uint TK_SLASH = 9u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_NOT = 19u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PERCENT = 41u;
static const uint TK_CARET = 42u;
static const uint TK_SHL = 43u;
static const uint TK_SHR = 44u;
static const uint TK_TILDE = 45u;
static const uint TK_INFIX_PLUS = 59u;
static const uint TK_INFIX_MINUS = 61u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_INC = 56u;
static const uint TK_DEC = 57u;
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_FN = 67u;
static const uint TK_WHILE = 72u;
static const uint TK_BREAK = 73u;
static const uint TK_CONTINUE = 74u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;

static const uint BLOCK_OWNER_NONE = 0u;
static const uint BLOCK_OWNER_WHILE = 1u;
static const uint BLOCK_OWNER_FN = 2u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;
static const uint TY_STRUCT_BASE = 4096u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint visible_type_for(uint i)
{
    return i < active_token_count() ? visible_type[i] : TY_UNKNOWN;
}

bool is_array_type(uint ty)
{
    return ty >= TY_ARRAY_BASE && ty < TY_STRUCT_BASE;
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

bool is_open_block_token(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_block_token(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

uint block_owner(uint open_i)
{
    if (token_kind(open_i) == TK_IF_LBRACE)
        return BLOCK_OWNER_NONE;

    uint paren_depth = 0u;
    uint j = open_i;
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_GROUP_RPAREN || kind == TK_RPAREN || kind == TK_CALL_RPAREN)
        {
            paren_depth += 1u;
        }
        else if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_CALL_LPAREN)
        {
            if (paren_depth > 0u)
                paren_depth -= 1u;
        }

        if (paren_depth != 0u)
            continue;
        if (kind == TK_WHILE)
            return BLOCK_OWNER_WHILE;
        if (kind == TK_FN)
            return BLOCK_OWNER_FN;
        if (kind == TK_SEMICOLON || is_open_block_token(kind) || is_close_block_token(kind))
            return BLOCK_OWNER_NONE;
    }
    return BLOCK_OWNER_NONE;
}

bool inside_while_body(uint pos)
{
    uint block_depth = 0u;
    uint j = pos;
    for (uint guard = 0u; guard < 512u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (is_close_block_token(kind))
        {
            block_depth += 1u;
            continue;
        }
        if (!is_open_block_token(kind))
            continue;

        if (block_depth > 0u)
        {
            block_depth -= 1u;
            continue;
        }

        uint owner = block_owner(j);
        if (owner == BLOCK_OWNER_WHILE)
            return true;
        if (owner == BLOCK_OWNER_FN)
            return false;
    }
    return false;
}

void check_loop_control(uint pos, uint want)
{
    if (token_kind(pos) != want)
    {
        record_error(pos, ERR_BAD_HIR, want);
        return;
    }
    if (active_hir_node_count() != 0u)
    {
        if (pos >= active_token_count() || loop_depth[pos] <= 0)
            record_error(pos, ERR_LOOP_CONTROL, want);
        return;
    }
    if (!inside_while_body(pos))
        record_error(pos, ERR_LOOP_CONTROL, want);
}

bool postfix_incdec_lvalue(uint i)
{
    if (i == 0u)
        return false;
    uint prev = token_kind(i - 1u);
    return prev == TK_IDENT || prev == TK_INDEX_RBRACKET;
}

bool prefix_incdec_lvalue(uint i)
{
    uint n_active = active_token_count();
    if (i + 1u >= n_active)
        return false;
    if (token_kind(i + 1u) != TK_IDENT)
        return false;
    return i + 2u >= n_active || token_kind(i + 2u) != TK_CALL_LPAREN;
}

void check_incdec_lvalue(uint i)
{
    if (!prefix_incdec_lvalue(i) && !postfix_incdec_lvalue(i))
        record_error(i, ERR_ASSIGN_MISMATCH, token_kind(i));
}

uint unary_operand_token(uint i)
{
    uint n_active = active_token_count();
    uint cur = i + 1u;
    for (uint guard = 0u; guard < 16u && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_PREFIX_PLUS || kind == TK_PREFIX_MINUS ||
            kind == TK_NOT || kind == TK_TILDE)
        {
            cur += 1u;
            continue;
        }
        return cur;
    }
    return INVALID;
}

void check_unary_operand(uint i, uint op)
{
    uint operand_i = unary_operand_token(i);
    if (operand_i == INVALID)
        return;

    uint operand = token_kind(operand_i);
    if (op == TK_NOT)
    {
        if (operand == TK_STRING || operand == TK_ARRAY_LBRACKET)
            record_error(i, ERR_COND_TYPE, operand);
    }
    else if (op == TK_TILDE)
    {
        if (operand == TK_STRING || operand == TK_FLOAT || operand == TK_ARRAY_LBRACKET)
            record_error(i, ERR_ASSIGN_MISMATCH, operand);
    }
}

bool is_integer_binary_operator(uint op)
{
    return op == TK_PERCENT || op == TK_CARET || op == TK_SHL || op == TK_SHR;
}

bool is_numeric_binary_operator(uint op)
{
    return op == TK_INFIX_PLUS || op == TK_INFIX_MINUS || op == TK_STAR || op == TK_SLASH ||
           is_integer_binary_operator(op);
}

bool is_checked_binary_operator(uint op)
{
    return is_numeric_binary_operator(op) || op == TK_LT || op == TK_GT || op == TK_LE ||
           op == TK_GE || op == TK_EQEQ || op == TK_NOT_EQUAL || op == TK_ANDAND ||
           op == TK_OROR;
}

uint binary_left_operand_token(uint i)
{
    if (i == 0u)
        return INVALID;

    uint cur = i - 1u;
    if (token_kind(cur) != TK_GROUP_RPAREN)
        return cur;

    uint depth = 0u;
    uint j = cur + 1u;
    for (uint guard = 0u; guard < 32u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind == TK_GROUP_RPAREN)
        {
            depth += 1u;
            continue;
        }
        if (kind == TK_GROUP_LPAREN)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u && j + 1u < i)
                return j + 1u;
        }
    }
    return cur;
}

bool binary_operand_rejected(uint operand, uint op)
{
    if (operand == TK_ARRAY_LBRACKET || operand == TK_ARRAY_RBRACKET)
        return true;
    if (operand == TK_STRING)
        return true;
    if ((is_numeric_binary_operator(op) || op == TK_LT || op == TK_GT || op == TK_LE ||
         op == TK_GE) &&
        (operand == TK_TRUE || operand == TK_FALSE))
        return true;
    if (is_integer_binary_operator(op) && operand == TK_FLOAT)
        return true;
    return false;
}

void check_binary_operands(uint i, uint op)
{
    uint left_i = binary_left_operand_token(i);
    uint right_i = unary_operand_token(i);
    if (left_i != INVALID && binary_operand_rejected(token_kind(left_i), op))
    {
        record_error(left_i, ERR_ASSIGN_MISMATCH, op);
        return;
    }
    if (right_i != INVALID && binary_operand_rejected(token_kind(right_i), op))
        record_error(right_i, ERR_ASSIGN_MISMATCH, op);
}

bool assignable_to_int(uint ty)
{
    return ty == TY_UNKNOWN || ty == TY_INT || ty == TY_UINT || ty == TY_CHAR;
}

uint simple_index_expr_type(uint open_i)
{
    uint operand_i = unary_operand_token(open_i);
    if (operand_i == INVALID)
        return TY_UNKNOWN;

    uint kind = token_kind(operand_i);
    if (kind == TK_TRUE || kind == TK_FALSE)
        return TY_BOOL;
    if (kind == TK_INT)
        return TY_INT;
    if (kind == TK_FLOAT)
        return TY_FLOAT;
    if (kind == TK_STRING)
        return TY_STRING;
    if (kind == TK_CHAR)
        return TY_CHAR;
    if (kind == TK_ARRAY_LBRACKET)
        return TY_ARRAY_BASE + TY_UNKNOWN;
    if (kind == TK_IDENT)
        return visible_type_for(operand_i);
    return TY_UNKNOWN;
}

void check_index_operands(uint open_i)
{
    if (open_i == 0u)
        return;

    uint base_i = open_i - 1u;
    if (token_kind(base_i) == TK_IDENT)
    {
        uint base_ty = visible_type_for(base_i);
        if (base_ty != TY_UNKNOWN && !is_array_type(base_ty))
        {
            record_error(open_i, ERR_ASSIGN_MISMATCH, base_ty);
            return;
        }
    }

    uint idx_ty = simple_index_expr_type(open_i);
    if (!assignable_to_int(idx_ty))
        record_error(open_i + 1u, ERR_ASSIGN_MISMATCH, TY_INT * 256u + idx_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    uint n_hir = active_hir_node_count();
    if (i < n_hir)
    {
        uint kind = hir_kind[i];
        if (kind == HIR_BREAK_STMT || kind == HIR_CONTINUE_STMT)
        {
            uint pos = hir_token_pos[i];
            if (pos == INVALID || pos >= active_token_count())
                record_error(active_token_count(), ERR_BAD_HIR, pos);
            else
                check_loop_control(pos, kind == HIR_BREAK_STMT ? TK_BREAK : TK_CONTINUE);
        }
    }

    if (i < active_token_count())
    {
        uint token = token_kind(i);
        if (token == TK_INC || token == TK_DEC)
            check_incdec_lvalue(i);
        else if (token == TK_NOT || token == TK_TILDE)
            check_unary_operand(i, token);
        else if (is_checked_binary_operator(token))
            check_binary_operands(i, token);
        else if (token == TK_INDEX_LBRACKET)
            check_index_operands(i);
    }

    if (n_hir != 0u || i >= active_token_count())
        return;

    uint kind = token_kind(i);
    if (kind == TK_BREAK || kind == TK_CONTINUE)
        check_loop_control(i, kind);
}
