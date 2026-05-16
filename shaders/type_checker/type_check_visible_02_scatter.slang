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
StructuredBuffer<uint> token_file_id;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> enclosing_fn_end;
StructuredBuffer<uint> scope_end;
StructuredBuffer<uint> call_intrinsic_tag;
RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;
static const uint ENCODE_BASE = 0xfffffffeu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint INTRINSIC_NONE = 0u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_AMPERSAND = 25u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_DOT = 35u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_ARROW = 75u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_LPAREN = 76u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_PARAM_COMMA = 84u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_CONST = 92u;
static const uint TK_ENUM = 93u;
static const uint TK_STRUCT = 94u;
static const uint TK_MATCH = 95u;
static const uint TK_IMPL = 98u;
static const uint TK_FOR = 100u;
static const uint TK_IN = 101u;
static const uint TK_SELF_VALUE = 105u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return min(token_count[0], gParams.n_tokens);
}

uint token_kind(uint i)
{
    uint n = active_token_count();
    return i < n ? token_words[i].kind : 0u;
}

uint file_id_for_token(uint i)
{
    return i < active_token_count() ? token_file_id[i] : INVALID;
}

bool same_file(uint a, uint b)
{
    uint file_a = file_id_for_token(a);
    uint file_b = file_id_for_token(b);
    return file_a != INVALID && file_a == file_b;
}

uint name_id_for_token(uint i)
{
    return i < active_token_count() ? name_id_by_token[i] : INVALID;
}

bool same_name_id(uint a, uint b)
{
    uint an = name_id_for_token(a);
    uint bn = name_id_for_token(b);
    return an != INVALID && an == bn;
}

bool is_builtin_call(uint i)
{
    if (i >= active_token_count() || call_intrinsic_tag[i] == INTRINSIC_NONE)
        return false;
    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    return next == TK_CALL_LPAREN || next == TK_LPAREN;
}

bool is_open_block_token(uint kind)
{
    return kind == TK_LBRACE || kind == TK_IF_LBRACE;
}

bool is_close_block_token(uint kind)
{
    return kind == TK_RBRACE || kind == TK_IF_RBRACE;
}

bool is_bracket_open_token(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET ||
           kind == TK_TYPE_ARRAY_LBRACKET;
}

bool is_bracket_close_token(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET ||
           kind == TK_TYPE_ARRAY_RBRACKET;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN ||
           kind == TK_PARAM_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN ||
           kind == TK_PARAM_RPAREN;
}

uint matching_group_open_before(uint close_i)
{
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 64u && close_i > guard; guard += 1u)
    {
        uint j = close_i - guard;
        uint kind = token_kind(j);
        if (is_group_close_kind(kind))
            depth += 1u;
        else if (is_group_open_kind(kind))
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
    }
    return INVALID;
}

uint match_token_for_brace(uint brace_i)
{
    if (brace_i == 0u)
        return INVALID;
    uint close_i = brace_i - 1u;
    if (!is_group_close_kind(token_kind(close_i)))
        return INVALID;
    uint open_i = matching_group_open_before(close_i);
    if (open_i == INVALID || open_i == 0u)
        return INVALID;
    return token_kind(open_i - 1u) == TK_MATCH ? open_i - 1u : INVALID;
}

uint enclosing_match_token(uint token_i)
{
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < 256u && token_i > guard; guard += 1u)
    {
        uint j = token_i - guard;
        uint kind = token_kind(j);
        if (kind == TK_RBRACE)
            depth += 1u;
        else if (kind == TK_LBRACE)
        {
            if (depth == 0u)
                return match_token_for_brace(j);
            depth -= 1u;
        }
    }
    return INVALID;
}

uint enclosing_scope_limit(uint i)
{
    uint n = active_token_count();
    if (i >= n)
        return n;
    uint fn_end = enclosing_fn_end[i];
    return fn_end == 0u ? n : min(fn_end, n);
}

bool has_hir_scope_end()
{
    return gParams.n_hir_nodes != 0u;
}

uint cached_declaration_scope_end(uint decl_i)
{
    uint n = active_token_count();
    if (decl_i >= n)
        return n;
    uint end_i = scope_end[decl_i];
    return end_i == 0u || end_i == INVALID ? n : min(end_i, n);
}

