// x86_64 declaration stack-layout projection.
//
// This pass compresses type-checker declaration/type-instance records into a
// backend-owned declaration layout table. Instruction count/generation passes
// consume this single record array instead of binding the full semantic type
// surface.

import gpu_index;
import atomics;
import prefix_scan;
import status;

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
StructuredBuffer<uint> hir_stmt_record;
StructuredBuffer<uint> hir_expr_record;
StructuredBuffer<uint> hir_call_callee_node;
StructuredBuffer<uint> hir_member_name_token;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> x86_expr_resolved_node;
StructuredBuffer<uint> x86_node_func;
StructuredBuffer<uint> x86_struct_access_record;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_elem_ref_tag;
StructuredBuffer<uint> type_instance_elem_ref_payload;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> x86_struct_type_record;
StructuredBuffer<uint> x86_struct_record_status;
StructuredBuffer<uint> x86_enum_type_record;
StructuredBuffer<uint> x86_enum_record_status;
StructuredBuffer<uint> x86_decl_width_by_node;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> x86_decl_scan_local_prefix;
StructuredBuffer<uint> x86_decl_scan_block_prefix;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;

RWStructuredBuffer<uint> x86_decl_layout_record;
RWStructuredBuffer<uint> x86_decl_layout_status;

static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint INVALID = 0xffffffffu;

static const uint X86_DECL_LAYOUT_OK = 1u;
static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_ERR_DECL_LAYOUT = 27u;

static const uint HIR_PARAM = 4u;
static const uint HIR_TYPE = 5u;
static const uint HIR_STMT = 7u;
static const uint HIR_LET_STMT = 8u;
static const uint HIR_CALL_EXPR = 19u;
static const uint HIR_MEMBER_EXPR = 21u;
static const uint HIR_NAME_EXPR = 22u;
static const uint HIR_ARRAY_EXPR = 24u;
static const uint HIR_FOR_STMT = 30u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;

static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;
static const uint HIR_PARAM_RECORD_NODE = 3u;

static const uint STMT_RECORD_STRIDE = 4u;
static const uint STMT_RECORD_KIND_LET = 1u;
static const uint STMT_RECORD_KIND_CONST = 4u;
static const uint STMT_RECORD_KIND_FOR = 7u;

static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_DECL_AGG_ENUM = 2u;
static const uint X86_DECL_AGG_STRUCT = 3u;
static const uint EXPR_RECORD_VALUE_TOKEN = 3u;
static const uint X86_STRUCT_ACCESS_LITERAL = 2u;
static const uint X86_STRUCT_ACCESS_ARRAY_LITERAL = 3u;
// Keep local-slot displacements within x86 signed disp32 while allowing large
// generated functions to exceed the old 16-bit-era guard.
static const uint MAX_X86_LOCAL_SLOTS = 1000000u;
static const uint WG_SIZE = 256u;
static const uint EXPR_RECORD_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_STRIDE = 4u;
static const uint X86_DECL_LAYOUT_KIND_BITS = 4u;
static const uint X86_DECL_LAYOUT_KIND_MASK = 0x0fu;
static const uint X86_DECL_LAYOUT_NODE_MAX = 0x0fffffffu;
static const uint X86_STRUCT_ACCESS_STRIDE = 3u;
static const uint X86_STRUCT_ACCESS_KIND_BITS = 4u;
static const uint X86_STRUCT_ACCESS_KIND_MASK = 0x0fu;

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

