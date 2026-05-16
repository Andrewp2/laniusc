// Validate aggregate member and struct-literal field records.
//
// This pass consumes parser/HIR member and struct-field metadata plus the
// field-result records published by the type-instance passes. It reports invalid
// field selections without scanning dot/brace token neighborhoods or comparing
// source spelling.

import generated_parse_production_ids;

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
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> member_result_ref_tag;
StructuredBuffer<uint> member_result_field_ordinal;

RWStructuredBuffer<uint> status;

static const uint INVALID = 0xffffffffu;
static const uint ERR_INVALID_MEMBER_ACCESS = 8u;

static const uint TYPE_REF_INVALID = 0u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_STRUCT_ITEM = 27u;

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

uint parent_node(uint node)
{
    uint p = valid_node(node) ? parent[node] : INVALID;
    return valid_node(p) ? p : INVALID;
}

uint first_child_node(uint node)
{
    uint child = valid_node(node) ? first_child[node] : INVALID;
    return valid_node(child) ? child : INVALID;
}

uint next_sibling_node(uint node)
{
    uint sibling = valid_node(node) ? next_sibling[node] : INVALID;
    return valid_node(sibling) ? sibling : INVALID;
}

void record_error(uint token_i, uint code, uint detail)
{
    uint old;
    InterlockedMin(status[1], token_i, old);
    if (token_i <= old)
    {
        status[0] = 0u;
        status[2] = code;
        status[3] = detail;
    }
}

bool same_name_id(uint left_token, uint right_token)
{
    if (!valid_token(left_token) || !valid_token(right_token))
        return false;
    uint left = name_id_by_token[left_token];
    uint right = name_id_by_token[right_token];
    return left != INVALID && left == right;
}

uint struct_node_for_literal(uint literal_node)
{
    uint head_node = valid_node(literal_node) ? hir_struct_lit_head_node[literal_node] : INVALID;
    uint head_token = valid_node(head_node) ? hir_token_pos[head_node] : INVALID;
    if (!valid_token(head_token))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_STRUCT_ITEM && same_name_id(hir_item_name_token[node], head_token))
            return node;
    }
    return INVALID;
}

bool struct_has_field(uint struct_node, uint field_token)
{
    if (!valid_node(struct_node) || !valid_token(field_token))
        return false;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_struct_field_parent_struct[node] != struct_node)
            continue;
        if (same_name_id(hir_token_pos[node], field_token))
            return true;
    }
    return false;
}

void validate_struct_literal_field_node(uint node)
{
    uint field_token = hir_token_pos[node];
    if (!valid_token(field_token))
        return;

    uint literal_node = hir_struct_lit_field_parent_lit[node];
    uint struct_node = struct_node_for_literal(literal_node);
    if (!valid_node(struct_node))
        return;

    if (!struct_has_field(struct_node, field_token))
        record_error(field_token, ERR_INVALID_MEMBER_ACCESS, 0u);
}

uint next_descendant_node(uint root, uint cur)
{
    uint child = first_child_node(cur);
    if (child != INVALID)
        return child;

    uint node = cur;
    [loop]
    for (uint guard = 0u; guard < 64u && node != INVALID; guard += 1u)
    {
        if (node == root)
            return INVALID;
        uint sibling = next_sibling_node(node);
        if (sibling != INVALID)
            return sibling;
        node = parent_node(node);
    }
    return INVALID;
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
