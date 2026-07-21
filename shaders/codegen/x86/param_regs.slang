// x86_64 compact parameter row -> SysV register lookup scatter.
//
// The frontend publishes one dense owner/name/type/ordinal row per parameter.
// This pass projects those compact rows into declaration-token keyed backend
// records so function-body planning can look up ABI registers without retaining
// the parser's sparse raw parameter columns.

import gpu_index;
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
StructuredBuffer<uint> hir_token_pos;
struct HirCore { uint kind; uint parent; uint token_start; uint token_end; };
struct HirPayload { uint a; uint b; uint c; uint d; };
struct HirParam { uint owner; uint name_token; uint type_node; uint ordinal; };
StructuredBuffer<uint> compact_hir_count;
StructuredBuffer<HirCore> compact_hir_core;
StructuredBuffer<HirPayload> compact_hir_payload;
StructuredBuffer<uint> compact_param_count;
StructuredBuffer<HirParam> compact_params;
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint> fn_entrypoint_tag;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> fn_return_ref_tag;
StructuredBuffer<uint> fn_return_ref_payload;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_mode;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_param_type;
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

RWStructuredBuffer<uint> x86_param_reg_record;
RWStructuredBuffer<uint> x86_param_reg_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_PARAM_REGS_OK = 1u;
static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_ERR_ENTRYPOINT_PARAMS = 49u;
static const uint X86_ERR_PARAM_REG_COUNT = 51u;
static const uint X86_ERR_ENTRYPOINT_AGG_RETURN = 54u;
static const uint ENTRYPOINT_MAIN = 1u;

static const uint HIR_FN = 3u;
static const uint HIR_TYPE = 5u;
static const uint HIR_TYPE_FORM_ARRAY = 2u;
static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint PARAM_CACHE_STRIDE = 4u;
static const uint X86_REG_EDI = 7u;
static const uint X86_REG_ESI = 6u;
static const uint X86_REG_EDX = 2u;
static const uint X86_REG_ECX = 1u;
static const uint X86_REG_R8D = 8u;
static const uint X86_REG_R9D = 9u;
static const uint TYPE_REF_SCALAR = 1u;
static const uint TYPE_REF_INSTANCE = 3u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_INSTANCE_SLICE = 3u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TY_UNKNOWN = 0u;
static const uint TY_STRING = 7u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint X86_DECL_AGG_ARRAY = 1u;
static const uint X86_DECL_AGG_ENUM = 2u;
static const uint X86_DECL_AGG_STRUCT = 3u;
static const uint X86_DECL_AGG_STRING = 4u;
static const uint METHOD_RECEIVER_NONE = 0u;
static const uint METHOD_RECEIVER_EXPLICIT = 3u;
static const uint X86_PARAM_REG_STRIDE = 6u;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;
static const uint X86_PARAM_REG_KIND_BITS = 4u;

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

uint active_compact_param_count()
{
    return min(compact_param_count[0u], gParams.n_tokens);
}

bool valid_token(uint token)
{
    return token != INVALID && token < gParams.n_tokens;
}

uint sysv_integer_arg_reg(uint ordinal)
{
    if (ordinal == 0u) return X86_REG_EDI;
    if (ordinal == 1u) return X86_REG_ESI;
    if (ordinal == 2u) return X86_REG_EDX;
    if (ordinal == 3u) return X86_REG_ECX;
    if (ordinal == 4u) return X86_REG_R8D;
    if (ordinal == 5u) return X86_REG_R9D;
    return INVALID;
}

uint semantic_type_width(uint ty);

uint named_type_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    uint enum_token = type_instance_decl_token[ty];
    if (valid_token(enum_token) && x86_enum_type_record[enum_token] > 1u)
        return x86_enum_type_record[enum_token];
    if (valid_token(enum_token) && x86_struct_type_record[enum_token] != 0u)
        return x86_struct_type_record[enum_token];
    return 1u;
}

uint type_ref_leaf_width(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return semantic_type_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return named_type_width(payload);
    return 1u;
}

uint type_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    if (type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[ty] != 0u)
    {
        uint elem_width = type_ref_leaf_width(
            type_instance_elem_ref_tag[ty],
            type_instance_elem_ref_payload[ty]);
        return max(elem_width, 1u) * type_instance_len_payload[ty];
    }
    return named_type_width(ty);
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