uint stmt_slot(uint node, uint slot)
{
    return row_major_load<uint>(
        hir_stmt_record,
        node,
        STMT_RECORD_STRIDE,
        slot,
        INVALID);
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

uint struct_access_word(uint row, uint slot)
{
    return row_major_load<uint>(
        x86_struct_access_record,
        row,
        X86_STRUCT_ACCESS_STRIDE,
        slot,
        INVALID);
}

uint struct_access_kind(uint row)
{
    uint info = struct_access_word(row, 2u);
    return info == INVALID ? 0u : info & X86_STRUCT_ACCESS_KIND_MASK;
}

uint struct_access_payload0(uint row)
{
    return struct_access_word(row, 0u);
}

uint expr_value_token(uint node)
{
    return valid_node(node) ? expr_slot(node, EXPR_RECORD_VALUE_TOKEN) : INVALID;
}

uint resolve_expr(uint node)
{
    return valid_node(node) ? x86_expr_resolved_node[node] : INVALID;
}

uint array_literal_node_for_expr(uint expr_node)
{
    uint node = resolve_expr(expr_node);
    return valid_node(node) && hir_kind[node] == HIR_ARRAY_EXPR ? node : INVALID;
}

bool is_local_decl_node(uint node)
{
    if (!valid_node(node))
        return false;
    uint stmt_kind = stmt_slot(node, 0u);
    return (hir_kind[node] == HIR_LET_STMT || hir_kind[node] == HIR_STMT) &&
           (stmt_kind == STMT_RECORD_KIND_LET || stmt_kind == STMT_RECORD_KIND_CONST);
}

bool is_for_node(uint node)
{
    return valid_node(node) &&
           (hir_kind[node] == HIR_FOR_STMT || hir_kind[node] == HIR_STMT) &&
           stmt_slot(node, 0u) == STMT_RECORD_KIND_FOR;
}

uint param_decl_token_for_node(uint node)
{
    if (!valid_node(node) || hir_kind[node] != HIR_PARAM)
        return INVALID;
    uint4 record = hir_param_record[node];
    return record[HIR_PARAM_RECORD_NODE] == node ? record[HIR_PARAM_RECORD_NAME_TOKEN] : INVALID;
}

bool type_instance_is_unsized_array(uint ty)
{
    if (!valid_token(ty))
        return false;
    if (type_instance_kind[ty] == TYPE_INSTANCE_SLICE)
        return true;
    return type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
           !(type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
             type_instance_len_payload[ty] != 0u);
}

bool decl_is_unsized_array(uint decl_token)
{
    return valid_token(decl_token) &&
           decl_type_ref_tag[decl_token] == TYPE_REF_INSTANCE &&
           type_instance_is_unsized_array(decl_type_ref_payload[decl_token]);
}

bool array_len_for_decl(uint decl_token, out uint len)
{
    len = 0u;
    if (!valid_token(decl_token))
        return false;
    if (decl_type_ref_tag[decl_token] != TYPE_REF_INSTANCE)
        return false;

    uint instance = decl_type_ref_payload[decl_token];
    if (!valid_token(instance))
        return false;
    if (type_instance_kind[instance] != TYPE_INSTANCE_ARRAY ||
        type_instance_len_kind[instance] != TYPE_LEN_LITERAL)
        return false;

    len = type_instance_len_payload[instance];
    return len != 0u;
}

bool enum_width_for_decl(uint decl_token, out uint width)
{
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint enum_token = INVALID;
    uint tag = decl_type_ref_tag[decl_token];
    uint payload = decl_type_ref_payload[decl_token];
    uint semantic_ty = visible_type[decl_token] != TY_UNKNOWN ? visible_type[decl_token] :
                       (tag == TYPE_REF_SCALAR ? payload : TY_UNKNOWN);
    if (semantic_ty >= TY_ENUM_BASE && semantic_ty < TY_GENERIC_BASE)
    {
        enum_token = semantic_ty - TY_ENUM_BASE;
    }
    else if (tag == TYPE_REF_INSTANCE)
    {
        if (!valid_token(payload))
            return false;
        enum_token = type_instance_decl_token[payload];
    }
    else
    {
        return false;
    }

    if (!valid_token(enum_token))
        return false;

    width = x86_enum_type_record[enum_token];
    return width > 1u;
}

bool struct_width_for_decl(uint decl_token, out uint width)
{
    width = 0u;
    if (!valid_token(decl_token))
        return false;

    uint struct_token = INVALID;
    uint tag = decl_type_ref_tag[decl_token];
    uint payload = decl_type_ref_payload[decl_token];
    uint semantic_ty = visible_type[decl_token] != TY_UNKNOWN ? visible_type[decl_token] :
                       (tag == TYPE_REF_SCALAR ? payload : TY_UNKNOWN);
    if (semantic_ty >= TY_STRUCT_BASE && semantic_ty < TY_ENUM_BASE)
    {
        struct_token = semantic_ty - TY_STRUCT_BASE;
    }
    else if (tag == TYPE_REF_INSTANCE)
    {
        if (!valid_token(payload))
            return false;
        struct_token = type_instance_decl_token[payload];
    }
    else
    {
        return false;
    }

    if (!valid_token(struct_token))
        return false;

    width = x86_struct_type_record[struct_token];
    return width != 0u;
}

uint semantic_type_storage_width(uint ty)
{
    if (ty >= TY_ENUM_BASE && ty < TY_GENERIC_BASE)
        return 2u;
    if (ty >= TY_STRUCT_BASE && ty < TY_ENUM_BASE)
    {
        uint struct_token = ty - TY_STRUCT_BASE;
        if (valid_token(struct_token) && x86_struct_type_record[struct_token] != 0u)
            return x86_struct_type_record[struct_token];
    }
    return 1u;
}

uint named_type_instance_storage_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    uint decl_token = type_instance_decl_token[ty];
    if (valid_token(decl_token) && x86_enum_type_record[decl_token] > 1u)
        return x86_enum_type_record[decl_token];
    if (valid_token(decl_token) && x86_struct_type_record[decl_token] != 0u)
        return x86_struct_type_record[decl_token];
    return 1u;
}

