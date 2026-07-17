// Record struct-literal field expectations from parser-owned HIR metadata.
//
// This pass does not substitute generic arguments itself. It publishes the
// declaration-side field ref plus the contextual type-instance token; the next
// pass substitutes generic slots using the type-instance argument table.
// Generic field refs use the precomputed generic-parameter slot table instead
// of scanning declaration subtrees.

import fixed.key;
import range_query;

struct Params
{
    uint n_tokens;
    uint source_len;
    uint n_hir_nodes;
    uint n_source_files;
    uint parser_feature_flags;
};

ConstantBuffer<Params> gParams;

struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };

static const uint PARSER_FEATURE_STRUCTS = 0x00000010u;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_struct_lit_head_node;
StructuredBuffer<uint> hir_struct_lit_field_parent_lit;
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> struct_field_key_order;
StructuredBuffer<uint> name_id_by_token;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> type_generic_param_slot_by_token;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> path_segment_count;
StructuredBuffer<uint> path_segment_base;
StructuredBuffer<uint> path_segment_token;
StructuredBuffer<uint> struct_lit_context_decl_token;
StructuredBuffer<uint> struct_lit_context_instance;

RWStructuredBuffer<uint> struct_init_field_context_instance;
RWStructuredBuffer<uint> struct_init_field_expected_ref_tag;
RWStructuredBuffer<uint> struct_init_field_expected_ref_payload;
RWStructuredBuffer<uint> struct_init_field_ordinal;
RWStructuredBuffer<uint> struct_init_field_ordinal_by_node;
RWStructuredBuffer<uint> struct_init_field_decl_node_by_node;
RWStructuredBuffer<uint> struct_init_field_ordinal_by_row;
RWStructuredBuffer<uint> struct_init_field_decl_token_by_row;

static const uint INVALID = 0xffffffffu;

static const uint TYPE_REF_GENERIC_PARAM = 2u;
static const uint HIR_STRUCT_ITEM = 27u;
static const uint HIR_STRUCT_LITERAL_EXPR = 28u;

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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_tokens);
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_tokens);
}

bool valid_compact_node(uint i)
{
    return i != INVALID && i < active_compact_hir_count();
}

bool valid_compact_field(uint i)
{
    return i != INVALID && i < active_compact_field_count();
}

uint compact_field_row_for_name_token(uint name_token)
{
    if (!valid_token(name_token))
        return INVALID;
    uint begin = 0u;
    uint end = active_compact_field_count();
    while (begin < end)
    {
        uint middle = begin + (end - begin) / 2u;
        if (compact_fields[middle].name_token < name_token)
            begin = middle + 1u;
        else
            end = middle;
    }
    return begin < active_compact_field_count() &&
           compact_fields[begin].name_token == name_token
               ? begin
               : INVALID;
}

uint type_head_token_for_node(uint type_node)
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

    uint type_head = compact_hir_core[type_node].token_start;
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
    return valid_compact_node(node) && compact_hir_core[node].kind == HIR_STRUCT_ITEM
        ? node
        : INVALID;
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

bool field_row_for_literal_field(uint struct_node, uint field_token, out uint field_row, out uint field_ordinal)
{
    field_row = INVALID;
    field_ordinal = INVALID;
    if (!valid_compact_node(struct_node) || !valid_token(field_token))
        return false;

    uint field_name = name_id_by_token[field_token];
    if (field_name == INVALID)
        return false;

    StructFieldLookupKey key;
    key.struct_node = struct_node;
    key.name_id = field_name;
    QueryRange range = equal_range_query<StructFieldLookupKey, StructFieldKeyCompare>(
        active_compact_field_count(),
        key);
    if (range.end != range.begin + 1u)
        return false;

    field_row = struct_field_key_order[range.begin];
    if (!valid_compact_field(field_row) ||
        compact_fields[field_row].owner != struct_node ||
        compact_hir_core[struct_node].kind != HIR_STRUCT_ITEM)
        return false;
    field_ordinal = compact_fields[field_row].ordinal;
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
    if (!valid_compact_node(struct_node))
        return;

    uint decl_field_row;
    uint field_ordinal;
    if (!field_row_for_literal_field(struct_node, field_token, decl_field_row, field_ordinal))
        return;

    HirField decl_field = compact_fields[decl_field_row];
    uint field_type_node = decl_field.value;
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
    // Backend-facing field identity is token-keyed and survives release of the
    // raw parser tree.
    struct_init_field_decl_node_by_node[field_node] = decl_field.name_token;
    uint literal_hir = raw_to_compact_hir[literal_node];
    uint row = compact_field_row_for_name_token(field_token);
    if (!valid_compact_node(literal_hir) || !valid_compact_field(row))
        return;
    HirPayload literal_payload = compact_hir_payload[literal_hir];
    HirField literal_field = compact_fields[row];
    if (literal_field.owner != literal_hir || literal_payload.b == INVALID ||
        row < literal_payload.b || row - literal_payload.b >= literal_payload.c)
        return;
    struct_init_field_ordinal_by_row[row] = field_ordinal;
    struct_init_field_decl_token_by_row[row] = decl_field.name_token;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 dtid: SV_DispatchThreadID)
{
    if ((gParams.parser_feature_flags & PARSER_FEATURE_STRUCTS) == 0u)
        return;
    uint i = linear_thread_id(dtid);
    if (!valid_node(i))
        return;
    struct_init_field_ordinal_by_node[i] = INVALID;
    struct_init_field_decl_node_by_node[i] = INVALID;

    uint literal_node = hir_struct_lit_field_parent_lit[i];
    if (!valid_node(literal_node) || hir_kind[literal_node] != HIR_STRUCT_LITERAL_EXPR)
        return;
    publish_struct_init_field_node(i);
}
