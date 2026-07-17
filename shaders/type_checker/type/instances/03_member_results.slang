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

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_call_parent_by_callee;
StructuredBuffer<uint> hir_member_receiver_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
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
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_tokens);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

bool valid_compact_node(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

bool valid_compact_field(uint row)
{
    return row != INVALID && row < active_compact_field_count();
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
    return valid_compact_node(node) && compact_hir_core[node].kind == HIR_STRUCT_ITEM
        ? node
        : INVALID;
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
        uint field_row = row < active_compact_field_count() ? struct_field_key_order[row] : INVALID;
        if (!valid_compact_field(field_row))
            return 0u;
        HirField field = compact_fields[field_row];
        uint owner = field.owner;
        uint token = field.name_token;
        uint name_id = valid_token(token) ? name_id_by_token[token] : INVALID;
        if (!valid_compact_node(owner) ||
            compact_hir_core[owner].kind != HIR_STRUCT_ITEM || name_id == INVALID)
            return 0u;
        if (lane == 0u)
            return fixed_key_encode_nullable_u32(owner, INVALID);
        if (lane == 1u)
            return fixed_key_encode_nullable_u32(name_id, INVALID);
        return fixed_key_encode_nullable_u32(field_row, INVALID);
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

uint field_row_for_member(uint struct_node, uint member_token)
{
    if (!valid_compact_node(struct_node) || !valid_token(member_token))
        return INVALID;

    uint name_id = name_id_by_token[member_token];
    if (name_id == INVALID)
        return INVALID;

    StructFieldLookupKey key;
    key.struct_node = struct_node;
    key.name_id = name_id;
    QueryRange range = equal_range_query<StructFieldLookupKey, StructFieldKeyCompare>(
        active_compact_field_count(),
        key);
    if (range.end != range.begin + 1u)
        return INVALID;
    uint field_row = struct_field_key_order[range.begin];
    return valid_compact_field(field_row) ? field_row : INVALID;
}

uint ordinal_for_field_row(uint struct_node, uint field_row)
{
    if (!valid_compact_node(struct_node) || !valid_compact_field(field_row))
        return INVALID;
    return compact_fields[field_row].owner == struct_node
               ? compact_fields[field_row].ordinal
               : INVALID;
}

uint type_head_token_for_compact_node(uint type_node)
{
    if (!valid_compact_node(type_node))
        return INVALID;
    uint path_i = path_id_by_owner_hir[type_node];
    uint path_count = min(path_count_out[0u], gParams.n_hir_nodes);
    if (path_i != INVALID && path_i < path_count)
    {
        uint count = path_segment_count[path_i];
        if (count != 0u)
        {
            uint row = path_segment_base[path_i] + count - 1u;
            uint leaf = row < gParams.n_tokens ? path_segment_token[row] : INVALID;
            if (valid_token(leaf))
                return leaf;
        }
    }
    uint token = compact_hir_core[type_node].token_start;
    return valid_token(token) ? token : INVALID;
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
        uint field_row = field_row_for_member(struct_node, member_token);
        if (!valid_compact_field(field_row))
            return;

        HirField field = compact_fields[field_row];
        uint type_token = type_head_token_for_compact_node(field.value);
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
            ordinal_for_field_row(struct_node, field_row);
        // The backend-facing artifact carries a stable source-token identity,
        // never a raw parser row.
        member_result_field_node[member_token] = field.name_token;
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