uint matching_block_end(uint open_i, uint limit_i)
{
    uint n = min(limit_i, active_token_count());
    uint depth = 0u;
    [loop]
    for (uint j = open_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_block_token(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_close_block_token(kind))
            continue;
        if (depth == 0u)
            return j;
        depth -= 1u;
    }
    return n;
}

uint function_body_end(uint fn_i)
{
    uint n = enclosing_scope_limit(fn_i);
    [loop]
    for (uint j = fn_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE || kind == TK_IF_LBRACE)
            return matching_block_end(j, n);
        if (kind == TK_SEMICOLON)
            return j;
    }
    return n;
}

uint let_scope_end(uint decl_i)
{
    uint n = enclosing_scope_limit(decl_i);
    uint depth = 0u;
    [loop]
    for (uint j = decl_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_FN)
        {
            j = function_body_end(j);
            continue;
        }
        if (is_open_block_token(kind))
        {
            depth += 1u;
            continue;
        }
        if (!is_close_block_token(kind))
            continue;
        if (depth == 0u)
            return j;
        depth -= 1u;
    }
    return n;
}

uint param_scope_end(uint decl_i)
{
    uint n = enclosing_scope_limit(decl_i);
    if (n != active_token_count())
        return n;

    bool saw_params_end = false;
    [loop]
    for (uint j = decl_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_PARAM_RPAREN || kind == TK_RPAREN)
        {
            saw_params_end = true;
            continue;
        }
        if (saw_params_end && (kind == TK_LBRACE || kind == TK_IF_LBRACE))
            return matching_block_end(j, n);
        if (kind == TK_FN || kind == TK_SEMICOLON)
            return n;
    }
    return n;
}

bool is_self_receiver_decl_at(uint i)
{
    if (token_kind(i) != TK_SELF_VALUE || i == 0u)
        return false;
    uint prev = token_kind(i - 1u);
    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    bool prev_ok = prev == TK_PARAM_LPAREN || prev == TK_LPAREN || prev == TK_PARAM_COMMA ||
                   prev == TK_COMMA || prev == TK_AMPERSAND;
    bool next_ok = next == TK_COLON || next == TK_PARAM_RPAREN || next == TK_RPAREN ||
                   next == TK_PARAM_COMMA || next == TK_COMMA;
    return prev_ok && next_ok;
}

bool is_param_decl_at(uint i)
{
    uint kind = token_kind(i);
    if (is_self_receiver_decl_at(i))
        return true;
    if (i == 0u || i + 1u >= active_token_count() || token_kind(i + 1u) != TK_COLON)
        return false;

    uint prev = token_kind(i - 1u);
    if (kind == TK_PARAM_IDENT)
        return prev != TK_COLON;
    return kind == TK_IDENT && prev != TK_LET && prev != TK_CONST && prev != TK_ENUM &&
           prev != TK_STRUCT && prev != TK_COLON;
}

bool is_for_iter_decl_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_FOR &&
           i + 1u < active_token_count() && token_kind(i + 1u) == TK_IN;
}

uint for_body_open(uint iter_i)
{
    uint n = enclosing_scope_limit(iter_i);
    uint bracket_depth = 0u;
    uint group_depth = 0u;
    [loop]
    for (uint j = iter_i + 2u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LPAREN || kind == TK_CALL_LPAREN || kind == TK_PARAM_LPAREN)
        {
            group_depth += 1u;
            continue;
        }
        if ((kind == TK_RPAREN || kind == TK_PARAM_RPAREN) && group_depth > 0u)
        {
            group_depth -= 1u;
            continue;
        }
        if (is_bracket_open_token(kind))
        {
            bracket_depth += 1u;
            continue;
        }
        if (is_bracket_close_token(kind) && bracket_depth > 0u)
        {
            bracket_depth -= 1u;
            continue;
        }
        if (group_depth == 0u && bracket_depth == 0u && is_open_block_token(kind))
            return j;
        if (group_depth == 0u && bracket_depth == 0u &&
            (kind == TK_SEMICOLON || kind == TK_FN || is_close_block_token(kind)))
            return INVALID;
    }
    return INVALID;
}

uint for_iter_scope_end(uint iter_i)
{
    uint open_i = for_body_open(iter_i);
    if (open_i == INVALID)
        return iter_i;
    return matching_block_end(open_i, enclosing_scope_limit(iter_i));
}

