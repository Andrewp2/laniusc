// x86_64 parameter declaration -> SysV register lookup scatter.
//
// The parser owns hir_param_record rows. This pass scatters those sparse
// parameter rows into declaration-token keyed backend records so function-body
// planning can look up parameter ABI registers without scanning the whole HIR.

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
StructuredBuffer<uint> hir_node_decl_token;
StructuredBuffer<uint> hir_token_pos;
StructuredBuffer<uint> hir_fn_return_type_node;
StructuredBuffer<uint> hir_type_form;
StructuredBuffer<uint> hir_type_len_value;
StructuredBuffer<uint> x86_tree_subtree_end;
StructuredBuffer<uint> method_decl_param_offset;
StructuredBuffer<uint> method_decl_receiver_ref_tag;
StructuredBuffer<uint> method_decl_receiver_ref_payload;
StructuredBuffer<uint> call_return_type;
StructuredBuffer<uint> call_return_type_token;
StructuredBuffer<uint> call_param_type;
StructuredBuffer<uint4> hir_param_record;
StructuredBuffer<uint> decl_type_ref_tag;
StructuredBuffer<uint> decl_type_ref_payload;
StructuredBuffer<uint> visible_type;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
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

static const uint HIR_PARAM_RECORD_FN = 0u;
static const uint HIR_PARAM_RECORD_ORDINAL = 1u;
static const uint HIR_PARAM_RECORD_NAME_TOKEN = 2u;
static const uint HIR_PARAM_RECORD_NODE = 3u;

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
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;
static const uint X86_PARAM_REG_STRIDE = 5u;
static const uint X86_PARAM_REG_ORDINAL_BITS = 4u;
static const uint X86_PARAM_REG_ORDINAL_MASK = 0x0fu;
static const uint X86_PARAM_REG_ARG_REG_MASK = 0x0fu;

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

uint type_width(uint ty)
{
    if (!valid_token(ty))
        return 1u;
    if (type_instance_kind[ty] == TYPE_INSTANCE_ARRAY &&
        type_instance_len_kind[ty] == TYPE_LEN_LITERAL &&
        type_instance_len_payload[ty] != 0u)
        return type_instance_len_payload[ty];
    uint enum_token = type_instance_decl_token[ty];
    if (valid_token(enum_token) && x86_enum_type_record[enum_token] > 1u)
        return x86_enum_type_record[enum_token];
    if (valid_token(enum_token) && x86_struct_type_record[enum_token] != 0u)
        return x86_struct_type_record[enum_token];
    return 1u;
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

uint semantic_type_width(uint ty)
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
    if (method_decl_param_offset[fn_decl_token] != decl_token)
        return 1u;
    return type_ref_width(
        method_decl_receiver_ref_tag[fn_decl_token],
        method_decl_receiver_ref_payload[fn_decl_token]);
}

uint pack_param_reg_info(uint ordinal, uint arg_reg)
{
    if (ordinal > X86_PARAM_REG_ORDINAL_MASK || arg_reg > X86_PARAM_REG_ARG_REG_MASK)
        return INVALID;
    return ordinal | (arg_reg << X86_PARAM_REG_ORDINAL_BITS);
}

void write_param_reg_record_at(
    uint record_key,
    uint fn_node,
    uint link,
    uint ordinal,
    uint arg_reg,
    uint width,
    uint semantic_ty)
{
    uint info = pack_param_reg_info(ordinal, arg_reg);
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
        semantic_ty);
    row_major_store<uint>(
        x86_param_reg_record,
        record_key,
        X86_PARAM_REG_STRIDE,
        4u,
        link);
}

void write_param_reg_record(
    uint decl_token,
    uint fn_node,
    uint param_node,
    uint ordinal,
    uint arg_reg,
    uint width,
    uint semantic_ty)
{
    write_param_reg_record_at(decl_token, fn_node, param_node, ordinal, arg_reg, width, semantic_ty);
}

void scatter_param_reg(uint param_node)
{
    uint4 record = hir_param_record[param_node];
    uint fn_node = record[HIR_PARAM_RECORD_FN];
    uint ordinal = record[HIR_PARAM_RECORD_ORDINAL];
    uint decl_token = record[HIR_PARAM_RECORD_NAME_TOKEN];
    uint source_param_node = record[HIR_PARAM_RECORD_NODE];
    if (!valid_node(fn_node) || !valid_node(source_param_node) ||
        !valid_token(decl_token) || ordinal >= X86_SYSV_MAX_INTEGER_ARGS)
        return;

    uint fn_decl_token = hir_node_decl_token[fn_node];
    if (!valid_token(fn_decl_token))
        fn_decl_token = hir_token_pos[fn_node];
    if (!valid_token(fn_decl_token))
        return;

    uint fn_return_width = valid_token(fn_decl_token)
                               ? max(
                                     max(
                                         max(
                                             semantic_type_width(call_return_type[fn_decl_token]),
                                             type_width(call_return_type_token[fn_decl_token])),
                                         decl_type_width(fn_decl_token)),
                                     function_return_hir_width(fn_node))
                               : 1u;
    uint abi_ordinal = ordinal + (fn_return_width > 1u ? 1u : 0u);
    uint arg_reg = sysv_integer_arg_reg(abi_ordinal);
    if (arg_reg == INVALID)
        return;

    uint param_type = row_major_load<uint>(
        call_param_type,
        fn_decl_token,
        PARAM_CACHE_STRIDE,
        ordinal,
        TY_UNKNOWN);
    uint width = decl_is_unsized_array(decl_token)
                     ? 0u
                     : max(
                           max(
                               max(decl_type_width(decl_token), semantic_type_width(param_type)),
                               method_receiver_width(fn_decl_token, decl_token)),
                           1u);
    uint semantic_ty = param_type != TY_UNKNOWN ? param_type : visible_type[decl_token];
    write_param_reg_record(decl_token, fn_node, source_param_node, ordinal, arg_reg, width, semantic_ty);
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

    scatter_param_reg(node_i);
}