uint type_ref_leaf_storage_width(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return semantic_type_storage_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return named_type_instance_storage_width(payload);
    return 1u;
}

uint type_instance_storage_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    if (type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[ty] != 0u)
    {
        uint elem_width = type_ref_leaf_storage_width(
            type_instance_elem_ref_tag[ty],
            type_instance_elem_ref_payload[ty]);
        return max(elem_width, 1u) * type_instance_len_payload[ty];
    }
    return named_type_instance_storage_width(ty);
}

uint width_for_decl(uint decl_token)
{
    if (!valid_token(decl_token))
        return 1u;
    if (decl_type_ref_tag[decl_token] == TYPE_REF_INSTANCE)
        return max(
            type_instance_storage_width(decl_type_ref_payload[decl_token]),
            semantic_type_storage_width(visible_type[decl_token]));
    uint enum_width = 0u;
    if (enum_width_for_decl(decl_token, enum_width))
        return max(enum_width, visible_type[decl_token] != TY_UNKNOWN
                                   ? (visible_type[decl_token] >= TY_ENUM_BASE &&
                                      visible_type[decl_token] < TY_GENERIC_BASE ? 2u : 1u)
                                   : 1u);
    uint struct_width = 0u;
    if (struct_width_for_decl(decl_token, struct_width))
        return struct_width;
    return 1u;
}

bool semantic_aggregate_kind_width(uint semantic_ty, out uint kind, out uint width)
{
    kind = 0u;
    width = 0u;
    if (semantic_ty >= TY_ENUM_BASE && semantic_ty < TY_GENERIC_BASE)
    {
        uint enum_token = semantic_ty - TY_ENUM_BASE;
        uint enum_width = valid_token(enum_token) ? x86_enum_type_record[enum_token] : 0u;
        kind = X86_DECL_AGG_ENUM;
        width = max(enum_width, 2u);
        return true;
    }
    if (semantic_ty >= TY_STRUCT_BASE && semantic_ty < TY_ENUM_BASE)
    {
        uint struct_token = semantic_ty - TY_STRUCT_BASE;
        uint struct_width = valid_token(struct_token) ? x86_struct_type_record[struct_token] : 0u;
        if (struct_width > 1u)
        {
            kind = X86_DECL_AGG_STRUCT;
            width = struct_width;
            return true;
        }
    }
    return false;
}

