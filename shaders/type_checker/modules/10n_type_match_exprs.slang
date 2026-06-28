// GPU match-expression result typing.
//
// Scheduling contract:
// - Dispatch after match-pattern binding and before the general scope/token
//   validation passes.
// - Use parser-owned match-arm owner/rank records to type arms independently
//   and publish the expression result type in call_return_type[match_token].
// - Arm-local names are consumed from the visible_decl/visible_type bindings
//   produced by type_check_modules_10m_bind_match_patterns.slang.

import atomics;
import generated_parse_production_ids;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> token_count;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_match_arm_start;
StructuredBuffer<uint> hir_match_arm_count;
StructuredBuffer<uint> hir_match_arm_result_node;
StructuredBuffer<uint> hir_match_payload_match_node;
StructuredBuffer<uint> hir_match_payload_ordinal;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_BAD_HIR = 6u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;
static const uint HIR_MATCH_EXPR = 34u;

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
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

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

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool valid_token(uint token)
{
    return token != INVALID && token < active_token_count();
}

uint expr_record_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_FORM) : HIR_EXPR_NONE;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_record_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token];
}

uint scalar_type_for_literal_prod(uint prod)
{
    if (prod == PROD_INT)
        return TY_INT;
    if (prod == PROD_TRUE || prod == PROD_FALSE)
        return TY_BOOL;
    if (prod == PROD_FLOAT)
        return TY_FLOAT;
    if (prod == PROD_STRING)
        return TY_STRING;
    if (prod == PROD_CHAR)
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

    uint token = hir_token_pos[node];
    if (hir_kind[node] == HIR_NAME_EXPR)
        return visible_type_for_token(token);

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return visible_type_for_token(member_token);
    }

    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR)
    {
        uint head_node = hir_struct_lit_head_node[node];
        return valid_node(head_node) ? visible_type_for_token(hir_token_pos[head_node])
                                     : TY_UNKNOWN;
    }

    if (hir_kind[node] == HIR_INDEX_EXPR || hir_kind[node] == HIR_MATCH_EXPR)
        return valid_token(token) ? call_return_type[token] : TY_UNKNOWN;

    if (hir_kind[node] == HIR_CALL_EXPR && valid_token(token))
    {
        uint ty = call_return_type[token];
        if (ty != TY_UNKNOWN)
            return ty;
        if (token > 0u)
            return call_return_type[token - 1u];
    }

    return TY_UNKNOWN;
}

uint expr_type(uint result_node)
{
    uint node = resolve_expr(result_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint direct_ty = direct_node_type(node);
    if (direct_ty != TY_UNKNOWN)
        return direct_ty;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_value_token(node);
        if (!valid_token(token))
            token = hir_token_pos[node];
        return visible_type_for_token(token);
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
        form == HIR_EXPR_DIV)
    {
        uint left_ty = direct_node_type(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_LEFT)));
        uint right_ty = direct_node_type(resolve_expr(expr_record_slot(node, HIR_EXPR_RECORD_RIGHT)));
        return left_ty == TY_FLOAT || right_ty == TY_FLOAT ? TY_FLOAT : TY_INT;
    }

    if (form == HIR_EXPR_MOD ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

bool same_result_type(uint left, uint right)
{
    if (left == TY_UNKNOWN || right == TY_UNKNOWN)
        return false;
    return left == right;
}

void validate_match_node(uint match_node, uint match_i)
{
    uint arm_i = hir_match_arm_start[match_node];
    uint arm_count = hir_match_arm_count[match_node];
    if (arm_count == 0u || !valid_node(arm_i))
    {
        record_error(match_i, ERR_BAD_HIR, HIR_MATCH_EXPR);
    }

    if (valid_node(arm_i) && hir_match_payload_match_node[arm_i] != match_node)
        record_error(match_i, ERR_BAD_HIR, HIR_MATCH_EXPR);
}

void record_arm_bad_hir(uint arm_node)
{
    uint arm_i = hir_token_pos[arm_node];
    record_error(valid_token(arm_i) ? arm_i : active_token_count(),
                 ERR_BAD_HIR,
                 HIR_MATCH_EXPR);
}

void publish_match_arm_type(uint arm_node)
{
    uint match_node = hir_match_payload_match_node[arm_node];
    if (!valid_node(match_node) || hir_kind[match_node] != HIR_MATCH_EXPR)
    {
        record_arm_bad_hir(arm_node);
        return;
    }

    uint match_i = hir_token_pos[match_node];
    if (!valid_token(match_i))
    {
        record_error(active_token_count(), ERR_BAD_HIR, match_i);
        return;
    }

    uint ordinal = hir_match_payload_ordinal[arm_node];
    if (ordinal >= hir_match_arm_count[match_node])
    {
        record_error(match_i, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }

    uint result_node = hir_match_arm_result_node[arm_node];
    if (!valid_node(result_node))
    {
        record_error(match_i, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }

    uint result_start = hir_token_pos[result_node];
    if (!valid_token(result_start))
    {
        record_error(match_i, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }

    uint arm_ty = expr_type(result_node);
    if (arm_ty == TY_UNKNOWN)
    {
        record_error(result_start, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }

    uint prior = atomic_u32_compare_exchange(
        call_return_type,
        match_i,
        TY_UNKNOWN,
        arm_ty);
    if (prior != TY_UNKNOWN && !same_result_type(prior, arm_ty))
        record_error(result_start, ERR_ASSIGN_MISMATCH, arm_ty);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (i >= active_hir_node_count())
        return;

    if (hir_kind[i] == HIR_MATCH_EXPR)
    {
        uint match_i = hir_token_pos[i];
        if (!valid_token(match_i))
        {
            record_error(active_token_count(), ERR_BAD_HIR, match_i);
            return;
        }
        validate_match_node(i, match_i);
    }

    if (node_kind[i] == PROD_MATCH_ARM)
    {
        publish_match_arm_type(i);
    }
}
