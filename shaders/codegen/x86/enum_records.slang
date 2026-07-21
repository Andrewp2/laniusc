// x86_64 enum layout/value projection.
//
// This pass turns parser HIR enum metadata plus module-resolver declaration
// rows into backend-owned records. Later x86 stages consume these records
// instead of recognizing enum constructors by spelling or by stdlib shape.

import gpu_index;
struct Params
{
    uint n_tokens;
    uint source_len;
    uint out_capacity;
    uint n_hir_nodes;
};

ConstantBuffer<Params> gParams;

struct HirVariant { uint owner; uint name_token; uint ordinal; uint file_id; };
StructuredBuffer<uint> compact_variant_count;
StructuredBuffer<HirVariant> compact_variants;
StructuredBuffer<uint> compact_variant_payload_count;

StructuredBuffer<uint> hir_status;
StructuredBuffer<uint> hir_kind;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> raw_to_compact_hir;
StructuredBuffer<uint> path_count_out;
StructuredBuffer<uint> path_id_by_owner_hir;
StructuredBuffer<uint> resolved_value_decl;
StructuredBuffer<uint> resolved_value_status;
StructuredBuffer<uint> visible_decl;
StructuredBuffer<uint> decl_count_out;
StructuredBuffer<uint> decl_kind;
StructuredBuffer<uint> decl_name_token;
StructuredBuffer<uint> decl_id_by_name_token;
StructuredBuffer<uint> decl_hir_node;
StructuredBuffer<uint> decl_parent_type_decl;

RWStructuredBuffer<uint> x86_enum_type_record;
RWStructuredBuffer<uint2> x86_enum_value_record;
RWStructuredBuffer<uint> x86_enum_record_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_ENUM_WIDTH_TAG_PAYLOAD = 2u;
static const uint X86_ENUM_VALUE_CALL_CTOR = 1u;
static const uint X86_ENUM_VALUE_UNIT_CTOR = 2u;
static const uint X86_ENUM_VALUE_VARIANT_REF = 3u;
static const uint X86_ENUM_VALUE_KIND_BITS = 4u;
static const uint X86_ENUM_VALUE_KIND_MASK = 0x0fu;
static const uint X86_ENUM_VALUE_PAYLOAD_COUNT_MAX = 0x0fffffffu;

static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_PATH_EXPR = 33u;

static const uint EXPR_RECORD_STRIDE = 4u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;

static const uint PATH_RESOLVE_STATUS_OK = 0u;
static const uint HIR_ITEM_KIND_ENUM = 7u;
static const uint HIR_ITEM_KIND_ENUM_VARIANT = 9u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return gParams.n_hir_nodes == 0u ? 0u : min(gParams.n_hir_nodes, hir_status[5u]);
}

uint active_path_count()
{
    return min(path_count_out[0u], gParams.n_hir_nodes);
}

uint active_decl_count()
{
    return min(decl_count_out[0u], gParams.n_hir_nodes);
}

uint active_variant_count()
{
    return min(compact_variant_count[0u], gParams.n_hir_nodes);
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
    return row_major_load<uint>(
        hir_expr_record,
        node,
        EXPR_RECORD_STRIDE,
        slot,
        INVALID);
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint callee_token_for_call(uint call_node)
{
    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    return valid_node(callee_node) ? expr_value_token(callee_node) : INVALID;
}

uint path_node_for_value_node(uint node)
{
    if (hir_kind[node] == HIR_PATH_EXPR)
        return node;
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        uint callee_node = resolve_expr(hir_call_callee_node[node]);
        if (valid_node(callee_node) && hir_kind[callee_node] == HIR_PATH_EXPR)
            return callee_node;
    }
    return INVALID;
}

bool variant_record_from_decl(
    uint decl_i,
    out uint variant_token,
    out uint enum_token,
    out uint variant_node,
    out uint ordinal,
    out uint payload_count)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant_node = INVALID;
    ordinal = INVALID;
    payload_count = 0u;

    uint decl_count = active_decl_count();
    if (decl_i >= decl_count || decl_kind[decl_i] != HIR_ITEM_KIND_ENUM_VARIANT)
        return false;

    uint enum_decl_i = decl_parent_type_decl[decl_i];
    if (enum_decl_i >= decl_count || decl_kind[enum_decl_i] != HIR_ITEM_KIND_ENUM)
        return false;

    variant_node = decl_hir_node[decl_i];
    if (variant_node >= active_variant_count())
        return false;

    variant_token = decl_name_token[decl_i];
    enum_token = decl_name_token[enum_decl_i];
    ordinal = compact_variants[variant_node].ordinal;
    payload_count = compact_variant_payload_count[variant_node];
    return valid_token(variant_token) && valid_token(enum_token);
}

