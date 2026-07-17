// HIR array-literal projection and validation.
//
// This pass consumes return-statement records, expression records, parser-owned
// array literal links, visible scalar types, declaration/function type refs, and
// bounded array type-instance records. It publishes the array-return sentinel
// for `return [..];` when the literal's linked element expressions match the
// enclosing function's bounded array length. Element validation is per
// array-element record, so array literal size does not become a per-thread loop.
// It also validates annotated local array literal declarations from HIR records.
// It does not inspect token kinds, token spelling, source bytes, helper names,
// or punctuation.

import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirArrayElement { uint array; uint value; uint ordinal; uint file_id; };

StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_array_element_count;
StructuredBuffer<uint> compact_array_element_row_count;
StructuredBuffer<HirArrayElement> compact_array_elements;
StructuredBuffer<uint> enclosing_fn;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_return_type;
RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;

static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

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
static const uint HIR_EXPR_INDEX = 26u;
static const uint HIR_EXPR_FLOAT = 27u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_FLOAT = 5u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint ERR_ASSIGN_MISMATCH = 3u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < min(compact_hir_count[0u], gParams.n_tokens);
}

uint active_compact_array_element_count()
{
    return min(compact_array_element_row_count[0u], gParams.n_tokens);
}

uint compact_array_length(uint array_node)
{
    return valid_compact_node(array_node)
        ? compact_array_element_count[array_node]
        : INVALID;
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint bounded_array_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_kind[payload] != TYPE_INSTANCE_ARRAY)
        return INVALID;
    if (type_instance_len_kind[payload] != TYPE_LEN_LITERAL)
        return INVALID;
    return payload;
}

uint function_return_array_instance(uint return_node)
{
    if (!valid_compact_node(return_node) ||
        compact_hir_core[return_node].kind != HIR_RETURN_STMT ||
        compact_hir_payload[return_node].a != STMT_RECORD_KIND_RETURN)
        return INVALID;
    uint return_token = compact_hir_core[return_node].token_start;
    if (!valid_token(return_token))
        return INVALID;

    uint encoded_fn = enclosing_fn[return_token];
    uint fn_node = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    uint fn_token = valid_compact_node(fn_node) ? compact_hir_payload[fn_node].b : INVALID;
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint let_array_instance(uint let_node)
{
    if (!valid_compact_node(let_node) ||
        compact_hir_payload[let_node].a != STMT_RECORD_KIND_LET)
        return INVALID;

    uint decl_token = compact_hir_payload[let_node].b;
    if (!valid_token(decl_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        decl_type_ref_tag[decl_token],
        decl_type_ref_payload[decl_token]);
}

bool same_type_ref(uint lhs_tag, uint lhs_payload, uint rhs_tag, uint rhs_payload)
{
    return lhs_tag == rhs_tag && lhs_payload == rhs_payload;
}

bool publish_scalar_ref(uint ty, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    if (ty == TY_UNKNOWN || ty == INVALID || ty == ARRAY_RETURN_OK)
        return false;
    tag = TYPE_REF_SCALAR;
    payload = ty;
    return true;
}

uint visible_scalar_type_for_name_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN && ty != INVALID)
        return ty;

    uint decl_token = visible_decl[token];
    if (valid_token(decl_token))
    {
        ty = visible_type[decl_token];
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;
    }
    return TY_UNKNOWN;
}

uint visible_type_for_token(uint token)
{
    if (!valid_token(token))
        return TY_UNKNOWN;

    uint ty = visible_type[token];
    if (ty != TY_UNKNOWN && ty != INVALID)
        return ty;

    uint decl_token = visible_decl[token];
    if (valid_token(decl_token))
    {
        ty = visible_type[decl_token];
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;
    }
    return TY_UNKNOWN;
}

uint struct_literal_head_type_for_token(uint token)
{
    uint ty = visible_type_for_token(token);
    if (ty != TY_UNKNOWN && ty != INVALID)
        return ty;

    uint decl_token = valid_token(token) ? visible_decl[token] : INVALID;
    if (valid_token(decl_token))
        return TY_STRUCT_BASE + decl_token;

    return TY_UNKNOWN;
}

uint direct_array_literal_let_node(uint array_node)
{
    if (!valid_compact_node(array_node) ||
        compact_hir_core[array_node].kind != HIR_ARRAY_EXPR)
        return INVALID;
    uint let_node = compact_hir_payload[array_node].d;
    if (!valid_compact_node(let_node) ||
        compact_hir_payload[let_node].a != STMT_RECORD_KIND_LET)
        return INVALID;
    return compact_hir_payload[let_node].c == array_node ? let_node : INVALID;
}

