// HIR member field result projection.
//
// The preceding member-receiver pass records the receiver type ref and receiver
// instance for every HIR member expression. This pass projects the selected
// struct field from parser-owned struct metadata and interned field-name ids.
// Generic field refs use the precomputed generic-parameter slot table instead
// of scanning declaration subtrees.

import fixed.key;
import range_query;

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
StructuredBuffer<uint> hir_expr_result_root_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> struct_field_key_order;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_decl_hir_node_by_token;

RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;

static const uint INVALID = 0xffffffffu;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_INDEX_EXPR = 20u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_REF_ERROR = 4u;

static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;

static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint WG_SIZE = 256u;
static const uint MAX_GROUPS_X = 65535u;
static const uint HIR_EXPR_RECORD_STRIDE = 4u;
static const uint HIR_EXPR_RECORD_LEFT = 1u;
static const uint HIR_EXPR_RECORD_VALUE_TOKEN = 3u;

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

uint result_expr(uint node)
{
    if (!valid_node(node))
        return INVALID;
    uint root = hir_expr_result_root_node[node];
    return valid_node(root) ? root : node;
}

uint name_or_path_token_for_node(uint node)
{
    if (!valid_node(node) ||
        (hir_kind[node] != HIR_NAME_EXPR && hir_kind[node] != HIR_PATH_EXPR))
        return INVALID;

    uint token = expr_slot(node, HIR_EXPR_RECORD_VALUE_TOKEN);
    return valid_token(token) ? token : INVALID;
}

uint name_token_for_expr(uint node)
{
    uint token = name_or_path_token_for_node(node);
    if (valid_token(token))
        return token;

    return name_or_path_token_for_node(result_expr(node));
}

uint scalar_struct_decl_token(uint payload)
{
    if (payload >= TY_STRUCT_BASE && payload < TY_ENUM_BASE)
        return payload - TY_STRUCT_BASE;
    return INVALID;
}

bool array_or_slice_instance_from_ref(uint ref_tag, uint ref_payload, out uint instance)
{
    instance = INVALID;
    if (ref_tag != TYPE_REF_INSTANCE || !valid_token(ref_payload))
        return false;

    uint kind = type_instance_kind[ref_payload];
    if (kind != TYPE_INSTANCE_ARRAY && kind != TYPE_INSTANCE_SLICE)
        return false;

    uint elem_tag = type_instance_elem_ref_tag[ref_payload];
    uint elem_payload = type_instance_elem_ref_payload[ref_payload];
    if (elem_tag == TYPE_REF_INVALID || elem_tag == TYPE_REF_ERROR ||
        elem_payload == INVALID)
        return false;

    instance = ref_payload;
    return true;
}

bool indexed_receiver_element_ref(uint member_node, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;

    uint receiver_node = valid_node(member_node) ? hir_member_receiver_node[member_node] : INVALID;
    if (!valid_node(receiver_node) || hir_kind[receiver_node] != HIR_INDEX_EXPR)
        return false;

    uint receiver_base = expr_slot(receiver_node, HIR_EXPR_RECORD_LEFT);
    uint receiver_token = name_token_for_expr(receiver_base);
    uint receiver_decl = valid_token(receiver_token) ? visible_decl[receiver_token] : INVALID;
    if (!valid_token(receiver_decl))
        return false;

    uint array_instance = INVALID;
    if (!array_or_slice_instance_from_ref(
            decl_type_ref_tag[receiver_decl],
            decl_type_ref_payload[receiver_decl],
            array_instance))
        return false;

    tag = type_instance_elem_ref_tag[array_instance];
    payload = type_instance_elem_ref_payload[array_instance];
    return tag != TYPE_REF_INVALID && tag != TYPE_REF_ERROR && payload != INVALID;
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

uint struct_node_for_decl_token(uint decl_token)
{
    if (!valid_token(decl_token))
        return INVALID;
    uint node = type_decl_hir_node_by_token[decl_token];
    return valid_node(node) && hir_kind[node] == HIR_STRUCT_ITEM ? node : INVALID;
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
        uint field_node = row < active_hir_node_count() ? struct_field_key_order[row] : INVALID;
        if (!valid_node(field_node))
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

uint field_node_for_member(uint struct_node, uint member_token)
{
    if (!valid_node(struct_node) || !valid_token(member_token))
        return INVALID;

    uint name_id = name_id_by_token[member_token];
    if (name_id == INVALID)
        return INVALID;

    StructFieldLookupKey key;
    key.struct_node = struct_node;
    key.name_id = name_id;
    QueryRange range = equal_range_query<StructFieldLookupKey, StructFieldKeyCompare>(
        active_hir_node_count(),
        key);
    if (range.end != range.begin + 1u)
        return INVALID;
    uint field_node = struct_field_key_order[range.begin];
    return valid_node(field_node) ? field_node : INVALID;
}

uint ordinal_for_field_node(uint struct_node, uint field_node)
{
    if (!valid_node(struct_node) || !valid_node(field_node))
        return INVALID;
    return hir_struct_field_parent_struct[field_node] == struct_node
               ? hir_struct_field_ordinal[field_node]
               : INVALID;
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

void publish_member_field_ref_for_node(uint member_node)
{
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;

    uint member_token = hir_member_name_token[member_node];
    if (!valid_token(member_token))
        return;

    if (member_expr_is_call_callee(member_node))
        return;

    uint receiver_tag = member_result_ref_tag[member_token];
    uint receiver_payload = member_result_ref_payload[member_token];
    uint indexed_tag = TYPE_REF_INVALID;
    uint indexed_payload = INVALID;
    if (indexed_receiver_element_ref(member_node, indexed_tag, indexed_payload))
    {
        receiver_tag = indexed_tag;
        receiver_payload = indexed_payload;
    }
    uint decl_token = receiver_decl_token(receiver_tag, receiver_payload);
    if (!valid_token(decl_token))
        return;

    uint struct_node = struct_node_for_decl_token(decl_token);
    uint field_node = field_node_for_member(struct_node, member_token);
    if (!valid_node(field_node))
        return;

    uint type_node = hir_struct_field_type_node[field_node];
    if (!valid_node(type_node))
        return;
    uint type_token = hir_token_pos[type_node];
    if (!valid_token(type_token))
        return;

    uint tag = type_expr_ref_tag[type_token];
    uint payload = type_expr_ref_payload[type_token];
    if (tag == TYPE_REF_INVALID || payload == INVALID)
        return;

    if (tag == TYPE_REF_GENERIC_PARAM)
    {
        if (!valid_token(payload))
            return;
        payload = type_generic_param_slot_by_token[payload];
        if (payload == INVALID)
            return;
    }

    member_result_field_ordinal[member_token] = ordinal_for_field_node(struct_node, field_node);
    member_result_field_node[member_token] = field_node;
    member_result_ref_tag[member_token] = tag;
    member_result_ref_payload[member_token] = payload;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    publish_member_field_ref_for_node(node);
}