bool type_instance_aggregate_kind_width(uint ty, out uint kind, out uint width)
{
    kind = 0u;
    width = 0u;
    if (!valid_token(ty))
        return false;
    if (type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[ty] != 0u)
    {
        kind = X86_DECL_AGG_ARRAY;
        width = type_instance_storage_width(ty);
        return width > 1u;
    }

    uint decl_token = type_instance_decl_token[ty];
    if (!valid_token(decl_token))
        return false;
    uint enum_width = x86_enum_type_record[decl_token];
    if (enum_width > 1u)
    {
        kind = X86_DECL_AGG_ENUM;
        width = enum_width;
        return true;
    }
    uint struct_width = x86_struct_type_record[decl_token];
    if (struct_width > 1u)
    {
        kind = X86_DECL_AGG_STRUCT;
        width = struct_width;
        return true;
    }
    return false;
}

uint decl_aggregate_kind(uint decl_token, uint semantic_ty)
{
    uint len = 0u;
    if (array_len_for_decl(decl_token, len))
        return X86_DECL_AGG_ARRAY;
    uint enum_width = 0u;
    if (enum_width_for_decl(decl_token, enum_width) ||
        (semantic_ty >= TY_ENUM_BASE && semantic_ty < TY_GENERIC_BASE))
        return X86_DECL_AGG_ENUM;
    uint struct_width = 0u;
    if (struct_width_for_decl(decl_token, struct_width) ||
        (semantic_ty >= TY_STRUCT_BASE && semantic_ty < TY_ENUM_BASE))
        return X86_DECL_AGG_STRUCT;
    return 0u;
}

bool aggregate_return_call_kind_width_for_decl_node(uint node, out uint kind, out uint width)
{
    kind = 0u;
    width = 0u;
    if (!is_local_decl_node(node))
        return false;

    uint call_node = resolve_expr(stmt_slot(node, 2u));
    if (!valid_node(call_node) || hir_kind[call_node] != HIR_CALL_EXPR)
        return false;

    uint callee_node = resolve_expr(hir_call_callee_node[call_node]);
    uint callee_token = INVALID;
    if (valid_node(callee_node) && hir_kind[callee_node] == HIR_MEMBER_EXPR)
        callee_token = hir_member_name_token[callee_node];
    else if (valid_node(callee_node) && hir_kind[callee_node] == HIR_NAME_EXPR)
        callee_token = expr_value_token(callee_node);
    if (!valid_token(callee_token))
        return false;

    uint semantic_kind = 0u;
    uint semantic_width = 0u;
    if (semantic_aggregate_kind_width(
            call_return_type[callee_token],
            semantic_kind,
            semantic_width))
    {
        kind = semantic_kind;
        width = semantic_width;
        return true;
    }

    return type_instance_aggregate_kind_width(
        call_return_type_token[callee_token],
        kind,
        width);
}

uint semantic_type_for_decl(uint decl_token)
{
    if (!valid_token(decl_token))
        return TY_UNKNOWN;
    uint visible_ty = visible_type[decl_token];
    if (visible_ty != TY_UNKNOWN)
        return visible_ty;
    return decl_type_ref_tag[decl_token] == TYPE_REF_SCALAR
               ? decl_type_ref_payload[decl_token]
               : TY_UNKNOWN;
}

bool struct_literal_width_for_decl_node(uint node, out uint width)
{
    width = 0u;
    if (!is_local_decl_node(node))
        return false;

    uint init_expr = stmt_slot(node, 2u);
    uint literal_record_node = resolve_expr(init_expr);
    if (!valid_node(literal_record_node))
        return false;

    uint literal_width = struct_access_payload0(literal_record_node);
    if (struct_access_kind(literal_record_node) != X86_STRUCT_ACCESS_LITERAL || literal_width == 0u)
        return false;

    width = literal_width;
    return true;
}

