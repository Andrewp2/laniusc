// Validate aggregate member and struct-literal field records.
//
// This pass consumes parser/HIR member and struct-field metadata plus the
// field-result records published by the type-instance passes. It reports invalid
// field selections without scanning dot/brace token neighborhoods or comparing
// source spelling.

import generated_parse_production_ids;
import status;
import tree_walk;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> first_child;
StructuredBuffer<uint> next_sibling;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> struct_init_field_ordinal;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;

static const uint TYPE_REF_INVALID = 0u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

static const uint HIR_EXPR = 14u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
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

uint aggregate_parent_record(uint node)
{
    return parent[node];
}

uint aggregate_first_child_record(uint node)
{
    return first_child[node];
}

uint aggregate_next_sibling_record(uint node)
{
    return next_sibling[node];
}

public struct AggregateAccessChildGraph : ITreeChildGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint first_child(uint node)
    {
        return aggregate_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return aggregate_next_sibling_record(node);
    }
}

public struct AggregateAccessLinkedGraph : ITreeLinkedGraph
{
    public static bool valid(uint node)
    {
        return valid_node(node);
    }

    public static uint parent(uint node)
    {
        return aggregate_parent_record(node);
    }

    public static uint first_child(uint node)
    {
        return aggregate_first_child_record(node);
    }

    public static uint next_sibling(uint node)
    {
        return aggregate_next_sibling_record(node);
    }
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint first_child_node(uint node)
{
    uint child;
    return tree_child_first<AggregateAccessChildGraph>(node, child) ? child : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool assignable(uint dst, uint src)
{
    if (dst == TY_UNKNOWN || src == TY_UNKNOWN)
        return true;
    if (dst == src)
        return true;
    if (dst == TY_INT)
        return src == TY_UINT || src == TY_CHAR;
    if (dst == TY_UINT)
        return src == TY_INT || src == TY_CHAR;
    if (dst == TY_FLOAT)
        return src == TY_INT || src == TY_UINT || src == TY_CHAR;
    return false;
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

uint visible_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint ty = visible_type[token_i];
    if (ty != TY_UNKNOWN)
        return ty;

    uint decl = visible_decl[token_i];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN)
            return ty;
    }

    return call_return_type[token_i];
}

uint expr_slot(uint node, uint slot)
{
    return valid_node(node) ? hir_expr_record[node * HIR_EXPR_RECORD_STRIDE + slot] : INVALID;
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

uint direct_expr_record_type(uint node)
{
    node = resolve_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        return visible_type_for_token(token_i);
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

uint direct_value_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(node);
    if (record_ty != TY_UNKNOWN)
        return record_ty;

    uint lit = scalar_type_for_literal_prod(node_kind[node]);
    if (lit != TY_UNKNOWN)
        return lit;

    uint token_i = hir_token_pos[node];
    if (hir_kind[node] == HIR_NAME_EXPR)
        return visible_type_for_token(token_i);

    if (hir_kind[node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[node];
        return visible_type_for_token(member_token);
    }

    if (hir_kind[node] == HIR_CALL_EXPR && valid_token(token_i))
        return token_i == 0u ? call_return_type[token_i] : call_return_type[token_i - 1u];

    return TY_UNKNOWN;
}

uint next_descendant_node(uint root, uint cur)
{
    uint next;
    return tree_next_preorder_within<AggregateAccessLinkedGraph>(
        root,
        cur,
        64u,
        next) ? next : INVALID;
}

bool expression_result_node(uint node)
{
    if (!valid_node(node))
        return false;
    return hir_kind[node] == HIR_CALL_EXPR ||
           hir_kind[node] == HIR_MEMBER_EXPR ||
           node_kind[node] == PROD_STRUCT_LIT;
}

uint preferred_result_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    uint result_ty = TY_UNKNOWN;
    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        if (expression_result_node(node))
        {
            uint ty = direct_value_type(node);
            if (ty != TY_UNKNOWN)
            {
                uint token_i = hir_token_pos[node];
                value_token = valid_token(token_i) ? token_i : INVALID;
                return ty;
            }
        }
        node = next_descendant_node(root, node);
    }
    return result_ty;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    if (expression_result_node(root))
    {
        uint root_ty = direct_value_type(root);
        if (root_ty != TY_UNKNOWN)
        {
            value_token = hir_token_pos[root];
            return root_ty;
        }
    }

    uint result_ty = preferred_result_type_from_node(root, value_token);
    if (result_ty != TY_UNKNOWN)
        return result_ty;

    uint node = root;
    [loop]
    for (uint guard = 0u; node != INVALID && guard < 256u; guard += 1u)
    {
        uint token_i = hir_token_pos[node];
        uint ty = direct_value_type(node);
        if (ty != TY_UNKNOWN)
        {
            value_token = valid_token(token_i) ? token_i : INVALID;
            return ty;
        }
        node = next_descendant_node(root, node);
    }
    return TY_UNKNOWN;
}

void validate_struct_literal_field_node(uint node)
{
    uint field_token = hir_token_pos[node];
    if (!valid_token(field_token))
        return;

    if (struct_init_field_ordinal[field_token] == INVALID)
    {
        record_error(field_token, ERR_INVALID_MEMBER_ACCESS, 0u);
        return;
    }

    uint expected = visible_type[field_token];
    if (expected == TY_UNKNOWN)
        return;

    uint value_root = hir_struct_lit_field_value_node[node];
    uint value_token = INVALID;
    uint actual = first_value_type_from_node(value_root, value_token);
    if (actual == TY_UNKNOWN)
    {
        value_token = valid_token(value_token) ? value_token : field_token;
        record_error(value_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
        return;
    }

    if (!assignable(expected, actual))
    {
        value_token = valid_token(value_token) ? value_token : field_token;
        record_error(value_token, ERR_ASSIGN_MISMATCH, expected * 256u + actual);
    }
}

bool member_expr_is_call(uint member_node)
{
    uint child = first_child_node(member_node);
    [loop]
    for (uint guard = 0u; guard < 96u && child != INVALID; guard += 1u)
    {
        if (hir_kind[child] == HIR_CALL_EXPR)
            return true;
        child = next_descendant_node(member_node, child);
    }
    return false;
}

void validate_member_expr_node(uint node)
{
    uint member_token = hir_member_name_token[node];
    if (!valid_token(member_token))
        return;

    if (member_expr_is_call(node))
        return;

    if (member_result_field_ordinal[member_token] != INVALID)
        return;

    uint receiver_tag = member_result_ref_tag[member_token];
    if (receiver_tag != TYPE_REF_INVALID)
        record_error(member_token, ERR_INVALID_MEMBER_ACCESS, receiver_tag);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    if (hir_kind[node] == HIR_MEMBER_EXPR)
        validate_member_expr_node(node);
    else if (node_kind[node] == PROD_STRUCT_LIT_FIELD)
        validate_struct_literal_field_node(node);
}