uint direct_array_literal_return_node(uint array_node)
{
    if (!valid_compact_node(array_node) ||
        compact_hir_core[array_node].kind != HIR_ARRAY_EXPR)
        return INVALID;
    uint return_node = compact_hir_payload[array_node].d;
    if (!valid_compact_node(return_node) ||
        compact_hir_payload[return_node].a != STMT_RECORD_KIND_RETURN)
        return INVALID;
    return compact_hir_payload[return_node].b == array_node ? return_node : INVALID;
}

uint scalar_struct_decl_token(uint payload)
{
    if (payload >= TY_STRUCT_BASE && payload < TY_ENUM_BASE)
        return payload - TY_STRUCT_BASE;
    return INVALID;
}

bool same_name_id(uint left_token, uint right_token)
{
    if (!valid_token(left_token) || !valid_token(right_token))
        return false;
    uint left_name = name_id_by_token[left_token];
    uint right_name = name_id_by_token[right_token];
    return left_name != INVALID && left_name == right_name;
}

bool compact_struct_literal_head_matches_decl(uint literal_node, uint decl_token)
{
    if (!valid_compact_node(literal_node) ||
        compact_hir_core[literal_node].kind != HIR_STRUCT_LITERAL_EXPR ||
        !valid_token(decl_token))
        return false;
    return same_name_id(compact_hir_core[literal_node].token_start, decl_token);
}

bool compact_struct_literal_matches_expected_ref(
    uint expr_node,
    uint expected_tag,
    uint expected_payload)
{
    if (!valid_compact_node(expr_node) ||
        compact_hir_core[expr_node].kind != HIR_STRUCT_LITERAL_EXPR)
        return false;

    uint decl_token = INVALID;
    if (expected_tag == TYPE_REF_SCALAR)
        decl_token = scalar_struct_decl_token(expected_payload);
    else if (expected_tag == TYPE_REF_INSTANCE && valid_token(expected_payload))
        decl_token = type_instance_decl_token[expected_payload];

    return compact_struct_literal_head_matches_decl(expr_node, decl_token);
}

uint compact_direct_scalar_expr_type(uint node)
{
    if (!valid_compact_node(node))
        return TY_UNKNOWN;
    HirCore core = compact_hir_core[node];
    HirPayload expr = compact_hir_payload[node];
    uint form = expr.a;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_NAME || core.kind == HIR_NAME_EXPR)
    {
        uint name_token = expr.d;
        if (!valid_token(name_token))
            name_token = core.token_start;
        return visible_scalar_type_for_name_token(name_token);
    }
    if (form == HIR_EXPR_INDEX || core.kind == HIR_INDEX_EXPR)
        return valid_token(core.token_start) ? call_return_type[core.token_start] : TY_UNKNOWN;
    return TY_UNKNOWN;
}

