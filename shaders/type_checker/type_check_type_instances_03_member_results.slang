// HIR member field result projection.
//
// The preceding member-receiver pass records the receiver type ref and receiver
// instance for every HIR member expression. This pass projects the selected
// struct field from parser-owned struct metadata and interned field-name ids.
// It does not read source bytes, token spellings, or token kinds.

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
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;

RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;

static const uint INVALID = 0xffffffffu;

static const uint HIR_STRUCT_ITEM = 27u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

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

uint member_node_for_token(uint member_token)
{
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] != 21u)
            continue;
        if (hir_member_name_token[node] == member_token)
            return node;
    }
    return INVALID;
}

uint scalar_struct_decl_token(uint payload)
{
    if (payload >= TY_STRUCT_BASE && payload < TY_ENUM_BASE)
        return payload - TY_STRUCT_BASE;
    return INVALID;
}

uint receiver_decl_token(uint tag, uint payload)
{
    if (tag == TYPE_REF_INSTANCE && valid_token(payload))
    {
        uint decl_token = type_instance_decl_token[payload];
        return valid_token(decl_token) ? decl_token : INVALID;
    }
    if (tag == TYPE_REF_SCALAR)
        return scalar_struct_decl_token(payload);
    return INVALID;
}

bool same_name_id(uint left_token, uint right_token)
{
    if (!valid_token(left_token) || !valid_token(right_token))
        return false;
    uint left = name_id_by_token[left_token];
    uint right = name_id_by_token[right_token];
    return left != INVALID && left == right;
}

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_kind[node] == HIR_STRUCT_ITEM && same_name_id(hir_item_name_token[node], decl_token))
            return node;
    }
    return INVALID;
}

uint field_node_for_member(uint struct_node, uint member_token)
{
    if (!valid_node(struct_node) || !valid_token(member_token))
        return INVALID;

    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_struct_field_parent_struct[node] != struct_node)
            continue;
        uint field_token = hir_token_pos[node];
        if (same_name_id(field_token, member_token))
            return node;
    }
    return INVALID;
}

uint ordinal_for_field_node(uint struct_node, uint field_node)
{
    if (!valid_node(struct_node) || !valid_node(field_node))
        return INVALID;

    uint ordinal = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (hir_struct_field_parent_struct[node] != struct_node)
            continue;
        if (node == field_node)
            return ordinal;
        ordinal += 1u;
    }
    return INVALID;
}

uint generic_decl_ancestor(uint node)
{
    uint cur = node;
    [loop]
    for (uint guard = 0u; guard < 128u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (cur != node && hir_kind[cur] == HIR_STRUCT_ITEM)
            return cur;
        uint p = parent[cur];
        if (!valid_node(p) || p == cur)
            return INVALID;
        cur = p;
    }
    return INVALID;
}

uint generic_param_slot_for_name(uint decl_node, uint param_token)
{
    if (!valid_node(decl_node) || !valid_token(param_token))
        return INVALID;

    uint param_name = name_id_by_token[param_token];
    if (param_name == INVALID)
        return INVALID;

    uint slot = 0u;
    uint n = active_hir_node_count();
    [loop]
    for (uint node = 0u; node < n; node += 1u)
    {
        if (node_kind[node] != PROD_ENUM_TYPE_PARAM || generic_decl_ancestor(node) != decl_node)
            continue;

        uint decl_param_token = hir_token_pos[node];
        if (valid_token(decl_param_token) && name_id_by_token[decl_param_token] == param_name)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

void publish_member_field_ref(uint member_token)
{
    uint member_node = member_node_for_token(member_token);
    if (!valid_node(member_node))
        return;

    uint receiver_tag = member_result_ref_tag[member_token];
    uint receiver_payload = member_result_ref_payload[member_token];
    uint decl_token = receiver_decl_token(receiver_tag, receiver_payload);
    if (!valid_token(decl_token))
        return;

    uint struct_node = struct_node_for_decl_token(decl_token);
    uint field_node = field_node_for_member(struct_node, member_token);
    if (!valid_node(field_node))
        return;
    member_result_field_ordinal[member_token] = ordinal_for_field_node(struct_node, field_node);

    uint type_node = hir_struct_field_type_node[field_node];
    if (!valid_node(type_node))
        return;
    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_GENERIC_PARAM)
        payload = generic_param_slot_for_name(struct_node, payload);

    member_result_ref_tag[member_token] = tag;
    member_result_ref_payload[member_token] = payload;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint token = linear_thread_id(dtid);
    if (!valid_token(token))
        return;
    if (member_result_ref_tag[token] == TYPE_REF_INVALID)
        return;
    publish_member_field_ref(token);
}
