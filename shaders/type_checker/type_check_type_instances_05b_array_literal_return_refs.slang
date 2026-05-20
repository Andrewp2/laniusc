// HIR array-literal return projection.
//
// This pass consumes return-statement records, expression records, parser-owned
// array literal links, visible scalar types, function return type refs, and
// bounded array type-instance records. It publishes the array-return sentinel
// for `return [..];` when the literal's linked element expressions match the
// enclosing function's bounded array element ref and literal length. It does not
// inspect token kinds, token spelling, source bytes, helper names, or
// punctuation.

import tree_walk;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_array_lit_first_element;
StructuredBuffer<uint> hir_array_lit_element_count;
StructuredBuffer<uint> hir_array_element_next;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;
static const uint ARRAY_RETURN_OK = 0xfffffffeu;

static const uint HIR_FN = 3u;
static const uint HIR_RETURN_STMT = 9u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;

static const uint STMT_RECORD_STRIDE = 4u;
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

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;

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

uint array_literal_parent_record(uint node)
{
    return parent[node];
}

public struct ArrayLiteralReturnWalkGraph : ITreeWalkGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return array_literal_parent_record(node);
    }
}

public struct ArrayLiteralReturnFnPredicate : ITreeWalkPredicate
{
    public static bool matches(uint node)
    {
        return hir_kind[node] == HIR_FN;
    }
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

uint owning_function_node(uint node)
{
    uint found;
    return find_self_or_ancestor<
        ArrayLiteralReturnWalkGraph,
        ArrayLiteralReturnFnPredicate>(
        node,
        128u,
        found) ? found : INVALID;
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
    uint fn_node = owning_function_node(return_node);
    if (!valid_node(fn_node))
        return INVALID;

    uint fn_token = hir_token_pos[fn_node];
    if (!valid_token(fn_token))
        return INVALID;

    return bounded_array_instance_from_ref(
        fn_return_ref_tag[fn_token],
        fn_return_ref_payload[fn_token]);
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

uint resolve_expr_node(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 128u && valid_node(node); guard += 1u)
    {
        if (hir_kind[node] == HIR_ARRAY_EXPR)
            return node;
        if (expr_record(node, EXPR_RECORD_FORM) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_record(node, EXPR_RECORD_LEFT);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

uint array_literal_for_return_expr(uint return_expr)
{
    uint node = resolve_expr_node(return_expr);
    return valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR ? node : INVALID;
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

bool scalar_expr_ref(uint expr_node, out uint tag, out uint payload)
{
    tag = 0u;
    payload = INVALID;
    uint node = resolve_expr_node(expr_node);
    if (!valid_node(node))
        return false;

    uint form = expr_record(node, EXPR_RECORD_FORM);
    if (form == HIR_EXPR_INT)
        return publish_scalar_ref(TY_INT, tag, payload);

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
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return publish_scalar_ref(TY_INT, tag, payload);

    return false;
}

bool array_literal_matches_return_instance(uint array_node, uint dst_instance)
{
    if (dst_instance == INVALID)
        return false;

    uint elem_tag = type_instance_elem_ref_tag[dst_instance];
    uint elem_payload = type_instance_elem_ref_payload[dst_instance];
    uint expected_len = type_instance_len_payload[dst_instance];
    uint count = hir_array_lit_element_count[array_node];
    if (count != expected_len)
        return false;

    uint element = hir_array_lit_first_element[array_node];
    [loop]
    for (uint ordinal = 0u; ordinal < count; ordinal += 1u)
    {
        if (!valid_node(element))
            return false;

        uint actual_tag = 0u;
        uint actual_payload = INVALID;
        if (!scalar_expr_ref(element, actual_tag, actual_payload))
            return false;
        if (!same_type_ref(elem_tag, elem_payload, actual_tag, actual_payload))
            return false;

        element = hir_array_element_next[element];
    }

    return true;
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
    if (array_literal_matches_return_instance(array_node, dst_instance))
        call_return_type[return_token] = ARRAY_RETURN_OK;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    publish_array_literal_return(node);
}
