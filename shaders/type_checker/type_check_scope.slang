import utils;

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
ByteAddressBuffer source_bytes;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> call_fn_index;
StructuredBuffer<uint> call_return_type;

// Shared with type_check_tokens: [0] ok, [1] first error token, [2] error code, [3] detail.
RWStructuredBuffer<uint> status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;

static const uint ERR_UNRESOLVED_IDENT = 2u;
static const uint ERR_BAD_HIR = 6u;

static const uint HIR_NAME_EXPR = 22u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_VOID = 1u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_ARRAY_BASE = 128u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_ASSIGN = 8u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LE = 14u;
static const uint TK_GE = 15u;
static const uint TK_EQEQ = 16u;
static const uint TK_ANDAND = 17u;
static const uint TK_OROR = 18u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_DOT = 35u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_PREFIX_MINUS = 60u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARROW = 75u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_LET_ASSIGN = 81u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool has_token_aligned_hir()
{
    return active_hir_node_count() == active_token_count() + 1u;
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint token_start(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].start : 0u;
}

uint token_len(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].len : 0u;
}

uint source_at(uint start, uint delta)
{
    uint idx = start + delta;
    return idx < gParams.source_len ? load_byte_at(source_bytes, idx) : 0u;
}

bool span5(uint start, uint len, uint a, uint b, uint c, uint d, uint e)
{
    return len == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool span2(uint start, uint len, uint a, uint b)
{
    return len == 2u && source_at(start, 0u) == a && source_at(start, 1u) == b;
}

bool span3(uint start, uint len, uint a, uint b, uint c)
{
    return len == 3u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c;
}

bool span4(uint start, uint len, uint a, uint b, uint c, uint d)
{
    return len == 4u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d;
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    return span5(token_start(i), token_len(i), a, b, c, d, e);
}

bool is_print_name(uint i)
{
    return token_text_eq5(i, 112u, 114u, 105u, 110u, 116u);
}

bool is_assert_name(uint i)
{
    uint start = token_start(i);
    return token_len(i) == 6u && source_at(start, 0u) == 97u &&
           source_at(start, 1u) == 115u && source_at(start, 2u) == 115u &&
           source_at(start, 3u) == 101u && source_at(start, 4u) == 114u &&
           source_at(start, 5u) == 116u;
}

bool is_builtin_name(uint i)
{
    return is_print_name(i) || is_assert_name(i);
}

bool token_text_eq(uint i, uint a, uint b, uint c, uint d)
{
    return span4(token_start(i), token_len(i), a, b, c, d);
}

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
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

uint primitive_type_code(uint type_i)
{
    uint start = token_start(type_i);
    uint len = token_len(type_i);
    if (span2(start, len, 105u, 56u) || span3(start, len, 105u, 49u, 54u) ||
        span3(start, len, 105u, 51u, 50u) || span3(start, len, 105u, 54u, 52u) ||
        span5(start, len, 105u, 115u, 105u, 122u, 101u))
        return TY_INT;

    if (span2(start, len, 117u, 56u) || span3(start, len, 117u, 49u, 54u) ||
        span3(start, len, 117u, 51u, 50u) || span3(start, len, 117u, 54u, 52u) ||
        span5(start, len, 117u, 115u, 105u, 122u, 101u))
        return TY_UINT;

    if (span3(start, len, 102u, 51u, 50u) || span3(start, len, 102u, 54u, 52u))
        return TY_FLOAT;
    if (span4(start, len, 98u, 111u, 111u, 108u))
        return TY_BOOL;
    if (span4(start, len, 99u, 104u, 97u, 114u))
        return TY_CHAR;

    return TY_UNKNOWN;
}

uint type_code_for_type_expr(uint type_i)
{
    uint cur = type_i;
    uint array_depth = 0u;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind != TK_TYPE_ARRAY_LBRACKET && kind != TK_ARRAY_LBRACKET && kind != TK_LBRACKET)
            break;
        array_depth += 1u;
        cur += 1u;
    }

    uint kind = token_kind(cur);
    uint elem = TY_UNKNOWN;
    if (kind == TK_TYPE_IDENT || kind == TK_IDENT)
        elem = primitive_type_code(cur);

    if (elem == TY_UNKNOWN)
        return TY_UNKNOWN;
    return array_depth == 0u ? elem : TY_ARRAY_BASE + elem;
}

bool is_bool_result_operator(uint kind)
{
    return kind == TK_LT || kind == TK_GT || kind == TK_LE || kind == TK_GE || kind == TK_EQEQ ||
           kind == TK_NOT_EQUAL || kind == TK_ANDAND || kind == TK_OROR;
}

