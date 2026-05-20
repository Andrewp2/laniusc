// GPU match-expression result typing.
//
// Scheduling contract:
// - Dispatch after match-pattern binding and before the general scope/token
//   validation passes.
// - Use parser-owned HIR match-expression spans to walk arms and publish the
//   expression result type in call_return_type[match_token].
// - Arm-local names are consumed from the visible_decl/visible_type bindings
//   produced by type_check_modules_10m_bind_match_patterns.slang.

import status;

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
StructuredBuffer<uint> hir_match_arm_start;
StructuredBuffer<uint> hir_match_arm_count;
StructuredBuffer<uint> hir_match_arm_next;
StructuredBuffer<uint> hir_match_arm_result_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
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
static const uint TK_STRING = 32u;
static const uint TK_FLOAT = 33u;
static const uint TK_CHAR = 34u;
static const uint TK_COLON = 38u;
static const uint TK_PARAM_IDENT = 79u;
static const uint TK_TYPE_IDENT = 80u;
static const uint TK_TRUE = 90u;
static const uint TK_FALSE = 91u;
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

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool is_name_kind(uint kind)
{
    return kind == TK_IDENT || kind == TK_TYPE_IDENT || kind == TK_PARAM_IDENT;
}

bool is_group_open_kind(uint kind)
{
    return kind == TK_LPAREN || kind == TK_GROUP_LPAREN || kind == TK_CALL_LPAREN;
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = payload < active_token_count() ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
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

void type_match(uint match_node, uint match_i)
{
    uint arm_i = hir_match_arm_start[match_node];
    uint arm_count = hir_match_arm_count[match_node];
    if (arm_count == 0u || !valid_node(arm_i))
    {
        record_error(match_i, ERR_BAD_HIR, TK_MATCH);
        return;
    }

    uint result_ty = TY_UNKNOWN;
    bool saw_arm = false;
    [loop]
    for (uint ordinal = 0u; ordinal < arm_count; ordinal += 1u)
    {
        if (!valid_node(arm_i))
        {
            record_error(match_i, ERR_BAD_HIR, TK_MATCH);
            return;
        }

        uint result_node = hir_match_arm_result_node[arm_i];
        if (!valid_node(result_node))
        {
            record_error(match_i, ERR_BAD_HIR, TK_MATCH);
            return;
        }

        uint result_start = hir_token_pos[result_node];
        uint result_end = hir_token_end[result_node];
        if (result_start == INVALID || result_end == INVALID || result_start >= result_end ||
            result_end > active_token_count())
        {
            record_error(match_i, ERR_BAD_HIR, TK_MATCH);
            return;
        }

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

        arm_i = hir_match_arm_next[arm_i];
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
    type_match(i, match_i);
}
