// GPU match-expression result typing.
//
// Scheduling contract:
// - Dispatch after match-pattern binding and before the general scope/token
//   validation passes.
// - Use parser-owned HIR match-expression spans to walk arms and publish the
//   expression result type in call_return_type[match_token].
// - Arm-local names are consumed from the visible_decl/visible_type bindings
//   produced by type_check_modules_10m_bind_match_patterns.slang.

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
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_token_end;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> name_id_by_token;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint MAX_TYPE_SCAN = 64u;

static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_BAD_HIR = 6u;

static const uint HIR_MATCH_EXPR = 34u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint TK_IDENT = 1u;
static const uint TK_INT = 2u;
static const uint TK_LPAREN = 4u;
static const uint TK_RPAREN = 5u;
static const uint TK_LT = 12u;
static const uint TK_GT = 13u;
static const uint TK_LBRACKET = 20u;
static const uint TK_RBRACKET = 21u;
static const uint TK_LBRACE = 22u;
static const uint TK_RBRACE = 23u;
static const uint TK_CALL_LPAREN = 28u;
static const uint TK_GROUP_LPAREN = 29u;
static const uint TK_INDEX_LBRACKET = 30u;
static const uint TK_ARRAY_LBRACKET = 31u;
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COMMA = 36u;
static const uint TK_COLON = 38u;
static const uint TK_NOT_EQUAL = 40u;
static const uint TK_GROUP_RPAREN = 62u;
static const uint TK_CALL_RPAREN = 63u;
static const uint TK_ARRAY_RBRACKET = 64u;
static const uint TK_INDEX_RBRACKET = 65u;
static const uint TK_FN = 67u;
static const uint TK_ARROW = 75u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
static const uint TK_ENUM = 93u;
static const uint TK_MATCH = 95u;
static const uint TK_PREFIX_PLUS = 58u;
static const uint TK_PREFIX_MINUS = 60u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

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

uint find_match_brace_close(uint open_i, uint limit_i)
{
    uint n = min(active_token_count(), limit_i);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < n; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LBRACE)
            depth += 1u;
        else if (kind == TK_RBRACE)
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

uint find_arm_arrow(uint pattern_i, uint limit_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint n = min(active_token_count(), limit_i);
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
                 (kind == TK_COMMA || kind == TK_RBRACE))
            return INVALID;
    }
    return INVALID;
}

uint arm_result_end(uint result_i, uint limit_i)
{
    uint group_depth = 0u;
    uint bracket_depth = 0u;
    uint brace_depth = 0u;
    uint n = min(active_token_count(), limit_i);
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

uint generic_param_list_open(uint item_i)
{
    uint n = active_token_count();
    uint limit = min(n, item_i + MAX_TYPE_SCAN);
    [loop]
    for (uint j = item_i + 1u; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            return j;
        if (kind == TK_LBRACE || kind == TK_LPAREN)
            return INVALID;
    }
    return INVALID;
}

uint generic_param_list_close(uint open_i)
{
    if (open_i == INVALID)
        return INVALID;

    uint n = active_token_count();
    uint limit = min(n, open_i + MAX_TYPE_SCAN);
    uint depth = 0u;
    [loop]
    for (uint j = open_i; j < limit; j += 1u)
    {
        uint kind = token_kind(j);
        if (kind == TK_LT)
            depth += 1u;
        else if (kind == TK_GT)
        {
            if (depth == 0u)
                return INVALID;
            depth -= 1u;
            if (depth == 0u)
                return j;
        }
        else if (kind == TK_LBRACE)
            return INVALID;
    }
    return INVALID;
}

bool is_type_generic_param_token(uint param_i, uint open_i, uint close_i)
{
    return param_i > open_i && param_i < close_i && is_name_kind(token_kind(param_i));
}

uint generic_param_decl_for_use(uint name_i)
{
    uint j = name_i;
    [loop]
    for (uint guard = 0u; guard < 256u && j > 0u; guard += 1u)
    {
        j -= 1u;
        uint kind = token_kind(j);
        if (kind != TK_FN && kind != TK_ENUM)
            continue;

        uint open_i = generic_param_list_open(j);
        if (open_i == INVALID)
            continue;
        uint close_i = generic_param_list_close(open_i);
        if (close_i == INVALID)
            continue;
        [loop]
        for (uint p = open_i + 1u; p < close_i; p += 1u)
        {
            if (is_type_generic_param_token(p, open_i, close_i) && same_name(p, name_i))
                return p;
        }
    }
    return INVALID;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint decl_i = generic_param_decl_for_use(payload);
        return decl_i == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + decl_i;
    }
    return TY_UNKNOWN;
}