uint semantic_type_width(uint ty)
{
    if (ty == TY_STRING)
        return 2u;
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

bool array_type_width_for_type_node(uint type_node, out uint width)
{
    width = 0u;
    if (!valid_node(type_node) ||
        hir_kind[type_node] != HIR_TYPE ||
        hir_type_form[type_node] != HIR_TYPE_FORM_ARRAY)
        return false;
    uint len = hir_type_len_value[type_node];
    if (len == INVALID || len <= 1u)
        return false;
    width = len;
    return true;
}

uint function_return_hir_width(uint fn_node)
{
    uint width = 0u;
    uint type_node = valid_node(fn_node) ? hir_fn_return_type_node[fn_node] : INVALID;
    return array_type_width_for_type_node(type_node, width) ? width : 1u;
}

bool upstream_ok()
{
    return x86_enum_record_status[0u] == X86_ENUM_RECORDS_OK &&
           x86_enum_record_status[1u] == 0u &&
           x86_struct_record_status[0u] == X86_STRUCT_RECORDS_OK &&
           x86_struct_record_status[1u] == 0u;
}

uint decl_type_width(uint decl_token)
{
    if (!valid_token(decl_token))
        return 1u;
    uint tag = decl_type_ref_tag[decl_token];
    uint payload = decl_type_ref_payload[decl_token];
    if (tag == TYPE_REF_SCALAR)
        return semantic_type_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return max(type_width(payload), semantic_type_width(visible_type[decl_token]));
    uint visible_ty = visible_type[decl_token];
    if (visible_ty != TY_UNKNOWN)
        return semantic_type_width(visible_ty);
    return 1u;
}

uint decl_semantic_type(uint decl_token, uint fallback_ty)
{
    if (!valid_token(decl_token))
        return fallback_ty;
    uint visible_ty = visible_type[decl_token];
    if (visible_ty != TY_UNKNOWN)
        return visible_ty;
    if (decl_type_ref_tag[decl_token] == TYPE_REF_SCALAR)
        return decl_type_ref_payload[decl_token];
    return fallback_ty;
}

uint type_ref_semantic_type(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return payload;
    if (tag != TYPE_REF_INSTANCE || !valid_token(payload))
        return TY_UNKNOWN;

    uint decl_token = type_instance_decl_token[payload];
    if (!valid_token(decl_token))
        return TY_UNKNOWN;
    if (x86_struct_type_record[decl_token] != 0u)
        return TY_STRUCT_BASE + decl_token;
    if (x86_enum_type_record[decl_token] != 0u)
        return TY_ENUM_BASE + decl_token;
    return TY_UNKNOWN;
}

uint method_receiver_semantic_type(uint fn_decl_token, uint decl_token)
{
    if (!valid_token(fn_decl_token) || !valid_token(decl_token) ||
        method_decl_receiver_mode[fn_decl_token] == METHOD_RECEIVER_NONE ||
        method_decl_param_offset[fn_decl_token] != decl_token)
        return TY_UNKNOWN;
    return type_ref_semantic_type(
        method_decl_receiver_ref_tag[fn_decl_token],
        method_decl_receiver_ref_payload[fn_decl_token]);
}

uint decl_aggregate_kind(uint decl_token, uint semantic_ty)
{
    if (semantic_ty == TY_STRING)
        return X86_DECL_AGG_STRING;
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

uint type_ref_width(uint tag, uint payload)
{
    if (tag == TYPE_REF_SCALAR)
        return semantic_type_width(payload);
    if (tag == TYPE_REF_INSTANCE)
        return type_width(payload);
    return 1u;
}

uint method_receiver_width(uint fn_decl_token, uint decl_token)
{
    if (!valid_token(fn_decl_token) || !valid_token(decl_token))
        return 1u;
    if (method_decl_receiver_mode[fn_decl_token] == METHOD_RECEIVER_NONE)
        return 1u;
    if (method_decl_param_offset[fn_decl_token] != decl_token)
        return 1u;
    return type_ref_width(
        method_decl_receiver_ref_tag[fn_decl_token],
        method_decl_receiver_ref_payload[fn_decl_token]);
}

uint pack_param_reg_info(uint arg_reg, uint aggregate_kind)
{
    if (arg_reg > X86_PARAM_REG_ARG_REG_MASK)
        return INVALID;
    return arg_reg |
           (aggregate_kind << X86_PARAM_REG_KIND_BITS);
}

bool fn_is_main_entrypoint(uint fn_node)
{
    return valid_node(fn_node) &&
           hir_kind[fn_node] == HIR_FN &&
           valid_token(hir_token_pos[fn_node]) &&
           fn_entrypoint_tag[hir_token_pos[fn_node]] == ENTRYPOINT_MAIN;
}

void publish_entrypoint_param_error(uint param_node)
{
    publish_stage_error_min_detail4(
        x86_param_reg_status,
        X86_ERR_ENTRYPOINT_PARAMS,
        param_node);
}

void publish_entrypoint_aggregate_return_error(uint fn_node)
{
    publish_stage_error_min_detail4(
        x86_param_reg_status,
        X86_ERR_ENTRYPOINT_AGG_RETURN,
        fn_node);
}

void publish_param_reg_count_error(uint param_node)
{
    publish_stage_error_min_detail4(
        x86_param_reg_status,
        X86_ERR_PARAM_REG_COUNT,
        param_node);
}

uint function_decl_token(uint fn_dense, uint fn_node)
{
    if (!valid_node(fn_node))
        return INVALID;
    uint decl_token = valid_dense(fn_dense) && compact_hir_core[fn_dense].kind == HIR_FN
                          ? compact_hir_payload[fn_dense].b
                          : hir_token_pos[fn_node];
    return valid_token(decl_token) ? decl_token : INVALID;
}

uint function_return_width(uint fn_dense, uint fn_node)
{
    uint fn_decl_token = function_decl_token(fn_dense, fn_node);
    if (!valid_token(fn_decl_token))
        return function_return_hir_width(fn_node);

    // The type checker publishes one explicit return reference per function
    // declaration. This is the ABI source of truth shared with call
    // resolution; call-result tables describe uses and declaration type refs
    // describe values, so neither may infer a hidden sret parameter here.
    uint return_tag = fn_return_ref_tag[fn_decl_token];
    if (return_tag == TYPE_REF_SCALAR || return_tag == TYPE_REF_INSTANCE)
        return type_ref_width(return_tag, fn_return_ref_payload[fn_decl_token]);

    return max(
        max(
            max(
                semantic_type_width(call_return_type[fn_decl_token]),
                type_width(call_return_type_token[fn_decl_token])),
            decl_type_width(fn_decl_token)),
        function_return_hir_width(fn_node));
}

void reject_unsupported_entrypoint_return(uint fn_node)
{
    if (!fn_is_main_entrypoint(fn_node))
        return;
    if (function_return_width(INVALID, fn_node) <= 1u)
        return;
    publish_entrypoint_aggregate_return_error(fn_node);
}

void write_param_reg_record_at(
    uint record_key,
    uint fn_node,
    uint link,
    uint ordinal,
    uint arg_reg,
    uint width,
    uint semantic_ty,
    uint aggregate_kind)
{
    uint info = pack_param_reg_info(arg_reg, aggregate_kind);
    if (info == INVALID)
        return;
    row_major_store<uint>(x86_param_reg_record, record_key, X86_PARAM_REG_STRIDE, 0u, fn_node);
    row_major_store<uint>(x86_param_reg_record, record_key, X86_PARAM_REG_STRIDE, 1u, width);
    row_major_store<uint>(x86_param_reg_record, record_key, X86_PARAM_REG_STRIDE, 2u, info);
    row_major_store<uint>(
        x86_param_reg_record,
        record_key,
        X86_PARAM_REG_STRIDE,
        3u,
        ordinal);
    row_major_store<uint>(
        x86_param_reg_record,
        record_key,
        X86_PARAM_REG_STRIDE,
        4u,
        semantic_ty);
    row_major_store<uint>(
        x86_param_reg_record,
        record_key,
        X86_PARAM_REG_STRIDE,
        5u,
        link);
}

void write_param_reg_record(
    uint decl_token,
    uint fn_node,
    uint param_node,
    uint ordinal,
    uint arg_reg,
    uint width,
    uint semantic_ty,
    uint aggregate_kind)
{
    write_param_reg_record_at(
        decl_token,
        fn_node,
        param_node,
        ordinal,
        arg_reg,
        width,
        semantic_ty,
        aggregate_kind);
}

void maybe_write_explicit_receiver_param_record(
    uint fn_decl_token,
    uint fn_node,
    uint source_param_node,
    uint fn_return_width,
    uint ordinal)
{
    if (!valid_token(fn_decl_token) ||
        method_decl_receiver_mode[fn_decl_token] != METHOD_RECEIVER_EXPLICIT)
        return;

    uint receiver_decl = method_decl_param_offset[fn_decl_token];
    if (!valid_token(receiver_decl))
        return;

    uint abi_ordinal = fn_return_width > 1u ? 1u : 0u;
    uint arg_reg = sysv_integer_arg_reg(abi_ordinal);
    if (arg_reg == INVALID)
        return;

    uint semantic_ty = visible_type[receiver_decl];
    uint width = method_receiver_width(fn_decl_token, receiver_decl);
    uint aggregate_kind = decl_aggregate_kind(receiver_decl, semantic_ty);
    write_param_reg_record_at(
        receiver_decl,
        fn_node,
        source_param_node,
        0u,
        arg_reg,
        width,
        semantic_ty,
        aggregate_kind);
}

void scatter_param_reg(uint row)
{
    if (row >= active_compact_param_count())
        return;

    HirParam parameter = compact_params[row];
    uint fn_dense = parameter.owner;
    uint ordinal = parameter.ordinal;
    uint decl_token = parameter.name_token;
    uint fn_decl_token = valid_dense(fn_dense) && compact_hir_core[fn_dense].kind == HIR_FN
                             ? compact_hir_payload[fn_dense].b
                             : INVALID;
    uint fn_node = valid_token(fn_decl_token)
                       ? x86_decl_node_by_token[fn_decl_token]
                       : INVALID;
    uint source_param_node = valid_token(decl_token)
                                 ? x86_decl_node_by_token[decl_token]
                                 : INVALID;
    if (!valid_dense(fn_dense) || compact_hir_core[fn_dense].kind != HIR_FN ||
        !valid_node(fn_node) || !valid_token(fn_decl_token) || !valid_token(decl_token))
        return;

    if (fn_is_main_entrypoint(fn_node))
    {
        publish_entrypoint_param_error(valid_node(source_param_node) ? source_param_node : fn_node);
        return;
    }

    if (ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
    {
        publish_param_reg_count_error(valid_node(source_param_node) ? source_param_node : fn_node);
        return;
    }

    uint fn_return_width = function_return_width(fn_dense, fn_node);
    maybe_write_explicit_receiver_param_record(
        fn_decl_token,
        fn_node,
        source_param_node,
        fn_return_width,
        ordinal);
    uint abi_ordinal = ordinal + (fn_return_width > 1u ? 1u : 0u);
    uint arg_reg = sysv_integer_arg_reg(abi_ordinal);
    if (arg_reg == INVALID)
    {
        publish_param_reg_count_error(valid_node(source_param_node) ? source_param_node : fn_node);
        return;
    }

    uint param_type = row_major_load<uint>(
        call_param_type,
        fn_decl_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        TY_UNKNOWN);
    uint semantic_ty = decl_semantic_type(decl_token, param_type);
    uint receiver_ty = method_receiver_semantic_type(fn_decl_token, decl_token);
    if (receiver_ty != TY_UNKNOWN)
        semantic_ty = receiver_ty;
    uint width = decl_is_unsized_array(decl_token)
                     ? 0u
                     : max(
                           max(decl_type_width(decl_token),
                               method_receiver_width(fn_decl_token, decl_token)),
                           1u);
    uint aggregate_kind = decl_aggregate_kind(decl_token, semantic_ty);
    write_param_reg_record(
        decl_token,
        fn_node,
        source_param_node,
        ordinal,
        arg_reg,
        width,
        semantic_ty,
        aggregate_kind);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u && !upstream_ok())
    {
        x86_param_reg_status[0u] = 0u;
        bool enum_ok = x86_enum_record_status[0u] == X86_ENUM_RECORDS_OK &&
                       x86_enum_record_status[1u] == 0u;
        x86_param_reg_status[1u] = enum_ok ? x86_struct_record_status[1u]
                                           : x86_enum_record_status[1u];
        x86_param_reg_status[2u] = enum_ok ? x86_struct_record_status[2u]
                                           : x86_enum_record_status[2u];
        x86_param_reg_status[3u] = 0u;
    }
    if (!upstream_ok())
        return;

    if (node_i >= active_hir_node_count())
        return;

    reject_unsupported_entrypoint_return(node_i);
    scatter_param_reg(node_i);
}
