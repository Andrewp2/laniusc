// Publish match result types from compact match-arm and dense expression rows.

import atomics;
import hir_expr_semantics;
import status;

struct Params { uint n_tokens; uint source_len; uint n_hir_nodes; };
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirMatchArm { uint owner; uint pattern; uint result; uint ordinal; };

ConstantBuffer<Params> gParams;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_match_arm_count;
StructuredBuffer<HirMatchArm> compact_match_arms;
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
static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_NAME = 2u;
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
static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_hir_count() { return min(compact_hir_count[0u], gParams.n_hir_nodes); }
uint active_arm_count() { return min(compact_match_arm_count[0u], gParams.n_hir_nodes); }
bool valid_hir(uint node) { return node != INVALID && node < active_hir_count(); }
bool valid_token(uint token) { return token != INVALID && token < gParams.n_tokens; }

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;
    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN)
        return ty;
    uint decl = visible_decl[token];
    if (valid_token(decl) && visible_type[decl] != TY_UNKNOWN)
        return visible_type[decl];
    return call_return_type[token];
}

uint expression_token(uint node)
{
    if (!valid_hir(node))
        return INVALID;
    uint token = compact_hir_payload[node].d;
    return valid_token(token) ? token : compact_hir_core[node].token_start;
}

uint direct_node_type(uint node)
{
    if (!valid_hir(node))
        return TY_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload payload = compact_hir_payload[node];
    uint literal = hir_scalar_type_for_expr_form(payload.a);
    if (literal != TY_UNKNOWN)
        return literal;
    if (core.kind == HIR_NAME_EXPR || core.kind == HIR_MEMBER_EXPR)
        return visible_type_for_token(expression_token(node));
    if (core.kind == HIR_STRUCT_LITERAL_EXPR)
        return visible_type_for_token(core.token_start);
    if (core.kind == HIR_INDEX_EXPR || core.kind == HIR_MATCH_EXPR)
        return valid_token(core.token_start) ? call_return_type[core.token_start] : TY_UNKNOWN;
    if (core.kind == HIR_CALL_EXPR)
    {
        uint callee = payload.a;
        uint callee_ty = valid_hir(callee)
            ? visible_type_for_token(expression_token(callee))
            : TY_UNKNOWN;
        if (callee_ty != TY_UNKNOWN)
            return callee_ty;
        return valid_token(core.token_start) ? call_return_type[core.token_start] : TY_UNKNOWN;
    }
    return TY_UNKNOWN;
}

uint expression_type(uint node)
{
    uint direct = direct_node_type(node);
    if (direct != TY_UNKNOWN || !valid_hir(node))
        return direct;
    HirPayload payload = compact_hir_payload[node];
    uint form = payload.a;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE || form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ || form == HIR_EXPR_NE || form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT || form == HIR_EXPR_LE || form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND || form == HIR_EXPR_OR)
        return TY_BOOL;
    if (form == HIR_EXPR_NAME)
        return visible_type_for_token(expression_token(node));
    if (form == HIR_EXPR_NEG || form == HIR_EXPR_ADD || form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL || form == HIR_EXPR_DIV)
    {
        uint left = direct_node_type(payload.b);
        uint right = direct_node_type(payload.c);
        return left == TY_FLOAT || right == TY_FLOAT ? TY_FLOAT : TY_INT;
    }
    if (form == HIR_EXPR_MOD || form == HIR_EXPR_BIT_OR || form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND || form == HIR_EXPR_SHL || form == HIR_EXPR_SHR)
        return TY_INT;
    return TY_UNKNOWN;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint arm_i = linear_thread_id(dtid);
    if (arm_i >= active_arm_count())
        return;
    HirMatchArm arm = compact_match_arms[arm_i];
    if (!valid_hir(arm.owner) || compact_hir_core[arm.owner].kind != HIR_MATCH_EXPR ||
        !valid_hir(arm.result))
    {
        uint token = valid_hir(arm.owner) ? compact_hir_core[arm.owner].token_start : 0u;
        record_min_token_error(status, valid_token(token) ? token : 0u, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }
    uint match_token = compact_hir_core[arm.owner].token_start;
    uint result_token = compact_hir_core[arm.result].token_start;
    if (!valid_token(match_token) || !valid_token(result_token))
    {
        record_min_token_error(status, valid_token(match_token) ? match_token : 0u,
                               ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }
    uint arm_ty = expression_type(arm.result);
    if (arm_ty == TY_UNKNOWN)
    {
        record_min_token_error(status, result_token, ERR_BAD_HIR, HIR_MATCH_EXPR);
        return;
    }
    uint prior = atomic_u32_compare_exchange(call_return_type, match_token, TY_UNKNOWN, arm_ty);
    if (prior != TY_UNKNOWN && prior != arm_ty)
        record_min_token_error(status, result_token, ERR_ASSIGN_MISMATCH, arm_ty);
}
