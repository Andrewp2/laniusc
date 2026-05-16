// Record struct-literal field expectations from parser-owned HIR metadata.
//
// This pass does not substitute generic arguments itself. It publishes the
// declaration-side field ref plus the contextual type-instance token; the next
// pass substitutes generic slots using the type-instance argument table.

import generated_parse_production_ids;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> parent;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_instance_decl_token;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;

static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;

uint linear_thread_id(uint3 dtid)
{
    return dtid.x + dtid.y * MAX_GROUPS_X * WG_SIZE;
}

uint active_token_count()
{
    return gParams.n_tokens;
}

uint active_node_count()
{
    return gParams.n_hir_nodes;
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

bool has_ancestor_node(uint node_i, uint ancestor_i)
{
    if (!valid_node(node_i) || !valid_node(ancestor_i))
        return false;

    uint cur = node_i;
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (cur == ancestor_i)
            return true;
        if (!valid_node(cur))
            return false;
        cur = parent[cur];
    }
    return false;
}

uint ancestor_with_production(uint node_i, uint prod)
{
    uint cur = node_i;
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        uint p = parent[cur];
        if (!valid_node(p))
            return INVALID;
        if (node_kind[p] == prod)
            return p;
        cur = p;
    }
    return INVALID;
}

bool is_item_decl_production(uint prod)
{
    return prod == PROD_FN || prod == PROD_EXTERN_FN || prod == PROD_TYPE_ALIAS ||
           prod == PROD_IMPL || prod == PROD_TRAIT || prod == PROD_ENUM || prod == PROD_STRUCT;
}

bool is_type_expr_production(uint prod)
{
    return prod == PROD_TYPE_IDENT || prod == PROD_TYPE_ARRAY || prod == PROD_TYPE_REF;
}

uint item_decl_ancestor(uint node_i)
{
    uint cur = node_i;
    [loop]
    for (uint guard = 0u; guard < 96u; guard += 1u)
    {
        if (!valid_node(cur))
            return INVALID;
        if (is_item_decl_production(node_kind[cur]))
            return cur;
        cur = parent[cur];
    }
    return INVALID;
}

uint first_type_expr_descendant(uint root_i)
{
    if (!valid_node(root_i))
        return INVALID;

    uint n = active_node_count();
    [loop]
    for (uint j = 0u; j < n; j += 1u)
    {
        if (is_type_expr_production(node_kind[j]) && has_ancestor_node(j, root_i))
            return j;
    }
    return INVALID;
}

uint type_head_token_for_node(uint type_node)
{
    if (!valid_node(type_node))
        return INVALID;
    uint type_head = hir_token_pos[type_node];
    return valid_token(type_head) ? type_head : INVALID;
}

uint instance_from_type_node(uint type_node)
{
    uint type_head = type_head_token_for_node(type_node);
    if (!valid_token(type_head) || !valid_token(type_instance_decl_token[type_head]))
        return INVALID;
    return type_head;
}

uint let_annotation_type_node(uint let_node)
{
    if (!valid_node(let_node))
        return INVALID;

    uint n = active_node_count();
    [loop]
    for (uint j = 0u; j < n; j += 1u)
    {
        if (node_kind[j] == PROD_LET_TYPE && has_ancestor_node(j, let_node))
            return first_type_expr_descendant(j);
    }
    return INVALID;
}

uint context_instance_for_struct_literal_node(uint literal_node)
{
    uint let_node = ancestor_with_production(literal_node, PROD_LET_STMT);
    return instance_from_type_node(let_annotation_type_node(let_node));
}

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;

    uint n = active_node_count();
    [loop]
    for (uint j = 0u; j < n; j += 1u)
    {
        if (node_kind[j] == PROD_STRUCT && hir_item_name_token[j] == decl_token)
            return j;
    }
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

bool literal_head_matches_decl(uint literal_node, uint decl_token)
{
    uint head_node = hir_struct_lit_head_node[literal_node];
    if (!valid_node(head_node) || !valid_token(decl_token))
        return false;
    return same_name_id(hir_token_pos[head_node], decl_token);
}

bool field_node_for_literal_field(uint struct_node, uint field_token, out uint field_node, out uint field_ordinal)
{
    field_node = INVALID;
    field_ordinal = INVALID;
    if (!valid_node(struct_node) || !valid_token(field_token))
        return false;

    uint field_name = name_id_by_token[field_token];
    if (field_name == INVALID)
        return false;

    uint ordinal = 0u;
    uint n = active_node_count();
    [loop]
    for (uint j = 0u; j < n; j += 1u)
    {
        if (node_kind[j] != PROD_STRUCT_FIELD ||
            hir_struct_field_parent_struct[j] != struct_node)
            continue;

        uint decl_field_token = hir_token_pos[j];
        if (valid_token(decl_field_token) && name_id_by_token[decl_field_token] == field_name)
        {
            field_node = j;
            field_ordinal = ordinal;
            return true;
        }
        ordinal += 1u;
    }
    return false;
}

uint generic_param_slot_for_name(uint decl_node, uint param_token)
{
    if (!valid_node(decl_node) || !valid_token(param_token))
        return INVALID;

    uint param_name = name_id_by_token[param_token];
    if (param_name == INVALID)
        return INVALID;

    uint slot = 0u;
    uint n = active_node_count();
    [loop]
    for (uint j = 0u; j < n; j += 1u)
    {
        if (node_kind[j] != PROD_ENUM_TYPE_PARAM || item_decl_ancestor(j) != decl_node)
            continue;

        uint decl_param_token = hir_token_pos[j];
        if (valid_token(decl_param_token) && name_id_by_token[decl_param_token] == param_name)
            return slot;
        slot += 1u;
    }
    return INVALID;
}

void publish_struct_init_field_node(uint field_node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[field_node];
    if (!valid_node(literal_node))
        return;

    uint field_token = hir_token_pos[field_node];
    if (!valid_token(field_token))
        return;

    uint instance_i = context_instance_for_struct_literal_node(literal_node);
    if (!valid_token(instance_i))
        return;

    uint decl_token = type_instance_decl_token[instance_i];
    if (!valid_token(decl_token) || !literal_head_matches_decl(literal_node, decl_token))
        return;

    uint struct_node = struct_node_for_decl_token(decl_token);
    if (!valid_node(struct_node))
        return;

    uint decl_field_node;
    uint field_ordinal;
    if (!field_node_for_literal_field(struct_node, field_token, decl_field_node, field_ordinal))
        return;

    uint field_type_node = hir_struct_field_type_node[decl_field_node];
    uint type_head = type_head_token_for_node(field_type_node);
    if (!valid_token(type_head))
        return;

    uint tag = type_expr_ref_tag[type_head];
    uint payload = type_expr_ref_payload[type_head];
    if (tag == TYPE_REF_GENERIC_PARAM)
        payload = generic_param_slot_for_name(struct_node, payload);

    struct_init_field_context_instance[field_token] = instance_i;
    struct_init_field_expected_ref_tag[field_token] = tag;
    struct_init_field_expected_ref_payload[field_token] = payload;
    struct_init_field_ordinal[field_token] = field_ordinal;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (!valid_node(i) || node_kind[i] != PROD_STRUCT_LIT_FIELD)
        return;
    publish_struct_init_field_node(i);
}