bool compact_scalar_expr_ref(uint node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    if (!valid_compact_node(node))
        return false;

    HirCore core = compact_hir_core[node];
    HirPayload expr = compact_hir_payload[node];
    uint form = expr.a;
    if (core.kind == HIR_STRUCT_LITERAL_EXPR)
        return publish_scalar_ref(
            struct_literal_head_type_for_token(core.token_start),
            tag,
            payload);
    uint direct = compact_direct_scalar_expr_type(node);
    if (direct != TY_UNKNOWN)
        return publish_scalar_ref(direct, tag, payload);
    if (form == HIR_EXPR_NOT ||
        form == HIR_EXPR_EQ ||
        form == HIR_EXPR_NE ||
        form == HIR_EXPR_LT ||
        form == HIR_EXPR_GT ||
        form == HIR_EXPR_LE ||
        form == HIR_EXPR_GE ||
        form == HIR_EXPR_AND ||
        form == HIR_EXPR_OR)
        return publish_scalar_ref(TY_BOOL, tag, payload);

    if (form == HIR_EXPR_NEG ||
        form == HIR_EXPR_ADD ||
        form == HIR_EXPR_SUB ||
        form == HIR_EXPR_MUL ||
        form == HIR_EXPR_DIV)
    {
        uint left_ty = compact_direct_scalar_expr_type(expr.b);
        uint right_ty = compact_direct_scalar_expr_type(expr.c);
        uint result_ty = left_ty == TY_FLOAT || right_ty == TY_FLOAT ? TY_FLOAT : TY_INT;
        return publish_scalar_ref(result_ty, tag, payload);
    }

    if (form == HIR_EXPR_MOD ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return publish_scalar_ref(TY_INT, tag, payload);

    return false;
}

bool array_literal_length_matches_instance(uint array_node, uint dst_instance)
{
    if (dst_instance == INVALID)
        return false;

    uint expected_len = type_instance_len_payload[dst_instance];
    return compact_array_length(array_node) == expected_len;
}

void publish_array_literal_return(uint return_node)
{
    if (!valid_compact_node(return_node) ||
        compact_hir_core[return_node].kind != HIR_RETURN_STMT ||
        compact_hir_payload[return_node].a != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = compact_hir_core[return_node].token_start;
    if (!valid_token(return_token))
        return;

    uint array_node = compact_hir_payload[return_node].b;
    if (!valid_compact_node(array_node) ||
        compact_hir_core[array_node].kind != HIR_ARRAY_EXPR)
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (array_literal_length_matches_instance(array_node, dst_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
}

void record_array_literal_element_mismatch(
    uint element_node,
    uint expected_tag,
    uint expected_payload,
    uint actual_tag,
    uint actual_payload)
{
    uint error_token = valid_compact_node(element_node)
        ? compact_hir_core[element_node].token_start
        : INVALID;
    if (valid_token(error_token))
    {
        uint detail = expected_tag == TYPE_REF_SCALAR && actual_tag == TYPE_REF_SCALAR
            ? expected_payload * 256u + actual_payload
            : 0u;
        record_min_token_error(
            status,
            error_token,
            ERR_ASSIGN_MISMATCH,
            detail);
    }
}

void validate_array_literal_let_length(uint array_node)
{
    if (!valid_compact_node(array_node) ||
        compact_hir_core[array_node].kind != HIR_ARRAY_EXPR)
        return;

    uint let_node = direct_array_literal_let_node(array_node);
    if (!valid_compact_node(let_node))
        return;

    uint dst_instance = let_array_instance(let_node);
    if (dst_instance == INVALID)
        return;

    uint expected_len = type_instance_len_payload[dst_instance];
    uint actual_len = compact_array_length(array_node);
    if (actual_len == expected_len)
        return;

    uint error_token = compact_hir_core[array_node].token_start;
    if (!valid_token(error_token))
        error_token = compact_hir_core[let_node].token_start;
    if (valid_token(error_token))
    {
        record_min_token_error(
            status,
            error_token,
            ERR_ASSIGN_MISMATCH,
            0u);
    }
}

void validate_array_literal_let_element(uint array_node, uint element_node)
{
    if (!valid_compact_node(array_node) || !valid_compact_node(element_node))
        return;

    uint let_node = direct_array_literal_let_node(array_node);
    if (!valid_compact_node(let_node))
        return;

    uint dst_instance = let_array_instance(let_node);
    if (dst_instance == INVALID)
        return;

    uint expected_tag = type_instance_elem_ref_tag[dst_instance];
    uint expected_payload = type_instance_elem_ref_payload[dst_instance];

    if (compact_struct_literal_matches_expected_ref(
            element_node,
            expected_tag,
            expected_payload))
        return;

    uint actual_tag = 0u;
    uint actual_payload = INVALID;
    if (!compact_scalar_expr_ref(element_node, actual_tag, actual_payload))
    {
        record_array_literal_element_mismatch(
            element_node,
            expected_tag,
            expected_payload,
            actual_tag,
            actual_payload);
        return;
    }

    if (same_type_ref(expected_tag, expected_payload, actual_tag, actual_payload))
        return;

    record_array_literal_element_mismatch(
        element_node,
        expected_tag,
        expected_payload,
        actual_tag,
        actual_payload);
}

void validate_array_literal_return_element(uint array_node, uint element_node)
{
    if (!valid_compact_node(array_node) || !valid_compact_node(element_node))
        return;

    uint return_node = direct_array_literal_return_node(array_node);
    if (!valid_compact_node(return_node))
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (dst_instance == INVALID)
        return;

    uint expected_tag = type_instance_elem_ref_tag[dst_instance];
    uint expected_payload = type_instance_elem_ref_payload[dst_instance];

    if (compact_struct_literal_matches_expected_ref(
            element_node,
            expected_tag,
            expected_payload))
        return;

    uint actual_tag = 0u;
    uint actual_payload = INVALID;
    if (!compact_scalar_expr_ref(element_node, actual_tag, actual_payload))
    {
        record_array_literal_element_mismatch(
            element_node,
            expected_tag,
            expected_payload,
            actual_tag,
            actual_payload);
        return;
    }

    if (same_type_ref(expected_tag, expected_payload, actual_tag, actual_payload))
        return;

    record_array_literal_element_mismatch(
        element_node,
        expected_tag,
        expected_payload,
        actual_tag,
        actual_payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (valid_compact_node(node))
    {
        publish_array_literal_return(node);
        validate_array_literal_let_length(node);
    }

    if (node >= active_compact_array_element_count())
        return;
    HirArrayElement element = compact_array_elements[node];
    if (!valid_compact_node(element.array) || !valid_compact_node(element.value))
        return;
    validate_array_literal_let_element(element.array, element.value);
    validate_array_literal_return_element(element.array, element.value);
}
