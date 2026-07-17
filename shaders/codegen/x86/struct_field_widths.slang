// x86_64 struct field scalar-width projection.
//
// This pass maps declaration field HIR rows to fixed-width scalar slot counts.
// A later prefix scan over these widths gives each field its struct-local
// scalar offset.

import atomics;
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
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirField { uint owner; uint name_token; uint value; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_field_count;
StructuredBuffer<HirField> compact_fields;
StructuredBuffer<uint> raw_to_compact_hir;
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
RWStructuredBuffer<uint> x86_struct_field_count_by_hir;
RWStructuredBuffer<uint> x86_struct_field_count_scan_input;
RWStructuredBuffer<uint> x86_decl_node_by_token;

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

uint active_compact_hir_count()
{
    return min(compact_hir_count[0u], gParams.n_hir_nodes);
}

bool valid_dense(uint node)
{
    return node != INVALID && node < active_compact_hir_count();
}

uint active_compact_field_count()
{
    return min(compact_field_count[0u], gParams.n_hir_nodes);
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

uint type_head_token_for_dense_type(uint type_node)
{
    if (!valid_dense(type_node))
        return INVALID;
    uint value_node = compact_hir_payload[type_node].b;
    if (valid_dense(value_node))
    {
        uint value_head = compact_hir_core[value_node].token_start;
        if (valid_token(value_head))
            return value_head;
    }
    uint type_head = compact_hir_core[type_node].token_start;
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
    uint dense = valid_node(struct_node) ? raw_to_compact_hir[struct_node] : INVALID;
    if (!valid_dense(dense) || compact_hir_core[dense].kind != HIR_STRUCT_ITEM)
        return 1u;
    uint count = x86_struct_field_count_by_hir[dense];
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

uint field_width_for_row(uint row)
{
    HirField field = compact_fields[row];
    uint field_token = field.name_token;
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

    uint type_head = type_head_token_for_dense_type(field.value);
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
    if (node >= active_compact_field_count())
        return;

    HirField field = compact_fields[node];
    if (!valid_dense(field.owner) ||
        compact_hir_core[field.owner].kind != HIR_STRUCT_ITEM ||
        field.ordinal >= gParams.n_hir_nodes)
        return;

    atomic_u32_max(x86_struct_field_count_by_hir, field.owner, field.ordinal + 1u);
    atomic_u32_max(x86_struct_field_count_scan_input, field.owner, field.ordinal + 1u);
    uint field_token = field.name_token;
    if (valid_token(field_token))
        x86_decl_node_by_token[field_token] = node;
    x86_struct_field_width_by_node[node] = field_width_for_row(node);
}
