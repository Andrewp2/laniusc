// Validate aggregate member and struct-literal field records.
//
// This pass consumes parser/HIR member and struct-field metadata plus the
// field-result records published by the type-instance passes. It reports invalid
// field selections from materialized relations instead of walking expression or
// call subtrees in this consumer.

import hir_expr_semantics;
import status;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_struct_lit_field_value_node;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> method_call_name_id;
StructuredBuffer<uint> method_call_site_module_id;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_field_ordinal;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> struct_field_key_order;
StructuredBuffer<uint> struct_lit_context_decl_token;
StructuredBuffer<uint> struct_init_field_ordinal;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_ASSIGN_MISMATCH = 3u;
static const uint ERR_CONDITION_TYPE = 5u;
static const uint ERR_LOOP_CONTROL = 7u;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;
static const uint ERR_CALL_MISMATCH = 10u;

static const uint TYPE_REF_INVALID = 0u;

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint TY_FLOAT = 5u;
static const uint TY_CHAR = 6u;
static const uint TY_STRING = 7u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_FORM = 0u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_RIGHT = 2u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_tokens);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

bool valid_compact_field(uint row)
{
    return row != INVALID && row < active_compact_field_count();
}

void record_error(uint token_i, uint code, uint detail)
{
    record_min_token_error(status, token_i, code, detail);
}

bool valid_struct_field_key_row(uint field_row)
{
    if (!valid_compact_field(field_row))
        return false;

    HirField field = compact_fields[field_row];
    uint owner = field.owner;
    uint token_i = field.name_token;
    return owner < active_compact_hir_count() &&
           compact_hir_core[owner].kind == HIR_STRUCT_ITEM &&
           valid_token(token_i) &&
           name_id_by_token[token_i] != INVALID;
}

bool same_decl_field_key(uint left_row, uint right_row)
{
    if (!valid_struct_field_key_row(left_row) ||
        !valid_struct_field_key_row(right_row))
        return false;

    HirField left = compact_fields[left_row];
    HirField right = compact_fields[right_row];
    return left.owner == right.owner &&
           name_id_by_token[left.name_token] == name_id_by_token[right.name_token];
}

void validate_sorted_struct_field_key_row(uint row)
{
    if (row == 0u || row >= active_compact_field_count())
        return;

    uint left_row = struct_field_key_order[row - 1u];
    uint right_row = struct_field_key_order[row];
    if (same_decl_field_key(left_row, right_row))
    {
        uint token_i = compact_fields[right_row].name_token;
        record_error(valid_token(token_i) ? token_i : 0u, ERR_INVALID_MEMBER_ACCESS, 1u);
    }
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

uint result_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint expr_value_token(uint node)
{
    return expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
}

uint direct_arithmetic_operand_type(uint node)
{
    node = result_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        return visible_type_for_token(token_i);
    }

    return TY_UNKNOWN;
}

uint call_callee_token(uint call_node)
{
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return INVALID;

    uint callee_node = result_expr(hir_call_callee_node[call_node]);
    if (!valid_node(callee_node))
        return INVALID;

    if (hir_kind[callee_node] == HIR_MEMBER_EXPR)
    {
        uint member_token = hir_member_name_token[callee_node];
        return valid_token(member_token) ? member_token : INVALID;
    }

    uint token = expr_value_token(callee_node);
    if (!valid_token(token))
        token = hir_token_pos[callee_node];
    return valid_token(token) ? token : INVALID;
}

uint direct_expr_record_type(uint node)
{
    node = result_expr(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE)
        return TY_BOOL;
    if (form == HIR_EXPR_INT)
        return TY_INT;
    if (form == HIR_EXPR_FLOAT)
        return TY_FLOAT;
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
        form == HIR_EXPR_DIV)
    {
        uint left_ty = direct_arithmetic_operand_type(expr_slot(node, HIR_EXPR_RECORD_LEFT));
        uint right_ty = direct_arithmetic_operand_type(expr_slot(node, HIR_EXPR_RECORD_RIGHT));
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

uint direct_value_type(uint node)
{
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint record_ty = direct_expr_record_type(node);
    if (record_ty != TY_UNKNOWN)
        return record_ty;

    uint lit = hir_scalar_type_for_expr_form(expr_form(node));
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

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_token = call_callee_token(node);
        return valid_token(callee_token) ? call_return_type[callee_token] : TY_UNKNOWN;
    }

    return TY_UNKNOWN;
}

uint first_value_type_from_node(uint root, out uint value_token)
{
    value_token = INVALID;
    if (!valid_node(root))
        return TY_UNKNOWN;

    uint node = result_expr(root);
    uint ty = direct_value_type(node);
    if (ty != TY_UNKNOWN)
    {
        uint token_i = hir_token_pos[node];
        value_token = valid_token(token_i) ? token_i : INVALID;
        return ty;
    }
    return TY_UNKNOWN;
}

void validate_struct_literal_field_node(uint node)
{
    uint field_token = hir_token_pos[node];
    if (!valid_token(field_token))
        return;

    uint value_root = hir_struct_lit_field_value_node[node];
    uint literal_node = hir_struct_lit_field_parent_lit[node];
    if (!valid_node(literal_node) || !valid_node(value_root))
        return;
    if (!valid_token(struct_lit_context_decl_token[literal_node]))
        return;

    if (struct_init_field_ordinal[field_token] == INVALID)
    {
        record_error(field_token, ERR_INVALID_MEMBER_ACCESS, 0u);
        return;
    }

    uint expected = visible_type[field_token];
    if (expected == TY_UNKNOWN)
        return;

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

bool member_expr_is_marked_method_call(uint member_token)
{
    return valid_token(member_token) &&
           (method_call_name_id[member_token] != INVALID ||
            method_call_site_module_id[member_token] != INVALID);
}

bool member_expr_is_call_callee(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_MEMBER_EXPR)
        return false;
    uint call_node = hir_call_parent_by_callee[node];
    return valid_node(call_node) &&
           hir_kind[call_node] == HIR_CALL_EXPR &&
           hir_call_callee_node[call_node] == node;
}

void validate_member_expr_node(uint node)
{
    uint member_token = hir_member_name_token[node];
    if (!valid_token(member_token))
        return;

    if (member_expr_is_marked_method_call(member_token) || member_expr_is_call_callee(node))
        return;

    if (member_result_field_ordinal[member_token] != INVALID)
        return;

    uint receiver_tag = member_result_ref_tag[member_token];
    if (receiver_tag != TYPE_REF_INVALID)
    {
        record_error(member_token, ERR_INVALID_MEMBER_ACCESS, receiver_tag);
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;

    validate_sorted_struct_field_key_row(node);

    if (hir_kind[node] == HIR_MEMBER_EXPR)
        validate_member_expr_node(node);
    else if (valid_node(hir_struct_lit_field_parent_lit[node]) &&
             hir_kind[hir_struct_lit_field_parent_lit[node]] == HIR_STRUCT_LITERAL_EXPR)
        validate_struct_literal_field_node(node);
}
