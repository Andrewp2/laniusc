// Record struct-literal field expectations from parser-owned HIR metadata.
//
// This pass does not substitute generic arguments itself. It publishes the
// declaration-side field ref plus the contextual type-instance token; the next
// pass substitutes generic slots using the type-instance argument table.
// Generic field refs use the precomputed generic-parameter slot table instead
// of scanning declaration subtrees.

import fixed_key;
import generated_parse_production_ids;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

StructuredBuffer<uint> node_kind;
StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> struct_field_key_order;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> struct_lit_context_decl_token;
StructuredBuffer<uint> struct_lit_context_instance;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;
RWStructuredBuffer<uint> struct_init_field_ordinal_by_node;

static const uint INVALID = 0xffffffffu;

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
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

bool valid_token(uint i)
{
    return i != INVALID && i < active_token_count();
}

bool valid_node(uint i)
{
    return i != INVALID && i < active_node_count();
}

uint type_head_token_for_node(uint type_node)
{
    if (!valid_node(type_node))
        return INVALID;

    // Type-instance collection publishes the leaf of each parser-owned path
    // type. Consumers use that record instead of rescanning the type subtree.
    uint leaf_node = hir_type_path_leaf_node[type_node];
    if (valid_node(leaf_node))
    {
        uint leaf = hir_token_pos[leaf_node];
        if (valid_token(leaf))
            return leaf;
    }

    uint value_node = hir_type_value_node[type_node];
    if (valid_node(value_node))
    {
        uint value_head = hir_token_pos[value_node];
        if (valid_token(value_head))
            return value_head;
    }
    uint type_head = hir_token_pos[type_node];
    return valid_token(type_head) ? type_head : INVALID;
}

bool context_for_struct_literal_node(uint literal_node, out uint decl_token, out uint instance_i)
{
    decl_token = INVALID;
    instance_i = INVALID;
    if (!valid_node(literal_node))
        return false;

    decl_token = struct_lit_context_decl_token[literal_node];
    instance_i = struct_lit_context_instance[literal_node];
    return valid_token(decl_token);
}

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    uint node = type_decl_hir_node_by_token[decl_token];
    return valid_node(node) && node_kind[node] == PROD_STRUCT ? node : INVALID;
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

public struct StructFieldLookupKey
{
    uint struct_node;
    uint name_id;
}

public struct StructFieldFixedKey : IFixedU32RowKey<StructFieldLookupKey>
{
    public static uint row_lane(uint row, uint lane)
    {
        uint field_node = row < active_node_count() ? struct_field_key_order[row] : INVALID;
        if (!valid_node(field_node) || node_kind[field_node] != PROD_STRUCT_FIELD)
            return 0u;
        uint owner = hir_struct_field_parent_struct[field_node];
        uint token = hir_token_pos[field_node];
        uint name_id = valid_token(token) ? name_id_by_token[token] : INVALID;
        if (!valid_node(owner) || name_id == INVALID)
            return 0u;
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(owner, INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(name_id, INVALID);
        return fixed_key_encode_nullable_u32(field_node, INVALID);
    }

    public static uint key_lane(StructFieldLookupKey key, uint lane)
    {
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(key.struct_node, INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(key.name_id, INVALID);
        return 0u;
    }
}

public struct StructFieldKeyCompare : IRowQueryCompare<StructFieldLookupKey>
{
    public static int compare(uint row, StructFieldLookupKey key)
    {
        return fixed_u32_row_key_compare<StructFieldLookupKey, StructFieldFixedKey>(
            row,
            key,
            2u);
    }
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

    StructFieldLookupKey key;
    key.struct_node = struct_node;
    key.name_id = field_name;
    QueryRange range = equal_range_query<StructFieldLookupKey, StructFieldKeyCompare>(
        active_node_count(),
        key);
    if (range.end != range.begin + 1u)
        return false;

    field_node = struct_field_key_order[range.begin];
    if (!valid_node(field_node) ||
        node_kind[field_node] != PROD_STRUCT_FIELD ||
        hir_struct_field_parent_struct[field_node] != struct_node)
        return false;
    field_ordinal = hir_struct_field_ordinal[field_node];
    return field_ordinal != INVALID;
}

void publish_struct_init_field_node(uint field_node)
{
    uint literal_node = hir_struct_lit_field_parent_lit[field_node];
    if (!valid_node(literal_node))
        return;

    uint field_token = hir_token_pos[field_node];
    if (!valid_token(field_token))
        return;

    uint decl_token = INVALID;
    uint instance_i = INVALID;
    if (!context_for_struct_literal_node(literal_node, decl_token, instance_i))
        return;
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
    {
        if (!valid_token(payload))
            return;
        payload = type_generic_param_slot_by_token[payload];
        if (payload == INVALID)
            return;
    }

    struct_init_field_context_instance[field_token] = instance_i;
    struct_init_field_expected_ref_tag[field_token] = tag;
    struct_init_field_expected_ref_payload[field_token] = payload;
    struct_init_field_ordinal[field_token] = field_ordinal;
    struct_init_field_ordinal_by_node[field_node] = field_ordinal;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint i = linear_thread_id(dtid);
    if (!valid_node(i))
        return;

    struct_init_field_ordinal_by_node[i] = INVALID;

    if (node_kind[i] != PROD_STRUCT_LIT_FIELD)
        return;
    publish_struct_init_field_node(i);
}
