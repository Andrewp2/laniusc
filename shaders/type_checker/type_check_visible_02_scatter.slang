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
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> enclosing_fn_end;
StructuredBuffer<uint> scope_end;
RWStructuredBuffer<uint> visible_decl;

static const uint INVALID = 0xffffffffu;
static const uint ENCODE_BASE = 0xfffffffeu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_COLON = 38u;
static const uint TK_DOT = 35u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_LET = 68u;
static const uint TK_ARROW = 75u;
static const uint TK_LET_IDENT = 78u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_PARAM_RPAREN = 77u;
static const uint TK_TYPE_ARRAY_LBRACKET = 85u;
static const uint TK_TYPE_ARRAY_RBRACKET = 86u;
static const uint TK_IF_LBRACE = 88u;
static const uint TK_IF_RBRACE = 89u;
static const uint TK_CONST = 92u;

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

bool same_text(uint a, uint b)
{
    uint len = token_len(a);
    if (len != token_len(b))
        return false;
    uint sa = token_start(a);
    uint sb = token_start(b);
    [loop]
    for (uint i = 0u; i < len; i += 1u)
    {
        if (source_at(sa, i) != source_at(sb, i))
            return false;
    }
    return true;
}

bool token_text_eq5(uint i, uint a, uint b, uint c, uint d, uint e)
{
    uint start = token_start(i);
    return token_len(i) == 5u && source_at(start, 0u) == a && source_at(start, 1u) == b &&
           source_at(start, 2u) == c && source_at(start, 3u) == d &&
           source_at(start, 4u) == e;
}

bool is_builtin_call(uint i)
{
    uint start = token_start(i);
    bool is_builtin = token_text_eq5(i, 112u, 114u, 105u, 110u, 116u) ||
                      (token_len(i) == 6u && source_at(start, 0u) == 97u &&
                       source_at(start, 1u) == 115u && source_at(start, 2u) == 115u &&
                       source_at(start, 3u) == 101u && source_at(start, 4u) == 114u &&
                       source_at(start, 5u) == 116u);
    if (!is_builtin)
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

uint declaration_scope_end(uint decl_i)
{
    if (has_hir_scope_end())
        return cached_declaration_scope_end(decl_i);

    uint kind = token_kind(decl_i);
    if (kind == TK_PARAM_IDENT ||
        (kind == TK_IDENT && decl_i + 1u < active_token_count() &&
         token_kind(decl_i + 1u) == TK_COLON &&
         (decl_i == 0u ||
          (token_kind(decl_i - 1u) != TK_LET && token_kind(decl_i - 1u) != TK_CONST))))
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
    [loop]
    for (uint j = decl_i + 1u; j < n; j += 1u)
    {
        uint kind = token_kind(j);
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
        if (kind == TK_SEMICOLON && bracket_depth == 0u)
            return j;
        if (bracket_depth == 0u &&
            (kind == TK_FN || is_open_block_token(kind) || is_close_block_token(kind)))
            return INVALID;
    }
    return INVALID;
}

bool is_let_decl_at(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_LET_IDENT || (kind == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_LET);
}

bool is_const_decl_at(uint i)
{
    return token_kind(i) == TK_IDENT && i > 0u && token_kind(i - 1u) == TK_CONST;
}

bool is_param_decl_at(uint i)
{
    uint kind = token_kind(i);
    return kind == TK_PARAM_IDENT ||
           (kind == TK_IDENT && i + 1u < active_token_count() && token_kind(i + 1u) == TK_COLON &&
            (i == 0u || (token_kind(i - 1u) != TK_LET && token_kind(i - 1u) != TK_CONST)));
}

bool ident_is_use(uint i)
{
    if (token_kind(i) != TK_IDENT)
        return false;

    uint prev = i > 0u ? token_kind(i - 1u) : 0u;
    if (prev == TK_FN || prev == TK_LET || prev == TK_CONST || prev == TK_DOT ||
        prev == TK_COLON || prev == TK_ARROW)
        return false;

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
        if (!is_let_decl_at(j) && !is_param_decl_at(j))
            continue;
        if (!same_text(j, ident_i))
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
        if (!same_text(j, ident_i))
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
