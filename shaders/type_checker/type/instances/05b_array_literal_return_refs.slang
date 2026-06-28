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

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> subtree_end;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_lit_context_stmt_node;
StructuredBuffer<uint> hir_array_element_parent_lit;
StructuredBuffer<uint> hir_struct_lit_head_node;
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
static const uint PROD_STRUCT_LIT = 275u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_RETURN = 2u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_RIGHT = 2u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint HIR_EXPR_NONE = 0u;
static const uint HIR_EXPR_FORWARD = 1u;
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

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_node(uint node)
{
    return node != INVALID && node < active_hir_node_count();
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint stmt_slot(uint node, uint slot)
{
    return node * STMT_RECORD_STRIDE + slot;
}

uint expr_slot(uint node, uint slot)
{
    return node * EXPR_RECORD_STRIDE + slot;
}

uint expr_record(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[expr_slot(node, slot)] : INVALID;
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
    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return INVALID;

    uint encoded_fn = enclosing_fn[return_token];
    uint fn_token = encoded_fn == 0u ? INVALID : encoded_fn - 1u;
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
}

uint let_array_instance(uint let_node)
{
    if (!valid_node(let_node) ||
        hir_stmt_record[stmt_slot(let_node, 0u)] != STMT_RECORD_KIND_LET)
        return INVALID;

    uint decl_token = hir_stmt_record[stmt_slot(let_node, 1u)];
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

uint resolve_expr_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint array_literal_for_return_expr(uint return_expr)
{
    uint node = resolve_expr_node(return_expr);
    return valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR ? node : INVALID;
}

uint direct_array_literal_let_node(uint array_node)
{
    uint let_node = valid_node(array_node) ? hir_array_lit_context_stmt_node[array_node] : INVALID;
    if (!valid_node(let_node) ||
        hir_stmt_record[stmt_slot(let_node, 0u)] != STMT_RECORD_KIND_LET)
        return INVALID;

    uint let_expr = hir_stmt_record[stmt_slot(let_node, 2u)];
    return array_literal_for_return_expr(let_expr) == array_node ? let_node : INVALID;
}

uint direct_array_literal_return_node(uint array_node)
{
    uint return_node = valid_node(array_node) ? hir_array_lit_context_stmt_node[array_node] : INVALID;
    if (!valid_node(return_node) ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return INVALID;

    uint return_expr = hir_stmt_record[stmt_slot(return_node, 1u)];
    return array_literal_for_return_expr(return_expr) == array_node ? return_node : INVALID;
}

bool index_expr_ref(uint index_node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    uint index_token = hir_token_pos[index_node];
    if (!valid_token(index_token))
        return false;

    uint ty = call_return_type[index_token];
    return publish_scalar_ref(ty, tag, payload);
}

uint direct_scalar_expr_type(uint expr_node)
{
    uint node = resolve_expr_node(expr_node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_record(node, EXPR_RECORD_FORM);
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_NAME)
    {
        uint name_token = expr_record(node, EXPR_RECORD_VALUE_TOKEN);
        if (!valid_token(name_token))
            name_token = hir_token_pos[node];
        return visible_scalar_type_for_name_token(name_token);
    }
    if (form == HIR_EXPR_INDEX || hir_kind[node] == HIR_INDEX_EXPR)
    {
        uint index_token = hir_token_pos[node];
        return valid_token(index_token) ? call_return_type[index_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint direct_struct_literal_node(uint node)
{
    if (!valid_node(node))
        return INVALID;
    if (hir_kind[node] == HIR_STRUCT_LITERAL_EXPR ||
        node_kind[node] == PROD_STRUCT_LIT ||
        valid_node(hir_struct_lit_head_node[node]))
        return node;

    uint resolved = resolve_expr_node(node);
    if (valid_node(resolved) &&
        (hir_kind[resolved] == HIR_STRUCT_LITERAL_EXPR ||
         node_kind[resolved] == PROD_STRUCT_LIT ||
         valid_node(hir_struct_lit_head_node[resolved])))
        return resolved;

    uint end = subtree_end[node];
    if (end != INVALID && end > node && end <= active_hir_node_count())
    {
        [loop]
        for (uint cursor = node + 1u; cursor < end; cursor += 1u)
        {
            if ((hir_kind[cursor] == HIR_STRUCT_LITERAL_EXPR ||
                 node_kind[cursor] == PROD_STRUCT_LIT) &&
                valid_node(hir_struct_lit_head_node[cursor]))
                return cursor;
        }
    }

    return INVALID;
}

bool struct_literal_expr_ref(uint expr_node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;

    uint literal_node = direct_struct_literal_node(expr_node);
    if (!valid_node(literal_node))
        return false;

    uint head_node = hir_struct_lit_head_node[literal_node];
    if (!valid_node(head_node))
        return false;

    uint head_token = hir_token_pos[head_node];
    uint ty = struct_literal_head_type_for_token(head_token);
    return publish_scalar_ref(ty, tag, payload);
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

bool struct_literal_head_matches_decl(uint literal_node, uint decl_token)
{
    uint head_node = valid_node(literal_node) ? hir_struct_lit_head_node[literal_node] : INVALID;
    if (!valid_node(head_node) || !valid_token(decl_token))
        return false;
    return same_name_id(hir_token_pos[head_node], decl_token);
}

bool struct_literal_matches_expected_ref(uint expr_node, uint expected_tag, uint expected_payload)
{
    uint literal_node = direct_struct_literal_node(expr_node);
    if (!valid_node(literal_node))
        return false;

    uint decl_token = INVALID;
    if (expected_tag == TYPE_REF_SCALAR)
        decl_token = scalar_struct_decl_token(expected_payload);
    else if (expected_tag == TYPE_REF_INSTANCE && valid_token(expected_payload))
        decl_token = type_instance_decl_token[expected_payload];

    return struct_literal_head_matches_decl(literal_node, decl_token);
}

bool scalar_expr_ref(uint expr_node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    uint node = resolve_expr_node(expr_node);
    if (!valid_node(node))
        return false;

    uint form = expr_record(node, EXPR_RECORD_FORM);
    if (struct_literal_expr_ref(expr_node, tag, payload))
        return true;

    if (form == HIR_EXPR_INT)
        return publish_scalar_ref(TY_INT, tag, payload);

    if (form == HIR_EXPR_FLOAT)
        return publish_scalar_ref(TY_FLOAT, tag, payload);

    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return publish_scalar_ref(TY_BOOL, tag, payload);

    if (form == HIR_EXPR_NAME)
    {
        uint name_token = expr_record(node, EXPR_RECORD_VALUE_TOKEN);
        if (!valid_token(name_token))
            name_token = hir_token_pos[node];
        return publish_scalar_ref(visible_scalar_type_for_name_token(name_token), tag, payload);
    }

    if (form == HIR_EXPR_INDEX || hir_kind[node] == HIR_INDEX_EXPR)
        return index_expr_ref(node, tag, payload);

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
        uint left_ty = direct_scalar_expr_type(expr_record(node, EXPR_RECORD_LEFT));
        uint right_ty = direct_scalar_expr_type(expr_record(node, EXPR_RECORD_RIGHT));
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
    return hir_array_lit_element_count[array_node] == expected_len;
}

void publish_array_literal_return(uint return_node)
{
    if (hir_kind[return_node] != HIR_RETURN_STMT ||
        hir_stmt_record[stmt_slot(return_node, 0u)] != STMT_RECORD_KIND_RETURN)
        return;

    uint return_token = hir_token_pos[return_node];
    if (!valid_token(return_token))
        return;

    uint return_expr = hir_stmt_record[stmt_slot(return_node, 1u)];
    if (!valid_node(return_expr))
        return;

    uint array_node = array_literal_for_return_expr(return_expr);
    if (!valid_node(array_node))
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (array_literal_length_matches_instance(array_node, dst_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
}

void record_array_literal_element_mismatch(
    uint element_node,
    uint expected_tag,
    uint expected_payload)
{
    uint error_token = hir_token_pos[element_node];
    if (valid_token(error_token))
    {
        record_min_token_error(
            status,
            error_token,
            ERR_ASSIGN_MISMATCH,
            expected_tag * 256u + expected_payload);
    }
}

void validate_array_literal_let_length(uint array_node)
{
    if (!valid_node(array_node) || hir_kind[array_node] != HIR_ARRAY_EXPR)
        return;

    uint let_node = direct_array_literal_let_node(array_node);
    if (!valid_node(let_node))
        return;

    uint dst_instance = let_array_instance(let_node);
    if (dst_instance == INVALID)
        return;

    uint expected_len = type_instance_len_payload[dst_instance];
    uint actual_len = hir_array_lit_element_count[array_node];
    if (actual_len == expected_len)
        return;

    uint error_token = hir_token_pos[array_node];
    if (!valid_token(error_token))
        error_token = hir_token_pos[let_node];
    if (valid_token(error_token))
    {
        record_min_token_error(
            status,
            error_token,
            ERR_ASSIGN_MISMATCH,
            TYPE_REF_INSTANCE * 256u + TYPE_INSTANCE_ARRAY);
    }
}

void validate_array_literal_let_element(uint element_node)
{
    if (!valid_node(element_node))
        return;

    uint array_node = hir_array_element_parent_lit[element_node];
    if (!valid_node(array_node))
        return;

    uint let_node = direct_array_literal_let_node(array_node);
    if (!valid_node(let_node))
        return;

    uint dst_instance = let_array_instance(let_node);
    if (dst_instance == INVALID)
        return;

    uint expected_tag = type_instance_elem_ref_tag[dst_instance];
    uint expected_payload = type_instance_elem_ref_payload[dst_instance];

    if (struct_literal_matches_expected_ref(element_node, expected_tag, expected_payload))
        return;

    uint actual_tag = 0u;
    uint actual_payload = INVALID;
    if (!scalar_expr_ref(element_node, actual_tag, actual_payload))
    {
        record_array_literal_element_mismatch(element_node, expected_tag, expected_payload);
        return;
    }

    if (same_type_ref(expected_tag, expected_payload, actual_tag, actual_payload))
        return;

    record_array_literal_element_mismatch(element_node, expected_tag, expected_payload);
}

void validate_array_literal_return_element(uint element_node)
{
    if (!valid_node(element_node))
        return;

    uint array_node = hir_array_element_parent_lit[element_node];
    if (!valid_node(array_node))
        return;

    uint return_node = direct_array_literal_return_node(array_node);
    if (!valid_node(return_node))
        return;

    uint dst_instance = function_return_array_instance(return_node);
    if (dst_instance == INVALID)
        return;

    uint expected_tag = type_instance_elem_ref_tag[dst_instance];
    uint expected_payload = type_instance_elem_ref_payload[dst_instance];

    if (struct_literal_matches_expected_ref(element_node, expected_tag, expected_payload))
        return;

    uint actual_tag = 0u;
    uint actual_payload = INVALID;
    if (!scalar_expr_ref(element_node, actual_tag, actual_payload))
    {
        record_array_literal_element_mismatch(element_node, expected_tag, expected_payload);
        return;
    }

    if (same_type_ref(expected_tag, expected_payload, actual_tag, actual_payload))
        return;

    record_array_literal_element_mismatch(element_node, expected_tag, expected_payload);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_array_literal_return(node);
    validate_array_literal_let_length(node);
    validate_array_literal_let_element(node);
    validate_array_literal_return_element(node);
}