uint declaration_type(uint decl_i)
{
    if (decl_i >= active_token_count())
        return TY_UNKNOWN;
    uint cached = visible_type[decl_i];
    if (cached != TY_UNKNOWN)
        return cached;
    if (decl_i + 2u < active_token_count() && token_kind(decl_i + 1u) == TK_COLON)
        return type_ref_to_type_code(type_expr_ref_tag[decl_i + 2u], type_expr_ref_payload[decl_i + 2u]);
    return TY_UNKNOWN;
}

uint literal_head_type(uint cur)
{
    uint kind = token_kind(cur);
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
    return TY_UNKNOWN;
}

uint expr_type(uint expr_i, uint limit_i)
{
    uint cur = expr_i;
    uint n = active_token_count();
    [loop]
    for (uint guard = 0u; guard < 16u && cur < limit_i && cur < n; guard += 1u)
    {
        uint kind = token_kind(cur);
        if (is_group_open_kind(kind) || kind == TK_PREFIX_PLUS || kind == TK_PREFIX_MINUS)
        {
            cur += 1u;
            continue;
        }

        uint literal = literal_head_type(cur);
        if (literal != TY_UNKNOWN)
            return literal;

        if (kind == TK_MATCH)
            return call_return_type[cur];

        if (is_name_kind(kind))
        {
            if (cur + 1u < limit_i && is_group_open_kind(token_kind(cur + 1u)))
                return call_return_type[cur];

            uint ty = visible_type[cur];
            if (ty != TY_UNKNOWN)
                return ty;

            uint decl_i = visible_decl[cur];
            if (decl_i != INVALID)
                return declaration_type(decl_i);

            return call_return_type[cur];
        }

        return TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

bool same_result_type(uint left, uint right)
{
    if (left == TY_UNKNOWN || right == TY_UNKNOWN)
        return false;
    return left == right;
}

void type_match(uint match_i, uint end_i)
{
    if (match_i + 1u >= active_token_count() || !is_group_open_kind(token_kind(match_i + 1u)))
    {
        record_error(match_i, ERR_BAD_HIR, TK_MATCH);
        return;
    }

    uint group_close = find_group_close(match_i + 1u, end_i);
    if (group_close == INVALID || group_close + 1u >= end_i ||
        token_kind(group_close + 1u) != TK_LBRACE)
    {
        record_error(match_i, ERR_BAD_HIR, TK_MATCH);
        return;
    }

    uint brace_open = group_close + 1u;
    uint brace_close = find_match_brace_close(brace_open, end_i);
    if (brace_close == INVALID)
    {
        record_error(match_i, ERR_BAD_HIR, TK_MATCH);
        return;
    }

    uint result_ty = TY_UNKNOWN;
    uint arm_i = brace_open + 1u;
    bool saw_arm = false;
    [loop]
    for (uint guard = 0u; guard < 64u && arm_i < brace_close; guard += 1u)
    {
        if (token_kind(arm_i) == TK_COMMA)
        {
            arm_i += 1u;
            continue;
        }

        uint arrow_i = find_arm_arrow(arm_i, brace_close);
        if (arrow_i == INVALID)
        {
            record_error(match_i, ERR_BAD_HIR, TK_ARROW);
            return;
        }
        uint result_start = arrow_i + 1u;
        uint result_end = arm_result_end(result_start, brace_close);
        uint arm_ty = expr_type(result_start, result_end);
        if (arm_ty == TY_UNKNOWN)
        {
            record_error(result_start, ERR_BAD_HIR, TK_MATCH);
            return;
        }

        if (!saw_arm)
        {
            result_ty = arm_ty;
            saw_arm = true;
        }
        else if (!same_result_type(result_ty, arm_ty))
        {
            record_error(result_start, ERR_ASSIGN_MISMATCH, arm_ty);
            return;
        }

        arm_i = result_end;
        if (arm_i < brace_close && token_kind(arm_i) == TK_COMMA)
            arm_i += 1u;
    }

    if (!saw_arm || result_ty == TY_UNKNOWN)
    {
        record_error(match_i, ERR_BAD_HIR, TK_MATCH);
        return;
    }
    call_return_type[match_i] = result_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;
    if (hir_kind[i] != HIR_MATCH_EXPR)
        return;

    uint match_i = hir_token_pos[i];
    uint end_i = hir_token_end[i];
    if (match_i == INVALID || end_i == INVALID || match_i >= active_token_count() ||
        end_i > active_token_count() || token_kind(match_i) != TK_MATCH)
    {
        record_error(active_token_count(), ERR_BAD_HIR, match_i);
        return;
    }
    type_match(match_i, end_i);
}