bool array_literal_width_for_decl_node(uint node, out uint width)
{
    width = 0u;
    if (!is_local_decl_node(node))
        return false;

    uint init_expr = stmt_slot(node, 2u);
    uint literal_node = array_literal_node_for_expr(init_expr);
    if (!valid_node(literal_node))
        return false;

    uint literal_width = struct_access_payload0(literal_node);
    if (struct_access_kind(literal_node) != X86_STRUCT_ACCESS_ARRAY_LITERAL || literal_width == 0u)
        return false;

    width = literal_width;
    return true;
}

bool is_scalar_param_node(uint node)
{
    uint decl_token = param_decl_token_for_node(node);
    return valid_token(decl_token) &&
           !decl_is_unsized_array(decl_token) &&
           width_for_decl(decl_token) == 1u;
}

uint decl_token_for_layout_node(uint node)
{
    if (is_scalar_param_node(node))
        return param_decl_token_for_node(node);
    return stmt_slot(node, 1u);
}

uint local_width_for_node(uint node)
{
    if (is_for_node(node))
    {
        uint decl_token = stmt_slot(node, 1u);
        return width_for_decl(decl_token) + 1u;
    }
    if (is_scalar_param_node(node))
        return 1u;
    if (is_local_decl_node(node))
    {
        uint width = width_for_decl(stmt_slot(node, 1u));
        if (width > 1u)
            return width;

        uint array_width = 0u;
        if (array_literal_width_for_decl_node(node, array_width))
            return array_width;

        uint literal_width = 0u;
        if (struct_literal_width_for_decl_node(node, literal_width))
            return literal_width;
        uint call_return_width = 0u;
        uint call_return_kind = 0u;
        if (aggregate_return_call_kind_width_for_decl_node(node, call_return_kind, call_return_width))
            return call_return_width;
        return width;
    }
    return 0u;
}

uint scanned_prefix_for_node(uint node)
{
    return global_exclusive_prefix(
        node,
        WG_SIZE,
        x86_decl_scan_local_prefix,
        x86_decl_scan_block_prefix);
}

uint base_slot_for_node(uint target_node)
{
    if (!valid_node(target_node))
        return INVALID;
    uint owner_fn = x86_node_func[target_node];
    if (!valid_node(owner_fn))
        return INVALID;
    uint node_prefix = scanned_prefix_for_node(target_node);
    uint fn_prefix = scanned_prefix_for_node(owner_fn);
    return node_prefix >= fn_prefix ? node_prefix - fn_prefix : INVALID;
}

bool has_layout_owner(uint node)
{
    if (!valid_node(node))
        return false;
    return valid_node(x86_node_func[node]);
}

void publish_error(uint detail, uint extent)
{
    publish_stage_error_min_detail4(
        x86_decl_layout_status,
        X86_ERR_DECL_LAYOUT,
        detail);
    atomic_u32_max(x86_decl_layout_status, 3u, extent);
}

uint pack_decl_layout_info(uint agg_kind, uint node)
{
    if (agg_kind > X86_DECL_LAYOUT_KIND_MASK || node > X86_DECL_LAYOUT_NODE_MAX)
        return INVALID;
    return (node << X86_DECL_LAYOUT_KIND_BITS) | agg_kind;
}

void write_decl_layout_record(uint row, uint word0, uint word1, uint word2, uint word3)
{
    row_major_store<uint>(x86_decl_layout_record, row, X86_DECL_LAYOUT_STRIDE, 0u, word0);
    row_major_store<uint>(x86_decl_layout_record, row, X86_DECL_LAYOUT_STRIDE, 1u, word1);
    row_major_store<uint>(x86_decl_layout_record, row, X86_DECL_LAYOUT_STRIDE, 2u, word2);
    row_major_store<uint>(x86_decl_layout_record, row, X86_DECL_LAYOUT_STRIDE, 3u, word3);
}

