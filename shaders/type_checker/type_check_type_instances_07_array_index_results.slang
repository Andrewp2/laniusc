// HIR array/slice index result projection.
//
// This pass consumes parser-owned index-expression records, visible-decl
// records, declaration type refs, and array/slice type-instance records. It
// publishes the element type at the index-expression token for later type
// checks. It does not inspect token kinds, token spelling, source bytes, or
// generic parameter token neighborhoods.

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
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_state;

RWStructuredBuffer<uint> call_return_type;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_INSTANCE_RESOLVED = 1u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_GENERIC_BASE = 8192u;

static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

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

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
}

uint base_node_for_index(uint index_node)
{
    return expr_slot(index_node, HIR_EXPR_RECORD_LEFT);
}

uint expr_form(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_FORM);
}

uint resolve_expr(uint node)
{
    [loop]
    for (uint guard = 0u; guard < 64u && valid_node(node); guard += 1u)
    {
        if (expr_form(node) != HIR_EXPR_FORWARD)
            return node;
        uint child = expr_slot(node, HIR_EXPR_RECORD_LEFT);
        if (!valid_node(child))
            return node;
        node = child;
    }
    return node;
}

uint scalar_expr_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_NAME)
    {
        uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (!valid_token(token))
            token = hir_token_pos[node];
        if (!valid_token(token))
            return TY_UNKNOWN;

        uint decl_token = visible_decl[token];
        if (!valid_token(decl_token))
            return TY_UNKNOWN;
        if (decl_type_ref_tag[decl_token] != TYPE_REF_SCALAR)
            return TY_UNKNOWN;

        return decl_type_ref_payload[decl_token];
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
        form == HIR_EXPR_MOD ||
        form == HIR_EXPR_DIV ||
        form == HIR_EXPR_BIT_OR ||
        form == HIR_EXPR_BIT_XOR ||
        form == HIR_EXPR_BIT_AND ||
        form == HIR_EXPR_SHL ||
        form == HIR_EXPR_SHR)
        return TY_INT;

    return TY_UNKNOWN;
}

uint index_operand_scalar_type(uint index_node)
{
    if (!valid_node(index_node) || hir_kind[index_node] != HIR_INDEX_EXPR)
        return TY_UNKNOWN;
    return scalar_expr_type(expr_slot(index_node, HIR_EXPR_RECORD_RIGHT));
}

uint name_token_for_expr(uint root)
{
    uint node = resolve_expr(root);
    if (!valid_node(node) || hir_kind[node] != HIR_NAME_EXPR)
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : hir_token_pos[node];
}

uint type_instance_from_ref(uint tag, uint payload)
{
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return INVALID;
    if (type_instance_state[payload] != TYPE_INSTANCE_RESOLVED)
        return INVALID;

    uint kind = type_instance_kind[payload];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return INVALID;

    return payload;
}

uint array_or_slice_instance_from_decl(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    return type_instance_from_ref(decl_type_ref_tag[decl_token], decl_type_ref_payload[decl_token]);
}

uint array_or_slice_instance_for_base_node(uint base_node)
{
    if (!valid_node(base_node))
        return INVALID;

    uint base_token = name_token_for_expr(base_node);
    if (!valid_token(base_token))
        return INVALID;

    uint decl_token = visible_decl[base_token];
    return array_or_slice_instance_from_decl(decl_token);
}

uint type_ref_to_type_code(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;

    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        uint slot = valid_token(payload) ? type_generic_param_slot_by_token[payload] : INVALID;
        return slot == INVALID ? TY_UNKNOWN : TY_GENERIC_BASE + slot;
    }

    return TY_UNKNOWN;
}

void publish_index_result(uint index_node)
{
    uint result_token = hir_token_pos[index_node];
    if (!valid_token(result_token))
        return;
    if (index_operand_scalar_type(index_node) != TY_INT)
        return;

    uint base_node = base_node_for_index(index_node);
    uint instance = array_or_slice_instance_for_base_node(base_node);
    if (instance == INVALID)
        return;

    uint elem_ty = type_ref_to_type_code(
        type_instance_elem_ref_tag[instance],
        type_instance_elem_ref_payload[instance]);
    if (elem_ty != TY_UNKNOWN)
        call_return_type[result_token] = elem_ty;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node) || hir_kind[node] != HIR_INDEX_EXPR)
        return;

    publish_index_result(node);
}
