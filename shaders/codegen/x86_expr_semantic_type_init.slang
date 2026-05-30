// x86_64 expression numeric-type seed pass.
//
// Pareas carries node result types into codegen as attributed tree data. This
// pass seeds a backend numeric-type record from HIR/typechecker records and
// links expression nodes whose numeric mode is inherited from another
// expression node. Step passes pointer-jump those links.

import gpu_index;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> x86_call_type_record;
StructuredBuffer<uint> x86_decl_layout_record;
StructuredBuffer<uint> x86_param_reg_record;

RWStructuredBuffer<uint> x86_expr_semantic_record;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_MATCH_EXPR = 34u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_FORM = 0u;
static const uint EXPR_RECORD_LEFT = 1u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

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

static const uint TY_UNKNOWN = 0u;
static const uint TY_BOOL = 2u;
static const uint TY_INT = 3u;
static const uint TY_UINT = 4u;
static const uint EXPR_SEMANTIC_LINK_MASK = 0x3fffffffu;
static const uint EXPR_SEMANTIC_UINT_FLAG = 0x40000000u;

static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_PARAM_REG_STRIDE = 5u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool valid_token(uint token)
{
    return valid_index_or_invalid(token, gParams.n_tokens, INVALID);
}

uint compare_type(uint ty)
{
    return ty == TY_UINT ? TY_UINT : TY_UNKNOWN;
}

uint pack_expr_semantic_record(uint ty, uint link)
{
    uint packed_link =
        valid_node(link) && link < EXPR_SEMANTIC_LINK_MASK
            ? link
            : EXPR_SEMANTIC_LINK_MASK;
    uint type_bits = compare_type(ty) == TY_UINT ? EXPR_SEMANTIC_UINT_FLAG : 0u;
    return type_bits | packed_link;
}

uint expr_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_form(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_FORM) : 0u;
}

uint expr_left(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_LEFT) : INVALID;
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint expr_root_node(uint node)
{
    return valid_node(node) ? hir_expr_result_root_node[node] : INVALID;
}

uint call_type_word(uint call_node, uint slot)
{
    return row_major_load<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        slot,
        INVALID);
}

uint decl_layout_type(uint decl_token)
{
    return row_major_load<uint>(
        x86_decl_layout_record,
        decl_token,
        X86_DECL_LAYOUT_STRIDE,
        3u,
        INVALID);
}

uint param_reg_type(uint decl_token)
{
    return row_major_load<uint>(
        x86_param_reg_record,
        decl_token,
        X86_PARAM_REG_STRIDE,
        3u,
        INVALID);
}

uint visible_type_for_token(uint token_i)
{
    if (!valid_token(token_i))
        return TY_UNKNOWN;

    uint ty = visible_type[token_i];
    if (ty != TY_UNKNOWN && ty != INVALID)
        return ty;

    uint decl = visible_decl[token_i];
    if (valid_token(decl))
    {
        ty = visible_type[decl];
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;

        ty = param_reg_type(decl);
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;

        ty = decl_layout_type(decl);
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;
    }

    ty = call_return_type[token_i];
    return ty == INVALID ? TY_UNKNOWN : ty;
}

uint direct_expr_numeric_type(uint node)
{
    node = expr_root_node(node);
    if (!valid_node(node))
        return TY_UNKNOWN;

    uint form = expr_form(node);
    if (form == HIR_EXPR_TRUE || form == HIR_EXPR_FALSE || form == HIR_EXPR_NOT ||
        form == HIR_EXPR_AND || form == HIR_EXPR_OR)
        return TY_BOOL;

    if (form == HIR_EXPR_INT)
        return TY_INT;

    if (form == HIR_EXPR_NAME)
    {
        uint token_i = expr_value_token(node);
        if (!valid_token(token_i))
            token_i = hir_token_pos[node];
        return visible_type_for_token(token_i);
    }

    uint token_i = hir_token_pos[node];
    if (hir_kind[node] == HIR_INDEX_EXPR || hir_kind[node] == HIR_MEMBER_EXPR ||
        hir_kind[node] == HIR_MATCH_EXPR)
        return visible_type_for_token(token_i);

    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint ty = call_type_word(node, 0u);
        if (ty != TY_UNKNOWN && ty != INVALID)
            return ty;
        return visible_type_for_token(token_i);
    }

    return TY_UNKNOWN;
}

bool inherited_numeric_form(uint form)
{
    return form == HIR_EXPR_NEG ||
           form == HIR_EXPR_ADD ||
           form == HIR_EXPR_SUB ||
           form == HIR_EXPR_MUL ||
           form == HIR_EXPR_MOD ||
           form == HIR_EXPR_DIV ||
           form == HIR_EXPR_BIT_OR ||
           form == HIR_EXPR_BIT_XOR ||
           form == HIR_EXPR_BIT_AND ||
           form == HIR_EXPR_SHL ||
           form == HIR_EXPR_SHR ||
           form == HIR_EXPR_EQ ||
           form == HIR_EXPR_NE ||
           form == HIR_EXPR_LT ||
           form == HIR_EXPR_GT ||
           form == HIR_EXPR_LE ||
           form == HIR_EXPR_GE;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    uint resolved = expr_root_node(node);
    if (!valid_node(resolved))
    {
        x86_expr_semantic_record[node] = pack_expr_semantic_record(TY_UNKNOWN, INVALID);
        return;
    }

    uint ty = direct_expr_numeric_type(resolved);
    if (ty != TY_UNKNOWN)
    {
        x86_expr_semantic_record[node] = pack_expr_semantic_record(ty, INVALID);
        return;
    }

    uint form = expr_form(resolved);
    uint left = expr_left(resolved);
    uint link = inherited_numeric_form(form) && valid_node(left)
                    ? expr_root_node(left)
                    : INVALID;
    x86_expr_semantic_record[node] = pack_expr_semantic_record(TY_UNKNOWN, link);
}