uint find_stmt_semicolon(uint start_i)
{
    uint bracket_depth = 0u;
    uint n_active = active_token_count();
    for (uint j = start_i + 1u; j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
            kind == TK_TYPE_ARRAY_LBRACKET)
        {
            bracket_depth += 1u;
        }
        else if (kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
                 kind == TK_TYPE_ARRAY_RBRACKET)
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
        }
        else if (kind == TK_SEMICOLON && bracket_depth == 0u)
        {
            return j;
        }
    }
    return INVALID;
}

uint let_decl_semicolon(uint decl_i)
{
    if (has_token_aligned_hir() && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET &&
        decl_i < active_hir_node_count())
    {
        uint end_i = hir_token_end[decl_i];
        if (end_i != INVALID && end_i > decl_i)
        {
            uint semi = end_i - 1u;
            if (token_kind(semi) == TK_SEMICOLON)
                return semi;
        }
    }
    return find_stmt_semicolon(decl_i);
}

uint find_let_assign(uint let_ident_i, uint semi_i)
{
    uint n_active = active_token_count();
    for (uint j = let_ident_i + 1u; j < semi_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LET_ASSIGN || kind == TK_ASSIGN)
            return j;
    }
    return INVALID;
}

bool is_const_decl_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_CONST;
}

uint find_function_return_type(uint fn_i)
{
    return fn_i < active_token_count() ? call_return_type[fn_i] : TY_UNKNOWN;
}

uint find_named_function_return(uint name_i)
{
    return name_i < active_token_count() ? call_return_type[name_i] : TY_UNKNOWN;
}

uint literal_head_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint n_active = active_token_count();
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n_active; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (kind == TK_GROUP_LPAREN || kind == TK_LPAREN || kind == TK_PREFIX_PLUS ||
            kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }

        if (kind == TK_INT)
            return TY_INT;
        if (kind == TK_TRUE || kind == TK_FALSE)
            return TY_BOOL;
        if (kind == TK_FLOAT)
            return TY_FLOAT;
        if (kind == TK_STRING)
            return TY_STRING;
        if (kind == TK_CHAR)
            return TY_CHAR;
        if (kind == TK_ARRAY_LBRACKET || kind == TK_LBRACKET)
        {
            uint elem_cur = cur + 1u;
            for (uint elem_guard = 0u;
                 elem_guard < 16u && elem_cur < limit_i && elem_cur < n_active;
                 elem_guard += 1u)
            {
                uint elem_kind = token_kind(elem_cur);
                if (elem_kind == TK_GROUP_LPAREN || elem_kind == TK_LPAREN ||
                    elem_kind == TK_PREFIX_PLUS || elem_kind == TK_PREFIX_MINUS)
                {
                    elem_cur += 1u;
                    continue;
                }
                if (elem_kind == TK_INT)
                    return TY_ARRAY_BASE + TY_INT;
                if (elem_kind == TK_TRUE || elem_kind == TK_FALSE)
                    return TY_ARRAY_BASE + TY_BOOL;
                if (elem_kind == TK_FLOAT)
                    return TY_ARRAY_BASE + TY_FLOAT;
                if (elem_kind == TK_STRING)
                    return TY_ARRAY_BASE + TY_STRING;
                if (elem_kind == TK_CHAR)
                    return TY_ARRAY_BASE + TY_CHAR;
                break;
            }
            return TY_UNKNOWN;
        }
        return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint scanned_expr_result_type(uint expr_i, uint limit_i)
{
    bool saw_float = false;
    uint n_active = active_token_count();
    for (uint j = expr_i; j < limit_i && j < n_active; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_bool_result_operator(kind))
            return TY_BOOL;
        if (kind == TK_FLOAT)
            saw_float = true;
    }
    return saw_float ? TY_FLOAT : TY_UNKNOWN;
}

bool find_named_function(uint name_i)
{
    return name_i < active_token_count() && call_return_type[name_i] != TY_UNKNOWN;
}

uint resolved_visible_decl(uint ident_i)
{
    if (ident_i >= active_token_count())
        return INVALID;
    return visible_decl[ident_i];
}

uint declaration_type_shallow(uint decl_i)
{
    uint kind = token_kind(decl_i);
    if (kind == TK_PARAM_IDENT ||
        (kind == TK_IDENT && decl_i + 1u < active_token_count() &&
         token_kind(decl_i + 1u) == TK_COLON &&
         (decl_i == 0u ||
          (token_kind(decl_i - 1u) != TK_LET && token_kind(decl_i - 1u) != TK_CONST &&
           token_kind(decl_i - 1u) != TK_ENUM && token_kind(decl_i - 1u) != TK_STRUCT))))
        return type_code_for_type_expr(decl_i + 2u);

    if (is_const_decl_at(decl_i))
        return type_code_for_type_expr(decl_i + 2u);

    if (kind == TK_LET_IDENT ||
        (kind == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET))
    {
        if (token_kind(decl_i + 1u) == TK_COLON)
            return type_code_for_type_expr(decl_i + 2u);

        uint semi = let_decl_semicolon(decl_i);
        if (semi == INVALID)
            return TY_UNKNOWN;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return TY_UNKNOWN;

        uint scanned = scanned_expr_result_type(assign_i + 1u, semi);
        if (scanned != TY_UNKNOWN)
            return scanned;

        uint head = literal_head_type(assign_i + 1u, semi);
        if (head != TY_UNKNOWN)
            return head;

        uint cur = assign_i + 1u;
        uint n_active = active_token_count();
        for (uint guard = 0u; guard < 16u && cur < semi && cur < n_active; guard += 1u)
        {
            uint head_kind = token_kind(cur);
            if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN ||
                head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
            {
                cur += 1u;
                continue;
            }
            if (head_kind == TK_IDENT && cur + 1u < semi &&
                (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN))
            {
                if (is_builtin_name(cur))
                    return TY_VOID;
                return find_named_function_return(cur);
            }
            break;
        }
    }

    return TY_UNKNOWN;
}

