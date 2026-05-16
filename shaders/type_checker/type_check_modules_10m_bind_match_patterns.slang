// GPU match-pattern binder for resolved enum variant paths.
//
// This pass consumes resolver rows and publishes arm-local declaration links.
// Payload type substitution is handled by the following payload pass so each
// shader stays within WebGPU's storage-buffer limits.

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
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_kind;
StructuredBuffer<uint> path_owner_token;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_parent_type_decl;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> language_name_id;

RWStructuredBuffer<uint> module_value_path_status;
RWStructuredBuffer<uint> visible_decl;
RWStructuredBuffer<uint> visible_type;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_TYPE_SCAN = 64u;
static const uint LANGUAGE_SYMBOL_WILDCARD = 18u;

static const uint PATH_RECORD_KIND_HIR_PATH_EXPR = 3u;
static const uint PATH_RESOLVE_STATUS_OK = 0u;

static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_ENUM_BASE = 6144u;

static const uint TK_IDENT = 1u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_COMMA = 36u;
static const uint TK_SEMICOLON = 37u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_MATCH = 95u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_path_count()
{
    return min(path_count_out[0], gParams.n_hir_nodes);
}

uint token_kind(uint i)
{
    return i < active_token_count() ? token_words[i].kind : 0u;
}

bool token_is_wildcard(uint i)
{
    return i < active_token_count() && name_id_by_token[i] != INVALID &&
           name_id_by_token[i] == language_name_id[LANGUAGE_SYMBOL_WILDCARD];
}

bool is_name_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

bool is_group_close_kind(uint kind)
{
    return kind == TK_RPAREN || kind == TK_GROUP_RPAREN || kind == TK_CALL_RPAREN;
}

bool is_bracket_open_kind(uint kind)
{
    return kind == TK_LBRACKET || kind == TK_ARRAY_LBRACKET || kind == TK_INDEX_LBRACKET;
}

bool is_bracket_close_kind(uint kind)
{
    return kind == TK_RBRACKET || kind == TK_ARRAY_RBRACKET || kind == TK_INDEX_RBRACKET;
}

bool same_name(uint a, uint b)
{
    uint n = active_token_count();
    if (a >= n || b >= n)
        return false;
    uint left = name_id_by_token[a];
    uint right = name_id_by_token[b];
    return left != INVALID && left == right;
}

uint find_group_close(uint open_i, uint limit_i)
{
    uint n = min(active_token_count(), limit_i);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            depth += 1u;
        else if (is_group_close_kind(kind))
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

uint matching_group_open_before(uint close_i)
{
    uint depth = 0u;
    [loop]
    for (uint guard = 0u; guard < MAX_TYPE_SCAN && close_i > guard; guard += 1u)
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

uint find_arm_arrow(uint pattern_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint j = pattern_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (is_bracket_open_kind(kind))
            bracket_depth += 1u;
        else if (is_bracket_close_kind(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (group_depth == 0u && bracket_depth == 0u && kind == TK_ARROW)
            return j;
        else if (group_depth == 0u && bracket_depth == 0u &&
                 (kind == TK_COMMA || kind == TK_RBRACE || kind == TK_SEMICOLON))
            return INVALID;
    }
    return INVALID;
}

uint arm_result_end(uint result_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    uint n = active_token_count();
    [loop]
    for (uint j = result_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            group_depth += 1u;
        else if (is_group_close_kind(kind) && group_depth > 0u)
            group_depth -= 1u;
        else if (is_bracket_open_kind(kind))
            bracket_depth += 1u;
        else if (is_bracket_close_kind(kind) && bracket_depth > 0u)
            bracket_depth -= 1u;
        else if (kind == TK_LBRACE)
            brace_depth += 1u;
        else if (kind == TK_RBRACE)
        {
            if (brace_depth == 0u && group_depth == 0u && bracket_depth == 0u)
                return j;
            if (brace_depth > 0u)
                brace_depth -= 1u;
        }
        else if (kind == TK_COMMA && group_depth == 0u && bracket_depth == 0u &&
                 brace_depth == 0u)
            return j;
    }
    return n;
}

uint leaf_token_for_pattern(uint pattern_i, uint arrow_i)
{
    uint leaf = pattern_i;
    [loop]
    for (uint j = pattern_i; j < arrow_i && j < active_token_count(); j += 1u)
    {
        uint kind = token_kind(j);
        if (is_group_open_kind(kind))
            return leaf;
        if (is_name_kind(kind))
            leaf = j;
    }
    return leaf;
}

bool enum_variant_decl(uint decl_i, out uint variant_token, out uint enum_token)
{
    variant_token = INVALID;
    enum_token = INVALID;
    if (decl_i >= gParams.n_hir_nodes || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= gParams.n_hir_nodes || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    variant_token = decl_name_token[decl_i];
    enum_token = decl_name_token[enum_decl_i];
    return variant_token != INVALID && enum_token != INVALID &&
           variant_token < active_token_count() && enum_token < active_token_count();
}

uint first_payload_binding(uint leaf_token)
{
    if (leaf_token + 1u >= active_token_count() || !is_group_open_kind(token_kind(leaf_token + 1u)))
        return INVALID;
    uint close_i = find_group_close(leaf_token + 1u, active_token_count());
    if (close_i == INVALID)
        return INVALID;
    [loop]
    for (uint j = leaf_token + 2u; j < close_i; j += 1u)
    {
        if (is_name_kind(token_kind(j)))
            return j;
    }
    return INVALID;
}

void bind_decl(uint use_i, uint decl_i)
{
    if (use_i >= active_token_count())
        return;
    visible_decl[use_i] = decl_i;
    module_value_path_status[use_i] = INVALID;
}

void bind_payload_uses(uint result_start, uint result_end, uint binder_i)
{
    [loop]
    for (uint j = result_start; j < result_end && j < active_token_count(); j += 1u)
    {
        if (is_name_kind(token_kind(j)) && same_name(j, binder_i))
            bind_decl(j, binder_i);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint path_i = linear_thread_id(dtid);
    if (path_i >= active_path_count())
        return;
    if (path_kind[path_i] != PATH_RECORD_KIND_HIR_PATH_EXPR)
        return;

    uint owner_token = path_owner_token[path_i];
    if (owner_token >= active_token_count())
        return;

    uint match_i = enclosing_match_token(owner_token);
    if (match_i == INVALID)
        return;
    uint arrow_i = find_arm_arrow(owner_token);
    if (arrow_i == INVALID)
        return;
    if (token_is_wildcard(owner_token))
    {
        bind_decl(owner_token, owner_token);
        visible_type[owner_token] = TY_UNKNOWN;
        return;
    }
    if (resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return;

    uint variant_token;
    uint enum_token;
    if (!enum_variant_decl(resolved_value_decl[path_i], variant_token, enum_token))
        return;

    bind_decl(owner_token, variant_token);
    visible_type[owner_token] = TY_ENUM_BASE + enum_token;

    uint leaf_token = leaf_token_for_pattern(owner_token, arrow_i);
    uint binder_i = first_payload_binding(leaf_token);
    if (binder_i == INVALID)
        return;

    bind_decl(binder_i, binder_i);
    visible_type[binder_i] = TY_UNKNOWN;
    bind_payload_uses(arrow_i + 1u, arm_result_end(arrow_i + 1u), binder_i);
}