uint declaration_scope_end(uint decl_i)
{
    if (is_for_iter_decl_at(decl_i))
        return for_iter_scope_end(decl_i);
    if (has_hir_scope_end())
        return cached_declaration_scope_end(decl_i);

    uint kind = token_kind(decl_i);
    if (is_param_decl_at(decl_i))
        return param_scope_end(decl_i);
    if (kind == TK_LET_IDENT ||
        (kind == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_LET))
        return let_scope_end(decl_i);
    if (kind == TK_IDENT && decl_i > 0u && token_kind(decl_i - 1u) == TK_CONST)
        return active_token_count();
    return decl_i;
}

uint let_decl_statement_end(uint decl_i)
{
    uint n = active_token_count();
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    [loop]
    for (uint j = decl_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_open_block_token(kind) && j > 0u && token_kind(j - 1u) == TK_IDENT)
        {
            brace_depth += 1u;
            continue;
        }
        if (is_close_block_token(kind) && brace_depth > 0u)
        {
            brace_depth -= 1u;
            continue;
        }
        if (is_bracket_open_token(kind))
        {
            bracket_depth += 1u;
            continue;
        }
        if (is_bracket_close_token(kind))
        {
            if (bracket_depth > 0u)
                bracket_depth -= 1u;
            continue;
        }
        if (kind == TK_SEMICOLON && bracket_depth == 0u && brace_depth == 0u)
            return j;
        if (bracket_depth == 0u && brace_depth == 0u &&
            (kind == TK_FN || is_open_block_token(kind) || is_close_block_token(kind)))
            return INVALID;
    }
    return INVALID;
}

bool is_let_decl_at(uint i)
{
    uint kind = token_kind(i);
    return i > 0u && token_kind(i - 1u) == TK_LET &&
           (kind == TK_LET_IDENT || kind == TK_IDENT);
}

bool is_const_decl_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_CONST;
}

bool ident_is_use(uint i)
{
    uint kind = token_kind(i);
    if (kind == TK_SELF_VALUE)
        return !is_self_receiver_decl_at(i) && (i == 0u || token_kind(i - 1u) != TK_DOT);
    if (kind != TK_IDENT)
        return false;

    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_ARROW && enclosing_match_token(i) == INVALID)
        return false;
    if (prev == TK_FN || prev == TK_LET || prev == TK_CONST || prev == TK_ENUM ||
        prev == TK_STRUCT || prev == TK_IMPL || prev == TK_FOR || prev == TK_DOT)
        return false;
    uint j = i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint prior = token_kind(j);
        if (prior == TK_IMPL)
            return false;
        if (prior == TK_LBRACE || prior == TK_RBRACE || prior == TK_FN ||
            prior == TK_SEMICOLON)
            break;
    }

    uint next = i + 1u < active_token_count() ? token_kind(i + 1u) : 0u;
    if (is_builtin_call(i))
        return false;
    return next != TK_COLON;
}

uint enclosing_search_start(uint i)
{
    if (i >= active_token_count())
        return 0u;
    uint encoded_fn = enclosing_fn[i];
    if (encoded_fn == 0u)
        return 0u;
    return encoded_fn - 1u;
}

uint resolve_visible_declaration(uint ident_i)
{
    uint lower = enclosing_search_start(ident_i);
    uint j = ident_i;
    [loop]
    while (j > lower)
    {
        j -= 1u;
        if (!is_let_decl_at(j) && !is_param_decl_at(j) && !is_for_iter_decl_at(j))
            continue;
        if (!same_name_id(j, ident_i))
            continue;

        if (is_let_decl_at(j))
        {
            uint stmt_end = let_decl_statement_end(j);
            if (stmt_end == INVALID || ident_i <= stmt_end)
                continue;
        }

        uint end_i = declaration_scope_end(j);
        if (ident_i < end_i)
            return j;
    }

    j = ident_i;
    [loop]
    while (j > 0u)
    {
        j -= 1u;
        if (!is_const_decl_at(j))
            continue;
        if (!same_file(j, ident_i))
            continue;
        if (!same_name_id(j, ident_i))
            continue;

        uint stmt_end = let_decl_statement_end(j);
        if (stmt_end == INVALID || ident_i <= stmt_end)
            continue;

        return j;
    }
    return INVALID;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    uint n = active_token_count();
    if (i >= n || !ident_is_use(i))
        return;

    uint decl_i = resolve_visible_declaration(i);
    if (decl_i == INVALID)
        return;

    uint encoded = ENCODE_BASE - decl_i;
    visible_decl[i] = encoded;
}
