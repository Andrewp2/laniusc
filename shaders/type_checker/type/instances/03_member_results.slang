// HIR member field result projection.
//
// The preceding member-receiver pass records the initial receiver type for
// every member-chain root and links consecutive member nodes. One lane owns
// each independent chain and carries the exact result ref through sorted
// (struct, field-name) lookups. Generic fields are substituted before the next
// transition, so layout and result types remain receiver-dependent at every
// depth without token rescans or fixed retry counts.

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
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_ordinal;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> struct_field_key_order;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_arg_start;
StructuredBuffer<uint> type_instance_arg_count;
StructuredBuffer<uint> type_instance_arg_ref_tag;
StructuredBuffer<uint> type_instance_arg_ref_payload;
StructuredBuffer<uint> type_instance_arg_row_start;
StructuredBuffer<uint> type_instance_arg_row_count_out;
StructuredBuffer<uint> type_instance_arg_row_ref_tag;
StructuredBuffer<uint> type_instance_arg_row_ref_payload;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> member_next_node;

RWStructuredBuffer<uint> member_result_context_instance;
RWStructuredBuffer<uint> member_result_ref_tag;
RWStructuredBuffer<uint> member_result_ref_payload;
RWStructuredBuffer<uint> member_result_field_ordinal;
RWStructuredBuffer<uint> member_result_field_node;

static const uint INVALID = 0xffffffffu;

static const uint HIR_STRUCT_ITEM = 27u;
static const uint TYPE_REF_INVALID = 0u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint TYPE_REF_INSTANCE = 3u;

static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
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

uint instance_arg_ref_index(uint instance, uint slot)
{
    uint start = type_instance_arg_start[instance];
    return start == INVALID ? INVALID : start + slot;
}

uint instance_arg_row_ref_index(uint instance, uint slot)
{
    uint start = type_instance_arg_row_start[instance];
    uint ref_i = start == INVALID ? INVALID : start + slot;
    return ref_i != INVALID && ref_i < type_instance_arg_row_count_out[0u]
        ? ref_i
        : INVALID;
}

bool instance_arg_ref(uint instance, uint slot, out uint tag, out uint payload)
{
    tag = TYPE_REF_INVALID;
    payload = INVALID;
    if (!valid_token(instance) || slot >= type_instance_arg_count[instance])
        return false;

    uint row_i = instance_arg_row_ref_index(instance, slot);
    if (row_i != INVALID)
    {
        tag = type_instance_arg_row_ref_tag[row_i];
        payload = type_instance_arg_row_ref_payload[row_i];
        if (tag != TYPE_REF_INVALID)
            return payload != INVALID;
    }

    uint ref_i = instance_arg_ref_index(instance, slot);
    if (ref_i == INVALID)
        return false;
    tag = type_instance_arg_ref_tag[ref_i];
    payload = type_instance_arg_ref_payload[ref_i];
    return tag != TYPE_REF_INVALID && payload != INVALID;
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

void publish_member_field_chain_for_root(uint member_node)
{
    if (!valid_node(member_node) || hir_kind[member_node] != HIR_MEMBER_EXPR)
        return;
    if (member_expr_is_call_callee(member_node))
        return;

    uint receiver_node = hir_member_receiver_node[member_node];
    if (valid_node(receiver_node) && hir_kind[receiver_node] == HIR_MEMBER_EXPR)
        return;

    uint first_token = hir_member_name_token[member_node];
    if (!valid_token(first_token))
        return;
    uint receiver_tag = member_result_ref_tag[first_token];
    uint receiver_payload = member_result_ref_payload[first_token];
    if (receiver_tag == TYPE_REF_INVALID || receiver_payload == INVALID)
        return;

    uint steps = 0u;
    while (valid_node(member_node) &&
           hir_kind[member_node] == HIR_MEMBER_EXPR &&
           steps < active_hir_node_count())
    {
        uint member_token = hir_member_name_token[member_node];
        if (!valid_token(member_token) || member_expr_is_call_callee(member_node))
            return;

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

        uint context_instance = receiver_tag == TYPE_REF_INSTANCE && valid_token(receiver_payload)
            ? receiver_payload
            : INVALID;
        if (tag == TYPE_REF_GENERIC_PARAM)
        {
            if (!valid_token(payload))
                return;
            uint slot = type_generic_param_slot_by_token[payload];
            if (slot == INVALID || context_instance == INVALID ||
                !instance_arg_ref(context_instance, slot, tag, payload))
                return;
        }

        member_result_context_instance[member_token] = context_instance;
        member_result_field_ordinal[member_token] =
            ordinal_for_field_node(struct_node, field_node);
        member_result_field_node[member_token] = field_node;
        member_result_ref_tag[member_token] = tag;
        member_result_ref_payload[member_token] = payload;

        receiver_tag = tag;
        receiver_payload = payload;
        member_node = member_next_node[member_node];
        steps += 1u;
    }
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    uint node = linear_thread_id(dtid);
    if (!valid_node(node))
        return;
    publish_member_field_chain_for_root(node);
}
