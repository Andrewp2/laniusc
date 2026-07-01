// x86_64 struct field scalar-width projection.
//
// This pass maps declaration field HIR rows to fixed-width scalar slot counts.
// A later prefix scan over these widths gives each field its struct-local
// scalar offset.

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
StructuredBuffer<uint> hir_item_name_token;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_type_value_node;
StructuredBuffer<uint> hir_type_path_leaf_node;
StructuredBuffer<uint> hir_struct_field_parent_struct;
StructuredBuffer<uint> hir_struct_field_type_node;
StructuredBuffer<uint> hir_struct_decl_field_count;
StructuredBuffer<uint> type_expr_ref_tag;
StructuredBuffer<uint> type_expr_ref_payload;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> module_type_path_type;
StructuredBuffer<uint> type_decl_hir_node_by_token;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> x86_enum_type_record;

RWStructuredBuffer<uint> x86_struct_type_record;
RWStructuredBuffer<uint> x86_struct_field_width_by_node;
RWStructuredBuffer<uint> x86_struct_field_count_scan_input;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint HIR_STRUCT_ITEM = 27u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRING = 7u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
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

uint visible_decl_for_type_token(uint token)
{
    if (!valid_token(token))
        return INVALID;
    uint decl = visible_decl[token];
    return valid_token(decl) ? decl : INVALID;
}

uint type_head_token_for_node(uint type_node)
{
    if (!valid_node(type_node))
        return INVALID;

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

uint scalar_type_width(uint ty)
{
    if (ty == TY_STRING)
        return 2u;
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
    {
        uint enum_token = ty - TY_ENUM_BASE;
        uint enum_width = valid_token(enum_token) ? x86_enum_type_record[enum_token] : 0u;
        return max(enum_width, 2u);
    }
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
    {
        uint struct_token = ty - TY_STRUCT_BASE;
        uint struct_width = valid_token(struct_token) ? x86_struct_type_record[struct_token] : 0u;
        return max(struct_width, 1u);
    }
    return 1u;
}

uint declared_struct_field_count_width(uint decl_token)
{
    if (!valid_token(decl_token))
        return 1u;
    uint struct_node = type_decl_hir_node_by_token[decl_token];
    if (!valid_node(struct_node) || hir_kind[struct_node] != HIR_STRUCT_ITEM)
        return 1u;
    uint count = hir_struct_decl_field_count[struct_node];
    return count == 0u ? 1u : count;
}

uint projected_named_type_width(uint ty)
{
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
    {
        uint struct_token = ty - TY_STRUCT_BASE;
        uint struct_width = valid_token(struct_token) ? x86_struct_type_record[struct_token] : 0u;
        return struct_width != 0u ? struct_width : declared_struct_field_count_width(struct_token);
    }
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
    {
        uint enum_token = ty - TY_ENUM_BASE;
        uint enum_width = valid_token(enum_token) ? x86_enum_type_record[enum_token] : 0u;
        return max(enum_width, 2u);
    }
    return ty == TY_UNKNOWN ? 1u : scalar_type_width(ty);
}

uint semantic_type_width(uint ty)
{
    return ty == TY_UNKNOWN ? 1u : scalar_type_width(ty);
}

uint named_instance_width(uint instance)
{
    if (!valid_token(instance))
        return 1u;

    uint decl_token = type_instance_decl_token[instance];
    if (valid_token(decl_token) && x86_enum_type_record[decl_token] > 1u)
        return x86_enum_type_record[decl_token];
    if (valid_token(decl_token) && x86_struct_type_record[decl_token] != 0u)
        return x86_struct_type_record[decl_token];
    return 1u;
}

uint named_type_token_width(uint token)
{
    if (valid_token(token))
    {
        uint projected = module_type_path_type[token];
        uint projected_width = projected_named_type_width(projected);
        if (projected_width > 1u)
            return projected_width;
    }
    uint decl_token = visible_decl_for_type_token(token);
    if (!valid_token(decl_token))
        return 1u;
    uint decl_projected = module_type_path_type[decl_token];
    uint decl_projected_width = projected_named_type_width(decl_projected);
    if (decl_projected_width > 1u)
        return decl_projected_width;
    if (x86_enum_type_record[decl_token] > 1u)
        return x86_enum_type_record[decl_token];
    if (x86_struct_type_record[decl_token] != 0u)
        return x86_struct_type_record[decl_token];
    return 1u;
}

uint type_ref_width_shallow(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return scalar_type_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return named_instance_width(payload);
    return 1u;
}

uint type_ref_width(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return scalar_type_width(payload);
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return 1u;

    if (type_instance_kind[payload] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[payload] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[payload] != 0u)
    {
        uint elem_width = type_ref_width_shallow(
            type_instance_elem_ref_tag[payload],
            type_instance_elem_ref_payload[payload]);
        return max(elem_width, 1u) * type_instance_len_payload[payload];
    }

    return named_instance_width(payload);
}

uint field_width_for_node(uint node)
{
    uint field_token = hir_token_pos[node];
    if (valid_token(field_token))
    {
        uint semantic_width = semantic_type_width(visible_type[field_token]);
        if (semantic_width > 1u)
            return semantic_width;
        uint decl_width = type_ref_width(
            decl_type_ref_tag[field_token],
            decl_type_ref_payload[field_token]);
        if (decl_width > 1u)
            return decl_width;
    }

    uint type_node = hir_struct_field_type_node[node];
    uint type_head = type_head_token_for_node(type_node);
    if (!valid_token(type_head))
        return 1u;
    uint type_head_width = semantic_type_width(visible_type[type_head]);
    if (type_head_width > 1u)
        return type_head_width;
    uint type_head_decl_width = type_ref_width(
        decl_type_ref_tag[type_head],
        decl_type_ref_payload[type_head]);
    if (type_head_decl_width > 1u)
        return type_head_decl_width;
    uint width = type_ref_width(
        type_expr_ref_tag[type_head],
        type_expr_ref_payload[type_head]);
    if (width <= 1u)
        width = named_type_token_width(type_head);
    return max(width, 1u);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (!valid_node(node))
        return;

    x86_struct_field_width_by_node[node] = 0u;
    x86_struct_field_count_scan_input[node] = 0u;

    if (hir_kind[node] == HIR_STRUCT_ITEM)
    {
        uint decl_token = hir_item_name_token[node];
        uint field_count = hir_struct_decl_field_count[node];
        x86_struct_field_count_scan_input[node] = field_count;
        if (valid_token(decl_token) && field_count != 0u && x86_struct_type_record[decl_token] == 0u)
            x86_struct_type_record[decl_token] = field_count;
    }

    if (!valid_node(hir_struct_field_parent_struct[node]))
        return;

    x86_struct_field_width_by_node[node] = field_width_for_node(node);
}