bool publish_decl_layout_record(uint row, uint base, uint width, uint agg_kind, uint node)
{
    uint info = pack_decl_layout_info(agg_kind, node);
    if (info == INVALID)
        return false;
    uint decl_token = valid_node(node) ? decl_token_for_layout_node(node) : row;
    write_decl_layout_record(row, base, width, info, semantic_type_for_decl(decl_token));
    return true;
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node = linear_dispatch_id(tid);
    if (node == 0u)
    {
        bool enum_ok = x86_enum_record_status[0u] == X86_ENUM_RECORDS_OK &&
                       x86_enum_record_status[1u] == 0u;
        bool struct_ok = x86_struct_record_status[0u] == X86_STRUCT_RECORDS_OK &&
                         x86_struct_record_status[1u] == 0u;
        x86_decl_layout_status[0u] = enum_ok && struct_ok ? X86_DECL_LAYOUT_OK : 0u;
        x86_decl_layout_status[1u] = enum_ok && struct_ok ? 0u : X86_ERR_DECL_LAYOUT;
        x86_decl_layout_status[2u] = enum_ok ? x86_struct_record_status[2u]
                                             : x86_enum_record_status[2u];
        x86_decl_layout_status[3u] = 0u;
    }

    if (x86_enum_record_status[0u] != X86_ENUM_RECORDS_OK ||
        x86_enum_record_status[1u] != 0u ||
        x86_struct_record_status[0u] != X86_STRUCT_RECORDS_OK ||
        x86_struct_record_status[1u] != 0u)
        return;

    if (!is_local_decl_node(node) && !is_for_node(node) && !is_scalar_param_node(node))
        return;

    uint decl_token = decl_token_for_layout_node(node);
    if (!valid_token(decl_token))
        return;
    if (!has_layout_owner(node))
        return;

    uint base = base_slot_for_node(node);
    uint width = x86_decl_width_by_node[node];
    if (base == INVALID || base + width > MAX_X86_LOCAL_SLOTS)
    {
        publish_error(node, base == INVALID ? INVALID : base + width);
        return;
    }

    if (is_for_node(node))
    {
        uint for_width = width_for_decl(decl_token);
        uint for_kind = decl_aggregate_kind(decl_token, semantic_type_for_decl(decl_token));
        bool decl_ok = publish_decl_layout_record(decl_token, base, for_width, for_kind, node);
        if (!decl_ok)
        {
            publish_error(node, base + width);
            return;
        }
        atomic_u32_max(x86_decl_layout_status, 3u, base + width);
        return;
    }

    if (is_scalar_param_node(node))
    {
        if (!publish_decl_layout_record(decl_token, base, 1u, 0u, node))
        {
            publish_error(node, base + width);
            return;
        }
        atomic_u32_max(x86_decl_layout_status, 3u, base + width);
        return;
    }

    uint array_len = 0u;
    uint enum_width = 0u;
    uint struct_width = 0u;
    uint agg_kind = array_len_for_decl(decl_token, array_len) ? X86_DECL_AGG_ARRAY : 0u;
    if (agg_kind == 0u && array_literal_width_for_decl_node(node, array_len))
        agg_kind = X86_DECL_AGG_ARRAY;
    if (agg_kind == 0u && enum_width_for_decl(decl_token, enum_width))
        agg_kind = X86_DECL_AGG_ENUM;
    if (agg_kind == 0u && struct_width_for_decl(decl_token, struct_width))
        agg_kind = X86_DECL_AGG_STRUCT;
    if (agg_kind == 0u && struct_literal_width_for_decl_node(node, struct_width))
        agg_kind = X86_DECL_AGG_STRUCT;
    uint call_return_width = 0u;
    uint call_return_kind = 0u;
    if (agg_kind == 0u &&
        aggregate_return_call_kind_width_for_decl_node(node, call_return_kind, call_return_width) &&
        call_return_width == width)
        agg_kind = call_return_kind;
    if (!publish_decl_layout_record(decl_token, base, width, agg_kind, node))
    {
        publish_error(node, base + width);
        return;
    }
    atomic_u32_max(x86_decl_layout_status, 3u, base + width);
}