uint declaration_type(uint decl_i)
{
    for (uint depth = 0u; depth < 8u && decl_i != INVALID; depth += 1u)
    {
        uint shallow = declaration_type_shallow(decl_i);
        if (shallow != TY_UNKNOWN)
            return shallow;

        if (!(token_kind(decl_i) == TK_LET_IDENT ||
              (token_kind(decl_i) == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET)))
            return TY_UNKNOWN;

        uint semi = let_decl_semicolon(decl_i);
        if (semi == INVALID)
            return TY_UNKNOWN;
        uint assign_i = find_let_assign(decl_i, semi);
        if (assign_i == INVALID || assign_i + 1u >= semi)
            return TY_UNKNOWN;

        uint cur = assign_i + 1u;
        uint n_active = active_token_count();
        bool followed = false;
        for (uint guard = 0u; guard < 16u && cur < semi && cur < n_active; guard += 1u)
        {
            uint head_kind = token_kind(cur);
            if (head_kind == TK_GROUP_LPAREN || head_kind == TK_LPAREN ||
                head_kind == TK_PREFIX_PLUS || head_kind == TK_PREFIX_MINUS)
            {
                cur += 1u;
                continue;
            }
            if (head_kind == TK_IDENT &&
                !(cur + 1u < semi &&
                  (token_kind(cur + 1u) == TK_CALL_LPAREN || token_kind(cur + 1u) == TK_LPAREN)))
            {
                uint next_decl = resolved_visible_decl(cur);
                if (next_decl == INVALID || next_decl == decl_i)
                    return TY_UNKNOWN;
                decl_i = next_decl;
                followed = true;
            }
            break;
        }
        if (!followed)
            return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool ident_is_use(uint i)
{
    if (token_kind(i) != TK_IDENT)
        return false;
    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_DOT || prev == TK_LET || prev == TK_CONST ||
        prev == TK_ENUM || prev == TK_STRUCT)
        return false;
    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    if (next == TK_COLON)
        return false;
    return true;
}

bool ident_resolves_in_scope(uint i)
{
    if (is_builtin_name(i))
        return true;
    if (i + 1u < active_token_count() &&
        (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN))
        return find_named_function(i);
    return resolved_visible_decl(i) != INVALID;
}

void check_ident_use(uint i)
{
    if (!ident_is_use(i))
        return;
    if (!ident_resolves_in_scope(i))
        record_error(i, ERR_UNRESOLVED_IDENT, 0u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint i = tid.x;
    if (i < active_token_count())
    {
        if (token_kind(i) == TK_PARAM_IDENT ||
            (token_kind(i) == TK_IDENT && i + 1u < active_token_count() &&
             token_kind(i + 1u) == TK_COLON &&
             (i == 0u ||
              (token_kind(i - 1u) != TK_LET && token_kind(i - 1u) != TK_CONST &&
               token_kind(i - 1u) != TK_ENUM && token_kind(i - 1u) != TK_STRUCT))) ||
            token_kind(i) == TK_LET_IDENT ||
            (token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_LET) ||
            is_const_decl_at(i))
        {
            visible_type[i] = declaration_type(i);
        }

        if (ident_is_use(i) && !is_builtin_name(i) &&
            !(i + 1u < active_token_count() &&
              (token_kind(i + 1u) == TK_CALL_LPAREN || token_kind(i + 1u) == TK_LPAREN)))
        {
            uint decl = resolved_visible_decl(i);
            if (decl != INVALID)
                visible_type[i] = declaration_type(decl);
        }
    }

    uint n_hir = active_hir_node_count();
    if (i < n_hir)
    {
        if (hir_kind[i] == HIR_NAME_EXPR)
        {
            uint pos = hir_token_pos[i];
            if (pos == INVALID || pos >= active_token_count())
                record_error(active_token_count(), ERR_BAD_HIR, pos);
            else
                check_ident_use(pos);
        }
    }

    if (n_hir != 0u || i >= active_token_count())
        return;

    check_ident_use(i);
}
