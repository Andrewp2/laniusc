// SysV x86_64 call ABI projection over backend call records.
//
// x86_call_records owns the parser/resolver/type boundary,
// x86_call_arg_values owns per-call/per-ordinal argument lookup, and this pass
// records target/width ABI metadata without looking at argument expression
// forms.

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
StructuredBuffer<uint> x86_decl_node_by_token;
StructuredBuffer<uint4> x86_call_record;
StructuredBuffer<uint> x86_call_type_record;
StructuredBuffer<uint> call_record_status;
StructuredBuffer<uint> type_instance_kind;
StructuredBuffer<uint> type_instance_decl_token;
StructuredBuffer<uint> type_instance_len_kind;
StructuredBuffer<uint> type_instance_len_payload;
StructuredBuffer<uint> x86_struct_type_record;
StructuredBuffer<uint> x86_struct_record_status;
StructuredBuffer<uint> x86_enum_type_record;
StructuredBuffer<uint> x86_enum_record_status;

RWStructuredBuffer<uint2> x86_call_abi_record;
RWStructuredBuffer<uint> call_abi_status;

static const uint INVALID = 0xffffffffu;
static const uint DISPATCH_X_STRIDE = 16776960u;
static const uint X86_CALL_RECORDS_OK = 1u;
static const uint X86_CALL_ABI_OK = 1u;
static const uint X86_ENUM_RECORDS_OK = 1u;
static const uint X86_STRUCT_RECORDS_OK = 1u;
static const uint X86_ERR_CALL_ABI = 9u;

static const uint X86_CALL_TYPE_STRIDE = 3u;
static const uint X86_CALL_ABI_ARG_COUNT_BITS = 8u;
static const uint X86_CALL_ABI_ARG_COUNT_MASK = 0xffu;
static const uint X86_CALL_ABI_RETURN_WIDTH_MAX = 0x00ffffffu;

static const uint X86_SYSV_MAX_INTEGER_ARGS = 6u;
static const uint TYPE_INSTANCE_ARRAY = 2u;
static const uint TYPE_LEN_LITERAL = 1u;
static const uint TY_STRUCT_BASE = 4096u;
static const uint TY_ENUM_BASE = 6144u;
static const uint TY_GENERIC_BASE = 8192u;

uint linear_dispatch_id(uint3 tid)
{
    return linear_dispatch_thread_id_2d(tid, DISPATCH_X_STRIDE);
}

uint active_hir_node_count()
{
    return active_count_from_status(gParams.n_hir_nodes, hir_status, 5u);
}

bool valid_node(uint node)
{
    return valid_index_or_invalid(node, active_hir_node_count(), INVALID);
}

bool valid_token(uint token)
{
    return valid_index_or_invalid(token, gParams.n_tokens, INVALID);
}

uint call_record_slot(uint call_node)
{
    if (!valid_node(call_node))
        return INVALID;
    uint token = x86_call_record[call_node].z;
    return valid_token(token) ? token : INVALID;
}

bool call_records_ok()
{
    return stage_status4_ok(call_record_status, X86_CALL_RECORDS_OK);
}

bool enum_records_ok()
{
    return stage_status4_ok(x86_enum_record_status, X86_ENUM_RECORDS_OK);
}

bool struct_records_ok()
{
    return stage_status4_ok(x86_struct_record_status, X86_STRUCT_RECORDS_OK);
}

bool has_call_record(uint call_node)
{
    if (!valid_node(call_node))
        return false;

    uint4 record = x86_call_record[call_node];
    return uint4_any_not_equal(record, INVALID);
}

uint call_type_word(uint call_node, uint slot)
{
    return row_major_load<uint>(
        x86_call_type_record,
        call_node,
        X86_CALL_TYPE_STRIDE,
        slot,
        INVALID);
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

uint type_instance_width(uint ty)
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

uint call_return_width(uint semantic_ty, uint type_token)
{
    return max(semantic_type_width(semantic_ty), type_instance_width(type_token));
}

uint function_node_for_resolver_target(uint resolver_fn_token)
{
    if (!valid_token(resolver_fn_token))
        return INVALID;

    uint node = x86_decl_node_by_token[resolver_fn_token];
    return valid_node(node) ? node : INVALID;
}

void mark_call_abi_error(uint detail)
{
    publish_stage_error_min_detail4(call_abi_status, X86_ERR_CALL_ABI, detail);
}

uint pack_call_abi_info(uint arg_count, uint return_width)
{
    if (return_width > X86_CALL_ABI_RETURN_WIDTH_MAX)
        return INVALID;
    return (return_width << X86_CALL_ABI_ARG_COUNT_BITS) |
           (arg_count & X86_CALL_ABI_ARG_COUNT_MASK);
}

void project_call_record(uint call_node)
{
    uint4 call_record = x86_call_record[call_node];
    uint target_fn = function_node_for_resolver_target(call_record.y);
    uint arg_count = call_record.w;
    uint return_ty = call_type_word(call_node, 0u);
    uint return_ty_token = call_type_word(call_node, 1u);

    uint return_width = call_return_width(return_ty, return_ty_token);
    uint abi_register_count = arg_count + (return_width > 1u ? 1u : 0u);
    if (abi_register_count > X86_SYSV_MAX_INTEGER_ARGS)
        mark_call_abi_error(call_node);

    uint abi_info = pack_call_abi_info(arg_count, return_width);
    uint slot = call_record_slot(call_node);
    if (abi_info == INVALID || slot == INVALID)
        mark_call_abi_error(call_node);
    else
        x86_call_abi_record[slot] = uint2(target_fn, abi_info);
}

[shader("compute")]
[numthreads(256, 1, 1)]
void main(uint3 tid: SV_DispatchThreadID)
{
    uint node_i = linear_dispatch_id(tid);
    if (node_i == 0u && (!call_records_ok() || !enum_records_ok() || !struct_records_ok()))
    {
        call_abi_status[0u] = 0u;
        if (!call_records_ok())
        {
            call_abi_status[1u] = call_record_status[1u];
            call_abi_status[2u] = call_record_status[2u];
        }
        else if (!enum_records_ok())
        {
            call_abi_status[1u] = x86_enum_record_status[1u];
            call_abi_status[2u] = x86_enum_record_status[2u];
        }
        else
        {
            call_abi_status[1u] = x86_struct_record_status[1u];
            call_abi_status[2u] = x86_struct_record_status[2u];
        }
        call_abi_status[3u] = 0u;
    }

    if (!call_records_ok() || !enum_records_ok() || !struct_records_ok() ||
        node_i >= active_hir_node_count())
        return;

    if (has_call_record(node_i))
        project_call_record(node_i);
}