bool variant_record_from_decl_token(
    uint decl_token,
    out uint variant_token,
    out uint enum_token,
    out uint variant_node,
    out uint ordinal,
    out uint payload_count)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant_node = INVALID;
    ordinal = INVALID;
    payload_count = 0u;

    if (!valid_token(decl_token))
        return false;

    uint decl_i = decl_id_by_name_token[decl_token];
    return variant_record_from_decl(
        decl_i,
        variant_token,
        enum_token,
        variant_node,
        ordinal,
        payload_count);
}

bool variant_record_for_use_token(
    uint use_token,
    out uint variant_token,
    out uint enum_token,
    out uint variant_node,
    out uint ordinal,
    out uint payload_count)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant_node = INVALID;
    ordinal = INVALID;
    payload_count = 0u;

    if (!valid_token(use_token))
        return false;
    return variant_record_from_decl_token(
        visible_decl[use_token],
        variant_token,
        enum_token,
        variant_node,
        ordinal,
        payload_count);
}

bool variant_record_for_path_node(
    uint path_node,
    out uint variant_token,
    out uint enum_token,
    out uint variant_node,
    out uint ordinal,
    out uint payload_count)
{
    variant_token = INVALID;
    enum_token = INVALID;
    variant_node = INVALID;
    ordinal = INVALID;
    payload_count = 0u;

    if (!valid_node(path_node))
        return false;

    uint dense = raw_to_compact_hir[path_node];
    uint path_i = dense < gParams.n_hir_nodes
                      ? path_id_by_owner_hir[dense]
                      : INVALID;
    if (path_i >= active_path_count() ||
        resolved_value_status[path_i] != PATH_RESOLVE_STATUS_OK)
        return false;
    return variant_record_from_decl(
        resolved_value_decl[path_i],
        variant_token,
        enum_token,
        variant_node,
        ordinal,
        payload_count);
}

uint pack_enum_value_info(uint kind, uint payload_count)
{
    if (payload_count > X86_ENUM_VALUE_PAYLOAD_COUNT_MAX)
        return INVALID;
    return (payload_count << X86_ENUM_VALUE_KIND_BITS) |
           (kind & X86_ENUM_VALUE_KIND_MASK);
}

void scatter_decl_row(uint decl_i)
{
    if (decl_i >= active_decl_count())
        return;

    if (decl_kind[decl_i] == HIR_ITEM_KIND_ENUM)
    {
        uint enum_token = decl_name_token[decl_i];
        if (valid_token(enum_token))
            x86_enum_type_record[enum_token] = X86_ENUM_WIDTH_TAG_PAYLOAD;
        return;
    }

    uint variant_token = INVALID;
    uint enum_token = INVALID;
    uint variant_node = INVALID;
    uint ordinal = INVALID;
    uint payload_count = 0u;
    if (!variant_record_from_decl(
            decl_i,
            variant_token,
            enum_token,
            variant_node,
            ordinal,
            payload_count))
        return;

    x86_enum_type_record[enum_token] = X86_ENUM_WIDTH_TAG_PAYLOAD;
}

void scatter_value_record(uint node)
{
    uint path_node = path_node_for_value_node(node);
    uint use_token = INVALID;
    uint kind = 0u;
    if (hir_kind[node] == HIR_CALL_EXPR)
    {
        use_token = callee_token_for_call(node);
        kind = X86_ENUM_VALUE_CALL_CTOR;
    }
    else if (hir_kind[node] == HIR_NAME_EXPR)
    {
        use_token = expr_value_token(node);
        kind = X86_ENUM_VALUE_UNIT_CTOR;
    }
    else if (hir_kind[node] == HIR_PATH_EXPR)
    {
        kind = X86_ENUM_VALUE_UNIT_CTOR;
    }
    else
    {
        return;
    }

    uint variant_token = INVALID;
    uint enum_token = INVALID;
    uint variant_node = INVALID;
    uint ordinal = INVALID;
    uint payload_count = 0u;
    bool found_variant = false;
    if (valid_node(path_node))
    {
        found_variant = variant_record_for_path_node(
            path_node,
            variant_token,
            enum_token,
            variant_node,
            ordinal,
            payload_count);
    }
    if (!found_variant)
    {
        found_variant = variant_record_for_use_token(
            use_token,
            variant_token,
            enum_token,
            variant_node,
            ordinal,
            payload_count);
    }
    if (!found_variant)
        return;

    if (kind == X86_ENUM_VALUE_CALL_CTOR && payload_count == 0u)
        return;
    if (kind == X86_ENUM_VALUE_UNIT_CTOR && payload_count != 0u)
        kind = X86_ENUM_VALUE_VARIANT_REF;

    uint packed_info = pack_enum_value_info(kind, payload_count);
    if (packed_info != INVALID)
        x86_enum_value_record[node] = uint2(packed_info, ordinal);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node == 0u)
    {
        x86_enum_record_status[0u] = X86_ENUM_RECORDS_OK;
        x86_enum_record_status[1u] = 0u;
        x86_enum_record_status[2u] = INVALID;
        x86_enum_record_status[3u] = 0u;
    }

    if (!valid_node(node))
        return;

    scatter_decl_row(node);
    scatter_value_record(node);
}
